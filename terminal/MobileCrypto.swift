import CryptoKit
import Foundation
import Security

// Shared verbatim by the Mac app (Boterm, public) and the iPhone app (boterm-apps, private); keep both copies identical.
// Test vectors: boterm-apps/protocol/vectors.json, produced from this file.
enum MobileCrypto {
    static func raw(_ secret: SharedSecret) -> Data { secret.withUnsafeBytes { Data($0) } }
    static func key(_ ikm: Data, room: String, info: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm), salt: Data(room.utf8), info: info, outputByteCount: 32)
    }
    static func key(_ ikm: Data, room: String, _ info: String) -> SymmetricKey { key(ikm, room: room, info: Data(info.utf8)) }
    static func counterNonce(_ counter: UInt64) -> ChaChaPoly.Nonce {
        var bytes = Data(count: 4); withUnsafeBytes(of: counter.bigEndian) { bytes.append(contentsOf: $0) }
        return try! ChaChaPoly.Nonce(data: bytes)
    }
    static func seal(_ object: [String: Any], _ key: SymmetricKey, nonce: ChaChaPoly.Nonce = ChaChaPoly.Nonce()) throws -> String {
        try ChaChaPoly.seal(JSONSerialization.data(withJSONObject: object), using: key, nonce: nonce).combined.base64EncodedString()
    }
    /// Returns the nonce counter (last 8 bytes) with the decoded object.
    static func open(_ text: String, _ key: SymmetricKey) throws -> (UInt64, [String: Any]) {
        guard let data = Data(base64Encoded: text), data.count >= 28 else { throw CryptoKitError.authenticationFailure }
        let plain = try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: data), using: key)
        guard let object = try JSONSerialization.jsonObject(with: plain) as? [String: Any] else { throw CryptoKitError.authenticationFailure }
        let counter = data.subdata(in: 4..<12).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return (counter, object)
    }
    static func b64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func random(_ count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return data
    }
}

extension MobileCrypto {
    static func bytes(_ key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }
    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
    static func sha256hex(_ data: Data) -> String { hex(Data(SHA256.hash(data: data))) }
    /// The Mac proves room ownership to the relay: room = first 32 hex chars of SHA-256(signing pub ‖ 16-byte nonce).
    static func room(signingPublic: Data, nonce: Data) -> String { String(sha256hex(signingPublic + nonce).prefix(32)) }
    static func macRelayMessage(room: String, ts: Int64) -> Data { Data("boterm-relay-mac-v1|\(room)|\(ts)".utf8) }
    /// Bearer the phone shows the relay; the relay only learns its SHA-256 from the Mac.
    static func phoneRelayAuth(staticShared ss: Data, room: String) -> Data { bytes(key(ss, room: room, "boterm-relay-phone-v1")) }
    static func pairRelayAuth(token: Data, room: String) -> Data { bytes(key(token, room: room, "boterm-relay-pair-v1")) }
    /// What the phone's Ed25519 key signs in every handshake; e and n are the exact base64 strings of the body.
    static func handshakeMessage(room: String, e: String, t: Int64, n: String) -> Data { Data("boterm-hs-v1|\(room)|\(e)|\(t)|\(n)".utf8) }
    /// Six digits shown on both screens while pairing; the Mac owner confirms they match.
    static func sas(staticShared ss: Data, room: String, phoneSigning: Data) -> String {
        let d = bytes(key(ss, room: room, info: Data("boterm-sas-v1".utf8) + phoneSigning))
        let n = d.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return String(format: "%06u", n % 1_000_000)
    }
}
