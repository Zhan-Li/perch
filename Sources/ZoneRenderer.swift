import AppKit

/// Draws a single drop-target icon: a rounded card, a proxy of the screen, and
/// the cells the zone occupies.
///
/// Shared by the drag overlay and the layout editor so a zone can never look
/// like one thing while you are editing it and another thing mid-drag.
enum ZoneRenderer {

    /// `opacity` scales every layer at once, so the strip can be made to sit
    /// lightly over the windows it is arranging without the parts losing their
    /// relative contrast.
    static func draw(_ zone: Zone, in frame: NSRect, highlighted: Bool, opacity: CGFloat = 1) {
        let accent = NSColor.controlAccentColor
        let card = NSBezierPath(roundedRect: frame, xRadius: 9, yRadius: 9)

        // The card *is* the screen. There is no inset proxy rectangle inside
        // it, so the filled cells run to the icon's own edge — at these sizes
        // a border around a border around a fill just wastes the pixels that
        // carry the meaning.
        NSGraphicsContext.saveGraphicsState()
        card.addClip()

        let base = highlighted ? accent : NSColor(white: 0.11, alpha: 1)
        base.withAlphaComponent(0.94 * opacity).setFill()
        frame.fill()

        // Flipped because unitRect measures y from the top. Drawn as a plain
        // rectangle: the clip above gives it the card's corner radius wherever
        // it meets an edge, and leaves it square where it meets another cell.
        let unit = zone.unitRect
        NSColor(white: 1, alpha: (highlighted ? 0.98 : 0.82) * opacity).setFill()
        NSRect(
            x: frame.minX + unit.minX * frame.width,
            y: frame.maxY - (unit.minY + unit.height) * frame.height,
            width: unit.width * frame.width,
            height: unit.height * frame.height
        ).fill()

        NSGraphicsContext.restoreGraphicsState()

        NSColor(white: 1, alpha: (highlighted ? 0.55 : 0.22) * opacity).setStroke()
        card.lineWidth = 1
        card.stroke()
    }
}

/// A plain view wrapper so zone icons can sit in ordinary AppKit layouts.
final class ZoneIconView: NSView {
    var zone: Zone? {
        didSet { needsDisplay = true }
    }
    var highlighted = false {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let zone else { return }
        ZoneRenderer.draw(zone, in: bounds.insetBy(dx: 1, dy: 1), highlighted: highlighted)
    }
}
