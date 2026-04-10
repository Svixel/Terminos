import Cocoa
import CoreText
import SwiftTerm

// MARK: - Theme

private let bgColor = NSColor(red: 0x1C / 255.0, green: 0x1D / 255.0, blue: 0x24 / 255.0, alpha: 1.0)
private let creamColor = NSColor(red: 0xF5 / 255.0, green: 0xF0 / 255.0, blue: 0xE8 / 255.0, alpha: 1.0)
private let sidebarWidth: CGFloat = 220
/// Width of the sidebar when collapsed. Matches `Theme.headerHeight` so the header
/// area becomes a 1:1 square — toggle button on top, terminal-icon column under it.
private let collapsedSidebarWidth: CGFloat = 40
private let serverPanelWidth: CGFloat = 180
private let commandLineUnicode: UInt32 = 988747 // HugeIcons command-line solid-rounded
private let projectsPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Documents/CODE").path

/// Centralized design tokens. New components should read from here instead of hard-coding values.
enum Theme {
    /// Uniform height for every top-strip header (sidebar, tab area, server panel).
    static let headerHeight: CGFloat = 40
    /// Default left/right padding inside a header.
    static let horizontalPadding: CGFloat = 20
    /// Size of a trailing action button slot inside a header.
    static let headerButtonSize: CGFloat = 18
    static let headerFontSize: CGFloat = 12
    static let rowHeight: CGFloat = 28

    static var dividerCGColor: CGColor { creamColor.withAlphaComponent(0.08).cgColor }
    static var mutedLabelColor: NSColor { creamColor.withAlphaComponent(0.5) }
    static var subtleLabelColor: NSColor { creamColor.withAlphaComponent(0.3) }

    /// Running-server indicator dot color. Soft green that reads against the dark bg.
    static let statusRunningColor = NSColor(red: 0.35, green: 0.85, blue: 0.45, alpha: 1.0)
}

// MARK: - Font Registration

private var terminalFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .ultraLight)
private var uiFont: NSFont = .systemFont(ofSize: 13, weight: .light)
private var iconFontName: String?

private func registerFonts() {
    let resources = ["AzeretMono-Variable.ttf", "hgi-solid-rounded.ttf"]
    for filename in resources {
        guard let url = Bundle.module.url(forResource: filename, withExtension: nil, subdirectory: "Resources") else {
            NSLog("[Font] \(filename) not found in bundle")
            continue
        }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if let err = error?.takeRetainedValue() {
            NSLog("[Font] Registration error for \(filename): \(err)")
        }
    }

    // Address Azeret Mono's named instances directly by PostScript name. Going
    // through fontDescriptor weight traits on a variable font applies a variation
    // coordinate instead of picking the hinted named instance, which renders
    // soft at small sizes.
    if let ui = NSFont(name: "AzeretMono-Light", size: 13) {
        uiFont = ui
    }
    if let term = NSFont(name: "AzeretMono-ExtraLight", size: 13) {
        terminalFont = term
    }

    // Resolve icon font - find the PostScript name
    if let url = Bundle.module.url(forResource: "hgi-solid-rounded.ttf", withExtension: nil, subdirectory: "Resources"),
       let dataProvider = CGDataProvider(url: url as CFURL),
       let cgFont = CGFont(dataProvider),
       let psName = cgFont.postScriptName as String? {
        iconFontName = psName
    }
}

private func loadSVGIcon(named filename: String, size: CGFloat, tint: NSColor = creamColor, alpha: CGFloat = 1.0) -> NSImage? {
    guard let url = Bundle.module.url(forResource: filename, withExtension: nil, subdirectory: "Resources"),
          var svgString = try? String(contentsOf: url, encoding: .utf8) else { return nil }

    // Replace currentColor with actual hex color
    let r = Int(tint.redComponent * 255 * alpha)
    let g = Int(tint.greenComponent * 255 * alpha)
    let b = Int(tint.blueComponent * 255 * alpha)
    let hex = String(format: "#%02X%02X%02X", r, g, b)
    svgString = svgString.replacingOccurrences(of: "currentColor", with: hex)
    // Remove fill="none" on the root svg element so the paths render
    svgString = svgString.replacingOccurrences(of: "fill=\"none\"", with: "")

    guard let data = svgString.data(using: .utf8),
          let image = NSImage(data: data) else { return nil }
    image.size = NSSize(width: size, height: size)
    return image
}

private func makeIconView(named filename: String, size: CGFloat, alpha: CGFloat = 0.7) -> NSImageView {
    let view = NSImageView()
    if let img = loadSVGIcon(named: filename, size: size, alpha: alpha) {
        view.image = img
    }
    view.imageScaling = .scaleProportionallyUpOrDown
    return view
}

private let githubUnicode: UInt32 = 989462
private let gitBranchUnicode: UInt32 = 989452

enum TechStack {
    case ios, expo, nextjs, vite, unknown
}

private func detectTechStack(at path: String) -> TechStack {
    let fm = FileManager.default
    let contents = (try? fm.contentsOfDirectory(atPath: path)) ?? []

    // iOS / Swift
    if contents.contains("Package.swift") || contents.contains(where: { $0.hasSuffix(".xcodeproj") }) || contents.contains(where: { $0.hasSuffix(".xcworkspace") }) {
        return .ios
    }
    // Expo / React Native
    if contents.contains("app.json") || contents.contains("app.config.js") || contents.contains("app.config.ts") {
        return .expo
    }
    // Next.js
    if contents.contains(where: { $0.hasPrefix("next.config") }) {
        return .nextjs
    }
    // Vite
    if contents.contains(where: { $0.hasPrefix("vite.config") }) {
        return .vite
    }
    return .unknown
}

private func techStackIcons(for stack: TechStack) -> [String] {
    switch stack {
    case .ios: return ["apple-finder-solid-sharp.svg", "ai-phone-01-solid-sharp.svg"]
    case .expo: return ["ai-phone-01-solid-sharp.svg"]
    case .nextjs: return ["jsx-02"]  // keep as HugeIcon font glyph
    case .vite: return ["zap"]       // keep as HugeIcon font glyph
    case .unknown: return []
    }
}

private let jsxGlyph: UInt32 = 989796
private let zapGlyph: UInt32 = 992297

private func hugeIconString(_ unicode: UInt32, size: CGFloat, alpha: CGFloat = 0.4) -> NSAttributedString {
    guard let fontName = iconFontName,
          let font = NSFont(name: fontName, size: size),
          let scalar = Unicode.Scalar(unicode) else {
        return NSAttributedString(string: "")
    }
    return NSAttributedString(string: String(scalar), attributes: [
        .foregroundColor: creamColor.withAlphaComponent(alpha),
        .font: font
    ])
}

enum GitStatus {
    case none, gitOnly, github
}

private func checkGitStatus(at path: String) -> GitStatus {
    let gitDir = (path as NSString).appendingPathComponent(".git")
    guard FileManager.default.fileExists(atPath: gitDir) else { return .none }

    let configPath = (gitDir as NSString).appendingPathComponent("config")
    guard let config = try? String(contentsOfFile: configPath, encoding: .utf8) else { return .gitOnly }
    return config.contains("github.com") ? .github : .gitOnly
}

// MARK: - Server Detection

struct ServerInfo: Equatable {
    let port: Int
    let pid: Int32
    let processName: String
    let friendlyName: String
    /// Working directory of the listening process, resolved via `lsof -d cwd`.
    /// Nil if the lookup failed or the process has no cwd. Used to associate a
    /// running server with a project folder in the sidebar.
    let cwd: String?

    static func == (lhs: ServerInfo, rhs: ServerInfo) -> Bool {
        lhs.port == rhs.port && lhs.pid == rhs.pid
    }
}

class ServerDetector {
    var onServersChanged: (([ServerInfo]) -> Void)?

    private var timer: DispatchSourceTimer?
    private var lastServers: [ServerInfo] = []
    private let backgroundQueue = DispatchQueue(label: "server-detector", qos: .utility)

    private let ignoredProcesses: Set<String> = [
        "rapportd", "ControlCe", "mDNSResponder", "launchd",
        "sharingd", "AirPlayXPCHelper", "WiFiAgent", "bluetoothd"
    ]

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: backgroundQueue)
        timer.schedule(deadline: .now(), repeating: 5.0)
        timer.setEventHandler { [weak self] in self?.scan() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func scan() {
        let lsofOutput = runCommand("/usr/sbin/lsof", args: ["-iTCP", "-sTCP:LISTEN", "-n", "-P"])

        var seenPorts = Set<Int>()
        var rawEntries: [(pid: Int32, processName: String, port: Int)] = []

        for line in lsofOutput.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 9 else { continue }

            let processName = String(cols[0])
            guard !ignoredProcesses.contains(processName) else { continue }
            guard let pid = Int32(cols[1]) else { continue }

            // lsof appends "(LISTEN)" as its own whitespace-separated column, so the
            // address (e.g. "127.0.0.1:5174", "*:3000", "[::1]:5432") sits second-to-last.
            let name = String(cols[cols.count - 2])
            guard let colonIdx = name.lastIndex(of: ":"),
                  let port = Int(name[name.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)),
                  port >= 1024 else { continue }

            guard !seenPorts.contains(port) else { continue }
            seenPorts.insert(port)
            rawEntries.append((pid, processName, port))
        }

        var pidArgs: [Int32: String] = [:]
        for pid in Set(rawEntries.map(\.pid)) {
            pidArgs[pid] = runCommand("/bin/ps", args: ["-p", "\(pid)", "-o", "args="]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Batch cwd lookup: one lsof call for every PID we care about. The -Fn output
        // groups fields by process record (lines starting with `p`), followed by a
        // single `fcwd` descriptor and its `n` (path) field.
        var pidCwds: [Int32: String] = [:]
        let uniquePids = Set(rawEntries.map(\.pid))
        if !uniquePids.isEmpty {
            let pidsArg = uniquePids.map(String.init).joined(separator: ",")
            let cwdOutput = runCommand("/usr/sbin/lsof", args: ["-a", "-d", "cwd", "-Fn", "-p", pidsArg])
            var currentPid: Int32?
            for line in cwdOutput.split(separator: "\n") {
                let s = String(line)
                if s.hasPrefix("p") {
                    currentPid = Int32(s.dropFirst())
                } else if s.hasPrefix("n"), let pid = currentPid {
                    pidCwds[pid] = String(s.dropFirst())
                }
            }
        }

        let servers = rawEntries.map { entry -> ServerInfo in
            let args = pidArgs[entry.pid] ?? ""
            let friendly = identifyFramework(processName: entry.processName, args: args)
            return ServerInfo(
                port: entry.port,
                pid: entry.pid,
                processName: entry.processName,
                friendlyName: friendly,
                cwd: pidCwds[entry.pid]
            )
        }.sorted { $0.port < $1.port }

        if servers != lastServers {
            lastServers = servers
            DispatchQueue.main.async { [weak self] in
                self?.onServersChanged?(servers)
            }
        }
    }

    private func identifyFramework(processName: String, args: String) -> String {
        let argsLower = args.lowercased()
        switch processName {
        case "node":
            if argsLower.contains("next") { return "Next.js" }
            if argsLower.contains("vite") { return "Vite" }
            if argsLower.contains("nuxt") { return "Nuxt" }
            if argsLower.contains("remix") { return "Remix" }
            if argsLower.contains("express") { return "Express" }
            if argsLower.contains("firebase") { return "Firebase" }
            if argsLower.contains("astro") { return "Astro" }
            if argsLower.contains("webpack-dev-server") || argsLower.contains("react-scripts") { return "React" }
            return "Node"
        case "python", "python3":
            if argsLower.contains("flask") { return "Flask" }
            if argsLower.contains("django") || argsLower.contains("manage.py") { return "Django" }
            if argsLower.contains("uvicorn") || argsLower.contains("fastapi") { return "FastAPI" }
            return "Python"
        case "ruby":
            if argsLower.contains("rails") { return "Rails" }
            return "Ruby"
        case "php":
            if argsLower.contains("artisan") { return "Laravel" }
            return "PHP"
        case "java":
            if argsLower.contains("spring") { return "Spring" }
            return "Java"
        case "go": return "Go"
        case "postgres": return "Postgres"
        case "redis-server": return "Redis"
        default: return processName
        }
    }

    private func runCommand(_ path: String, args: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

// MARK: - Shell Environment

private func buildShellEnvironment() -> [String] {
    var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
    let userEnv = ProcessInfo.processInfo.environment
    for (key, value) in userEnv {
        if key == "TERM" || key == "COLORTERM" { continue }
        env.append("\(key)=\(value)")
    }
    return env
}

private func defaultShell() -> String {
    ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
}

// MARK: - Tab Model

class Tab {
    let id = UUID()
    let directory: String
    let terminalView: LocalProcessTerminalView
    var title: String

    init(directory: String) {
        self.directory = directory
        self.title = (directory as NSString).lastPathComponent
        self.terminalView = LocalProcessTerminalView(frame: .zero)

        // Configure terminal appearance
        terminalView.nativeForegroundColor = creamColor
        terminalView.nativeBackgroundColor = bgColor
        terminalView.layer?.backgroundColor = bgColor.cgColor
        terminalView.font = terminalFont

        // Hide the scrollbar visually but keep the NSScroller in the hierarchy so
        // SwiftTerm's wheel/trackpad scrolling continues to work. Setting isHidden
        // would remove it from event routing in some configurations.
        for subview in terminalView.subviews {
            if subview is NSScroller {
                subview.alphaValue = 0
            }
        }

        // Start shell
        let shell = defaultShell()
        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: buildShellEnvironment(),
            execName: "-" + (shell as NSString).lastPathComponent,
            currentDirectory: directory
        )
    }

    func sendCommand(_ command: String) {
        // Small delay to let the shell initialize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let bytes = Array((command + "\n").utf8)
            self.terminalView.send(source: self.terminalView, data: bytes[...])
        }
    }

    func terminate() {
        terminalView.terminate()
    }
}

// MARK: - Atoms

/// 1pt themed divider. Used under headers and between columns.
final class DividerView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.dividerCGColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// Solid colored circle used as a status indicator. Default `tag` (-1) so the
/// row's hover handler ignores it — the dot stays at full alpha regardless of
/// hover state.
final class StatusDotView: NSView {
    init(diameter: CGFloat, color: NSColor) {
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = diameter / 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// Icon button with a themed hover effect: SVG tint fades from `baseAlpha` to
/// `hoverAlpha` when the cursor enters, matching the alpha shift used by sidebar
/// rows. Both variants are rendered once at init and cached.
class HoverIconButton: NSButton {
    private let baseImage: NSImage?
    private let hoverImage: NSImage?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(svgName: String, iconSize: CGFloat = 14, baseAlpha: CGFloat = 0.5, hoverAlpha: CGFloat = 1.0) {
        self.baseImage = loadSVGIcon(named: svgName, size: iconSize, alpha: baseAlpha)
        self.hoverImage = loadSVGIcon(named: svgName, size: iconSize, alpha: hoverAlpha)
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .inline
        title = ""
        imageScaling = .scaleProportionallyUpOrDown
        image = baseImage
        imagePosition = .imageOnly
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        image = hoverImage
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        image = baseImage
    }
}

// MARK: - Molecules

/// Unified top-strip header used by the sidebar, tab area, and server panel.
/// Owns its label, optional trailing button, bottom divider, and window-drag behavior,
/// so every column header looks and behaves identically.
final class HeaderBar: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let divider = DividerView(frame: .zero)
    private var trailingButton: NSButton?
    /// Optional centered icon used in narrow mode. When the bar shrinks below
    /// `narrowThreshold`, the title hides and this icon is shown instead.
    private var narrowIconView: NSImageView?
    private let leftInset: CGFloat
    /// Width below which the header switches to narrow mode (title hidden, icon centered).
    private let narrowThreshold: CGFloat = 60

    /// Let the user drag the window by grabbing any empty area of the header.
    override var mouseDownCanMoveWindow: Bool { true }

    init(title: String, leftInset: CGFloat = Theme.horizontalPadding, narrowIcon: NSImage? = nil) {
        self.leftInset = leftInset
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = bgColor.cgColor

        titleLabel.stringValue = title
        titleLabel.font = uiFont.withSize(Theme.headerFontSize)
        titleLabel.textColor = Theme.mutedLabelColor
        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.backgroundColor = .clear

        addSubview(titleLabel)
        addSubview(divider)

        if let icon = narrowIcon {
            let iv = NSImageView()
            iv.image = icon
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.isHidden = true
            addSubview(iv)
            narrowIconView = iv
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Attach a trailing action button (e.g. sidebar collapse toggle). Pass nil to clear.
    func setTrailingButton(_ button: NSButton?) {
        trailingButton?.removeFromSuperview()
        trailingButton = button
        if let button {
            addSubview(button)
        }
        needsLayout = true
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutContent()
    }

    override func layout() {
        super.layout()
        layoutContent()
    }

    private func layoutContent() {
        let isNarrow = bounds.width <= narrowThreshold

        // Title is hidden in narrow mode so the icon (or trailing button) can claim
        // the visible area without competing for space.
        titleLabel.isHidden = isNarrow

        let trailingReserved: CGFloat = trailingButton != nil ? (Theme.headerButtonSize + 16) : Theme.horizontalPadding
        let labelSize = titleLabel.intrinsicContentSize
        let labelWidth = max(0, bounds.width - leftInset - trailingReserved)
        titleLabel.frame = NSRect(
            x: leftInset,
            y: (bounds.height - labelSize.height) / 2,
            width: labelWidth,
            height: labelSize.height
        )

        if let iconView = narrowIconView {
            iconView.isHidden = !isNarrow
            // Match the trailing-button footprint so the narrow :SERVERS glyph
            // reads at the same visual size as the /CODE collapse toggle.
            let size = Theme.headerButtonSize
            iconView.frame = NSRect(
                x: (bounds.width - size) / 2,
                y: (bounds.height - size) / 2,
                width: size,
                height: size
            )
        }

        if let button = trailingButton {
            // Right-align in normal widths, but if the bar is too narrow for the
            // right-edge formula (collapsed sidebar rail), fall back to centered.
            let preferredX = bounds.width - Theme.headerButtonSize - 12
            let buttonX = preferredX < 4 ? max(0, (bounds.width - Theme.headerButtonSize) / 2) : preferredX
            button.frame = NSRect(
                x: buttonX,
                y: (bounds.height - Theme.headerButtonSize) / 2,
                width: Theme.headerButtonSize,
                height: Theme.headerButtonSize
            )
        }

        divider.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
    }
}

// MARK: - Tab Bar View

protocol TabBarDelegate: AnyObject {
    func tabBarDidSelectTab(at index: Int)
    func tabBarDidCloseTab(at index: Int)
}

class TabBarView: NSView {
    weak var delegate: TabBarDelegate?
    private var tabs: [Tab] = []
    private var activeIndex: Int = -1
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = bgColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(tabs: [Tab], activeIndex: Int) {
        self.tabs = tabs
        self.activeIndex = activeIndex
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !tabs.isEmpty else { return }

        let tabWidth: CGFloat = min(180, bounds.width / CGFloat(tabs.count))

        for (i, tab) in tabs.enumerated() {
            let rect = NSRect(x: CGFloat(i) * tabWidth, y: 0, width: tabWidth, height: bounds.height)

            // Tab background
            if i == activeIndex {
                NSColor(white: 0.18, alpha: 1.0).setFill()
            } else {
                bgColor.setFill()
            }
            NSBezierPath.fill(rect)

            // Tab title
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: i == activeIndex ? creamColor : creamColor.withAlphaComponent(0.5),
                .font: uiFont.withSize(11)
            ]
            let title = tab.title as NSString
            let titleSize = title.size(withAttributes: attrs)
            let titleRect = NSRect(
                x: rect.minX + 10,
                y: rect.midY - titleSize.height / 2,
                width: min(titleSize.width, tabWidth - 30),
                height: titleSize.height
            )
            title.draw(in: titleRect, withAttributes: attrs)

            // Close button (x)
            let closeAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: creamColor.withAlphaComponent(0.4),
                .font: NSFont.systemFont(ofSize: 10)
            ]
            let closeStr = "\u{2715}" as NSString
            let closeSize = closeStr.size(withAttributes: closeAttrs)
            let closeRect = NSRect(
                x: rect.maxX - 20,
                y: rect.midY - closeSize.height / 2,
                width: closeSize.width,
                height: closeSize.height
            )
            closeStr.draw(in: closeRect, withAttributes: closeAttrs)

            // Separator
            if i < tabs.count - 1 {
                NSColor(white: 0.25, alpha: 1.0).setStroke()
                let sep = NSBezierPath()
                sep.move(to: NSPoint(x: rect.maxX, y: 4))
                sep.line(to: NSPoint(x: rect.maxX, y: bounds.height - 4))
                sep.lineWidth = 0.5
                sep.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let tabWidth: CGFloat = min(180, bounds.width / CGFloat(max(1, tabs.count)))
        let index = Int(point.x / tabWidth)
        guard index >= 0, index < tabs.count else { return }

        // Check if close button was clicked
        let tabRect = NSRect(x: CGFloat(index) * tabWidth, y: 0, width: tabWidth, height: bounds.height)
        if point.x > tabRect.maxX - 24 {
            delegate?.tabBarDidCloseTab(at: index)
        } else {
            delegate?.tabBarDidSelectTab(at: index)
        }
    }
}

// MARK: - Hover Row View

class HoverRowView: NSTableRowView {
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        // `.inVisibleRect` keeps the tracking area in sync when the row scrolls,
        // when the sidebar resizes, and when AppKit reuses rows. Without it the
        // hover state "locks" on the last-hovered row until you wiggle the mouse
        // back into a live rect.
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateHover()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateHover()
    }

    private func updateHover() {
        guard let cell = subviews.first else { return }
        // Leading icon — tag 100, any NSView (terminal SVG on project rows).
        if let lead = cell.viewWithTag(100) {
            lead.alphaValue = isHovered ? 1.0 : 0.6
        }
        // Primary text — tag 101 (project name on project rows, address on server rows).
        if let nameLabel = cell.viewWithTag(101) as? NSTextField {
            nameLabel.textColor = creamColor.withAlphaComponent(isHovered ? 1.0 : 0.5)
        }
    }
}

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
                ctx.duration = 0.2
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
        tableView.rowHeight = 28
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
        serversTableView.rowHeight = 32
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

        let rowHeight: CGFloat = 28
        let project = projects[row]

        let iconView = makeIconView(named: "file-terminal-solid-sharp.svg", size: 16, alpha: 0.5)
        iconView.frame = NSRect(x: 20, y: (rowHeight - 16) / 2, width: 16, height: 16)
        iconView.tag = 100
        cell.addSubview(iconView)

        let nameLabel = NSTextField(labelWithString: project.name)
        nameLabel.tag = 101
        nameLabel.font = uiFont.withSize(12)
        nameLabel.textColor = creamColor.withAlphaComponent(0.5)
        nameLabel.backgroundColor = .clear
        nameLabel.isBordered = false
        nameLabel.isEditable = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.sizeToFit()
        let nameHeight = nameLabel.frame.height
        nameLabel.frame = NSRect(x: 42, y: (rowHeight - nameHeight) / 2, width: bounds.width - 84, height: nameHeight)
        cell.addSubview(nameLabel)

        var iconX = bounds.width - 16
        if project.gitStatus != .none {
            let svgName = project.gitStatus == .github ? "github-solid-sharp.svg" : "git-branch-solid-sharp.svg"
            let gitView = makeIconView(named: svgName, size: 12, alpha: 0.3)
            iconX -= 14
            gitView.frame = NSRect(x: iconX, y: (rowHeight - 12) / 2, width: 12, height: 12)
            cell.addSubview(gitView)
        }

        let stackIcons = techStackIcons(for: project.techStack)
        for icon in stackIcons {
            if icon.hasSuffix(".svg") {
                let sv = makeIconView(named: icon, size: 12, alpha: 0.3)
                iconX -= 14
                sv.frame = NSRect(x: iconX, y: (rowHeight - 12) / 2, width: 12, height: 12)
                cell.addSubview(sv)
            } else {
                let glyph: UInt32 = icon == "jsx-02" ? jsxGlyph : zapGlyph
                let label = NSTextField(labelWithAttributedString: hugeIconString(glyph, size: 10, alpha: 0.3))
                iconX -= 14
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
        let rowHeight: CGFloat = 32
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
            x: 20 + (16 - dotSize) / 2,
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
        titleLabel.textColor = creamColor.withAlphaComponent(0.8)
        titleLabel.backgroundColor = .clear
        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.sizeToFit()
        let titleHeight = titleLabel.frame.height
        titleLabel.frame = NSRect(
            x: 42,
            y: (rowHeight - titleHeight) / 2,
            width: max(0, cellWidth - 84),
            height: titleHeight
        )
        cell.addSubview(titleLabel)

        let buttonY = (rowHeight - 16) / 2
        let safariBtn = ServerIconButton(svgName: "safari-solid-sharp.svg", port: item.server.port, browser: .safari)
        safariBtn.frame = NSRect(x: cellWidth - 48, y: buttonY, width: 16, height: 16)
        cell.addSubview(safariBtn)

        let chromeBtn = ServerIconButton(svgName: "chrome-solid-sharp.svg", port: item.server.port, browser: .chrome)
        chromeBtn.frame = NSRect(x: cellWidth - 26, y: buttonY, width: 16, height: 16)
        cell.addSubview(chromeBtn)

        return cell
    }
}

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

// MARK: - Tab Manager

class TabManager {
    private(set) var tabs: [Tab] = []
    private(set) var activeIndex: Int = -1

    var activeTab: Tab? {
        guard activeIndex >= 0, activeIndex < tabs.count else { return nil }
        return tabs[activeIndex]
    }

    func createTab(directory: String) -> Tab {
        let tab = Tab(directory: directory)
        tabs.append(tab)
        activeIndex = tabs.count - 1
        return tab
    }

    func closeTab(at index: Int) -> Tab? {
        guard index >= 0, index < tabs.count else { return nil }
        let tab = tabs.remove(at: index)
        tab.terminate()
        if tabs.isEmpty {
            activeIndex = -1
        } else if activeIndex >= tabs.count {
            activeIndex = tabs.count - 1
        }
        return tab
    }

    func selectTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        activeIndex = index
    }
}

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
        for subview in mainLayout.terminalContainer.subviews {
            subview.removeFromSuperview()
        }
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

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)

// Menu bar
let mainMenu = NSMenu()

// App menu
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "About Terminos", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
appMenu.addItem(NSMenuItem.separator())
appMenu.addItem(withTitle: "Quit Terminos", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appMenuItem.submenu = appMenu

// Shell menu
let shellMenuItem = NSMenuItem()
mainMenu.addItem(shellMenuItem)
let shellMenu = NSMenu(title: "Shell")
shellMenu.addItem(withTitle: "New Tab", action: #selector(AppDelegate.newTab(_:)), keyEquivalent: "t")
shellMenu.addItem(withTitle: "Close Tab", action: #selector(AppDelegate.closeTab(_:)), keyEquivalent: "w")
shellMenu.addItem(NSMenuItem.separator())
let nextTabItem = NSMenuItem(title: "Next Tab", action: #selector(AppDelegate.nextTab(_:)), keyEquivalent: String(Unicode.Scalar(NSRightArrowFunctionKey)!))
nextTabItem.keyEquivalentModifierMask = [.command, .shift]
shellMenu.addItem(nextTabItem)
let prevTabItem = NSMenuItem(title: "Previous Tab", action: #selector(AppDelegate.prevTab(_:)), keyEquivalent: String(Unicode.Scalar(NSLeftArrowFunctionKey)!))
prevTabItem.keyEquivalentModifierMask = [.command, .shift]
shellMenu.addItem(prevTabItem)
shellMenuItem.submenu = shellMenu

// Edit menu
let editMenuItem = NSMenuItem()
mainMenu.addItem(editMenuItem)
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editMenuItem.submenu = editMenu

app.mainMenu = mainMenu
app.run()
