import Cocoa

// MARK: - Server List View

/// Bottom half of the sidebar — the `:SERVERS` list. Receives pre-resolved
/// `(server, projectName)` pairs from `ProjectSidebarView`. In rail mode the
/// cells collapse down to a single status dot centered in the 40pt rail; the
/// shell flips the mode via `setContentVisible`.
class ServerListView: NSView {
    typealias Entry = (server: ServerInfo, projectName: String?)

    private let scrollView: NSScrollView
    private let tableView: NSTableView
    private var entries: [Entry] = []
    private var isCollapsedRail = false

    override init(frame: NSRect) {
        (scrollView, tableView) = makeSidebarTable(rowHeight: Theme.serverRowHeight)

        super.init(frame: frame)

        tableView.delegate = self
        tableView.dataSource = self
        scrollView.automaticallyAdjustsContentInsets = false
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        scrollView.frame = bounds
    }

    /// Replace the displayed entries and refresh the table.
    func update(_ newEntries: [Entry]) {
        entries = newEntries
        tableView.reloadData()
    }

    /// Switch between rail mode (single centered dot per row) and full mode
    /// (icon + title + browser buttons). Reload the table so cells are rebuilt
    /// against the new mode. Cells use `collapsedSidebarWidth` / `sidebarWidth`
    /// for positioning, so the reload is safe to call before the parent's
    /// frame animation finishes.
    func setContentVisible(_ visible: Bool, animated: Bool) {
        let newCollapsed = !visible
        guard isCollapsedRail != newCollapsed else { return }
        isCollapsedRail = newCollapsed
        tableView.reloadData()
    }
}

extension ServerListView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellID = NSUserInterfaceItemIdentifier("LeftServerCell")
        let cell = self.tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView
            ?? NSTableCellView(frame: .zero)
        cell.identifier = cellID
        cell.subviews.forEach { $0.removeFromSuperview() }

        let item = entries[row]
        let rowHeight = Theme.serverRowHeight
        let dotSize: CGFloat = 8

        if isCollapsedRail {
            // Rail: only the centered status dot. Hardcoded against
            // `collapsedSidebarWidth` because `bounds.width` may still hold
            // the expanded width while the frame animation is in flight.
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
        let titleLabel = makeLabel(titleText, fontSize: 13, color: Theme.strongLabelColor)
        titleLabel.tag = 101
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

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = HoverRowView()
        rowView.isEmphasized = false
        return rowView
    }
}
