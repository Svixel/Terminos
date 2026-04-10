import Cocoa
import CoreText

// MARK: - File-scope design constants

let bgColor = NSColor(red: 0x1C / 255.0, green: 0x1D / 255.0, blue: 0x24 / 255.0, alpha: 1.0)
let creamColor = NSColor(red: 0xF5 / 255.0, green: 0xF0 / 255.0, blue: 0xE8 / 255.0, alpha: 1.0)
let sidebarWidth: CGFloat = 220
/// Width of the sidebar when collapsed. Matches `Theme.headerHeight` so the header
/// area becomes a 1:1 square — toggle button on top, terminal-icon column under it.
let collapsedSidebarWidth: CGFloat = 40
let serverPanelWidth: CGFloat = 180
let projectsPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Documents/CODE").path

/// Centralized design tokens. New components should read from here instead of hard-coding values.
enum Theme {
    // MARK: Layout

    /// Uniform height for every top-strip header (sidebar, tab area, server panel).
    static let headerHeight: CGFloat = 40
    /// Default left/right padding inside a header.
    static let horizontalPadding: CGFloat = 20
    /// Size of a trailing action button slot inside a header.
    static let headerButtonSize: CGFloat = 18
    static let headerFontSize: CGFloat = 12
    static let rowHeight: CGFloat = 28
    /// Row height for the :SERVERS section in the sidebar.
    static let serverRowHeight: CGFloat = 32

    /// Left padding for the leading icon column in sidebar cells.
    static let cellLeading: CGFloat = 20
    /// Left padding for the primary text column in sidebar cells (sits one icon
    /// width + gap to the right of `cellLeading`).
    static let cellTextLeading: CGFloat = 42
    /// Horizontal stride between trailing icons in a sidebar cell.
    static let cellIconStride: CGFloat = 14

    // MARK: Animation

    /// Sidebar collapse/expand toggle duration.
    static let sidebarAnim: TimeInterval = 0.2
    /// Peek-on-hover expand/contract duration. Slightly faster than `sidebarAnim`
    /// so the rail "peeks" feel responsive vs deliberate.
    static let peekAnim: TimeInterval = 0.15

    // MARK: Color

    static var dividerColor: NSColor { creamColor.withAlphaComponent(0.08) }
    static var dividerCGColor: CGColor { dividerColor.cgColor }
    /// Strongest secondary text. Used for primary row titles like server addresses.
    static var strongLabelColor: NSColor { creamColor.withAlphaComponent(0.8) }
    static var mutedLabelColor: NSColor { creamColor.withAlphaComponent(0.5) }
    /// Used for secondary captions like the friendly name beneath a port.
    static var ghostLabelColor: NSColor { creamColor.withAlphaComponent(0.4) }
    static var subtleLabelColor: NSColor { creamColor.withAlphaComponent(0.3) }

    /// Running-server indicator dot color. Soft green that reads against the dark bg.
    static let statusRunningColor = NSColor(red: 0.35, green: 0.85, blue: 0.45, alpha: 1.0)
}

// MARK: - Font Registration

var terminalFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .ultraLight)
var uiFont: NSFont = .systemFont(ofSize: 13, weight: .light)
var iconFontName: String?

func registerFonts() {
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

// MARK: - Icon loading

func loadSVGIcon(named filename: String, size: CGFloat, tint: NSColor = creamColor, alpha: CGFloat = 1.0) -> NSImage? {
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

func makeIconView(named filename: String, size: CGFloat, alpha: CGFloat = 0.7) -> NSImageView {
    let view = NSImageView()
    if let img = loadSVGIcon(named: filename, size: size, alpha: alpha) {
        view.image = img
    }
    view.imageScaling = .scaleProportionallyUpOrDown
    return view
}
