import Cocoa

// MARK: - Sidebar Delegate

protocol SidebarDelegate: AnyObject {
    func sidebarDidSelectProject(path: String)
}

// MARK: - Project List View

/// Top half of the sidebar — the `/CODE` project list. Loads project metadata
/// at init, owns its scroll/table chrome, and emits a click via `delegate`.
/// In rail mode (`isCollapsedRail`) the list fades out completely.
class ProjectListView: NSView {
    weak var delegate: SidebarDelegate?

    private(set) var projects: [(name: String, gitStatus: GitStatus, techStack: TechStack)] = []
    private let scrollView: NSScrollView
    private let tableView: NSTableView
    private var isCollapsedRail = false

    override init(frame: NSRect) {
        (scrollView, tableView) = makeSidebarTable(rowHeight: Theme.rowHeight)

        super.init(frame: frame)

        loadProjects()
        setupTable()
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        scrollView.frame = bounds
    }

    /// Fade the project list to zero alpha when the sidebar collapses, then hide
    /// when the fade completes so the rail doesn't keep receiving hover hits on
    /// invisible rows. The reverse on expand: un-hide first, then fade in.
    func setContentVisible(_ visible: Bool, animated: Bool) {
        let newCollapsed = !visible
        guard isCollapsedRail != newCollapsed else { return }
        isCollapsedRail = newCollapsed

        if visible {
            scrollView.isHidden = false
        }

        let targetAlpha: CGFloat = visible ? 1.0 : 0.0
        let finalize: () -> Void = { [weak self] in
            guard let self, !visible else { return }
            self.scrollView.isHidden = true
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

    private func setupTable() {
        // .plain disables AppKit's automatic leading inset so the cell's own
        // x=Theme.cellLeading padding is the only source of left space.
        tableView.delegate = self
        tableView.dataSource = self
        tableView.action = #selector(projectRowClicked)
        tableView.target = self

        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.autoresizingMask = [.width, .height]
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

    @objc private func projectRowClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < projects.count else { return }
        let path = (projectsPath as NSString).appendingPathComponent(projects[row].name)
        delegate?.sidebarDidSelectProject(path: path)
    }
}

extension ProjectListView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        projects.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
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

        let nameLabel = makeLabel(project.name, fontSize: 12, color: Theme.mutedLabelColor)
        nameLabel.tag = 101
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

        for icon in techStackIcons(for: project.techStack) {
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

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = HoverRowView()
        rowView.isEmphasized = false
        return rowView
    }
}
