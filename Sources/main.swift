// StudySnap — press ⌥⇧S, drag over a question, and it opens in ChatGPT, Gemini or Claude
// with the screenshot pasted in.

import AppKit
import Carbon.HIToolbox

enum Site: String, CaseIterable {
    case chatgpt, gemini, claude

    var title: String {
        switch self {
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        case .claude: return "Claude"
        }
    }

    var url: URL {
        switch self {
        case .chatgpt: return URL(string: "https://chatgpt.com/")!
        case .gemini: return URL(string: "https://gemini.google.com/app")!
        case .claude: return URL(string: "https://claude.ai/new")!
        }
    }
}

enum Settings {
    private static let defaults = UserDefaults.standard

    /// nil means "ask every time".
    static var site: Site? {
        get { defaults.string(forKey: "site").flatMap(Site.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: "site") }
    }

    static var hasLaunched: Bool {
        get { defaults.bool(forKey: "hasLaunched") }
        set { defaults.set(newValue, forKey: "hasLaunched") }
    }

    static var autoSend: Bool {
        get { defaults.bool(forKey: "autoSend") }
        set { defaults.set(newValue, forKey: "autoSend") }
    }

    /// Seconds to wait for the website to load before pasting.
    static var pasteDelay: Double {
        get { defaults.object(forKey: "pasteDelay") as? Double ?? 5 }
        set { defaults.set(newValue, forKey: "pasteDelay") }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    private var statusItem: NSStatusItem!
    private var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "StudySnap")
        rebuildMenu()
        registerHotKey()

        if !Settings.hasLaunched {
            Settings.hasLaunched = true
            _ = askForSite()
            requestAccessibility()
        }
    }

    // MARK: Hotkey (⌥⇧S)

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { AppDelegate.shared.snap() }
            return noErr
        }, 1, &spec, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x5353_4E50), id: 1) // "SSNP"
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(optionKey | shiftKey), id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: Snap flow

    @objc func snap() {
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount

        // Built-in macOS region picker; -c puts the image on the clipboard.
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-i", "-c"]
        capture.terminationHandler = { _ in
            DispatchQueue.main.async {
                // Unchanged clipboard means the user pressed Esc.
                if pasteboard.changeCount != before { self.send() }
            }
        }
        try? capture.run()
    }

    private func send() {
        guard let site = Settings.site ?? askForSite() else { return }
        guard AXIsProcessTrusted() else {
            showAccessibilityHelp()
            return
        }
        // Paste into the chat that's already open; only open a new one if there isn't one.
        let reused = focusOpenTab(of: site)
        if !reused { NSWorkspace.shared.open(site.url) }

        waitForBrowser(site.url, attempts: 50) {
            // Pasting while the site is still loading gets lost when its chat box re-renders.
            self.waitForPageLoad(of: site, attempts: 100) { loaded in
                let delay = reused ? 0.5 : (loaded ? 1.5 : Settings.pasteDelay)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.paste()
                }
            }
        }
    }

    /// Polls (every 0.3s) until the browser's front tab is the site and has finished loading.
    /// Calls back with false if the browser can't tell us (e.g. Safari), so we fall back to the delay.
    private func waitForPageLoad(of site: Site, attempts: Int, then done: @escaping (Bool) -> Void) {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: site.url),
              let bundleID = Bundle(url: appURL)?.bundleIdentifier,
              bundleID != "com.apple.Safari",
              let name = scriptableBrowsers[bundleID]
        else { return done(false) }

        let source = """
            tell application "\(name)"
                set t to active tab of front window
                if URL of t does not contain "\(site.url.host!)" then return "wait"
                if loading of t then return "wait"
                return "ready"
            end tell
            """
        var error: NSDictionary?
        let state = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
        if state == "ready" { return done(true) }
        if state == nil || attempts == 0 { return done(false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.waitForPageLoad(of: site, attempts: attempts - 1, then: done)
        }
    }

    /// Browsers we can search for an open tab (via AppleScript), by bundle id.
    private let scriptableBrowsers: [String: String] = [
        "com.google.Chrome": "Google Chrome",
        "com.brave.Browser": "Brave Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.apple.Safari": "Safari",
    ]

    /// Brings an already-open tab for `site` to the front. Returns false if none is open.
    private func focusOpenTab(of site: Site) -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: site.url),
              let bundleID = Bundle(url: appURL)?.bundleIdentifier,
              let name = scriptableBrowsers[bundleID],
              !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        else { return false }

        let domain = site.url.host!
        let source = bundleID == "com.apple.Safari" ? """
            tell application "Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if URL of t contains "\(domain)" then
                                set current tab of w to t
                                set index of w to 1
                                activate
                                return "found"
                            end if
                        end try
                    end repeat
                end repeat
            end tell
            return "none"
            """ : """
            tell application "\(name)"
                repeat with w in windows
                    set i to 0
                    repeat with t in tabs of w
                        set i to i + 1
                        if URL of t contains "\(domain)" then
                            set active tab index of w to i
                            set index of w to 1
                            activate
                            return "found"
                        end if
                    end repeat
                end repeat
            end tell
            return "none"
            """

        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return result?.stringValue == "found"
    }

    /// Polls (every 0.2s) until the browser that opens `url` is the frontmost app,
    /// so ⌘V goes to the website and not to whatever was in front before.
    private func waitForBrowser(_ url: URL, attempts: Int, then done: @escaping () -> Void) {
        let browser = NSWorkspace.shared.urlForApplication(toOpen: url)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if browser == nil || front == browser || attempts == 0 {
            done()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.waitForBrowser(url, attempts: attempts - 1, then: done)
        }
    }

    private func paste() {
        pressKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        if Settings.autoSend {
            // Give the image a moment to upload before sending.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.pressKey(CGKeyCode(kVK_Return), flags: [])
            }
        }
    }

    private func pressKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Site picker

    /// Shows the "where should screenshots go?" dialog. Returns nil if cancelled.
    private func askForSite() -> Site? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Where should your screenshots go?"
        alert.informativeText = "You can change this any time from the menu bar icon."
        for site in Site.allCases { alert.addButton(withTitle: site.title) }
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Remember my choice"
        alert.suppressionButton?.state = .on

        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard Site.allCases.indices.contains(index) else { return nil }
        let site = Site.allCases[index]
        if alert.suppressionButton?.state == .on {
            Settings.site = site
            rebuildMenu()
        }
        return site
    }

    private func showAccessibilityHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "StudySnap can't paste yet"
        alert.informativeText = """
            Turn on StudySnap in System Settings → Privacy & Security → Accessibility.
            If it's already on, remove it with the – button and add it again (needed after every rebuild).

            Your screenshot is on the clipboard, so ⌘V works by hand for now.
            """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            // Until permission is granted the screenshot is still on the clipboard — ⌘V works by hand.
            NSLog("StudySnap: Accessibility permission needed for auto-paste")
        }
    }

    // MARK: Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(item("Snap a question  (⌥⇧S)", #selector(snap)))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Send screenshots to:", action: nil, keyEquivalent: ""))
        for site in Site.allCases {
            let siteItem = item("   " + site.title, #selector(pickSite(_:)))
            siteItem.representedObject = site.rawValue
            siteItem.state = Settings.site == site ? .on : .off
            menu.addItem(siteItem)
        }
        let ask = item("   Ask every time", #selector(pickSite(_:)))
        ask.state = Settings.site == nil ? .on : .off
        menu.addItem(ask)
        menu.addItem(.separator())

        let autoSend = item("Press Enter automatically", #selector(toggleAutoSend))
        autoSend.state = Settings.autoSend ? .on : .off
        menu.addItem(autoSend)

        let delayMenu = NSMenu()
        for seconds in [2.0, 3.0, 5.0, 8.0] {
            let delayItem = item("\(Int(seconds)) seconds", #selector(pickDelay(_:)))
            delayItem.representedObject = seconds
            delayItem.state = Settings.pasteDelay == seconds ? .on : .off
            delayMenu.addItem(delayItem)
        }
        let delay = NSMenuItem(title: "Wait before pasting", action: nil, keyEquivalent: "")
        delay.submenu = delayMenu
        menu.addItem(delay)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit StudySnap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func pickSite(_ sender: NSMenuItem) {
        Settings.site = (sender.representedObject as? String).flatMap(Site.init(rawValue:))
        rebuildMenu()
    }

    @objc private func toggleAutoSend() {
        Settings.autoSend.toggle()
        rebuildMenu()
    }

    @objc private func pickDelay(_ sender: NSMenuItem) {
        if let seconds = sender.representedObject as? Double { Settings.pasteDelay = seconds }
        rebuildMenu()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
