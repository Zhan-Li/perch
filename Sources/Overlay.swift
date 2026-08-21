import AppKit

/// A click-through window that floats above everything while a drag is in
/// progress. It must never take focus and must never swallow a mouse event, or
/// it would break the very drag it is trying to assist.
private final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws the icon strip plus, when an icon is hovered, a translucent footprint
/// showing exactly where the window will land.
private final class OverlayView: NSView {
    var zones: [Zone] = []
    var iconFrames: [NSRect] = []
    var hoverIndex: Int?
    var previewFrame: NSRect?

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor

        if let preview = previewFrame {
            let path = NSBezierPath(roundedRect: preview.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
            accent.withAlphaComponent(0.22).setFill()
            path.fill()
            accent.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 3
            path.stroke()
        }

        for (index, frame) in iconFrames.enumerated() where index < zones.count {
            ZoneRenderer.draw(zones[index], in: frame, highlighted: index == hoverIndex)
        }
    }
}

/// Owns the single overlay panel and answers the one question the drag monitor
/// cares about: "is the cursor over a drop target, and if so, which one?"
final class OverlayController {

    private var panel: OverlayPanel?
    private var view: OverlayView?
    private var config = Config.fallback

    /// Icon rectangles in global Cocoa coordinates, for hit testing.
    private var hitFrames: [NSRect] = []
    private var screen: NSScreen?
    private(set) var hoverIndex: Int?

    func reload(_ config: Config) {
        self.config = config
    }

    // MARK: - Lifecycle

    func show(on screen: NSScreen) {
        let panel = ensurePanel()
        self.screen = screen
        hoverIndex = nil

        panel.setFrame(screen.frame, display: false)
        layoutIcons(on: screen)

        view?.zones = config.zones
        view?.hoverIndex = nil
        view?.previewFrame = nil
        view?.needsDisplay = true

        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        hitFrames = []
        hoverIndex = nil
        screen = nil
    }

    /// Moves the strip to whichever display the cursor is on, the way Window
    /// Tidy did — the icons follow the window across monitors.
    func follow(cursor point: CGPoint) {
        guard let target = Geo.screen(containing: point) else { return }
        if screen?.frame != target.frame {
            show(on: target)
        }
        updateHover(at: point)
    }

    // MARK: - Hit testing

    @discardableResult
    func updateHover(at point: CGPoint) -> Int? {
        let cocoa = Geo.toCocoa(point)
        let padding = CGFloat(config.hitPadding)
        let index = hitFrames.firstIndex { $0.insetBy(dx: -padding, dy: -padding).contains(cocoa) }

        guard index != hoverIndex else { return hoverIndex }
        hoverIndex = index

        view?.hoverIndex = index
        view?.previewFrame = index.flatMap { previewFrame(for: $0) }
        view?.needsDisplay = true
        return index
    }

    /// Where the window should end up for the zone at `index`, in Quartz space.
    func targetFrame(for index: Int) -> CGRect? {
        guard let screen, config.zones.indices.contains(index) else { return nil }
        return config.zones[index].frame(in: Geo.toQuartz(screen.visibleFrame))
    }

    // MARK: - Layout

    private func ensurePanel() -> OverlayPanel {
        if let panel { return panel }
        let panel = OverlayPanel()
        let view = OverlayView(frame: .zero)
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        self.panel = panel
        self.view = view
        return panel
    }

    /// Places the icon strip, wrapping onto extra rows when there are more
    /// layouts than fit across the display.
    ///
    /// Icon size deliberately stays fixed in points rather than scaling with the
    /// screen: a point is very nearly the same physical size on every Mac
    /// display, and these are targets the user has to hit while already
    /// dragging a window — shrinking them to fit would make the app worst
    /// exactly when someone has defined the most layouts.
    private func layoutIcons(on screen: NSScreen) {
        let zones = config.zones
        guard !zones.isEmpty else {
            hitFrames = []
            view?.iconFrames = []
            return
        }

        let width = CGFloat(config.iconWidth)
        let height = CGFloat(config.iconHeight)
        let gap = CGFloat(config.iconGap)
        let usable = screen.visibleFrame

        let perRow = max(1, Int((usable.width * 0.92 + gap) / (width + gap)))
        let rowCount = Int(ceil(Double(zones.count) / Double(perRow)))

        // `top` is the y-origin of the first row; later rows stack downwards.
        let blockHeight = CGFloat(rowCount) * height + CGFloat(rowCount - 1) * gap
        let margin = CGFloat(config.topMargin)
        var top: CGFloat
        switch config.resolvedPlacement {
        case .top:
            top = usable.maxY - margin - height
        case .center:
            top = usable.midY + blockHeight / 2 - height
        case .bottom:
            top = usable.minY + margin + blockHeight - height
        }

        // Keep the whole block on screen whatever the anchor and row count.
        let lowestBottom = top - CGFloat(rowCount - 1) * (height + gap)
        if lowestBottom < usable.minY + 8 {
            top += usable.minY + 8 - lowestBottom
        }
        top = min(top, usable.maxY - height - 8)

        hitFrames = zones.indices.map { index in
            let row = index / perRow
            let column = index % perRow
            let inRow = min(perRow, zones.count - row * perRow)
            let rowWidth = CGFloat(inRow) * width + CGFloat(inRow - 1) * gap
            return NSRect(
                x: usable.midX - rowWidth / 2 + CGFloat(column) * (width + gap),
                y: top - CGFloat(row) * (height + gap),
                width: width,
                height: height
            )
        }

        // The view is panel-local, so shift the global rectangles by the origin.
        let origin = screen.frame.origin
        view?.iconFrames = hitFrames.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
    }

    private func previewFrame(for index: Int) -> NSRect? {
        guard let screen, let quartz = targetFrame(for: index) else { return nil }
        let cocoa = Geo.toCocoa(quartz)
        return cocoa.offsetBy(dx: -screen.frame.origin.x, dy: -screen.frame.origin.y)
    }
}
