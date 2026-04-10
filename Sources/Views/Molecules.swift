import Cocoa

// MARK: - Header Bar

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
        trackingArea = installHoverTrackingArea(replacing: trackingArea)
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
            nameLabel.textColor = isHovered ? creamColor : Theme.mutedLabelColor
        }
    }
}
