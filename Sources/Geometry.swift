import AppKit

/// macOS hands us two coordinate systems and they disagree about which way is up.
///
///   - Cocoa (NSScreen, NSWindow, NSView): origin at the bottom-left of the
///     primary display, y increases upwards.
///   - Quartz / Accessibility (CGEvent locations, kAXPosition): origin at the
///     top-left of the primary display, y increases downwards.
///
/// Everything that touches a window lives in Quartz space; everything that
/// draws lives in Cocoa space. These helpers are the only place we flip.
enum Geo {

    /// The primary display's top edge in Cocoa coordinates, which is the pivot
    /// for flipping between the two systems.
    static var flipY: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    static func toQuartz(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: flipY - rect.maxY, width: rect.width, height: rect.height)
    }

    static func toCocoa(_ rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: flipY - rect.maxY, width: rect.width, height: rect.height)
    }

    static func toCocoa(_ point: CGPoint) -> NSPoint {
        NSPoint(x: point.x, y: flipY - point.y)
    }

    /// The screen under a Quartz-space point, falling back to the main screen so
    /// callers never have to deal with the cursor being in the gap between two
    /// displays with mismatched heights.
    static func screen(containing point: CGPoint) -> NSScreen? {
        let cocoa = toCocoa(point)
        return NSScreen.screens.first { $0.frame.contains(cocoa) } ?? NSScreen.main
    }
}
