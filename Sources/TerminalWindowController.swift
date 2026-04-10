import Cocoa
import SwiftTerm

// MARK: - Terminal Window Controller

class TerminalWindowController: NSWindowController, SidebarDelegate, TabBarDelegate {
    let tabManager = TabManager()
    let mainLayout: MainLayoutView
    let serverDetector = ServerDetector()

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let windowWidth: CGFloat = min(1400, screenFrame.width * 0.8)
        let windowHeight: CGFloat = min(screenFrame.height * 0.85, 900)

        mainLayout = MainLayoutView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Terminos"
        window.contentView = mainLayout
        window.isRestorable = false
        window.minSize = NSSize(width: 700, height: 400)
        window.backgroundColor = bgColor
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)

        super.init(window: window)

        mainLayout.sidebar.delegate = self
        mainLayout.tabBar.delegate = self
        mainLayout.setEmptyState(true)

        serverDetector.onServersChanged = { [weak self] servers in
            guard let self else { return }
            // The /SERVERS section now lives in the bottom of the left sidebar. Only
            // pass in listeners whose working directory is inside the projects root,
            // so Spotify, Postgres, and other unrelated system processes are filtered.
            let projectServers = servers.filter { server in
                guard let cwd = server.cwd else { return false }
                return cwd == projectsPath || cwd.hasPrefix(projectsPath + "/")
            }
            self.mainLayout.sidebar.updateServers(projectServers)
            // Right panel is reserved for future image/webview previews — leave empty.
        }
        serverDetector.start()

        // Cmd+Shift+Left/Right switches tabs. A local monitor is used because
        // SwiftTerm's view captures arrow keys before menu key equivalents run.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.contains(.command), mods.contains(.shift) else { return event }
            switch Int(event.keyCode) {
            case 123: self.prevTab(); return nil
            case 124: self.nextTab(); return nil
            default: return event
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Tab Operations

    func openProject(at path: String) {
        let tab = tabManager.createTab(directory: path)
        tab.terminalView.processDelegate = self
        tab.sendCommand("claude")
        refreshUI()
    }

    func newTabInCurrentDirectory() {
        guard let current = tabManager.activeTab else { return }
        let tab = tabManager.createTab(directory: current.directory)
        tab.terminalView.processDelegate = self
        tab.sendCommand("claude")
        refreshUI()
    }

    func closeCurrentTab() {
        guard tabManager.activeIndex >= 0 else { return }
        if let closed = tabManager.closeTab(at: tabManager.activeIndex) {
            closed.terminalView.removeFromSuperview()
        }
        refreshUI()
    }

    func nextTab() {
        guard tabManager.tabs.count > 1 else { return }
        let next = (tabManager.activeIndex + 1) % tabManager.tabs.count
        tabManager.selectTab(at: next)
        refreshUI()
    }

    func prevTab() {
        guard tabManager.tabs.count > 1 else { return }
        let prev = (tabManager.activeIndex - 1 + tabManager.tabs.count) % tabManager.tabs.count
        tabManager.selectTab(at: prev)
        refreshUI()
    }

    private func refreshUI() {
        // Update tab bar
        mainLayout.tabBar.update(tabs: tabManager.tabs, activeIndex: tabManager.activeIndex)
        mainLayout.setEmptyState(tabManager.tabs.isEmpty)

        // Show active terminal
        mainLayout.terminalContainer.subviews.forEach { $0.removeFromSuperview() }
        if let activeTab = tabManager.activeTab {
            mainLayout.terminalContainer.addSubview(activeTab.terminalView)
            mainLayout.terminalContainer.layoutActiveTerminal()
            window?.makeFirstResponder(activeTab.terminalView)
            window?.title = activeTab.title
        } else {
            window?.title = "Terminos"
        }
    }

    // MARK: - SidebarDelegate

    func sidebarDidSelectProject(path: String) {
        openProject(at: path)
    }

    // MARK: - TabBarDelegate

    func tabBarDidSelectTab(at index: Int) {
        tabManager.selectTab(at: index)
        refreshUI()
    }

    func tabBarDidCloseTab(at index: Int) {
        if let closed = tabManager.closeTab(at: index) {
            closed.terminalView.removeFromSuperview()
        }
        refreshUI()
    }
}

extension TerminalWindowController: LocalProcessTerminalViewDelegate {
    /// Protocol stub — Terminos relies on AppKit autoresizing to forward size
    /// changes to the embedded terminal, so the controller has nothing to do here.
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // Update the tab title if this is the active terminal
        if let activeTab = tabManager.activeTab, activeTab.terminalView === source {
            if !title.isEmpty {
                activeTab.title = title
                mainLayout.tabBar.update(tabs: tabManager.tabs, activeIndex: tabManager.activeIndex)
                window?.title = title
            }
        }
    }

    /// Protocol stub — Terminos doesn't track per-tab cwd updates from OSC 7
    /// hints; tab titles come from `setTerminalTitle` instead.
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Find and close the tab whose terminal exited
            if let index = self.tabManager.tabs.firstIndex(where: { $0.terminalView === source }) {
                if let closed = self.tabManager.closeTab(at: index) {
                    closed.terminalView.removeFromSuperview()
                }
                self.refreshUI()
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: TerminalWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerFonts()

        windowController = TerminalWindowController()
        windowController?.showWindow(nil)

        // Center window
        if let window = windowController?.window, let screen = window.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        true
    }

    // MARK: - Menu Actions

    @objc func newTab(_ sender: Any?) {
        windowController?.newTabInCurrentDirectory()
    }

    @objc func closeTab(_ sender: Any?) {
        windowController?.closeCurrentTab()
    }

    @objc func nextTab(_ sender: Any?) {
        windowController?.nextTab()
    }

    @objc func prevTab(_ sender: Any?) {
        windowController?.prevTab()
    }
}
