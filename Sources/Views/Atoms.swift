import Cocoa

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
