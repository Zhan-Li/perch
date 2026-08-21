// Draws the Perch app icon and writes a 1024x1024 PNG.
//
//     swift tools/make-icon.swift out.png
//
// Generated rather than hand-drawn so the icon is reproducible and carries no
// licensing questions. The glyph is deliberately blunt — a screen with its left
// half filled — because it has to stay readable at 16pt in the Finder sidebar,
// where anything more detailed turns to mush.

import AppKit

let side = 1024.0
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(side), pixelsHigh: Int(side),
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else {
    fatalError("could not allocate bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

// macOS icons sit in a rounded square inset from the canvas edge, leaving room
// for the system's drop shadow. 824pt of art on a 1024pt canvas is Apple's grid.
let plateSide = 824.0
let plate = NSRect(
    x: (side - plateSide) / 2,
    y: (side - plateSide) / 2,
    width: plateSide,
    height: plateSide
)
let platePath = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)

NSGradient(starting: rgb(129, 140, 248), ending: rgb(67, 56, 202))?
    .draw(in: platePath, angle: -90)

// A hairline of light along the top edge, which is what stops a flat gradient
// from looking like a placeholder.
platePath.lineWidth = 3
NSColor(white: 1, alpha: 0.28).setStroke()
platePath.stroke()

// The glyph: a screen, left half filled. Same idea as the drop-target icons the
// app itself draws, so the icon and the product agree with each other.
let screen = NSRect(x: 282, y: 352, width: 460, height: 320)
let stroke = 30.0

let screenPath = NSBezierPath(roundedRect: screen, xRadius: 40, yRadius: 40)
screenPath.lineWidth = stroke
NSColor(white: 1, alpha: 0.95).setStroke()
screenPath.stroke()

// Fill the left half, with a clear gap to the outline. Without the gap the
// fill and the border merge into a single white blob and the icon stops
// reading as "a zone inside a screen".
let gap = stroke * 1.4
let leftHalf = NSRect(
    x: screen.minX + gap,
    y: screen.minY + gap,
    width: screen.width / 2 - gap - stroke * 0.35,
    height: screen.height - gap * 2
)
NSColor(white: 1, alpha: 0.95).setFill()
NSBezierPath(roundedRect: leftHalf, xRadius: 18, yRadius: 18).fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG")
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
