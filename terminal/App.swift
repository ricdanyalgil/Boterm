import AppKit
import WebKit

/// Accepts files dragged from Finder and hands their paths to the terminal; everything else keeps WebKit's behaviour.
final class DropWebView: WKWebView {
    var droppedFiles: (([String], NSPoint) -> Void)?
    private func files(_ info: any NSDraggingInfo) -> [String] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []).map(\.path)
    }
    override func draggingEntered(_ info: any NSDraggingInfo) -> NSDragOperation { files(info).isEmpty ? super.draggingEntered(info) : .copy }
    override func draggingUpdated(_ info: any NSDraggingInfo) -> NSDragOperation { files(info).isEmpty ? super.draggingUpdated(info) : .copy }
    override func prepareForDragOperation(_ info: any NSDraggingInfo) -> Bool { files(info).isEmpty ? super.prepareForDragOperation(info) : true }
    override func performDragOperation(_ info: any NSDraggingInfo) -> Bool {
        let paths = files(info)
        guard !paths.isEmpty else { return super.performDragOperation(info) }
        droppedFiles?(paths, convert(info.draggingLocation, from: nil))
        return true
    }
    override func concludeDragOperation(_ info: (any NSDraggingInfo)?) { if let info, !files(info).isEmpty { return }; super.concludeDragOperation(info) }
}

@MainActor
final class TerminalWindow: NSObject, WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate {
    let window: NSWindow
    let web: DropWebView
    private let firstShell = ShellSession()
    var shell: ShellSession { records[activeSessionID]?.shell ?? firstShell }
    struct Record { let shell: ShellSession; let workspace: String; var name: String; var agent = ""; var state = "idle"; var agentPID: Int32 = 0; var role = "" }
    var records: [String: Record] = [:]
    var activeSessionID = ""
    var voiceSessionID = ""
    var messages: [[String: Any]] = []
    var controlPath = ""
    private var rootLoaded = false
    private let theme = TerminalTheme.load()
    let dictation = TerminalDictation()
    let status = NSTextField(labelWithString: "Speak instead of typing · ⌃⌥V to start")
    let microphone = NSButton()
    let language = NSPopUpButton()
    let you = NSTextField(labelWithString: "")
    let assistant = NSTextField(labelWithString: "")
    let shortcuts = NSTextField(labelWithString: "")
    private var launched = false
    private(set) var allowClose = false
    var confirmingClose = false
    /// Only the first window runs the command given after `--`; windows opened later start a login shell.
    private let primary: Bool
    private let initialDirectory: String?
    private var recoveredTranscripts: [NSWindow] = []
    var didLoad: (() -> Void)?
    var inserted: ((String) -> Void)?
    var inputReceived: ((String) -> Void)?
    var closed: (() -> Void)?

    init(primary: Bool = true, directory: String? = nil) {
        self.primary = primary
        self.initialDirectory = directory
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        if let directory {
            config.userContentController.addUserScript(WKUserScript(source: "window.botermInitialDirectory = \(Self.json(directory));", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        web = DropWebView(frame: .zero, configuration: config)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Boterm"
        window.minSize = NSSize(width: 620, height: 380)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(srgbRed: 9/255, green: 11/255, blue: 16/255, alpha: 1)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        web.underPageBackgroundColor = window.backgroundColor
        web.navigationDelegate = self
        web.configuration.userContentController.add(self, name: "terminal")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let savedLanguage = UserDefaults.standard.string(forKey: "language") ?? "pt-BR"
        for code in ["pt-BR", "pt-PT", "en-US"] {
            language.addItem(withTitle: code)
            language.lastItem?.representedObject = code
            if code == savedLanguage { language.select(language.lastItem) }
        }
        language.setAccessibilityLabel("Dictation language")
        language.target = self
        language.action = #selector(changeLanguage)
        microphone.image = NSImage(systemSymbolName: "mic", accessibilityDescription: nil)
        microphone.imagePosition = .imageLeading
        microphone.bezelStyle = .rounded
        microphone.contentTintColor = NSColor(srgbRed: 169/255, green: 210/255, blue: 1, alpha: 1)
        microphone.setContentCompressionResistancePriority(.required, for: .horizontal)
        microphone.target = self
        microphone.action = #selector(toggleVoice)
        let spacer = NSView()
        let bar = NSStackView(views: [status, spacer, language, microphone])
        bar.orientation = .horizontal
        bar.spacing = 12
        you.textColor = NSColor(srgbRed: 169/255, green: 210/255, blue: 1, alpha: 1)
        assistant.textColor = .labelColor
        shortcuts.textColor = .secondaryLabelColor
        for label in [you, assistant, shortcuts] { label.font = .systemFont(ofSize: 11) }
        let footer = NSStackView(views: [you, assistant, NSView(), shortcuts])
        footer.orientation = .horizontal
        footer.spacing = 16
        let root = NSView()
        window.contentView = root
        for view in [bar, web, footer] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: root.topAnchor), web.leadingAnchor.constraint(equalTo: root.leadingAnchor), web.trailingAnchor.constraint(equalTo: root.trailingAnchor), web.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -4),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), bar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16), bar.heightAnchor.constraint(equalToConstant: 32),
            footer.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 4), footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16), footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8)
        ])
        applyLanguage()
        web.registerForDraggedTypes(web.registeredDraggedTypes + [.fileURL])
        web.droppedFiles = { [weak self] paths, point in
            guard let self else { return }
            self.window.makeFirstResponder(self.web)
            self.js("window.voz.drop(\(Self.json(paths)), \(point.x), \(self.web.isFlipped ? point.y : self.web.bounds.height - point.y))")
        }
        dictation.changed = { [weak self] state in self?.voiceState(state) }
        dictation.metered = { [weak self] level, seconds in self?.js("window.voz.meter(\(level), \(seconds))") }
        dictation.completed = { [weak self] text in
            guard let self else { return }
            guard let target = self.records[self.voiceSessionID], target.shell.pid > 0 else { self.recover(text, reason: self.tr("Session ended. Your dictation is preserved here.", "Sessão encerrada. Seu ditado ficou guardado aqui.")); return }
            self.web.evaluateJavaScript("window.voz.insert(\(Self.json(text)), \(Self.json(self.voiceSessionID)))") { [weak self] _, error in
                guard let self else { return }
                if let error { self.recover(text, reason: self.tr("Could not insert the transcript: ", "Não foi possível inserir o texto: ") + error.localizedDescription) }
                else { self.status.stringValue = self.tr("Text inserted · review before pressing Enter", "Texto inserido · revise antes de apertar Enter"); self.inserted?(text) }
            }
        }
        dictation.failed = { [weak self] message in self?.error(message) }
        if let folder = Bundle.main.resourceURL?.appendingPathComponent("web") {
            web.loadFileURL(folder.appendingPathComponent("index.html"), allowingReadAccessTo: folder)
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    static func json(_ value: Any) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), encoding: .utf8)!
    }
    func js(_ script: String) { web.evaluateJavaScript(script, completionHandler: nil) }
    func error(_ message: String) { status.stringValue = message; status.toolTip = message }

    private func recover(_ text: String, reason: String) {
        error(reason)
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 360), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = tr("Recovered dictation — review before closing", "Ditado recuperado — revise antes de fechar")
        panel.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: panel.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        let editor = NSTextView(frame: scroll.bounds)
        editor.autoresizingMask = [.width]
        editor.isVerticallyResizable = true
        editor.string = text
        editor.font = .systemFont(ofSize: 15)
        editor.textContainerInset = NSSize(width: 16, height: 16)
        scroll.documentView = editor
        panel.contentView = scroll
        recoveredTranscripts.append(panel)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func toggleVoice() {
        if dictation.state == .recording || dictation.state == .paused { dictation.stop() }
        else if dictation.state == .idle, shell.pid > 0 { voiceSessionID = activeSessionID; dictation.start(language: languageCode) }
        window.makeFirstResponder(web)
        js("window.voz.focus()")
    }
    @objc func cancelVoice() { dictation.cancel(); window.makeFirstResponder(web) }
    @objc func changeLanguage() { UserDefaults.standard.set(languageCode, forKey: "language"); applyLanguage() }

    var languageCode: String { language.selectedItem?.representedObject as? String ?? "pt-BR" }
    /// The interface follows the language chosen for dictation.
    func tr(_ en: String, _ pt: String) -> String { languageCode.hasPrefix("pt") ? pt : en }
    private func applyLanguage() {
        let names = ["pt-BR": tr("Portuguese (Brazil)", "Português (Brasil)"), "pt-PT": tr("Portuguese (Portugal)", "Português (Portugal)"), "en-US": tr("English (US)", "Inglês (EUA)")]
        for item in language.itemArray { item.title = names[item.representedObject as? String ?? ""] ?? item.title }
        language.toolTip = tr("Choose the language you will speak. Recognition runs on your Mac.", "Escolha o idioma em que vai falar. O reconhecimento roda no seu Mac.")
        microphone.title = tr("Dictate", "Ditar")
        microphone.toolTip = tr("Start voice dictation (Control + Option + V). Your text stays editable.", "Começar a ditar (Control + Option + V). O texto continua editável.")
        you.stringValue = theme["name"] ?? "VS Code"
        assistant.stringValue = "ANSI"
        shortcuts.stringValue = tr("⌘C Copy · ⌘V Paste · ⌘T Terminal · ⌃⌥V Voice", "⌘C Copiar · ⌘V Colar · ⌘T Terminal · ⌃⌥V Voz")
        voiceState(dictation.state)
    }

    private func voiceState(_ state: TerminalDictation.State) {
        // While dictating, the controls live only in the voice line inside the terminal.
        let active = state != .idle
        language.isHidden = active
        microphone.isHidden = active
        microphone.isEnabled = shell.pid > 0
        status.stringValue = switch state {
        case .idle: tr("Speak instead of typing · ⌃⌥V to start", "Fale em vez de digitar · ⌃⌥V para começar")
        case .preparing: tr("Preparing microphone · authorize access if macOS asks", "Preparando o microfone · autorize se o macOS pedir")
        case .recording: tr("Listening · click Stop & insert when you are done", "Ouvindo · clique em Parar e inserir quando terminar")
        case .pausing: tr("Pausing microphone…", "Pausando o microfone…")
        case .paused: tr("Paused · your recording is preserved", "Pausado · sua gravação está preservada")
        case .resuming: tr("Resuming microphone…", "Retomando o microfone…")
        case .stopping: tr("Transcribing on your Mac…", "Transcrevendo no seu Mac…")
        }
        js("window.voz.state(\(Self.json(state.rawValue)), \(Self.json(languageCode)))")
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "recentProjects":
            js("window.voz.recentProjects(\(Self.json(ProjectHistory.paths())))")
        case "chooseDevelopmentDirectory":
            guard window.attachedSheet == nil else { return }
            let panel = NSOpenPanel()
            panel.title = "Selecionar pasta do projeto"
            panel.prompt = "Selecionar pasta"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            let current = body["directory"] as? String ?? ""
            panel.directoryURL = URL(fileURLWithPath: current.hasPrefix("/") ? current : NSHomeDirectory(), isDirectory: true)
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                ProjectHistory.remember(url.path)
                self?.js("window.voz.developmentDirectory(\(Self.json(url.path)))")
                self?.js("window.voz.recentProjects(\(Self.json(ProjectHistory.paths())))")
            }
        case "development":
            guard let directory = body["directory"] as? String, directory.hasPrefix("/"),
                  let providers = body["providers"] as? [String], providers.count == 8,
                  providers.allSatisfy({ ["codex", "claude", "agy", "gemini"].contains($0) }),
                  let objective = body["objective"] as? String, objective.count <= 2000, records.count + 8 <= 32 else {
                js("window.voz.developmentError('Configuração inválida ou limite de terminais atingido.')"); return
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
                js("window.voz.developmentError('A pasta do software não existe. Use um caminho absoluto válido.')"); return
            }
            js("window.voz.startDevelopment(\(Self.json(["directory": directory, "objective": objective, "providers": providers])))")
        case "ready":
            guard let id = body["session"] as? String, UUID(uuidString: id) != nil,
                  let workspace = body["workspace"] as? String, UUID(uuidString: workspace) != nil,
                  records[id] == nil, records.count < 32 else { return }
            js("window.voz.theme(\(Self.json(theme)))")
            let session = launched ? ShellSession() : firstShell
            let initial = !launched
            launched = true
            records[id] = Record(shell: session, workspace: workspace, name: String((body["name"] as? String ?? "Terminal").prefix(80)), role: String((body["role"] as? String ?? "").prefix(40)))
            activeSessionID = id
            session.output = { [weak self] data in self?.js("window.voz.write(\(Self.json(data.base64EncodedString())), \(Self.json(id)))") }
            session.ended = { [weak self] in
                guard let self else { return }
                if self.voiceSessionID == id { self.dictation.cancel() }
                self.js("window.voz.ended(\(Self.json(id)))")
                if self.activeSessionID == id { self.microphone.isEnabled = false }
            }
            do {
                let args = CommandLine.arguments
                let currentDirectory = FileManager.default.currentDirectoryPath
                let cwd = (body["directory"] as? String) ?? initialDirectory ?? (currentDirectory == "/" ? NSHomeDirectory() : currentDirectory)
                let prompt = body["prompt"] as? String ?? ""
                guard prompt.utf8.count <= 15000, !prompt.contains("\0") else { throw ControlError.invalid("Invalid agent prompt") }
                let environment = ["BOTERM_INITIAL_PROMPT": prompt, "BOTERM_SOCKET": controlPath, "BOTERM_SESSION": id, "BOTERM_WORKSPACE": workspace,
                    "BOTERM_CLI": Bundle.main.resourceURL?.appendingPathComponent("bin/boterm").path ?? "",
                    "BOTERM_AGENT_GUIDE": Bundle.main.resourceURL?.appendingPathComponent("AGENT_GUIDE.md").path ?? ""]
                if let agent = body["agent"] as? String, ["codex", "claude", "agy", "gemini", "opencode"].contains(agent) {
                    try session.start(executable: "/bin/zsh", arguments: ["-lic", "exec \"$BOTERM_CLI\" agent " + agent + (prompt.isEmpty ? "" : (["gemini", "agy"].contains(agent) ? " --prompt-interactive" : "") + " \"$BOTERM_INITIAL_PROMPT\"")], directory: cwd, environment: environment)
                } else if initial, primary, let index = args.firstIndex(of: "--"), args.count > index + 1 {
                    try session.start(executable: args[index + 1], arguments: Array(args.dropFirst(index + 2)), directory: cwd, environment: environment)
                } else {
                    try session.start(executable: "/bin/zsh", arguments: ["-l"], directory: cwd, environment: environment)
                }
                if let columns = body["columns"] as? Int, let rows = body["rows"] as? Int { session.resize(columns: columns, rows: rows) }
                if body["directory"] as? String != nil || initialDirectory != nil {
                    ProjectHistory.remember(cwd)
                }
                voiceState(dictation.state)
                if !rootLoaded { rootLoaded = true; didLoad?() }
            } catch { self.error("Could not start the terminal: \(error.localizedDescription)") }
        case "activate":
            if let id = body["session"] as? String, records[id] != nil { activeSessionID = id; voiceState(dictation.state) }
        case "input":
            if let id = body["session"] as? String, let text = body["data"] as? String, text.utf8.count <= 1_048_576 {
                inputReceived?(text); records[id]?.shell.write(text)
            }
        case "resize":
            if let id = body["session"] as? String, let cols = body["columns"] as? Int, let rows = body["rows"] as? Int { records[id]?.shell.resize(columns: cols, rows: rows) }
        case "voice": toggleVoice()
        case "cancelVoice": cancelVoice()
        case "pauseVoice": dictation.togglePause()
        case "copy": if let text = body["text"] as? String, !text.isEmpty, text.utf8.count <= 1_048_576 { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
        case "paste": pasteText()
        case "closeSession": if let id = body["session"] as? String { closeSession(id) }
        case "rename": if let id = body["session"] as? String { renameSession(id) }
        case "layoutProfiles": js("window.voz.layoutProfiles(\(Self.json(LayoutProfiles.all())))")
        case "saveLayout":
            if let layout = body["layout"] as? String { saveLayout(layout, suggested: body["name"] as? String ?? "") }
        case "deleteLayout":
            if let name = body["name"] as? String { deleteLayout(name) }
        case "messengerState": (NSApp.delegate as? AppDelegate)?.sendMessengerState(to: self)
        case "telegramSetup": (NSApp.delegate as? AppDelegate)?.setupTelegram(for: self)
        case "revokePermission":
            if let id = body["id"] as? String { try? PermissionStore.revoke(id); (NSApp.delegate as? AppDelegate)?.sendMessengerState(to: self) }
        case "message":
            if let from = body["session"] as? String, let to = body["to"] as? String, let text = body["text"] as? String {
                do { _ = try postMessage(from: from, to: to, text: text) } catch { self.error(error.localizedDescription) }
            }
        default: break
        }
    }

    func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        let url = action.request.url
        if action.navigationType == .linkActivated, url?.absoluteString == "https://github.com/ricdanyalgil/VozTTY" {
            NSWorkspace.shared.open(url!)
            return .cancel
        }
        let root = Bundle.main.resourceURL?.appendingPathComponent("web").standardizedFileURL.path ?? ""
        return url?.isFileURL == true && url!.standardizedFileURL.path.hasPrefix(root + "/") ? .allow : .cancel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !allowClose {
            Task {
                guard await confirmHistoryClose() else { return }
                end(); window.performClose(nil)
            }
            return false
        }
        end()
        return true
    }
    func end() { allowClose = true; dictation.cancel(); records.values.forEach { $0.shell.close() }; web.configuration.userContentController.removeScriptMessageHandler(forName: "terminal") }
    func windowWillClose(_ notification: Notification) { closed?() }
    func closeForTest() { allowClose = true; window.performClose(nil) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var terminals: [TerminalWindow] = []
    var control: LocalControl?
    var agentTimer: Timer?
    let telegram = TelegramBridge()
    private var cascade = NSPoint.zero
    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let vocabularyItem = appMenu.addItem(withTitle: "Edit Vocabulary…", action: #selector(editVocabulary), keyEquivalent: ",")
        vocabularyItem.target = self
        let controlItem = appMenu.addItem(withTitle: pt ? "Permitir controle do computador…" : "Allow Computer Control…", action: #selector(allowComputerControl), keyEquivalent: "")
        controlItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Boterm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let shellItem = NSMenuItem()
        let shellMenu = NSMenu(title: "Shell")
        shellMenu.addItem(withTitle: pt ? "Novo terminal" : "New Terminal", action: #selector(newTab), keyEquivalent: "t").target = self
        shellMenu.addItem(withTitle: pt ? "Nova janela" : "New Window", action: #selector(newWindow), keyEquivalent: "n").target = self
        shellMenu.addItem(.separator())
        shellMenu.addItem(withTitle: pt ? "Salvar histórico…" : "Save History…", action: #selector(saveHistory), keyEquivalent: "s").target = self
        shellMenu.addItem(withTitle: pt ? "Histórico salvo…" : "Saved History…", action: #selector(showHistory), keyEquivalent: "").target = self
        shellItem.submenu = shellMenu
        main.addItem(shellItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key).target = self
        }
        editItem.submenu = edit
        main.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: pt ? "Janela" : "Window")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApplication.shared.mainMenu = main
        NSApplication.shared.windowsMenu = windowMenu
        do {
            control = try LocalControl { [weak self] data in
                await self?.controlRequest(data) ?? Data("{}".utf8)
            }
        } catch { NSAlert(error: error).runModal() }
        agentTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAgentStates() }
        }
        connectTelegram()
        newWindow()
        NSApplication.shared.activate(ignoringOtherApps: true)
        #if VOZ_TEST
        if let terminal = terminals.first { Task { await terminal.runIntegrationTest() } }
        #endif
    }

    @objc func newWindow() {
        openWindow()
    }
    func openWindow(directory: String? = nil) {
        let terminal = TerminalWindow(primary: terminals.isEmpty, directory: directory)
        terminal.controlPath = control?.path ?? ""
        // The first window stays centred (.zero leaves it in place); each later one steps down and right.
        cascade = terminal.window.cascadeTopLeft(from: terminals.isEmpty ? .zero : cascade)
        // Removed on the next turn so the window is not released inside its own close callback.
        terminal.closed = { [weak self, weak terminal] in
            DispatchQueue.main.async { self?.terminals.removeAll { $0 === terminal } }
        }
        terminals.append(terminal)
    }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for path in ProjectHistory.paths() {
            let item = menu.addItem(withTitle: URL(fileURLWithPath: path).lastPathComponent, action: #selector(openRecentProject(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = path; item.toolTip = path
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(withTitle: pt ? "Nova janela" : "New Window", action: #selector(newWindow), keyEquivalent: "").target = self
        return menu
    }
    @objc func openRecentProject(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        guard let directory = ProjectHistory.directory(path) else {
            let alert = NSAlert(); alert.messageText = pt ? "A pasta do projeto não está disponível." : "The project folder is unavailable."
            alert.informativeText = path; alert.runModal(); return
        }
        ProjectHistory.remember(directory)
        openWindow(directory: directory)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newWindow() }
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { control = nil }
    private var pt: Bool { (UserDefaults.standard.string(forKey: "language") ?? "pt-BR").hasPrefix("pt") }

    /// Programs started in this terminal inherit its macOS privacy grants, so agent CLIs can drive the mouse,
    /// keyboard and screen once Boterm itself is allowed. Ad hoc builds lose the grant on every rebuild.
    @objc func allowComputerControl() {
        let input = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        let screen = CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
        let alert = NSAlert()
        let state = { (ok: Bool) in ok ? (self.pt ? "permitido" : "allowed") : (self.pt ? "falta permitir" : "not allowed yet") }
        alert.messageText = input && screen
            ? (pt ? "O Boterm já pode controlar o computador" : "Boterm can control this Mac")
            : (pt ? "Permita o Boterm nos Ajustes do Sistema" : "Allow Boterm in System Settings")
        alert.informativeText = (pt
            ? "Mouse e teclado (Acessibilidade): \(state(input))\nVer a tela (Gravação de Tela): \(state(screen))\n\nO que rodar neste terminal passa a poder usar o mouse, o teclado e a tela. Depois de permitir, feche e abra o Boterm. AppleScript pede autorização na primeira vez que for usado."
            : "Mouse and keyboard (Accessibility): \(state(input))\nScreen (Screen Recording): \(state(screen))\n\nPrograms run in this terminal can then use the mouse, keyboard and screen. Reopen Boterm after allowing. AppleScript asks the first time it is used.")
        alert.addButton(withTitle: "OK")
        if !input || !screen { alert.addButton(withTitle: pt ? "Abrir Ajustes" : "Open Settings") }
        if alert.runModal() == .alertSecondButtonReturn {
            let pane = input ? "Privacy_ScreenCapture" : "Privacy_Accessibility"
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
        }
    }

    @objc func editVocabulary() {
        do {
            try Vocabulary.createFileIfNeeded()
            if !NSWorkspace.shared.open(Vocabulary.fileURL) {
                throw NSError(domain: "Boterm.Vocabulary", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not open vocabulary.txt in your text editor."])
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let pending = terminals.filter { !$0.allowClose }
        guard !pending.isEmpty else { return .terminateNow }
        Task {
            for terminal in pending {
                terminal.window.makeKeyAndOrderFront(nil)
                guard await terminal.confirmHistoryClose() else {
                    sender.reply(toApplicationShouldTerminate: false); return
                }
            }
            pending.forEach { $0.end() }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
