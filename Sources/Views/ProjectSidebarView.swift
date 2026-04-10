import Cocoa

// MARK: - Project Sidebar View

protocol SidebarDelegate: AnyObject {
    func sidebarDidSelectProject(path: String)
}

class ProjectSidebarView: NSView {
    weak var delegate: SidebarDelegate?
    var onToggle: (() -> Void)?
    /// Fires when the mouse enters the sidebar bounds. Used by the layout to trigger
    /// peek-on-hover while the sidebar is collapsed.
    var onMouseEnter: (() -> Void)?
    /// Fires when the mouse exits the sidebar bounds.
    var onMouseExit: (() -> Void)?
    private let header: HeaderBar
    private let toggleButton: HoverIconButton
    private let scrollView: NSScrollView
    private let tableView: NSTableView
    private var projects: [(name: String, gitStatus: GitStatus, techStack: TechStack)] = []
    private var hoverTrackingArea: NSTrackingArea?

    // :SERVERS section (bottom of left sidebar)
    private let serversHeader: HeaderBar
    private let serversScrollView: NSScrollView
    private let serversTableView: NSTableView
    /// Hairline that sits flush with the top edge of the :SERVERS section so the
    /// boundary between the project list and the server list is visible.
    private let serversTopDivider: DividerView
    /// Server list shown in the bottom section of the sidebar. Each entry pairs the
    /// raw server with the name of the project its working directory belongs to.
    private var runningServers: [(server: ServerInfo, projectName: String?)] = []
    /// Floor for the bottom :SERVERS section. The section is responsive above this.
    private let serverSectionMinHeight: CGFloat = 280
    /// True when the sidebar is showing as a 40pt rail. Cell builders check this
    /// so they render a centered status dot instead of the full row content.
    /// Kept in sync by `setContentVisible` from `MainLayoutView`.
    private var isCollapsedRail = false

    override init(frame: NSRect) {
        header = HeaderBar(title: "/CODE")

        toggleButton = HoverIconButton(
            svgName: "layout-align-left-solid-sharp.svg",
            iconSize: 14,
            baseAlpha: 0.5,
            hoverAlpha: 1.0
        )

        scrollView = NSScrollView(frame: .zero)
        tableView = NSTableView(frame: scrollView.bounds)

        let serverIcon = loadSVGIcon(named: "mcp-server-solid-sharp.svg", size: 14, alpha: 0.6)
        serversHeader = HeaderBar(title: ":SERVERS", narrowIcon: serverIcon)
        serversScrollView = NSScrollView(frame: .zero)
        serversTableView = NSTableView(frame: .zero)
        serversTopDivider = DividerView(frame: .zero)

        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = bgColor.cgColor

        toggleButton.target = self
        toggleButton.action = #selector(toggleSidebar)
        header.setTrailingButton(toggleButton)

        addSubview(header)
        addSubview(serversHeader)
        addSubview(serversTopDivider)

        loadProjects()
        setupTableView()
        setupServersTableView()

        // Force initial layout — `MainLayoutView.applyLayout` will set our frame to
        // the same dimensions we were created with, so AppKit's `resizeSubviews`
        // never fires on its own.
        performLayout()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = hoverTrackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExit?()
    }

    /// Hook for `MainLayoutView` to notify the sidebar of collapse changes. In
    /// rail mode we fade the project list to zero and swap the server rows down
    /// to a single centered status dot. The /CODE header (with its toggle) and
    /// the :SERVERS header (narrow mode: centered MCP icon + bottom divider)
    /// stay visible so the rail still reads as two sections.
    func setContentVisible(_ visible: Bool, animated: Bool) {
        let newCollapsed = !visible
        guard isCollapsedRail != newCollapsed else { return }
        isCollapsedRail = newCollapsed

        // Un-hide BEFORE fade-in so the animation runs on a visible layer.
        // Fade-out hides AFTER the animation completes (below).
        if visible {
            scrollView.isHidden = false
        }

        // Entering rail: reload now so cells immediately draw the centered dot.
        // Cells use `collapsedSidebarWidth` (not `bounds.width`) for positioning,
        // so reloading before the frame animation finishes is safe.
        if !visible {
            serversTableView.reloadData()
        }

        let targetAlpha: CGFloat = visible ? 1.0 : 0.0

        let finalize: () -> Void = { [weak self] in
            guard let self = self else { return }
            if visible {
                // Leaving rail: rebuild cells with the full layout.
                self.serversTableView.reloadData()
            } else {
                self.scrollView.isHidden = true
            }
        }

        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Theme.sidebarAnim
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                scrollView.animator().alphaValue = targetAlpha
            }, completionHandler: finalize)
        } else {
            scrollView.alphaValue = targetAlpha
            finalize()
        }
    }

    /// Refresh the bottom :SERVERS section. Each server is paired with the name
    /// of the project its working directory lives inside.
    func updateServers(_ servers: [ServerInfo]) {
        runningServers = servers.map { server -> (server: ServerInfo, projectName: String?) in
            var projectName: String?
            if let cwd = server.cwd {
                for project in projects {
                    let projectPath = (projectsPath as NSString).appendingPathComponent(project.name)
                    if cwd == projectPath || cwd.hasPrefix(projectPath + "/") {
                        projectName = project.name
                        break
                    }
                }
            }
            return (server: server, projectName: projectName)
        }
        serversTableView.reloadData()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggleSidebar() {
        onToggle?()
    }

    private func loadProjects() {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: projectsPath) else { return }
        projects = contents
            .filter { name in
                var isDir: ObjCBool = false
                let full = (projectsPath as NSString).appendingPathComponent(name)
                return FileManager.default.fileExists(atPath: full, isDirectory: &isDir) && isDir.boolValue
                    && !name.hasPrefix(".")
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { name in
                let full = (projectsPath as NSString).appendingPathComponent(name)
                return (name: name, gitStatus: checkGitStatus(at: full), techStack: detectTechStack(at: full))
            }
    }

    private func setupTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("project"))
        column.width = frame.width
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = Theme.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .none
        // .plain disables AppKit's automatic leading inset so the cell's own x=20
        // padding is the only source of left space.
        tableView.style = .plain
        tableView.delegate = self
        tableView.dataSource = self
        tableView.action = #selector(projectRowClicked)
        tableView.target = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.autoresizingMask = [.width, .height]

        addSubview(scrollView)
    }

    private func setupServersTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("server"))
        column.width = frame.width
        serversTableView.addTableColumn(column)
        serversTableView.headerView = nil
        serversTableView.backgroundColor = .clear
        serversTableView.rowHeight = Theme.serverRowHeight
        serversTableView.intercellSpacing = NSSize(width: 0, height: 0)
        serversTableView.selectionHighlightStyle = .none
        serversTableView.style = .plain
        serversTableView.delegate = self
        serversTableView.dataSource = self

        serversScrollView.documentView = serversTableView
        serversScrollView.hasVerticalScroller = false
        serversScrollView.hasHorizontalScroller = false
        serversScrollView.drawsBackground = false
        serversScrollView.automaticallyAdjustsContentInsets = false

        addSubview(serversScrollView)
    }

    @objc private func projectRowClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < projects.count else { return }
        let path = (projectsPath as NSString).appendingPathComponent(projects[row].name)
        delegate?.sidebarDidSelectProject(path: path)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        performLayout()
    }

    /// Position every owned subview based on the current `bounds`. Called from
    /// `resizeSubviews` AND from `init`, because AppKit short-circuits
    /// `resizeSubviews` when the parent assigns a frame equal to the existing one,
    /// which is exactly what `MainLayoutView.applyLayout` does for the sidebar at
    /// startup. Without this manual call, the sidebar contents stay at .zero until
    /// the first interaction nudges a relayout.
    private func performLayout() {
        // Layout from top to bottom in y-up coordinates:
        //   /CODE header        (Theme.headerHeight)
        //   project list        (whatever's left)
        //   :SERVERS header     (Theme.headerHeight)
        //   server list         (>= serverSectionMinHeight)
        //
        // Server section is responsive (~45% of window) but never shorter than the
        // floor, and never tall enough to push the project list below 0.
        let preferredServerHeight = max(serverSectionMinHeight, bounds.height * 0.45)
        let serverSectionHeight = min(preferredServerHeight, max(0, bounds.height - Theme.headerHeight))

        header.frame = NSRect(
            x: 0,
            y: bounds.height - Theme.headerHeight,
            width: bounds.width,
            height: Theme.headerHeight
        )

        let projectListHeight = max(0, bounds.height - Theme.headerHeight - serverSectionHeight)
        scrollView.frame = NSRect(
            x: 0,
            y: serverSectionHeight,
            width: bounds.width,
            height: projectListHeight
        )

        serversHeader.frame = NSRect(
            x: 0,
            y: serverSectionHeight - Theme.headerHeight,
            width: bounds.width,
            height: Theme.headerHeight
        )

        // 1pt hairline along the top edge of the :SERVERS section, marking the
        // boundary between the project list and the server list above the header.
        serversTopDivider.frame = NSRect(
            x: 0,
            y: serverSectionHeight,
            width: bounds.width,
            height: 1
        )

        serversScrollView.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: max(0, serverSectionHeight - Theme.headerHeight)
        )
    }
}

extension ProjectSidebarView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === self.serversTableView {
            return runningServers.count
        }
        return projects.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === self.serversTableView {
            return makeServerCell(row: row)
        }
        return makeProjectCell(row: row)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = HoverRowView()
        rowView.isEmphasized = false
        return rowView
    }

    private func makeProjectCell(row: Int) -> NSView {
        let cellID = NSUserInterfaceItemIdentifier("ProjectCell")
        let cell = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView
            ?? NSTableCellView(frame: .zero)
        cell.identifier = cellID
        cell.subviews.forEach { $0.removeFromSuperview() }

        let rowHeight = Theme.rowHeight
        let project = projects[row]

        let iconView = makeIconView(named: "file-terminal-solid-sharp.svg", size: 16, alpha: 0.5)
        iconView.frame = NSRect(x: Theme.cellLeading, y: (rowHeight - 16) / 2, width: 16, height: 16)
        iconView.tag = 100
        cell.addSubview(iconView)

        let nameLabel = NSTextField(labelWithString: project.name)
        nameLabel.tag = 101
        nameLabel.font = uiFont.withSize(12)
        nameLabel.textColor = Theme.mutedLabelColor
        nameLabel.backgroundColor = .clear
        nameLabel.isBordered = false
        nameLabel.isEditable = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.sizeToFit()
        let nameHeight = nameLabel.frame.height
        nameLabel.frame = NSRect(
            x: Theme.cellTextLeading,
            y: (rowHeight - nameHeight) / 2,
            width: bounds.width - Theme.cellTextLeading * 2,
            height: nameHeight
        )
        cell.addSubview(nameLabel)

        var iconX = bounds.width - 16
        if project.gitStatus != .none {
            let svgName = project.gitStatus == .github ? "github-solid-sharp.svg" : "git-branch-solid-sharp.svg"
            let gitView = makeIconView(named: svgName, size: 12, alpha: 0.3)
            iconX -= Theme.cellIconStride
            gitView.frame = NSRect(x: iconX, y: (rowHeight - 12) / 2, width: 12, height: 12)
            cell.addSubview(gitView)
        }

        let stackIcons = techStackIcons(for: project.techStack)
        for icon in stackIcons {
            if icon.hasSuffix(".svg") {
                let sv = makeIconView(named: icon, size: 12, alpha: 0.3)
                iconX -= Theme.cellIconStride
                sv.frame = NSRect(x: iconX, y: (rowHeight - 12) / 2, width: 12, height: 12)
                cell.addSubview(sv)
            } else {
                let glyph: UInt32 = icon == "jsx-02" ? jsxGlyph : zapGlyph
                let label = NSTextField(labelWithAttributedString: hugeIconString(glyph, size: 10, alpha: 0.3))
                iconX -= Theme.cellIconStride
                label.frame = NSRect(x: iconX, y: (rowHeight - 16) / 2, width: 14, height: 16)
                cell.addSubview(label)
            }
        }
        return cell
    }

    /// Server row in the bottom :SERVERS section. Layout matches the project rows:
    /// leading status dot at x=24 (centered on the project icon column), title at
    /// x=42 (same as project names), Safari/Chrome buttons trailing. In rail mode
    /// (`isCollapsedRail`) only a single status dot is rendered, centered in the
    /// 40pt rail.
    private func makeServerCell(row: Int) -> NSView {
        let cellID = NSUserInterfaceItemIdentifier("LeftServerCell")
        let cell = serversTableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView
            ?? NSTableCellView(frame: .zero)
        cell.identifier = cellID
        cell.subviews.forEach { $0.removeFromSuperview() }

        let item = runningServers[row]
        let rowHeight = Theme.serverRowHeight
        let dotSize: CGFloat = 8

        if isCollapsedRail {
            // Rail: only the centered status dot. Hardcode against
            // `collapsedSidebarWidth` because `bounds.width` may still hold the
            // expanded width while the frame animation is in flight.
            let dot = StatusDotView(diameter: dotSize, color: Theme.statusRunningColor)
            dot.frame = NSRect(
                x: (collapsedSidebarWidth - dotSize) / 2,
                y: (rowHeight - dotSize) / 2,
                width: dotSize,
                height: dotSize
            )
            cell.addSubview(dot)
            return cell
        }

        // Full layout. Use `sidebarWidth` instead of `bounds.width` so peek-in
        // reloads build cells with the final expanded width, not the rail width
        // that's still in place while the frame animation runs.
        let cellWidth = sidebarWidth

        // Status dot — sits in the same x slot as the project terminal icon.
        let dot = StatusDotView(diameter: dotSize, color: Theme.statusRunningColor)
        dot.frame = NSRect(
            x: Theme.cellLeading + (16 - dotSize) / 2,
            y: (rowHeight - dotSize) / 2,
            width: dotSize,
            height: dotSize
        )
        cell.addSubview(dot)

        let prefix = item.projectName ?? ""
        let titleText = prefix.isEmpty ? ":\(item.server.port)" : "\(prefix):\(item.server.port)"
        let titleLabel = NSTextField(labelWithString: titleText)
        titleLabel.tag = 101
        titleLabel.font = uiFont.withSize(13)
        titleLabel.textColor = Theme.strongLabelColor
        titleLabel.backgroundColor = .clear
        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.sizeToFit()
        let titleHeight = titleLabel.frame.height
        titleLabel.frame = NSRect(
            x: Theme.cellTextLeading,
            y: (rowHeight - titleHeight) / 2,
            width: max(0, cellWidth - Theme.cellTextLeading - Theme.cellIconStride),
            height: titleHeight
        )
        cell.addSubview(titleLabel)

        return cell
    }
}
