import SwiftUI
import AppKit
import WebKit
import JavaScriptCore
import ServiceManagement
import CoreGraphics

@MainActor final class BriefingModel: ObservableObject {
    @Published var markdown = ""
    @Published var file: URL?
    @Published var status = "Choose your briefing folder to get started."
    @Published var checking = false
    @Published var error: String?
    @Published var folder: String { didSet { defaults.set(folder, forKey: "folder") } }
    @Published var pattern: String { didSet { defaults.set(pattern, forKey: "pattern") } }
    @Published var dateFormat: String { didSet { defaults.set(dateFormat, forKey: "dateFormat") } }
    @Published var modifiedToday: Bool { didSet { defaults.set(modifiedToday, forKey: "modifiedToday") } }
    @Published var autoOpen: Bool { didSet { defaults.set(autoOpen, forKey: "autoOpen") } }
    @Published var startHour: Int { didSet { defaults.set(startHour, forKey: "startHour") } }
    @Published var endHour: Int { didSet { defaults.set(endHour, forKey: "endHour") } }
    let defaults = UserDefaults.standard
    var present: (() -> Void)?
    var readerVisible: (() -> Bool)?
    var locked = false
    var timer: Timer?
    var observers: [NSObjectProtocol] = []
    var lastContent: String?
    init() {
        let d = UserDefaults.standard
        folder = d.string(forKey: "folder") ?? ""
        pattern = d.string(forKey: "pattern") ?? "*{date}*.md"
        dateFormat = d.string(forKey: "dateFormat") ?? "yyyy-MM-dd"
        modifiedToday = d.object(forKey: "modifiedToday") as? Bool ?? false
        autoOpen = d.object(forKey: "autoOpen") as? Bool ?? true
        startHour = d.object(forKey: "startHour") as? Int ?? 8
        endHour = d.object(forKey: "endHour") as? Int ?? 15
    }
    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.locked = false; self?.refresh() }
            })
        }
        for (name, value) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.locked = value; if !value { self?.refresh() } }
            })
        }
        observers.append(workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.locked = true } })
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        refresh()
    }
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.prompt = "Use Briefing Folder"
        if panel.runModal() == .OK, let url = panel.url { folder = url.path; refresh() }
    }
    func refresh() {
        guard !checking else { return }
        guard !folder.isEmpty else { status = "Choose your briefing folder to get started."; return }
        checking = true
        let path = folder
        let rules = BriefingRules(pattern: pattern, dateFormat: dateFormat, useModificationDate: modifiedToday)
        let now = Date()
        DispatchQueue.global(qos: .utility).async {
            let result: Result<(URL, String)?, Error> = Result {
                let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles])
                let candidates = urls.compactMap { url -> (URL, Date, Int)? in
                    guard let info = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey]), info.isRegularFile == true,
                          let date = info.contentModificationDate, rules.matches(url, modified: date, now: now) else { return nil }
                    return (url, date, info.fileSize ?? 0)
                }.sorted { $0.1 == $1.1 ? $0.0.lastPathComponent < $1.0.lastPathComponent : $0.1 > $1.1 }
                guard let best = candidates.first else { return nil }
                guard best.2 <= 5_000_000 else { throw NSError(domain: "Briefing", code: 1, userInfo: [NSLocalizedDescriptionKey: "The briefing exceeds the 5 MB reading limit."]) }
                let content = try String(contentsOf: best.0, encoding: .utf8)
                guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                // Avoid opening a file while its producer is actively writing it.
                guard Date().timeIntervalSince(best.1) >= 2 else { return nil }
                return (best.0, content)
            }
            DispatchQueue.main.async { self.finish(result, now: now) }
        }
    }
    private func finish(_ result: Result<(URL, String)?, Error>, now: Date) {
        checking = false
        switch result {
        case .failure(let err): file = nil; markdown = ""; error = err.localizedDescription; status = "Couldn’t read the briefing folder."
        case .success(nil):
            error = nil; file = nil; markdown = ""
            status = "Waiting for today’s briefing. Checking every 30 seconds."
        case .success(.some(let (url, content))):
            error = nil; file = url
            if markdown != content { markdown = content }
            status = "Today’s briefing is ready"
            if readerVisible?() == true { markRead() }
            let session = CGSessionCopyCurrentDictionary() as? [String: Any]
            let isLocked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
            let onConsole = session?["kCGSSessionOnConsoleKey"] as? Bool ?? true
            if BriefingRules.shouldOpen(now: now, start: startHour, end: endHour, lastDay: defaults.string(forKey: "openedDay") ?? "", available: true, enabled: autoOpen, unlocked: !locked && !isLocked && onConsole) {
                markRead(); present?()
            }
        }
    }
    func markRead() { defaults.set(BriefingRules.dayKey(Date()), forKey: "openedDay") }
}

struct ReaderView: View {
    @ObservedObject var model: BriefingModel
    var preferences: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "sun.horizon.fill").font(.system(size: 30)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Morning Brief").font(.title2.weight(.semibold))
                    Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day()).foregroundStyle(.secondary)
                }
                Spacer()
                if model.checking { ProgressView().controlSize(.small) }
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("Check for briefing")
                Button(action: preferences) { Image(systemName: "slider.horizontal.3") }.help("Preferences")
            }.padding(24)
            Divider()
            if !model.markdown.isEmpty {
                MarkdownView(markdown: model.markdown)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: model.error == nil ? "cup.and.saucer" : "folder.badge.questionmark").font(.system(size: 56, weight: .light)).foregroundStyle(.orange)
                    Text(model.folder.isEmpty ? "A calmer start to your day" : "Your briefing is on its way").font(.title.weight(.medium))
                    Text(model.error ?? model.status).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 430)
                    Button(model.folder.isEmpty ? "Choose Briefing Folder…" : "Preferences…", action: preferences).buttonStyle(.borderedProminent).tint(.orange)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Circle().fill(model.file == nil ? Color.orange : Color.green).frame(width: 6, height: 6)
                Text(model.error ?? model.status).lineLimit(1)
                Spacer()
                if let file = model.file { Button("Reveal File") { NSWorkspace.shared.activateFileViewerSelecting([file]) }.buttonStyle(.link) }
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 12)
        }.frame(minWidth: 660, minHeight: 480)
    }
}

struct PreferencesView: View {
    @ObservedObject var model: BriefingModel
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    var body: some View {
        Form {
            Section("Briefing files") {
                HStack { TextField("Folder", text: $model.folder); Button("Choose…") { model.chooseFolder() } }
                TextField("Filename pattern", text: $model.pattern)
                TextField("Date format", text: $model.dateFormat)
                Text("Use {date} for today and * for any text. Example: *{date}*.md with yyyy-MM-dd. For a fixed filename, use summary.md and enable modified today. Both .md and .markdown are supported when the pattern matches.").font(.caption).foregroundStyle(.secondary)
                Toggle("Require file to be modified today", isOn: $model.modifiedToday)
            }
            Section("Morning routine") {
                Toggle("Bring briefing forward once each day", isOn: $model.autoOpen)
                Picker("Start checking for automatic opening", selection: $model.startHour) { ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) } }
                Picker("Stop automatic opening", selection: $model.endHour) { ForEach(1..<25) { Text($0 == 24 ? "Midnight" : String(format: "%02d:00", $0)).tag($0) } }
                if model.endHour <= model.startHour { Text("Stop time must be later than start time. Automatic opening is paused.").foregroundStyle(.red) }
                Text("Waits for the first available briefing in this window, including late arrivals. Opening it manually also counts for today. Keep Morning Brief running; closing its window leaves it in the menu bar.").font(.caption).foregroundStyle(.secondary)
                Toggle("Launch at login", isOn: $login).onChange(of: login) { enabled in
                    do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = nil }
                    catch { loginError = error.localizedDescription }
                    login = SMAppService.mainApp.status == .enabled
                }
                if SMAppService.mainApp.status == .requiresApproval { Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() } }
                if let loginError { Text(loginError).foregroundStyle(.red).font(.caption) }
            }
            Button("Apply & Check Now") { model.refresh() }
        }.formStyle(.grouped).padding(12).frame(width: 600, height: 620)
    }
}

struct MarkdownView: NSViewRepresentable {
    let markdown: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.previous != markdown else { return }
        context.coordinator.previous = markdown
        view.loadHTMLString(context.coordinator.render(markdown), baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var previous: String?
        let js = JSContext()!
        override init() {
            super.init()
            if let url = Bundle.main.url(forResource: "markdown-it.min", withExtension: "js"), let source = try? String(contentsOf: url, encoding: .utf8) {
                js.evaluateScript(source)
                js.evaluateScript("var renderer = markdownit({html:false, linkify:true, typographer:true});")
            }
        }
        func render(_ markdown: String) -> String {
            js.setObject(markdown, forKeyedSubscript: "source" as NSString)
            let html = js.evaluateScript("renderer.render(source)")?.toString() ?? "Unable to load the bundled Markdown renderer."
            return """
            <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:;"><style>
            :root{color-scheme:light dark;--ink:#282c34;--muted:#68717d;--paper:#fffcf6;--line:#e5dfd3;--accent:#a44f1b;--code:#f0ebe2}
            @media(prefers-color-scheme:dark){:root{--ink:#e6e2dc;--muted:#aaa59d;--paper:#202225;--line:#3d4045;--accent:#f4b079;--code:#2c3036}}
            *{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:17px/1.7 -apple-system,BlinkMacSystemFont,sans-serif;overflow-wrap:break-word}article{max-width:850px;margin:auto;padding:38px 48px 80px}h1,h2,h3,h4{line-height:1.25;letter-spacing:-.025em}h1{font-size:35px;margin:0 0 25px;font-weight:700}h2{font-size:25px;margin-top:38px;padding-bottom:10px;border-bottom:1px solid var(--line)}h3{font-size:20px;margin-top:28px}p,ul,ol{margin:16px 0}li{padding-left:5px;margin:6px 0}li::marker{color:var(--accent)}a{color:var(--accent);text-underline-offset:3px}blockquote{border-left:3px solid var(--accent);margin:24px 0;padding:1px 22px;color:var(--muted)}pre{overflow:auto;background:var(--code);padding:18px;border-radius:10px}code{font:14px/1.6 ui-monospace,Menlo,monospace;background:var(--code);padding:2px 5px;border-radius:4px}pre code{padding:0}table{border-collapse:collapse;display:block;overflow:auto;width:100%;font-size:15px;margin:24px 0}th,td{border:1px solid var(--line);padding:10px 14px;text-align:left}th{background:var(--code)}hr{border:0;border-top:1px solid var(--line);margin:30px 0}img{max-width:100%}input{accent-color:var(--accent)}
            </style></head><body><article>\(html)</article></body></html>
            """
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            } else { decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel) }
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BriefingModel()
    var window: NSWindow!
    var settingsWindow: NSWindow?
    var statusItem: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Morning Brief"; window.isReleasedWhenClosed = false; window.center()
        window.contentView = NSHostingView(rootView: ReaderView(model: model, preferences: { [weak self] in self?.preferences() }))
        model.present = { [weak self] in self?.show() }
        model.readerVisible = { [weak self] in self?.window.isVisible == true && self?.window.isMiniaturized == false }
        let mainMenu = NSMenu(); let root = NSMenuItem(); mainMenu.addItem(root)
        let appMenu = NSMenu(); root.submenu = appMenu
        appMenu.addItem(withTitle: "About Morning Brief", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(withTitle: "Preferences…", action: #selector(preferences), keyEquivalent: ",")
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Quit Morning Brief", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        // A nil target routes these actions to the focused view through the responder chain.
        for (title, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        NSApp.mainMenu = mainMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sun.horizon", accessibilityDescription: "Morning Brief")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Morning Brief", action: #selector(openBrief), keyEquivalent: "")
        menu.addItem(withTitle: "Check Now", action: #selector(check), keyEquivalent: "")
        menu.addItem(withTitle: "Preferences…", action: #selector(preferences), keyEquivalent: "")
        menu.addItem(.separator()); menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        model.start()
        if model.folder.isEmpty { show() }
    }
    func show() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    @objc func openBrief() { if model.file != nil { model.markRead() }; show(); model.refresh() }
    @objc func check() { model.refresh() }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(nil) }
    @objc func preferences() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 620), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Morning Brief Preferences"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: PreferencesView(model: model)); w.center(); settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openBrief(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct MorningBriefApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
