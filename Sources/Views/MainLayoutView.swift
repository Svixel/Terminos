import Cocoa

// MARK: - Terminal Container View

class TerminalContainerView: NSView {
    private let maxTerminalWidth: CGFloat = 1200
    private let padding: CGFloat = 20

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = bgColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutActiveTerminal()
    }

    func layoutActiveTerminal() {
        guard let terminal = subviews.first else { return }
        let terminalWidth = min(bounds.width - padding * 2, maxTerminalWidth)
        let terminalHeight = bounds.height - padding * 2
        let x = (bounds.width - terminalWidth) / 2
        terminal.frame = NSRect(x: x, y: padding, width: terminalWidth, height: terminalHeight)
    }
}

// MARK: - Server Panel

enum BrowserTarget {
    case safari, chrome
}

class ServerIconButton: HoverIconButton {
    let port: Int
    let browser: BrowserTarget

    init(svgName: String, port: Int, browser: BrowserTarget) {
        self.port = port
        self.browser = browser
        super.init(svgName: svgName, iconSize: 16, baseAlpha: 0.5, hoverAlpha: 1.0)
        target = self
        action = #selector(openInBrowser)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func openInBrowser() {
        guard let url = URL(string: "http://127.0.0.1:\(port)") else { return }
        let bundleID: String
        switch browser {
        case .safari: bundleID = "com.apple.Safari"
        case .chrome: bundleID = "com.google.Chrome"
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
        }
    }
}

class ServerPanelView: NSView {
    private let scrollView: NSScrollView
    private let tableView: NSTableView
    private let header: HeaderBar
    private(set) var servers: [ServerInfo] = []

    override init(frame: NSRect) {
        (scrollView, tableView) = makeSidebarTable(rowHeight: Theme.rowHeight)
        header = HeaderBar(title: "/SERVERS")

        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = bgColor.cgColor

        tableView.delegate = self
        tableView.dataSource = self

        addSubview(header)
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(servers: [ServerInfo]) {
        self.servers = servers
        tableView.reloadData()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        header.frame = NSRect(x: 0, y: bounds.height - Theme.headerHeight, width: bounds.width, height: Theme.headerHeight)
        scrollView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - Theme.headerHeight)
    }
}

extension ServerPanelView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        servers.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellID = NSUserInterfaceItemIdentifier("ServerCell")
        let cell = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView
            ?? NSTableCellView(frame: .zero)
        cell.identifier = cellID
        cell.subviews.forEach { $0.removeFromSuperview() }

        let server = servers[row]
        let cellWidth = bounds.width

        // Port label
        let portLabel = makeLabel(":\(server.port)", fontSize: 11, color: Theme.strongLabelColor)
        portLabel.frame = NSRect(x: 10, y: 18, width: cellWidth - 60, height: 14)
        cell.addSubview(portLabel)

        // Friendly name
        let nameLabel = makeLabel(server.friendlyName, fontSize: 9, color: Theme.ghostLabelColor)
        nameLabel.frame = NSRect(x: 10, y: 4, width: cellWidth - 60, height: 14)
        cell.addSubview(nameLabel)

        // Safari button
        let safariBtn = ServerIconButton(svgName: "safari-solid-sharp.svg", port: server.port, browser: .safari)
        safariBtn.frame = NSRect(x: cellWidth - 48, y: 10, width: 16, height: 16)
        cell.addSubview(safariBtn)

        // Chrome button
        let chromeBtn = ServerIconButton(svgName: "chrome-solid-sharp.svg", port: server.port, browser: .chrome)
        chromeBtn.frame = NSRect(x: cellWidth - 26, y: 10, width: 16, height: 16)
        cell.addSubview(chromeBtn)

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NSTableRowView()
        rowView.isEmphasized = false
        return rowView
    }
}

// MARK: - Window Layout

/// Pure layout calculation for `MainLayoutView`. Reads zero instance state, so
/// the math is trivially eyeballable. `MainLayoutView.applyLayout` builds one
/// of these per pass and copies the rects out (animated or direct) onto the
/// matching subviews.
struct WindowLayout {
    let sidebar: NSRect
    let verticalDivider: NSRect
    let tabBar: NSRect
    let horizontalDivider: NSRect
    let terminal: NSRect
    let serverPanel: NSRect
    let serverDivider: NSRect
    let titlebarDivider: NSRect
    let emptyLabel: NSRect
    /// True when the window is fullscreen and the titlebar hairline should hide.
    let titlebarHidden: Bool

    init(bounds: NSRect, topInset: CGFloat, sidebarCollapsed: Bool, isPeeking: Bool, emptyLabelSize: NSSize) {
        let usableHeight = bounds.height - topInset
        let effectiveSidebarWidth: CGFloat = (sidebarCollapsed && !isPeeking) ? collapsedSidebarWidth : sidebarWidth
        let rightX = effectiveSidebarWidth
        let contentWidth = bounds.width - effectiveSidebarWidth - serverPanelWidth
        let panelX = bounds.width - serverPanelWidth

        sidebar = NSRect(x: 0, y: 0, width: effectiveSidebarWidth, height: usableHeight)
        verticalDivider = NSRect(x: effectiveSidebarWidth, y: 0, width: 1, height: usableHeight)
        tabBar = NSRect(x: rightX, y: usableHeight - Theme.headerHeight, width: contentWidth, height: Theme.headerHeight)
        horizontalDivider = NSRect(x: rightX, y: usableHeight - Theme.headerHeight, width: contentWidth, height: 1)
        terminal = NSRect(x: rightX, y: 0, width: contentWidth, height: usableHeight - Theme.headerHeight)
        serverPanel = NSRect(x: panelX, y: 0, width: serverPanelWidth, height: usableHeight)
        serverDivider = NSRect(x: panelX, y: 0, width: 1, height: usableHeight)
        titlebarDivider = NSRect(x: 0, y: usableHeight, width: bounds.width, height: 1)
        emptyLabel = NSRect(
            x: rightX + (contentWidth - emptyLabelSize.width) / 2,
            y: (usableHeight - emptyLabelSize.height) / 2,
            width: emptyLabelSize.width,
            height: emptyLabelSize.height
        )
        titlebarHidden = topInset <= 0
    }
}

// MARK: - Main Layout View

class MainLayoutView: NSView {
    let sidebar: ProjectSidebarView
    let tabBar: TabBarView
    let terminalContainer: TerminalContainerView
    let serverPanel: ServerPanelView
    private let emptyLabel: NSTextField
    private let verticalDivider: NSView
    private let serverDivider: NSView
    private let horizontalDivider: NSView
    /// Hairline under the macOS titlebar (traffic-light strip). Hidden in fullscreen.
    private let titlebarDivider: DividerView
    private(set) var sidebarCollapsed = false
    /// Transient state: sidebar is expanded on hover while still logically collapsed.
    /// Reset whenever the user clicks the toggle (which flips `sidebarCollapsed`).
    private var isPeeking = false

    override init(frame: NSRect) {
        sidebar = ProjectSidebarView(frame: NSRect(x: 0, y: 0, width: sidebarWidth, height: frame.height))
        tabBar = TabBarView(frame: .zero)
        terminalContainer = TerminalContainerView(frame: .zero)
        serverPanel = ServerPanelView(frame: .zero)

        emptyLabel = makeLabel("Select a project to begin", fontSize: 14, color: Theme.subtleLabelColor)
        emptyLabel.alignment = .center

        verticalDivider = NSView()
        verticalDivider.wantsLayer = true
        verticalDivider.layer?.backgroundColor = Theme.dividerCGColor

        serverDivider = NSView()
        serverDivider.wantsLayer = true
        serverDivider.layer?.backgroundColor = Theme.dividerCGColor

        horizontalDivider = NSView()
        horizontalDivider.wantsLayer = true
        horizontalDivider.layer?.backgroundColor = Theme.dividerCGColor

        titlebarDivider = DividerView(frame: .zero)

        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = bgColor.cgColor

        sidebar.onToggle = { [weak self] in self?.toggleSidebar() }
        sidebar.onMouseEnter = { [weak self] in self?.setPeeking(true) }
        sidebar.onMouseExit = { [weak self] in self?.setPeeking(false) }

        addSubview(sidebar)
        addSubview(tabBar)
        addSubview(terminalContainer)
        addSubview(serverPanel)
        addSubview(emptyLabel)
        addSubview(verticalDivider)
        addSubview(serverDivider)
        addSubview(horizontalDivider)
        addSubview(titlebarDivider)

        layoutSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutSubviews()
    }

    /// `applyLayout` reads `titlebarSafeInset` from `window.contentLayoutRect`, but
    /// at `init` time we're not in a window yet — `window` is nil and the inset
    /// returns 0, so the column headers end up flush with the very top of the
    /// content view (right under the traffic lights). Re-running the layout once
    /// the view is attached to a window picks up the real inset.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            layoutSubviews()
        }
    }

    func toggleSidebar() {
        sidebarCollapsed.toggle()
        isPeeking = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.sidebarAnim
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            applyLayout(animated: true)
        }
    }

    /// Peek-on-hover: while the sidebar is logically collapsed, hovering over the rail
    /// temporarily expands it. Clicking the toggle button locks the expansion by
    /// flipping `sidebarCollapsed` (see `toggleSidebar`).
    private func setPeeking(_ peeking: Bool) {
        guard sidebarCollapsed else { return }
        guard isPeeking != peeking else { return }
        isPeeking = peeking
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Theme.peekAnim
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            applyLayout(animated: true)
        }
    }

    /// MainLayoutView itself is draggable so users can move the window by grabbing the
    /// empty titlebar safe-area strip above the column headers.
    override var mouseDownCanMoveWindow: Bool { true }

    /// Height reserved at the top of the window for the system titlebar (traffic lights).
    /// Zero in fullscreen, ~28pt otherwise. Read from `contentLayoutRect` so AppKit stays
    /// the source of truth and transitions (fullscreen enter/exit) Just Work.
    private var titlebarSafeInset: CGFloat {
        guard let window = window else { return 0 }
        return max(0, bounds.height - window.contentLayoutRect.height)
    }

    private func layoutSubviews() {
        applyLayout(animated: false)
    }

    private func applyLayout(animated: Bool) {
        let layout = WindowLayout(
            bounds: bounds,
            topInset: titlebarSafeInset,
            sidebarCollapsed: sidebarCollapsed,
            isPeeking: isPeeking,
            emptyLabelSize: emptyLabel.intrinsicContentSize
        )

        titlebarDivider.isHidden = layout.titlebarHidden

        // Hide the project list in rail mode (collapsed, not peeking). Stays in sync
        // with the sidebar width animation.
        sidebar.setContentVisible(!(sidebarCollapsed && !isPeeking), animated: animated)

        // Pull the assignment closure out so the eight frame writes don't repeat
        // the animator/direct branch each time.
        let assign: (NSView, NSRect) -> Void = animated
            ? { $0.animator().frame = $1 }
            : { $0.frame = $1 }

        assign(sidebar, layout.sidebar)
        assign(verticalDivider, layout.verticalDivider)
        assign(tabBar, layout.tabBar)
        assign(horizontalDivider, layout.horizontalDivider)
        assign(terminalContainer, layout.terminal)
        assign(serverPanel, layout.serverPanel)
        assign(serverDivider, layout.serverDivider)
        assign(titlebarDivider, layout.titlebarDivider)
        assign(emptyLabel, layout.emptyLabel)
    }

    func setEmptyState(_ empty: Bool) {
        emptyLabel.isHidden = !empty
        tabBar.isHidden = empty
    }
}
