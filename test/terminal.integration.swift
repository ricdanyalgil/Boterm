import Foundation
import AppKit

private enum VoiceTestError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}

/// A Finder-like file drag, so the native drop path runs without a mouse.
@MainActor private final class FileDrag: NSObject, @MainActor NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    init(_ urls: [URL]) { draggingPasteboard = NSPasteboard(name: .init("VozTTYTestDrag")); draggingPasteboard.clearContents(); draggingPasteboard.writeObjects(urls as [NSURL]) }
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

@MainActor
extension TerminalWindow {
    func testUntil(_ message: String, seconds: Double = 30, _ check: () async throws -> Bool) async throws {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if try await check() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "VozTTYTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    func screenText() async throws -> String {
        (try await web.evaluateJavaScript("window.voz.screen()")) as? String ?? ""
    }

    func runIntegrationTest() async {
        let env = ProcessInfo.processInfo.environment
        guard let destination = env["VOZ_TEST_RESULT"] else { return }
        let mode = env["VOZ_TEST_MODE"] ?? "inspect"
        var result: [String: Any] = ["passed": false, "mode": mode, "terminal": "Boterm native", "automaticEnter": false]
        var inputs: [String] = []
        inputReceived = { inputs.append($0) }
        func save() { try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: destination)) }
        save()
        do {
            try await testUntil("The terminal frontend did not start.") { self.shell.pid > 0 }
            try await Task.sleep(for: .seconds(6))
            var before = try await screenText()
            if let path = env["VOZ_TEST_SCREEN"] { try before.write(toFile: path, atomically: true, encoding: .utf8) }
            result["frontendReady"] = true
            result["childPID"] = shell.pid
            if mode == "customize", let fixture = env["VOZ_TEST_UI_SCRIPT"] {
                let script = try String(contentsOfFile: fixture, encoding: .utf8)
                result["checks"] = try await web.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
                var sizes: [[String: Any]] = []
                for size in [NSSize(width: 620, height: 380), NSSize(width: 800, height: 600), NSSize(width: 1440, height: 900), NSSize(width: 1120, height: 720)] {
                    window.setContentSize(size)
                    try await Task.sleep(for: .milliseconds(100))
                    js("window.voz.fit()")
                    try await testUntil("Customized workspace overflows") {
                        try await self.web.evaluateJavaScript("document.body.scrollWidth <= innerWidth && [...sessions.values()].filter(s => !s.host.hidden).every(s => { const box = s.host.querySelector('.terminal-content').getBoundingClientRect(); const screen = s.term.element.querySelector('.xterm-screen').getBoundingClientRect(); return screen.right <= box.right + 1 && screen.bottom <= box.bottom + 1; })") as? Bool == true
                    }
                    sizes.append(["width": size.width, "height": size.height, "fits": true])
                }
                result["sizes"] = sizes
                if let path = env["VOZ_TEST_SNAPSHOT"] {
                    try await Task.sleep(for: .milliseconds(300))
                    let image = try await web.takeSnapshot(configuration: nil)
                    guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { throw VoiceTestError.message("Snapshot failed") }
                    try png.write(to: URL(fileURLWithPath: path))
                }
                result["passed"] = true; save(); closeForTest(); return
            }
            if mode == "agent-launch" {
                try await web.evaluateJavaScript("document.getElementById('agent-kind').value = 'codex'; document.getElementById('launch-agent').click();")
                try await testUntil("Agent launcher did not start Codex", seconds: 30) {
                    self.records.values.contains { $0.agent == "codex" && $0.state == "running" && $0.shell.pid > 0 }
                }
                let sidebar = try await web.evaluateJavaScript("document.getElementById('sessions').textContent") as? String ?? ""
                guard sidebar.contains("Codex"), sidebar.contains("Em execução") else { throw VoiceTestError.message("Agent name/state badge missing") }
                result["nativeAgentLaunch"] = true; result["visibleAgentIdentity"] = true; result["passed"] = true
                save(); closeForTest(); return
            }
            if mode == "workspace" {
                let original = activeSessionID
                let originalPID = shell.pid
                let second = try await web.evaluateJavaScript("window.voz.create('Reviewer')") as! String
                try await testUntil("Second shell did not start") { self.records[second]?.shell.pid ?? 0 > 0 }
                guard records[original]?.shell.pid == originalPID else { throw VoiceTestError.message("Switching sessions restarted the original process") }
                let workspace = records[original]!.workspace
                _ = try postMessage(from: original, to: second, text: "Review this task")
                _ = try postMessage(from: second, to: original, text: "Review complete")
                guard messages.count == 2 else { throw VoiceTestError.message("Peer messages missing") }
                let other = try await web.evaluateJavaScript("window.voz.newWorkspace('Private project')") as! String
                try await testUntil("Other project did not start") { self.records.values.contains { $0.workspace == other && $0.shell.pid > 0 } }
                let privateID = records.first { $0.value.workspace == other }!.key
                do { _ = try postMessage(from: original, to: privateID, text: "must fail"); throw VoiceTestError.message("Cross-project message allowed") }
                catch is ControlError { }
                try await web.evaluateJavaScript("window.voz.activate(\(Self.json(original)))")
                let keys = try await web.evaluateJavaScript("terminalShortcut({type:'keydown',ctrlKey:true,code:'KeyC'}, false) === null && terminalShortcut({type:'keydown',ctrlKey:true,code:'KeyC'}, true) === 'copy'") as? Bool == true
                guard keys else { throw VoiceTestError.message("Ctrl+C semantics changed") }
                let themeOK = try await web.evaluateJavaScript("term.options.theme.background === '#0F111A' && term.options.theme.green === '#C3E88D' && typeof accents === 'undefined'") as? Bool == true
                guard themeOK else { throw VoiceTestError.message("Ocean palette or ANSI preservation incorrect") }
                let data = try JSONSerialization.data(withJSONObject: ["from":original,"workspace":workspace,"peerPID":originalPID,"command":"list"])
                guard let app = NSApplication.shared.delegate as? AppDelegate else { throw VoiceTestError.message("Missing app delegate") }
                let listed = try JSONSerialization.jsonObject(with: await app.controlRequest(data)) as! [String:Any]
                guard (listed["result"] as? [[String:Any]])?.count == 2 else { throw VoiceTestError.message("Session list crossed workspace boundary") }
                records[second]?.shell.write("\"$BOTERM_CLI\" message \(original) 'CLI peer request'\r")
                try await testUntil("CLI socket roundtrip timed out") { self.messages.last?["text"] as? String == "CLI peer request" }
                let submitRequest = try JSONSerialization.data(withJSONObject: ["from": original, "workspace": workspace, "peerPID": originalPID, "command": "send", "target": second, "text": "printf BOTERM_EXECUTED", "submit": true])
                let submitted = try JSONSerialization.jsonObject(with: await app.controlRequest(submitRequest)) as! [String: Any]
                guard submitted["error"] == nil else { throw VoiceTestError.message("Explicit submission failed") }
                try await testUntil("Explicit Enter arrived before the pasted command") {
                    let screen = try await self.web.evaluateJavaScript("window.voz.snapshot(\(Self.json(second)))") as? String ?? ""
                    return screen.components(separatedBy: "\n").contains(where: { $0.hasPrefix("BOTERM_EXECUTED") })
                }
                let peerRead = try JSONSerialization.data(withJSONObject: ["from": original, "workspace": workspace, "peerPID": originalPID, "command": "read", "target": second])
                let peerOutput = try JSONSerialization.jsonObject(with: await app.controlRequest(peerRead)) as! [String: Any]
                guard (peerOutput["result"] as? String)?.contains("BOTERM_EXECUTED") == true else { throw VoiceTestError.message("Peer terminal output could not be read") }
                result["peerOutputRead"] = true
                let privateRead = try JSONSerialization.data(withJSONObject: ["from": original, "workspace": workspace, "peerPID": originalPID, "command": "read", "target": privateID])
                let rejectedRead = try JSONSerialization.jsonObject(with: await app.controlRequest(privateRead)) as! [String: Any]
                guard rejectedRead["error"] != nil else { throw VoiceTestError.message("Cross-workspace read allowed") }
                inputs.removeAll()
                // Verify the actual native clipboard while preserving every original pasteboard type.
                let board = NSPasteboard.general
                let preserved = board.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } } ?? []
                defer {
                    board.clearContents()
                    let items = preserved.map { values in let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item }
                    board.writeObjects(items)
                }
                try await web.evaluateJavaScript("term.write('\\r\\nBOTERM_COPY_TEST', () => term.selectAll());")
                try await Task.sleep(for: .milliseconds(200))
                try await web.evaluateJavaScript("window.voz.copy()")
                try await testUntil("Native copy did not reach clipboard") { board.string(forType: .string)?.contains("BOTERM_COPY_TEST") == true }
                board.clearContents(); board.setString("BOTERM_DRAFT", forType: .string)
                try await web.evaluateJavaScript("term.clearSelection(); document.getElementById('paste-text').click();")
                try await testUntil("Paste did not reach PTY") { inputs.joined().contains("BOTERM_DRAFT") }
                guard !inputs.joined().contains("\r"), !inputs.joined().contains("\n") else { throw VoiceTestError.message("Paste submitted input") }
                voiceSessionID = original
                try await web.evaluateJavaScript("window.voz.activate(\(Self.json(second)))")
                dictation.completed?("BOTERM_PINNED_DICTATION")
                try await testUntil("Dictation did not return to its original terminal") {
                    (try await self.web.evaluateJavaScript("window.voz.snapshot(\(Self.json(original)))") as? String ?? "").contains("BOTERM_PINNED_DICTATION")
                }
                let wrongSession = try await web.evaluateJavaScript("window.voz.snapshot(\(Self.json(second)))") as? String ?? ""
                guard !wrongSession.contains("BOTERM_PINNED_DICTATION") else { throw VoiceTestError.message("Dictation crossed terminals") }
                try await web.evaluateJavaScript("window.voz.activate(\(Self.json(original)))")
                result["dictationPinnedToOrigin"] = true
                records[original]?.agent = "codex"; records[original]?.state = "running"; records[original]?.agentPID = Int32.max
                app.refreshAgentStates()
                guard records[original]?.state == "idle" else { throw VoiceTestError.message("A stopped agent remained marked running") }
                records[original]?.agent = ""
                try await web.evaluateJavaScript("window.voz.agent(\(Self.json(original)), '', 'idle')")
                result["agentStateClearsAfterExit"] = true
                try await web.evaluateJavaScript("split = true; fitVisible();")
                try await Task.sleep(for: .milliseconds(200))
                try await web.evaluateJavaScript("(() => { const r = sessions.get(\(Self.json(second))).host.getBoundingClientRect(); window.voz.drop(['/tmp/BOTERM_DROP_TARGET.txt'], r.x + r.width / 2, r.y + r.height / 2); })()")
                try await testUntil("Drop did not reach the pane under the pointer") {
                    (try await self.web.evaluateJavaScript("window.voz.snapshot(\(Self.json(second))).replace(/\\n/g, '')") as? String ?? "").contains("BOTERM_DROP_TARGET")
                }
                try await web.evaluateJavaScript("window.voz.activate(\(Self.json(original)))")
                result["dropTargetsPointerPane"] = true
                result["tabsKeepProcess"] = true; result["workspaceIsolation"] = true; result["peerMessages"] = true
                result["nativeClipboard"] = true; result["pasteWithoutEnter"] = true; result["cliSocket"] = true; result["oceanANSI"] = true
                result["explicitSubmitOrder"] = true
                if let screenPath = env["VOZ_TEST_WINDOW_SCREEN"] {
                    try await web.evaluateJavaScript("document.getElementById('team').open = true; split = true; fitVisible();")
                    try await Task.sleep(for: .milliseconds(400))
                    let image = try await web.takeSnapshot(configuration: nil)
                    if let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!), let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: URL(fileURLWithPath: screenPath)) }
                }
                result["passed"] = true
                if env["VOZ_TEST_KEEP_OPEN"] == "1" { result["socket"] = controlPath; result["workspace"] = workspace; result["session"] = original; result["peer"] = second }
                save()
                if let command = env["VOZ_TEST_CONTROL_COMMAND"] {
                    let runner = try await web.evaluateJavaScript("window.voz.create('Control regression')") as! String
                    try await testUntil("Control runner did not start") { self.records[runner]?.shell.pid ?? 0 > 0 }
                    try await Task.sleep(for: .seconds(1))
                    records[runner]?.shell.write(command + "\r")
                }
                if env["VOZ_TEST_KEEP_OPEN"] != "1" { closeForTest() }; return
            }
            if mode == "voice-controls" {
                var transcript: String?
                var failure: String?
                var readings: [(Double, Double)] = []
                let deliver = dictation.completed
                dictation.completed = { text in transcript = text; deliver?(text) }
                dictation.failed = { failure = $0 }
                let meter = dictation.metered
                dictation.metered = { level, seconds in readings.append((level, seconds)); meter?(level, seconds) }
                dictation.start(language: "pt-BR")
                try await testUntil("Microphone did not start: \(failure ?? "no error")", seconds: 90) { self.dictation.state == .recording || failure != nil }
                guard failure == nil else { throw VoiceTestError.message(failure!) }
                func speak(_ text: String) async throws {
                    let voice = Process()
                    voice.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                    voice.arguments = ["-v", "Luciana (Português (Brasil))", text]
                    try voice.run()
                    try await self.testUntil("Speech playback timed out.") { !voice.isRunning }
                    guard voice.terminationStatus == 0 else { throw VoiceTestError.message("Speech playback failed.") }
                }
                try await speak("Testando os controles de voz. Guarde esta primeira frase.")
                try await testUntil("No audio meter events arrived.") { readings.count > 5 }
                let waveMoved = try await web.evaluateJavaScript("voiceSamples.length > 5 && voiceSamples.some(sample => sample.level > 0.05) && document.getElementById('voice-envelope').getAttribute('d').length > 80") as? Bool == true
                try await web.evaluateJavaScript("document.getElementById('voice-pause').click()")
                try await testUntil("Pause was not acknowledged.") { self.dictation.state == .paused }
                let countAtPause = readings.count
                let pauseUI = try await web.evaluateJavaScript("document.getElementById('voice-panel').dataset.state === 'paused' && document.getElementById('voice-pause').getAttribute('aria-pressed') === 'true' && voiceSamples.length > 5 && voiceSamples.at(-1).level === 0 && voicePauses.length === 1 && voicePauses[0].end === undefined") as? Bool == true
                try await speak("Esta frase pausada deve ficar fora do texto.")
                guard readings.count == countAtPause, pauseUI else { throw VoiceTestError.message("Paused audio metering or UI is incorrect.") }
                try await web.evaluateJavaScript("document.getElementById('voice-pause').click()")
                try await testUntil("Resume was not acknowledged.") { self.dictation.state == .recording }
                try await speak("Agora continue a gravação. Guarde esta frase final.")
                try await web.evaluateJavaScript("document.getElementById('voice-pause').click()")
                try await testUntil("Second pause was not acknowledged.") { self.dictation.state == .paused }
                try await web.evaluateJavaScript("document.getElementById('voice-stop').click()")
                try await testUntil("Transcript did not arrive: \(failure ?? "no error")", seconds: 65) { transcript != nil || failure != nil }
                guard let transcript, failure == nil else { throw VoiceTestError.message(failure ?? "No transcript") }
                try await testUntil("Transcript was not inserted.") { !inputs.isEmpty }
                let sent = inputs.joined().replacingOccurrences(of: "\u{1b}[200~", with: "").replacingOccurrences(of: "\u{1b}[201~", with: "")
                guard sent == promptText(transcript), !sent.contains("\n"), !sent.contains("\r"), !transcript.lowercased().contains("frase pausada"), transcript.lowercased().contains("primeira frase"), transcript.lowercased().contains("frase final"), waveMoved else { throw VoiceTestError.message("Pause preservation, meter or draft transport failed.") }
                result["meterEvents"] = readings.count
                result["continuousHistoryReactsToAudio"] = waveMoved
                result["pauseStopsMetering"] = true
                result["pausedSpeechExcluded"] = true
                result["beforeAndAfterPausePreserved"] = true
                result["stopWhilePaused"] = true
                result["transportMatches"] = true
                result["passed"] = true
                save()
                if env["VOZ_TEST_KEEP_OPEN"] != "1" { closeForTest() }
                return
            }
            if mode == "layout" {
                let voiceStates = try await web.evaluateJavaScript("(() => { const states = ['idle', 'preparing', 'recording', 'pausing', 'paused', 'resuming', 'stopping']; return states.every(state => { window.voz.state(state); const panel = document.getElementById('voice-panel'); const enabled = ['recording', 'paused'].includes(state); return panel.hidden === (state === 'idle') && document.getElementById('voice-stop').disabled === !enabled && document.getElementById('voice-pause').disabled === !enabled && document.body.dataset.dictating === String(state !== 'idle'); }); })()") as? Bool == true
                guard voiceStates else { throw VoiceTestError.message("Voice controls do not match the recording lifecycle.") }
                guard web.frame.maxY >= window.contentView!.bounds.height - 1,
                      status.frame.height > 0,
                      try await web.evaluateJavaScript("document.body.firstElementChild.id === 'workspaces' && document.getElementById('terminal').compareDocumentPosition(document.getElementById('voice-panel')) === Node.DOCUMENT_POSITION_FOLLOWING") as? Bool == true else {
                    throw VoiceTestError.message("Projects must lead the window and dictation must follow the terminal.")
                }
                result["projectsFirst"] = true
                result["voiceStateControls"] = true
                let originalLanguage = language.indexOfSelectedItem
                var languageCodes: [String] = []
                for index in 0..<language.numberOfItems {
                    language.selectItem(at: index)
                    languageCodes.append(language.selectedItem?.representedObject as? String ?? "")
                }
                language.selectItem(at: originalLanguage)
                guard languageCodes == ["pt-BR", "pt-PT", "en-US"] else {
                    throw NSError(domain: "VozTTYTest", code: 7, userInfo: [NSLocalizedDescriptionKey: "Language labels no longer map to the speech engine identifiers."])
                }
                result["languageCodes"] = languageCodes
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
                var sizes: [[String: Any]] = []
                for size in [NSSize(width: 1120, height: 720), NSSize(width: 620, height: 380), NSSize(width: 800, height: 600), NSSize(width: 1440, height: 900), NSSize(width: 1120, height: 720)] {
                    window.setContentSize(size)
                    try await web.evaluateJavaScript("(() => { window.voz.state('recording'); const now = performance.now(); voiceSamples = Array.from({length: 180}, (_, i) => ({at: now - 18000 + i * 100, level: i > 90 && i < 120 ? 0 : Math.abs(Math.sin(i * .7)) * (.3 + .6 * Math.abs(Math.sin(i * .09)))})); voicePauses = [{start: now - 9000, end: now - 6000}]; drawVoiceWave(now); })()")
                    var metrics: [String: Any] = [:]
                    do {
                        try await testUntil("Terminal grid extends beyond its content area.", seconds: 4) {
                            metrics = try await self.web.evaluateJavaScript("(() => { const box = term.element.parentElement.getBoundingClientRect(); const grid = term.element.querySelector('.xterm-screen').getBoundingClientRect(); const panel = document.getElementById('voice-panel').getBoundingClientRect(); const expected = fit.proposeDimensions(); return {width: innerWidth, height: innerHeight, columns: term.cols, rows: term.rows, rightOverflow: Math.max(0, grid.right - box.right), bottomOverflow: Math.max(0, grid.bottom - box.bottom), fits: term.cols === expected.cols && term.rows === expected.rows && grid.right <= box.right + 1 && grid.bottom <= box.bottom + 1 && panel.top >= box.bottom - 1 && document.body.scrollWidth <= innerWidth}; })()") as? [String: Any] ?? [:]
                            return metrics["fits"] as? Bool == true
                        }
                    } catch {
                        sizes.append(metrics); result["sizes"] = sizes
                        throw error
                    }
                    sizes.append(metrics)
                    if let directory = env["VOZ_TEST_LAYOUT_SCREENS"] {
                        let image = try await web.takeSnapshot(configuration: nil)
                        if let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!), let png = bitmap.representation(using: .png, properties: [:]) {
                            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("layout-\(Int(size.width)).png"))
                        }
                    }
                }
                result["sizes"] = sizes
                let pauseHistory = try await web.evaluateJavaScript("document.querySelector('#voice-pauses rect') !== null && voiceSamples.length > 100") as? Bool == true
                guard pauseHistory else { throw VoiceTestError.message("The continuous waveform lost its voice or pause history.") }
                result["pauseHistoryRendered"] = true
                if env["VOZ_TEST_KEEP_OPEN"] == "1" {
                    window.title = "Boterm — Synthetic voice history preview"
                    try await web.evaluateJavaScript("cancelAnimationFrame(waveFrame); waveFrame = undefined")
                    result["passed"] = true
                    save(); return
                }
                try await web.evaluateJavaScript("window.voz.state('idle')")
                guard try await web.evaluateJavaScript("voiceSamples.length === 0 && voicePauses.length === 0 && waveFrame === undefined") as? Bool == true else { throw VoiceTestError.message("Voice history was retained after completion.") }
                result["passed"] = true
                save(); closeForTest(); return
            }
            if mode == "drop" {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("voztty-drop-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: folder) }
                let files = ["Câmera térmica (spec).pdf", "foto 1.png", "nota de voz.m4a"].map { folder.appendingPathComponent($0) }
                for file in files { try Data().write(to: file) }
                let drag = FileDrag(files)
                guard web.draggingEntered(drag) == .copy, web.performDragOperation(drag) else { throw VoiceTestError.message("The terminal refused a Finder file drop.") }
                web.concludeDragOperation(drag)
                try await testUntil("Dropped paths did not reach the PTY.", seconds: 5) { !inputs.isEmpty }
                let sent = inputs.joined().replacingOccurrences(of: "\u{1b}[200~", with: "").replacingOccurrences(of: "\u{1b}[201~", with: "")
                let expected = files.map { $0.path.replacingOccurrences(of: " ", with: "\\ ").replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)") }.joined(separator: " ") + " "
                guard sent == expected, !sent.contains("\r"), !sent.contains("\n") else { throw VoiceTestError.message("Dropped paths were \(sent), expected \(expected).") }
                result["droppedPaths"] = sent
                result["passed"] = true
                save(); closeForTest(); return
            }
            if mode == "snapshot", let path = env["VOZ_TEST_SNAPSHOT"] {
                // Visual check of colours: photographs the terminal page, no Screen Recording grant needed.
                let image = try await web.takeSnapshot(configuration: nil)
                guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { throw VoiceTestError.message("Snapshot failed.") }
                try png.write(to: URL(fileURLWithPath: path))
                result["passed"] = true; save(); closeForTest(); return
            }
            if mode == "inspect" { result["passed"] = true; save(); closeForTest(); return }
            if env["VOZ_TEST_TRUST_DISPOSABLE"] == "1", before.contains("Accessing workspace:"), before.contains("Yes, I trust this folder") {
                let cwd = FileManager.default.currentDirectoryPath
                let entries = try FileManager.default.contentsOfDirectory(atPath: cwd)
                guard (cwd.hasPrefix("/tmp/voztty-workspace.") || cwd.hasPrefix("/private/tmp/voztty-workspace.")), entries.isEmpty else {
                    throw NSError(domain: "VozTTYTest", code: 5, userInfo: [NSLocalizedDescriptionKey: "Refusing to trust a non-empty or non-test workspace."])
                }
                shell.write("\u{1b}[B\r")
                result["disposableWorkspaceSetup"] = true
                try await Task.sleep(for: .seconds(5))
                before = try await screenText()
            }
            if before.contains("Do you trust the files in this folder?"), before.contains("Don't trust") {
                // Stay untrusted: testing a draft needs no project hooks, skills or file access.
                shell.write("\u{1b}[B\u{1b}[B\r")
                result["untrustedWorkspaceUsed"] = true
                try await Task.sleep(for: .seconds(6))
                before = try await screenText()
            }
            if let path = env["VOZ_TEST_SCREEN"] { try before.write(toFile: path, atomically: true, encoding: .utf8) }
            if before.contains("Update available"), before.contains("esc skip") {
                shell.write("\u{1b}")
                try await Task.sleep(for: .seconds(3))
                before = try await screenText()
            }
            guard let ready = env["VOZ_TEST_READY"], before.range(of: ready, options: .regularExpression) != nil else {
                throw NSError(domain: "VozTTYTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "CLI has not reached the expected input prompt. See the local screen capture."])
            }
            let prefix = "VozTTY test: "
            try await web.evaluateJavaScript("window.voz.insert(\(Self.json(prefix)))")
            try await Task.sleep(for: .milliseconds(300))
            let countBefore = inputs.count
            let start = Date()
            var transcript = ""
            if mode == "long-microphone" {
                guard let phrasePath = env["VOZ_TEST_PHRASE"], let outputPath = env["VOZ_TEST_TRANSCRIPT"] else { throw CocoaError(.fileNoSuchFile) }
                let phrase = try String(contentsOfFile: phrasePath, encoding: .utf8)
                var delivered: String?
                inserted = { delivered = $0 }
                toggleVoice()
                try await testUntil("Microphone did not start. Check the macOS permission prompt.", seconds: 90) { self.dictation.state == .recording }
                result["microphoneReady"] = true; save()
                try await Task.sleep(for: .seconds(2))
                let voice = Process()
                voice.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                voice.arguments = ["-v", "Luciana (Português (Brasil))", "-r", "170", phrase]
                voice.standardOutput = FileHandle.nullDevice
                voice.standardError = FileHandle.nullDevice
                try voice.run()
                try await testUntil("Test phrase playback timed out.", seconds: 180) { !voice.isRunning }
                guard voice.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
                try await Task.sleep(for: .milliseconds(800))
                result["recordingSeconds"] = Date().timeIntervalSince(start)
                toggleVoice()
                try await testUntil("Long transcript did not arrive.", seconds: 65) { delivered != nil }
                result["audioSeconds"] = dictation.audioSeconds
                result["captureSeconds"] = dictation.captureSeconds
                transcript = delivered!
                let sourceWords = phrase.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                let outputWords = transcript.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                result["referenceWords"] = sourceWords.count
                result["openingPreserved"] = Array(sourceWords.prefix(6)) == Array(outputWords.prefix(6))
                result["closingPreserved"] = Array(sourceWords.suffix(6)) == Array(outputWords.suffix(6))
                try transcript.write(toFile: outputPath, atomically: true, encoding: .utf8)
            } else {
                guard let path = env["VOZ_TEST_TRANSCRIPT"] else { throw CocoaError(.fileNoSuchFile) }
                transcript = try String(contentsOfFile: path, encoding: .utf8)
                try await web.evaluateJavaScript("window.voz.insert(\(Self.json(transcript)))")
            }
            try await testUntil("Transcript did not reach the PTY.") { inputs.count > countBefore }
            try await Task.sleep(for: .seconds(3))
            let sent = inputs.dropFirst(countBefore).joined().replacingOccurrences(of: "\u{1b}[200~", with: "").replacingOccurrences(of: "\u{1b}[201~", with: "")
            guard sent == transcript, !sent.contains(where: { $0 == "\r" || $0 == "\n" || $0 == "\u{1b}" }) else {
                throw NSError(domain: "VozTTYTest", code: 3, userInfo: [NSLocalizedDescriptionKey: "PTY input differs from the transcript or includes a terminal control."])
            }
            let screen = try await screenText()
            if let path = env["VOZ_TEST_SCREEN"] { try screen.write(toFile: path, atomically: true, encoding: .utf8) }
            let compact = screen.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            let beginning = transcript.split(separator: " ").prefix(5).joined(separator: " ")
            let ending = transcript.split(separator: " ").suffix(5).joined(separator: " ")
            result["prefixVisible"] = compact.contains(prefix.trimmingCharacters(in: .whitespaces))
            result["beginningVisible"] = compact.contains(beginning)
            result["endingVisible"] = compact.contains(ending)
            result["pasteIndicator"] = screen.range(of: "(?i)pasted|paste|colad", options: .regularExpression) != nil
            result["characters"] = transcript.count
            result["words"] = transcript.split(whereSeparator: { $0.isWhitespace }).count
            result["transportMatches"] = true
            result["childAliveAfterDraft"] = shell.pid > 0
            result["automaticEnter"] = false
            guard shell.pid > 0, (result["prefixVisible"] as? Bool == true), (result["endingVisible"] as? Bool == true || result["pasteIndicator"] as? Bool == true) else {
                throw NSError(domain: "VozTTYTest", code: 4, userInfo: [NSLocalizedDescriptionKey: "The CLI draft is not visibly confirmed. Inspect the local screen capture."])
            }
            if mode == "cli" {
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
                let selectionPreserved = try await web.evaluateJavaScript("(() => { const row = term.buffer.active.baseY; const text = term.buffer.active.getLine(row).translateToString(true); term.select(0, row, term.cols); const selected = term.getSelection(); term.clearSelection(); return selected.trimEnd() === text.trimEnd(); })()") as? Bool == true
                result["selectionPreserved"] = selectionPreserved
                guard selectionPreserved else { throw NSError(domain: "VozTTYTest", code: 6, userInfo: [NSLocalizedDescriptionKey: "Accented text selection changed the terminal text."]) }
            }
            result["insertionPassed"] = true
            result["passed"] = mode != "long-microphone" || (result["openingPreserved"] as? Bool == true && result["closingPreserved"] as? Bool == true)
        } catch { dictation.cancel(); result["error"] = error.localizedDescription }
        save()
        if env["VOZ_TEST_KEEP_OPEN"] != "1" { closeForTest() }
    }
}
