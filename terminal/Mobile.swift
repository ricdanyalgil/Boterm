import AppKit
import CoreImage
import CryptoKit
import Security

// Boterm Mobile: the phone app talks to this Mac through a relay that only forwards ciphertext.
// Full protocol: boterm-apps/protocol/PROTOCOL.md (private repo). In short:
//   relay  the Mac proves it owns the room (room = SHA-256(Ed25519 pub ‖ nonce)) and tells the relay which phone bearer may join.
//   pair   phone → mac, sealed with HKDF(ss ‖ token); the Mac owner confirms a 6-digit code before anything is saved.
//   hs     phone → mac, sealed with the static key and signed by the phone's Ed25519 key; carries a fresh ephemeral key.
//   msg    both ways, sealed with per-connection keys HKDF(ss ‖ DH(e,e')); the nonce is a strict counter.

/// The Mac's long-term keys: login Keychain, this device only, never synced or exported.
enum MobileKeychain {
    static func query(_ account: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.danyalgil.boterm.mobile", kSecAttrAccount as String: account] }
    static func load(_ account: String, make: () -> Data) throws -> Data {
        var result: AnyObject?
        var request = query(account); request[kSecReturnData as String] = true
        if SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data { return data }
        let data = make()
        var item = query(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ControlError.invalid("Não foi possível guardar a chave no Keychain") }
        return data
    }
    static func agreement() throws -> Curve25519.KeyAgreement.PrivateKey {
        try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: load("mac-x25519") { Curve25519.KeyAgreement.PrivateKey().rawRepresentation })
    }
    static func signing() throws -> Curve25519.Signing.PrivateKey {
        try Curve25519.Signing.PrivateKey(rawRepresentation: load("mac-ed25519") { Curve25519.Signing.PrivateKey().rawRepresentation })
    }
}

/// pub: phone X25519 static key; sign: phone Ed25519 key (only the public half ever reaches the Mac); nonce: room derivation.
struct MobileDevice: Codable { var id: String; var room: String; var nonce: String; var pub: String; var sign: String; var name: String; var push: String; var created: String; var platform: String?
    /// Push kinds the owner left on in the phone app; nil (older apps) means all.
    var kinds: [String]? }

enum MobileStore {
    static var file: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Boterm/mobile.json") }
    static func all() -> [MobileDevice] { (try? JSONDecoder().decode([MobileDevice].self, from: Data(contentsOf: file))) ?? [] }
    static func save(_ devices: [MobileDevice]) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder().encode(devices) else { return }
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    /// Names come from the phone: keep letters, digits, spaces and punctuation; drop every control, format and bidi character.
    static func clean(_ text: String, limit: Int) -> String {
        let kept = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !CharacterSet.illegalCharacters.contains($0) && $0.properties.generalCategory != .format }
        return String(String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces).prefix(limit))
    }
}

/// One relay connection: a paired phone, or a pairing still waiting for its QR code to be scanned and confirmed.
@MainActor final class MobileLink {
    var device: MobileDevice?
    let room: String
    private let nonce: Data
    private let mac: Curve25519.KeyAgreement.PrivateKey
    private let signer: Curve25519.Signing.PrivateKey
    private var pairing: (token: Data, expires: Date)?
    private var candidate: MobileDevice?
    private var task: URLSessionWebSocketTask?
    private var closed = false, backoff = 1.0
    private var sendKey: SymmetricKey?, receiveKey: SymmetricKey?
    /// Keys from the newest handshake; they replace the live ones only when the phone's first message decrypts under them,
    /// so a replayed handshake cannot kill a working session.
    private var nextKeys: (send: SymmetricKey, receive: SymmetricKey)?
    private var sent: UInt64 = 0, received: UInt64 = 0
    private var seen: [String: Date] = [:]
    private(set) var peerUp = false
    var confirm: ((MobileDevice, String) -> Void)?
    var paired: ((MobileDevice) -> Void)?
    var request: (@MainActor ([String: Any]) async -> [String: Any]?)?
    var ready: (() -> Void)?
    /// After each handshake the Mac answers (the phone proved its keys); the session starts with the phone's first message.
    var handshook: (() -> Void)?
    var isReady: Bool { sendKey != nil && peerUp }

    init(device: MobileDevice, mac: Curve25519.KeyAgreement.PrivateKey, signer: Curve25519.Signing.PrivateKey) {
        self.device = device; room = device.room; nonce = Data(base64Encoded: device.nonce) ?? Data(); self.mac = mac; self.signer = signer
    }
    init(pairingToken token: Data, mac: Curve25519.KeyAgreement.PrivateKey, signer: Curve25519.Signing.PrivateKey, lifetime: TimeInterval) {
        nonce = MobileCrypto.random(16)
        room = MobileCrypto.room(signingPublic: signer.publicKey.rawRepresentation, nonce: nonce)
        self.mac = mac; self.signer = signer; pairing = (token, Date().addingTimeInterval(lifetime))
    }

    func connect(relay: URL) {
        guard !closed, var parts = URLComponents(url: relay.appendingPathComponent("r/\(room)"), resolvingAgainstBaseURL: false),
              let ts = Optional(Int64(Date().timeIntervalSince1970 * 1000)),
              let signature = try? signer.signature(for: MobileCrypto.macRelayMessage(room: room, ts: ts)) else { return }
        parts.queryItems = [URLQueryItem(name: "role", value: "mac"), URLQueryItem(name: "pub", value: MobileCrypto.b64url(signer.publicKey.rawRepresentation)),
                            URLQueryItem(name: "nonce", value: MobileCrypto.b64url(nonce)), URLQueryItem(name: "ts", value: String(ts)),
                            URLQueryItem(name: "sig", value: MobileCrypto.b64url(signature))]
        guard let url = parts.url else { return }
        let task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = 256 * 1024
        self.task = task; task.resume()
        allow()
        receive(task, relay: relay)
    }

    /// Tells the relay which phone bearer may take the phone slot: the pairing one until confirmed, the device one after.
    private func allow() {
        var hashes: [String] = []
        if let pairing { hashes.append(MobileCrypto.sha256hex(MobileCrypto.pairRelayAuth(token: pairing.token, room: room))) }
        if let device, let pub = Data(base64Encoded: device.pub), let ss = try? staticSecret(pub) {
            hashes.append(MobileCrypto.sha256hex(MobileCrypto.phoneRelayAuth(staticShared: ss, room: room)))
        }
        write(["relay": "allow", "h": hashes])
    }

    func close() { closed = true; task?.cancel(with: .goingAway, reason: nil); task = nil }

    private func receive(_ task: URLSessionWebSocketTask, relay: URL) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === task else { return }
                switch result {
                case .success(.string(let text)):
                    self.backoff = 1
                    await self.handle(text)
                    self.receive(task, relay: relay)
                case .success: self.receive(task, relay: relay)
                case .failure:
                    self.forgetSession()
                    guard !self.closed else { return }
                    let delay = self.backoff; self.backoff = min(self.backoff * 2, 30)
                    try? await Task.sleep(for: .seconds(delay))
                    if self.task === task { self.connect(relay: relay) }
                }
            }
        }
    }

    private func forgetSession() { peerUp = false; sendKey = nil; receiveKey = nil; nextKeys = nil }

    private func staticSecret(_ phone: Data) throws -> Data {
        MobileCrypto.raw(try mac.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: phone)))
    }

    /// Frames sealed with long-term keys carry an integer time (ms) and a random id; both are checked so a recorded frame cannot be replayed.
    private func fresh(_ object: [String: Any]) -> (Int64, String)? {
        guard let time = (object["t"] as? NSNumber)?.int64Value, let id = object["n"] as? String, (16...64).contains(id.count),
              abs(Int64(Date().timeIntervalSince1970 * 1000) - time) < 120_000, seen[id] == nil else { return nil }
        seen = seen.filter { Date().timeIntervalSince($0.value) < 240 }; seen[id] = Date()
        return (time, id)
    }

    var isPairingCandidatePending: Bool { candidate != nil }
    /// Called by the owner's click on the Mac; nothing is stored before it.
    func accept() {
        guard let candidate, device == nil else { return }
        device = candidate; self.candidate = nil
        allow(); paired?(candidate)
    }

    private func handle(_ text: String) async {
        guard text.utf8.count <= 256 * 1024, let frame = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return }
        guard let kind = frame["k"] as? String else {
            if frame["relay"] as? String == "peer" {
                peerUp = frame["up"] as? Bool == true
                if !peerUp { sendKey = nil; receiveKey = nil; nextKeys = nil }
            }
            return
        }
        guard let sealed = frame["c"] as? String else { return }
        switch kind {
        case "pair":
            guard sealed.utf8.count <= 4096, let pairing, device == nil, candidate == nil, Date() < pairing.expires,
                  let pub = (frame["pub"] as? String).flatMap({ Data(base64Encoded: $0) }), pub.count == 32,
                  let ss = try? staticSecret(pub),
                  let (_, body) = try? MobileCrypto.open(sealed, MobileCrypto.key(ss + pairing.token, room: room, "boterm-pair-v1 p2m")),
                  fresh(body) != nil,
                  let sign = (body["s"] as? String).flatMap({ Data(base64Encoded: $0) }), sign.count == 32,
                  (try? Curve25519.Signing.PublicKey(rawRepresentation: sign)) != nil else { return }
            self.pairing = nil // single use, even if the owner refuses
            let name = MobileStore.clean(body["name"] as? String ?? "", limit: 60)
            let device = MobileDevice(id: String(UUID().uuidString.prefix(8)).lowercased(), room: room, nonce: nonce.base64EncodedString(), pub: pub.base64EncodedString(),
                                      sign: sign.base64EncodedString(), name: name.isEmpty ? "Celular" : name, push: "", created: ISO8601DateFormatter().string(from: Date()), platform: nil)
            candidate = device
            confirm?(device, MobileCrypto.sas(staticShared: ss, room: room, phoneSigning: sign))
        case "hs":
            guard sealed.utf8.count <= 4096, let device, let pub = Data(base64Encoded: device.pub), let ss = try? staticSecret(pub),
                  let signKey = Data(base64Encoded: device.sign).flatMap({ try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }),
                  let (_, body) = try? MobileCrypto.open(sealed, MobileCrypto.key(ss, room: room, "boterm-static-v1 p2m")),
                  let e = body["e"] as? String, let theirs = Data(base64Encoded: e), theirs.count == 32,
                  let signature = (body["s"] as? String).flatMap({ Data(base64Encoded: $0) }),
                  let (t, n) = fresh(body),
                  signKey.isValidSignature(signature, for: MobileCrypto.handshakeMessage(room: room, e: e, t: t, n: n)),
                  let peer = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirs) else { return }
            let mine = Curve25519.KeyAgreement.PrivateKey()
            guard let dh = try? mine.sharedSecretFromKeyAgreement(with: peer) else { return }
            let transcript = theirs + mine.publicKey.rawRepresentation
            let ikm = ss + MobileCrypto.raw(dh)
            let reply: [String: Any] = ["e": mine.publicKey.rawRepresentation.base64EncodedString(), "p": e,
                                        "t": Int64(Date().timeIntervalSince1970 * 1000), "n": MobileCrypto.random(16).base64EncodedString()]
            guard let c = try? MobileCrypto.seal(reply, MobileCrypto.key(ss, room: room, "boterm-static-v1 m2p")) else { return }
            nextKeys = (MobileCrypto.key(ikm, room: room, info: Data("boterm-session-v1 m2p".utf8) + transcript),
                        MobileCrypto.key(ikm, room: room, info: Data("boterm-session-v1 p2m".utf8) + transcript))
            write(["k": "hs", "c": c])
            handshook?()
        case "msg":
            let body: [String: Any]
            if let next = nextKeys, let (counter, opened) = try? MobileCrypto.open(sealed, next.receive) {
                sendKey = next.send; receiveKey = next.receive; nextKeys = nil; sent = 0; received = counter; body = opened
            } else if let receiveKey, let (counter, opened) = try? MobileCrypto.open(sealed, receiveKey), counter > received {
                received = counter; body = opened
            } else { return }
            if let reply = await request?(body) { send(reply) }
            if body["type"] as? String == "sync" { ready?() }
        default: return
        }
    }

    func send(_ object: [String: Any]) {
        guard let sendKey, sent < UInt64.max - 1 else { return }
        sent += 1
        guard let c = try? MobileCrypto.seal(object, sendKey, nonce: MobileCrypto.counterNonce(sent)) else { return }
        write(["k": "msg", "c": c])
    }

    /// Asks the relay to wake the phone. Only a kind and a count travel; the relay holds the APNs/FCM credentials and the fixed wording.
    /// Mensageiro messages and approvals always push, because a connected socket does not mean the owner is looking
    /// (iOS keeps it open for a while after the app leaves the screen); terminal attention only while the phone is away.
    func wake(_ kind: String, badge: Int) {
        guard kind != "attention" || !peerUp, let device, !device.push.isEmpty, let platform = device.platform,
              device.kinds?.contains(kind) ?? true else { return }
        write(["relay": "push", "platform": platform, "token": device.push, "kind": kind, "badge": min(max(badge, 0), 999)])
    }

    private func write(_ frame: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: frame), let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    /// The QR code carries the relay, the room, the Mac's public key and the one-time token, never a long-term secret.
    func pairingURL(relay: URL, macName: String) -> String? {
        guard let pairing else { return nil }
        var parts = URLComponents(); parts.scheme = "boterm"; parts.host = "pair"
        parts.queryItems = [URLQueryItem(name: "v", value: "1"), URLQueryItem(name: "r", value: relay.absoluteString), URLQueryItem(name: "room", value: room),
                            URLQueryItem(name: "k", value: MobileCrypto.b64url(mac.publicKey.rawRepresentation)),
                            URLQueryItem(name: "t", value: MobileCrypto.b64url(pairing.token)), URLQueryItem(name: "n", value: String(macName.prefix(40)))]
        return parts.string
    }
}

@MainActor final class MobileBridge {
    static let defaultRelay = "wss://boterm-relay-384669004056.europe-west1.run.app"
    /// A custom relay must still be TLS (local ws:// only for tests on this Mac).
    var relay: URL {
        let custom = UserDefaults.standard.string(forKey: "mobileRelay") ?? ""
        let ok = custom.hasPrefix("wss://") || custom.hasPrefix("ws://127.0.0.1:") || custom.hasPrefix("ws://localhost:")
        return URL(string: ok ? custom : Self.defaultRelay) ?? URL(string: Self.defaultRelay)!
    }
    static let pairingLifetime: TimeInterval = 180
    private(set) var links: [MobileLink] = []
    private var lastState = "", attention: Set<String> = [], pendingAsks: Set<String> = []
    var notes: [[String: Any]] = []
    /// The pairing whose QR is on screen.
    var showing: MobileLink?
    /// Notes since the phone last synced; with the pending approvals it is the app icon's count.
    var unseen = 0
    var request: (@MainActor (MobileDevice, [String: Any]) async -> [String: Any]?)?
    var state: (@MainActor () async -> [String: Any])?
    var macName: String { Host.current().localizedName ?? "Mac" }

    func start() {
        guard let mac = try? MobileKeychain.agreement(), let signer = try? MobileKeychain.signing() else { return }
        for device in MobileStore.all() { open(MobileLink(device: device, mac: mac, signer: signer)) }
    }

    private func open(_ link: MobileLink) {
        link.request = { [weak self, weak link] body in
            guard let self, let link, let device = link.device else { return nil }
            return await self.request?(device, body)
        }
        link.ready = { [weak self, weak link] in Task { await self?.publish(force: true, to: link) } }
        links.append(link); link.connect(relay: relay)
    }

    func beginPairing() throws -> (MobileLink, String) {
        let link = MobileLink(pairingToken: MobileCrypto.random(32), mac: try MobileKeychain.agreement(), signer: try MobileKeychain.signing(), lifetime: Self.pairingLifetime)
        guard let url = link.pairingURL(relay: relay, macName: macName) else { throw ControlError.invalid("QR inválido") }
        open(link)
        return (link, url)
    }

    func cancelPairing(_ link: MobileLink) {
        guard link.device == nil else { return }
        link.close(); links.removeAll { $0 === link }
    }

    func save(_ device: MobileDevice) {
        MobileStore.save(MobileStore.all().filter { $0.id != device.id } + [device])
    }

    func remove(_ id: String) {
        for link in links where link.device?.id == id { link.close() }
        links.removeAll { $0.device?.id == id }
        MobileStore.save(MobileStore.all().filter { $0.id != id })
    }

    func note(_ text: String) {
        notes.append(["text": String(text.prefix(4000)), "time": ISO8601DateFormatter().string(from: Date())])
        if notes.count > 50 { notes.removeFirst() }
        unseen += 1
        links.forEach { $0.wake("note", badge: unseen + pendingAsks.count) }
        Task { await publish() }
    }

    /// Sends state when it changed, and a push (with no content) for new attention or new approvals to phones not looking.
    func publish(force: Bool = false, to only: MobileLink? = nil) async {
        guard !links.isEmpty, let state = await state?() else { return }
        let sessions = state["sessions"] as? [[String: Any]] ?? [], asks = state["asks"] as? [[String: Any]] ?? []
        let nowAttention = Set(sessions.compactMap { ($0["attention"] as? String ?? "").isEmpty ? nil : $0["id"] as? String })
        let nowAsks = Set(asks.compactMap { $0["id"] as? String })
        if !nowAsks.subtracting(pendingAsks).isEmpty { links.forEach { $0.wake("approval", badge: unseen + nowAsks.count) } }
        else if !nowAttention.subtracting(attention).isEmpty { links.forEach { $0.wake("attention", badge: unseen + nowAsks.count) } }
        attention = nowAttention; pendingAsks = nowAsks
        let text = (try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? ""
        guard force || text != lastState else { return }
        lastState = text
        for link in only.map({ [$0] }) ?? links where link.isReady { link.send(state) }
    }

    /// The QR's modules, row by row ("1" dark), without the quiet zone; the page draws them. Level Q leaves room for the mark in the middle.
    static func qrModules(_ text: String) -> (size: Int, bits: String)? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage"); filter.setValue("Q", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage, let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        let dark = { (x: Int, y: Int) in (rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceGray)?.whiteComponent ?? 1) < 0.5 }
        // The generator adds a quiet zone; the first dark pixel on the diagonal is the finder's corner.
        guard let edge = (0..<min(rep.pixelsWide, rep.pixelsHigh)).first(where: { dark($0, $0) }) else { return nil }
        let size = rep.pixelsWide - 2 * edge
        guard size >= 21 else { return nil }
        var bits = ""; bits.reserveCapacity(size * size)
        for y in 0..<size { for x in 0..<size { bits.append(dark(x + edge, y + edge) ? "1" : "0") } }
        return (size, bits)
    }
}

private let mobileKeys: [String: String] = ["enter": "\r", "esc": "\u{1b}", "up": "\u{1b}[A", "down": "\u{1b}[B", "tab": "\t", "ctrl-c": "\u{3}",
                                             "y": "y", "n": "n", "1": "1", "2": "2", "3": "3", "4": "4", "5": "5", "6": "6", "7": "7", "8": "8", "9": "9"]

/// Characters that make text read differently from what runs: controls (except newline and tab), every Unicode format
/// character (bidi, zero-width, tag characters U+E0000–E007F, soft hyphen…) except the zero-width joiner emoji need,
/// line/paragraph separators, and blank fillers that render as nothing. Same list in PROTOCOL.md and both apps.
func mobileHidden(_ c: Unicode.Scalar) -> Bool {
    if c == "\n" || c == "\t" { return false }
    if c.value == 0x200D { return false }
    switch c.properties.generalCategory {
    case .control, .format, .lineSeparator, .paragraphSeparator: return true
    default: return [0x034F, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x180E, 0x2800, 0x3164, 0xFFA0].contains(c.value)
    }
}

@MainActor extension AppDelegate {
    /// The one way screen text is produced for the phone; `key` hashes compare against exactly this string.
    func mobileScreen(_ terminal: TerminalWindow, _ id: String) async throws -> String {
        let text = (try await terminal.web.evaluateJavaScript("window.voz.snapshot(\(TerminalWindow.json(id)))")) as? String ?? ""
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).suffix(12000))
    }

    func connectMobile() {
        mobile.state = { [weak self] in await self?.mobileState() ?? [:] }
        mobile.request = { [weak self] device, body in await self?.mobileRequest(device, body) }
        telegram.mobilePaired = { !MobileStore.all().isEmpty }
        telegram.mobileNote = { [weak self] text in self?.mobile.note(text) }
        mobile.start()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in await self?.mobile.publish() } }
    }

    func mobileState() async -> [String: Any] {
        var sessions: [[String: Any]] = []
        for terminal in terminals {
            let page = (try? await terminal.web.evaluateJavaScript("window.voz.mobileState()")) as? [[String: Any]] ?? []
            for item in page {
                guard let id = item["id"] as? String, let record = terminal.records[id] else { continue }
                sessions.append(["id": id, "name": record.name, "role": record.role, "agent": record.agent, "state": record.state,
                                 "project": item["project"] ?? "", "attention": item["attention"] ?? "", "ended": item["ended"] ?? false, "color": item["color"] ?? ""])
            }
        }
        let asks = telegram.asks.values.filter { $0.status == "pending" }.sorted { $0.created < $1.created }.map { ask -> [String: Any] in
            let name = terminals.lazy.compactMap { $0.records[ask.session]?.name }.first ?? ""
            return ["id": ask.id, "question": ask.text, "scope": ask.scope ?? "", "from": name, "time": ask.created]
        }
        return ["type": "state", "mac": mobile.macName, "sessions": sessions, "asks": asks, "notes": mobile.notes]
    }

    private func mobileSession(_ id: String?) throws -> (TerminalWindow, TerminalWindow.Record) {
        guard let id, let terminal = terminals.first(where: { $0.records[id] != nil }), let record = terminal.records[id] else { throw ControlError.invalid("Terminal não encontrado") }
        return (terminal, record)
    }

    func mobileRequest(_ device: MobileDevice, _ body: [String: Any]) async -> [String: Any]? {
        let req = String((body["req"] as? String ?? "").prefix(64))
        do {
            // A frame the relay held back must not land on whatever the terminal shows now.
            guard let t = (body["t"] as? NSNumber)?.int64Value, abs(Int64(Date().timeIntervalSince1970 * 1000) - t) <= 30_000 else {
                throw ControlError.invalid("Pedido atrasado ou com relógio errado; tente de novo")
            }
            var result: [String: Any] = [:]
            switch body["type"] as? String {
            case "sync": mobile.unseen = 0; return nil
            case "screen":
                let (terminal, _) = try mobileSession(body["id"] as? String)
                result = ["text": try await mobileScreen(terminal, body["id"] as! String)]
            case "send":
                let (terminal, record) = try mobileSession(body["id"] as? String)
                guard record.shell.pid > 0 else { throw ControlError.invalid("Terminal encerrado") }
                guard let text = body["text"] as? String, !text.isEmpty, text.utf8.count <= 15000,
                      !text.unicodeScalars.contains(where: mobileHidden) else { throw ControlError.invalid("Texto inválido (até 15 KB, sem caracteres de controle ou invisíveis)") }
                let submit = body["submit"] as? Bool == true
                _ = try await terminal.web.evaluateJavaScript("window.voz.insert(\(TerminalWindow.json(text)), \(TerminalWindow.json(body["id"] as! String)), \(submit))")
                terminal.status.stringValue = "\(device.name): \(submit ? "enviou" : "escreveu um rascunho") em \(record.name)"
            case "key":
                let (terminal, record) = try mobileSession(body["id"] as? String)
                guard let key = body["key"] as? String, let sequence = mobileKeys[key], record.shell.pid > 0 else { throw ControlError.invalid("Tecla inválida") }
                // The phone says which prompt it was looking at; a key meant for one prompt never answers another.
                let page = (try? await terminal.web.evaluateJavaScript("window.voz.mobileState()")) as? [[String: Any]] ?? []
                let current = page.first { $0["id"] as? String == body["id"] as? String }?["attention"] as? String ?? ""
                guard let expect = body["expect"] as? String, expect == current else { throw ControlError.invalid("O terminal mudou desde que você olhou; confira de novo") }
                // The exact screen the user looked at: a key meant for one prompt never answers another with the same label. Ctrl-C only interrupts.
                if key != "ctrl-c" {
                    let now = MobileCrypto.sha256hex(Data(try await mobileScreen(terminal, body["id"] as! String).utf8))
                    guard body["screen"] as? String == now else { throw ControlError.invalid("A tela mudou desde que você olhou; confira de novo") }
                }
                record.shell.write(sequence)
                terminal.status.stringValue = "\(device.name): tecla \(key) em \(record.name)"
            case "answer":
                guard let id = body["ask"] as? String, let choice = body["choice"] as? String, ["once", "always", "no"].contains(choice) else { throw ControlError.invalid("Resposta inválida") }
                // The answer is bound to the question and scope the phone showed.
                guard let ask = telegram.asks[id], body["hash"] as? String == MobileCrypto.sha256hex(Data((ask.text + "\n" + (ask.scope ?? "")).utf8)) else { throw ControlError.invalid("O pedido mudou; confira de novo") }
                guard telegram.answerFromApp(id, choice: choice, device: device.name) else { throw ControlError.invalid("Pedido já respondido ou desconhecido") }
            case "message":
                guard let text = (body["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), (1...4000).contains(text.count),
                      !text.unicodeScalars.contains(where: mobileHidden) else { throw ControlError.invalid("Mensagem vazia, longa demais ou com caracteres de controle ou invisíveis") }
                var delivered = false
                for terminal in terminals {
                    for (id, record) in terminal.records where record.role == "Mensageiro" { terminal.postOwnerMessage(to: id, text: text, sender: "Celular · \(device.name)"); delivered = true }
                }
                guard delivered else { throw ControlError.invalid("Nenhum Mensageiro aberto no Mac") }
            case "push":
                let platform = body["platform"] as? String ?? ""
                let pattern = platform == "ios" ? #"^[0-9a-f]{64,200}\z"# : platform == "android" ? #"^[A-Za-z0-9_:\-]{20,400}\z"# : #"^\z"#
                guard let token = body["token"] as? String, !token.isEmpty, token.range(of: pattern, options: .regularExpression) != nil,
                      var updated = mobile.links.first(where: { $0.device?.id == device.id })?.device else { throw ControlError.invalid("Token inválido") }
                // Optional: the kinds the owner left on in the app's settings.
                if let kinds = body["kinds"] as? [String] {
                    guard kinds.count <= 3, Set(kinds).isSubset(of: ["attention", "approval", "note"]) else { throw ControlError.invalid("Tipos de aviso inválidos") }
                    updated.kinds = kinds
                }
                updated.push = token; updated.platform = platform; mobile.links.first { $0.device?.id == device.id }?.device = updated; mobile.save(updated)
            case "unpair":
                mobile.remove(device.id); return nil
            default: throw ControlError.invalid("Pedido desconhecido")
            }
            Task { await mobile.publish() }
            return ["type": "result", "req": req, "ok": true].merging(result) { $1 }
        } catch {
            return ["type": "result", "req": req, "ok": false, "error": error.localizedDescription]
        }
    }

    /// The QR shows in the page's own dialog (drawn on the construction grid); the 6-digit check stays a native sheet.
    @objc func pairPhone() {
        guard let terminal = focused ?? terminals.first, terminal.window.attachedSheet == nil else { return }
        let window = terminal.window
        if let open = mobile.showing { mobile.cancelPairing(open) }
        let link: MobileLink, url: String
        do { (link, url) = try mobile.beginPairing() } catch { NSAlert(error: error).beginSheetModal(for: window); return }
        guard let qr = MobileBridge.qrModules(url) else { mobile.cancelPairing(link); return }
        mobile.showing = link
        terminal.js("window.voz.pairing(\(TerminalWindow.json(["size": qr.size, "bits": qr.bits, "seconds": Int(MobileBridge.pairingLifetime)])))")
        link.confirm = { [weak self, weak window, weak terminal] device, code in
            guard let self, let window else { return }
            if self.mobile.showing === link { self.mobile.showing = nil }
            terminal?.js("window.voz.pairingClose()")
            let ask = NSAlert()
            ask.messageText = "Conectar “\(device.name)”?"
            ask.informativeText = "Confira que o celular mostra este código:\n\n\(code.prefix(3)) \(code.suffix(3))\n\nSe o código for diferente, ou se não foi você que leu o QR agora, clique em Recusar."
            ask.addButton(withTitle: "Recusar"); ask.addButton(withTitle: "Conectar")
            ask.buttons.first?.keyEquivalent = "\r"; ask.buttons.last?.keyEquivalent = ""
            ask.beginSheetModal(for: window) { response in
                if response == .alertSecondButtonReturn { link.accept() } else { self.mobile.cancelPairing(link) }
            }
        }
        link.paired = { [weak self, weak window] device in
            guard let self else { return }
            self.mobile.save(device)
            self.terminals.forEach { self.sendMessengerState(to: $0) }
            let done = NSAlert(); done.messageText = "Celular conectado: \(device.name)"
            done.informativeText = "Para desconectar: Boterm → Celulares conectados…"
            if let window { done.beginSheetModal(for: window) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + MobileBridge.pairingLifetime) { [weak self, weak terminal] in
            guard let self, link.device == nil, self.mobile.showing === link else { return }
            self.mobile.showing = nil; self.mobile.cancelPairing(link)
            terminal?.js("window.voz.pairingClose()")
        }
    }

    /// The page closed the QR (Cancelar, Escape or ×).
    func cancelShownPairing() {
        guard let link = mobile.showing else { return }
        mobile.showing = nil
        if !link.isPairingCandidatePending { mobile.cancelPairing(link) }
    }

    @objc func managePhones() {
        let devices = MobileStore.all()
        let alert = NSAlert()
        alert.messageText = "Celulares conectados"
        guard !devices.isEmpty else {
            alert.informativeText = "Nenhum celular conectado. Use Boterm → Conectar celular…"
            alert.runModal(); return
        }
        alert.informativeText = "Desconectar apaga a ligação neste Mac; o celular deixa de ver e de escrever nos terminais."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        for device in devices { popup.addItem(withTitle: "\(device.name) · desde \(device.created.prefix(10))"); popup.lastItem?.representedObject = device.id }
        alert.accessoryView = popup
        alert.addButton(withTitle: "Desconectar"); alert.addButton(withTitle: "Fechar")
        guard alert.runModal() == .alertFirstButtonReturn, let id = popup.selectedItem?.representedObject as? String else { return }
        mobile.remove(id)
    }
}
