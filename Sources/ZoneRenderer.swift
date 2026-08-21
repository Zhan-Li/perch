import AppKit

/// Draws a single drop-target icon: a rounded card, a proxy of the screen, and
/// the cells the zone occupies.
///
/// Shared by the drag overlay and the layout editor so a zone can never look
/// like one thing while you are editing it and another thing mid-drag.
enum ZoneRenderer {

    static func draw(_ zone: Zone, in frame: NSRect, highlighted: Bool) {
        let accent = NSColor.controlAccentColor

        let card = NSBezierPath(roundedRect: frame, xRadius: 9, yRadius: 9)
        (highlighted ? accent : NSColor(white: 0.11, alpha: 0.94)).setFill()
        card.fill()
        NSColor(white: 1, alpha: highlighted ? 0.55 : 0.22).setStroke()
        card.lineWidth = 1
        card.stroke()

        // The screen proxy: a small rectangle standing in for the display.
        let proxy = frame.insetBy(dx: frame.width * 0.13, dy: frame.height * 0.17)
        let proxyPath = NSBezierPath(roundedRect: proxy, xRadius: 3, yRadius: 3)
        NSColor(white: 1, alpha: highlighted ? 0.6 : 0.35).setStroke()
        proxyPath.lineWidth = 1
        proxyPath.stroke()

        // The filled cells, flipped because unitRect measures y from the top.
        let unit = zone.unitRect
        let fill = NSRect(
            x: proxy.minX + unit.minX * proxy.width,
            y: proxy.maxY - (unit.minY + unit.height) * proxy.height,
            width: unit.width * proxy.width,
            height: unit.height * proxy.height
        )
        NSColor(white: 1, alpha: highlighted ? 0.98 : 0.8).setFill()
        NSBezierPath(roundedRect: fill.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2).fill()
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
