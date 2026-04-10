import Cocoa

// MARK: - View helpers

extension NSView {
    /// Swap any prior tracking area for a fresh hover tracker that uses
    /// `.inVisibleRect`, so AppKit keeps the area in sync with scroll/resize
    /// instead of stranding `mouseExited` events on stale rects. Returns the
    /// new area; callers store it for the next `updateTrackingAreas` call.
    func installHoverTrackingArea(replacing previous: NSTrackingArea?) -> NSTrackingArea {
        if let previous { removeTrackingArea(previous) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        return area
    }
}

/// Build a borderless, non-editable label with the project's standard chrome.
/// Used by every cell builder so font / color / chrome decisions live in one place.
func makeLabel(_ text: String, fontSize: CGFloat, color: NSColor) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = uiFont.withSize(fontSize)
    label.textColor = color
    label.backgroundColor = .clear
    label.isBordered = false
    label.isEditable = false
    return label
}

/// Build a borderless, scrollerless `NSScrollView` + `NSTableView` pair wired
/// up with the project's standard sidebar-table chrome (no header, clear bg,
/// `.plain` style, `.none` selection highlight, no scrollers, no draws-bg).
/// Returns the pair already linked via `documentView`. Callers still set their
/// own `delegate`, `dataSource`, and any per-table extras (autoresizing,
/// content insets, target/action).
func makeSidebarTable(rowHeight: CGFloat) -> (NSScrollView, NSTableView) {
    let scrollView = NSScrollView(frame: .zero)
    let tableView = NSTableView(frame: .zero)

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col"))
    tableView.addTableColumn(column)
    tableView.headerView = nil
    tableView.backgroundColor = .clear
    tableView.rowHeight = rowHeight
    tableView.intercellSpacing = NSSize(width: 0, height: 0)
    tableView.selectionHighlightStyle = .none
    tableView.style = .plain

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.drawsBackground = false

    return (scrollView, tableView)
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
        trackingArea = installHoverTrackingArea(replacing: trackingArea)
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
