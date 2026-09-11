import AppKit
import QuartzCore

/// A click-through window that floats above everything while a drag is in
/// progress. It must never take focus and must never swallow a mouse event, or
/// it would break the very drag it is trying to assist.
private final class OverlayPanel: NSPanel {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
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
        // We drop our reference to throw the window away; AppKit must not
        // release it a second time behind ARC's back.
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the overlay panel and answers the one question the drag monitor cares
/// about: "is the cursor over a drop target, and if so, which one?"
///
/// The strip is built out of Core Animation layers rather than drawn in a
/// view's `draw(_:)`, and the panel is created fresh for every drag and thrown
/// away on drop. Both are deliberate. The first version marked a view dirty
/// and let the run loop repaint it; after the app had been running a while
/// that repaint stopped happening — the drag was detected, the zones were hit
/// tested, dropping still snapped the window, but nothing was painted. Drawing
/// synchronously (1.2.1) did not cure it either. AppKit gates its whole view
/// display cycle on the window's occlusion state, and once a long-hidden panel
/// and that gate get out of step there is no reliable way back from inside
/// the app.
///
/// Layers sidestep the gate: a layer's `contents` is a bitmap we rendered
/// ourselves, and setting it is a plain Core Animation property change that is
/// committed to the window server unconditionally — AppKit is never asked to
/// draw anything. A fresh panel per drag means there is also no long-lived
/// window-server window whose backing store can have been purged, or whose
/// visibility bookkeeping can have gone stale, between one drag and the next.
/// The cost is one window allocation at the start of each drag, well under a
/// millisecond.
final class OverlayController {

    private var panel: OverlayPanel?
    private var iconLayers: [CALayer] = []
    private var previewLayer: CALayer?
    private var config = Config.fallback

    /// Rendered icon bitmaps, keyed by everything that affects their pixels.
    /// Cleared whenever the config changes.
    private var iconImages: [IconKey: CGImage] = [:]

    /// Icon rectangles in global Cocoa coordinates, for hit testing.
    private var hitFrames: [NSRect] = []
    /// The same rectangles in panel-local coordinates, for the layers.
    private var iconFrames: [NSRect] = []
    private var screen: NSScreen?
    private(set) var hoverIndex: Int?

    /// Extra room around each icon bitmap so the 1pt card outline, which
    /// straddles the icon's edge, is not clipped by the layer's bounds.
    private static let bleed: CGFloat = 1

    func reload(_ config: Config) {
        self.config = config
        iconImages.removeAll()
    }

    // MARK: - Lifecycle

    func show(on screen: NSScreen) {
        self.screen = screen
        hoverIndex = nil

        // Reused only while a drag is crossing from one display to another;
        // `hide` throws the panel away at the end of every drag.
        let fresh = panel == nil
        let panel = self.panel ?? makePanel(frame: screen.frame)
        panel.setFrame(screen.frame, display: false)

        layoutIcons(on: screen)
        populateLayers(on: screen)

        panel.orderFrontRegardless()
        // Push the layer tree to the window server now rather than at the end
        // of this run loop turn, so the strip is on screen before the next
        // drag event arrives.
        CATransaction.flush()

        if Log.isEnabled {
            Log.write("""
                overlay show screen=\(screen.frame) fresh=\(fresh) window=\(panel.windowNumber) \
                visible=\(panel.isVisible) occlusion=\(panel.occlusionState.rawValue) \
                onActiveSpace=\(panel.isOnActiveSpace) appHidden=\(NSApp.isHidden) \
                icons=\(iconLayers.count) scale=\(screen.backingScaleFactor)
                """)
        }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        iconLayers = []
        previewLayer = nil
        hitFrames = []
        iconFrames = []
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
        let previous = hoverIndex
        hoverIndex = index

        guard let screen else { return index }
        let scale = screen.backingScaleFactor

        // Only the two icons whose state changed are touched, so this stays
        // cheap however many layouts there are.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let previous, iconLayers.indices.contains(previous) {
            iconLayers[previous].contents = iconImage(for: previous, highlighted: false, scale: scale)
        }
        if let index, iconLayers.indices.contains(index) {
            iconLayers[index].contents = iconImage(for: index, highlighted: true, scale: scale)
        }
        if let preview = index.flatMap({ previewFrame(for: $0) }) {
            previewLayer?.frame = preview.insetBy(dx: 2, dy: 2)
            previewLayer?.isHidden = false
        } else {
            previewLayer?.isHidden = true
        }
        CATransaction.commit()
        CATransaction.flush()
        return index
    }

    /// Where the window should end up for the zone at `index`, in Quartz space.
    func targetFrame(for index: Int) -> CGRect? {
        guard let screen, config.zones.indices.contains(index) else { return nil }
        return config.zones[index].frame(in: Geo.toQuartz(screen.visibleFrame))
    }

    // MARK: - Panel and layers

    private func makePanel(frame: NSRect) -> OverlayPanel {
        let panel = OverlayPanel(frame: frame)

        // Setting `layer` before `wantsLayer` makes the view layer-hosting:
        // AppKit leaves the sublayers entirely to us and never tries to draw
        // into them.
        let root = CALayer()
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.layer = root
        view.wantsLayer = true
        panel.contentView = view

        self.panel = panel
        return panel
    }

    /// Rebuilds the icon and footprint layers for the current config and screen.
    private func populateLayers(on screen: NSScreen) {
        guard let root = panel?.contentView?.layer else { return }
        let scale = screen.backingScaleFactor
        let accent = NSColor.controlAccentColor

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        root.sublayers?.forEach { $0.removeFromSuperlayer() }

        iconLayers = iconFrames.indices.map { index in
            let layer = CALayer()
            layer.frame = iconFrames[index].insetBy(dx: -Self.bleed, dy: -Self.bleed)
            layer.contentsScale = scale
            layer.contentsGravity = .resize
            layer.contents = iconImage(for: index, highlighted: false, scale: scale)
            root.addSublayer(layer)
            return layer
        }

        // The footprint is nothing but a rounded, bordered rectangle, which a
        // bare layer can be without any bitmap at all.
        let preview = CALayer()
        preview.backgroundColor = accent.withAlphaComponent(0.22).cgColor
        preview.borderColor = accent.withAlphaComponent(0.9).cgColor
        preview.borderWidth = 3
        preview.cornerRadius = 10
        preview.isHidden = true
        root.addSublayer(preview)
        previewLayer = preview

        CATransaction.commit()
    }

    private struct IconKey: Hashable {
        var zone: Zone
        var highlighted: Bool
        var scale: CGFloat
    }

    /// The bitmap for one icon, rendered on first use and cached. Rendering
    /// goes through `ZoneRenderer` so the icon is pixel-identical to the one
    /// in the layout editor.
    private func iconImage(for index: Int, highlighted: Bool, scale: CGFloat) -> CGImage? {
        guard config.zones.indices.contains(index) else { return nil }
        let zone = config.zones[index]
        let key = IconKey(zone: zone, highlighted: highlighted, scale: scale)
        if let cached = iconImages[key] { return cached }

        let width = CGFloat(config.iconWidth)
        let height = CGFloat(config.iconHeight)
        let bleed = Self.bleed
        let pixelWidth = Int(((width + 2 * bleed) * scale).rounded(.up))
        let pixelHeight = Int(((height + 2 * bleed) * scale).rounded(.up))

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
              ) else {
            return nil
        }
        context.scaleBy(x: scale, y: scale)

        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        // Dynamic colours such as the accent resolve against the current
        // appearance, which outside a view is whatever happens to be set.
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            ZoneRenderer.draw(
                zone,
                in: NSRect(x: bleed, y: bleed, width: width, height: height),
                highlighted: highlighted,
                opacity: CGFloat(config.resolvedOpacity)
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = context.makeImage()
        iconImages[key] = image
        return image
    }

    // MARK: - Layout

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
            iconFrames = []
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

        // The layers are panel-local, so shift the global rectangles by the
        // origin.
        let origin = screen.frame.origin
        iconFrames = hitFrames.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
    }

    private func previewFrame(for index: Int) -> NSRect? {
        guard let screen, let quartz = targetFrame(for: index) else { return nil }
        let cocoa = Geo.toCocoa(quartz)
        return cocoa.offsetBy(dx: -screen.frame.origin.x, dy: -screen.frame.origin.y)
    }
}
