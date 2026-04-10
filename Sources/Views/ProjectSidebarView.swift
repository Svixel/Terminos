import Cocoa

// MARK: - Project Sidebar View

/// The left column. Composes a `ProjectListView` (top) and a `ServerListView`
/// (bottom) under two `HeaderBar`s, owns the `/CODE` collapse toggle, the
/// peek-on-hover tracking that bubbles up to `MainLayoutView`, and the layout
/// math that splits the column between the two child sections.
class ProjectSidebarView: NSView {
    weak var delegate: SidebarDelegate? {
        didSet { projectList.delegate = delegate }
    }
    var onToggle: (() -> Void)?
    /// Fires when the mouse enters the sidebar bounds. Used by the layout to trigger
    /// peek-on-hover while the sidebar is collapsed.
    var onMouseEnter: (() -> Void)?
    /// Fires when the mouse exits the sidebar bounds.
    var onMouseExit: (() -> Void)?

    private let header: HeaderBar
    private let toggleButton: HoverIconButton
    private let serversHeader: HeaderBar
    /// Hairline that sits flush with the top edge of the :SERVERS section so the
    /// boundary between the project list and the server list is visible.
    private let serversTopDivider: DividerView
    private let projectList: ProjectListView
    private let serverList: ServerListView
    private var hoverTrackingArea: NSTrackingArea?
    /// Floor for the bottom :SERVERS section. The section is responsive above this.
    private let serverSectionMinHeight: CGFloat = 280

    override init(frame: NSRect) {
        header = HeaderBar(title: "/CODE")

        toggleButton = HoverIconButton(
            svgName: "layout-align-left-solid-sharp.svg",
            iconSize: 14,
            baseAlpha: 0.5,
            hoverAlpha: 1.0
        )

        let serverIcon = loadSVGIcon(named: "mcp-server-solid-sharp.svg", size: 14, alpha: 0.6)
        serversHeader = HeaderBar(title: ":SERVERS", narrowIcon: serverIcon)
        serversTopDivider = DividerView(frame: .zero)

        projectList = ProjectListView(frame: .zero)
        serverList = ServerListView(frame: .zero)

        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = bgColor.cgColor

        toggleButton.target = self
        toggleButton.action = #selector(toggleSidebar)
        header.setTrailingButton(toggleButton)

        addSubview(projectList)
        addSubview(serverList)
        addSubview(header)
        addSubview(serversHeader)
        addSubview(serversTopDivider)

        // Force initial layout — `MainLayoutView.applyLayout` will set our frame to
        // the same dimensions we were created with, so AppKit's `resizeSubviews`
        // never fires on its own.
        performLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        hoverTrackingArea = installHoverTrackingArea(replacing: hoverTrackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExit?()
    }

    /// Hook for `MainLayoutView` to notify the sidebar of collapse changes. Forward
    /// to both children: the project list fades to zero, the server list switches
    /// its rows down to a single centered status dot. The `/CODE` and `:SERVERS`
    /// headers stay visible — the latter falls into its own narrow mode (centered
    /// MCP icon) thanks to the rail width crossing `HeaderBar`'s threshold.
    func setContentVisible(_ visible: Bool, animated: Bool) {
        projectList.setContentVisible(visible, animated: animated)
        serverList.setContentVisible(visible, animated: animated)
    }

    /// Refresh the bottom `:SERVERS` section. Each server is paired with the name
    /// of the project its working directory lives inside.
    func updateServers(_ servers: [ServerInfo]) {
        let entries = servers.map { server in
            let projectName = server.cwd.flatMap { cwd in
                projectList.projects.first { project in
                    let projectPath = (projectsPath as NSString).appendingPathComponent(project.name)
                    return cwd == projectPath || cwd.hasPrefix(projectPath + "/")
                }?.name
            }
            return (server: server, projectName: projectName)
        }
        serverList.update(entries)
    }

    @objc private func toggleSidebar() {
        onToggle?()
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
        projectList.frame = NSRect(
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

        serverList.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: max(0, serverSectionHeight - Theme.headerHeight)
        )
    }
}
