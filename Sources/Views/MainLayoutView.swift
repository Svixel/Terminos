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
        for subview in subviews {
            let terminalWidth = min(bounds.width - padding * 2, maxTerminalWidth)
            let terminalHeight = bounds.height - padding * 2
            let x = (bounds.width - terminalWidth) / 2
            subview.frame = NSRect(x: x, y: padding, width: terminalWidth, height: terminalHeight)
        }
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
        scrollView = NSScrollView(frame: .zero)
        tableView = NSTableView(frame: .zero)
        header = HeaderBar(title: "/SERVERS")

        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = bgColor.cgColor

        setupTableView()
        addSubview(header)
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("server"))
        column.width = frame.width
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 28
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .none
        tableView.style = .plain
        tableView.delegate = self
        tableView.dataSource = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
    }

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
        let portLabel = NSTextField(labelWithString: ":\(server.port)")
        portLabel.font = uiFont.withSize(11)
        portLabel.textColor = creamColor.withAlphaComponent(0.8)
        portLabel.isBordered = false
        portLabel.isEditable = false
        portLabel.frame = NSRect(x: 10, y: 18, width: cellWidth - 60, height: 14)
        cell.addSubview(portLabel)

        // Friendly name
        let nameLabel = NSTextField(labelWithString: server.friendlyName)
        nameLabel.font = uiFont.withSize(9)
        nameLabel.textColor = creamColor.withAlphaComponent(0.4)
        nameLabel.isBordered = false
        nameLabel.isEditable = false
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

        emptyLabel = NSTextField(labelWithString: "Select a project to begin")
        emptyLabel.font = uiFont.withSize(14)
        emptyLabel.textColor = creamColor.withAlphaComponent(0.3)
        emptyLabel.alignment = .center

        verticalDivider = NSView()
        verticalDivider.wantsLayer = true
        verticalDivider.layer?.backgroundColor = creamColor.withAlphaComponent(0.08).cgColor

        serverDivider = NSView()
        serverDivider.wantsLayer = true
        serverDivider.layer?.backgroundColor = creamColor.withAlphaComponent(0.08).cgColor

        horizontalDivider = NSView()
        horizontalDivider.wantsLayer = true
        horizontalDivider.layer?.backgroundColor = creamColor.withAlphaComponent(0.08).cgColor

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
            ctx.duration = 0.2
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
            ctx.duration = 0.15
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
        let topInset = titlebarSafeInset
        let usableHeight = bounds.height - topInset
        let effectiveSidebarWidth: CGFloat = (sidebarCollapsed && !isPeeking) ? collapsedSidebarWidth : sidebarWidth
        let sw: CGFloat = effectiveSidebarWidth
        let rightX = sw
        let contentWidth = bounds.width - sw - serverPanelWidth
        let panelX = bounds.width - serverPanelWidth

        let sidebarTarget = NSRect(x: 0, y: 0, width: effectiveSidebarWidth, height: usableHeight)
        let dividerTarget = NSRect(x: sw, y: 0, width: 1, height: usableHeight)
        let tabTarget = NSRect(x: rightX, y: usableHeight - Theme.headerHeight, width: contentWidth, height: Theme.headerHeight)
        let hDivTarget = NSRect(x: rightX, y: usableHeight - Theme.headerHeight, width: contentWidth, height: 1)
        let termTarget = NSRect(x: rightX, y: 0, width: contentWidth, height: usableHeight - Theme.headerHeight)
        let panelTarget = NSRect(x: panelX, y: 0, width: serverPanelWidth, height: usableHeight)
        let sDivTarget = NSRect(x: panelX, y: 0, width: 1, height: usableHeight)
        let titlebarDivTarget = NSRect(x: 0, y: usableHeight, width: bounds.width, height: 1)
        let labelSize = emptyLabel.intrinsicContentSize
        let labelTarget = NSRect(
            x: rightX + (contentWidth - labelSize.width) / 2,
            y: (usableHeight - labelSize.height) / 2,
            width: labelSize.width,
            height: labelSize.height
        )

        titlebarDivider.isHidden = topInset <= 0

        // Hide the project list in rail mode (collapsed, not peeking). Stays in sync
        // with the sidebar width animation.
        let contentVisible = !(sidebarCollapsed && !isPeeking)
        sidebar.setContentVisible(contentVisible, animated: animated)

        if animated {
            sidebar.animator().frame = sidebarTarget
            verticalDivider.animator().frame = dividerTarget
            tabBar.animator().frame = tabTarget
            horizontalDivider.animator().frame = hDivTarget
            terminalContainer.animator().frame = termTarget
            serverPanel.animator().frame = panelTarget
            serverDivider.animator().frame = sDivTarget
            titlebarDivider.animator().frame = titlebarDivTarget
            emptyLabel.animator().frame = labelTarget
        } else {
            sidebar.frame = sidebarTarget
            verticalDivider.frame = dividerTarget
            tabBar.frame = tabTarget
            horizontalDivider.frame = hDivTarget
            terminalContainer.frame = termTarget
            serverPanel.frame = panelTarget
            serverDivider.frame = sDivTarget
            titlebarDivider.frame = titlebarDivTarget
            emptyLabel.frame = labelTarget
        }
    }

    func setEmptyState(_ empty: Bool) {
        emptyLabel.isHidden = !empty
        tabBar.isHidden = empty
    }
}
