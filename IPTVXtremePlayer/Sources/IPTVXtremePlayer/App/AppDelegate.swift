import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Boot the libVLC engine, pointing at bundled plugins when packaged,
        // otherwise the installed VLC.app.
        let booted = VLCPlayer.bootEngine(pluginPath: AppDelegate.vlcPluginPath())
        if !booted {
            Log.error("libVLC failed to initialize")
        } else {
            Log.info("libVLC \(VLCPlayer.version) ready")
        }

        buildMenu()
        _ = DownloadManager.shared   // load + reconcile the offline download index

        let wc = MainWindowController()
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        mainWindow = wc
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Warn before quitting mid-download (an interrupted download must be retried).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let active = DownloadManager.shared.records.filter { $0.status == .downloading || $0.status == .queued }
        guard !active.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit while \(active.count == 1 ? "a download is" : "downloads are") in progress?"
        alert.informativeText = "Unfinished downloads will stop and can be retried from Downloads later."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Keep Downloading")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    /// Locate VLC plugins: bundled in the .app's Frameworks/plugins first, then
    /// the system VLC.app installation.
    static func vlcPluginPath() -> String? {
        if let frameworks = Bundle.main.privateFrameworksURL {
            let bundled = frameworks.appendingPathComponent("plugins").path
            if FileManager.default.fileExists(atPath: bundled) { return bundled }
        }
        let system = "/Applications/VLC.app/Contents/MacOS/plugins"
        if FileManager.default.fileExists(atPath: system) { return system }
        return nil
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About IPTVXtremePlayer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide IPTVXtremePlayer", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit IPTVXtremePlayer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // Edit menu (for the search field: copy/paste/select-all)
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        // View menu
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        let fs = NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fs)
        viewItem.submenu = viewMenu

        // Window menu
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}
