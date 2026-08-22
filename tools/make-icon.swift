// Draws the Perch app icon and writes a 1024x1024 PNG.
//
//     swift tools/make-icon.swift out.png
//
// Generated rather than hand-drawn so the icon is reproducible and carries no
// licensing questions.
//
// The glyph is two tiles rather than an outlined screen: a solid one and a
// translucent one, lifted off the plate with a soft shadow. It reads as windows
// arranged side by side, and the depth is what stops it looking like a flat
// 2013 icon. Everything is kept chunky because the artwork is downscaled to
// 16pt for the Finder sidebar, where fine detail turns to mush.

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

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// macOS icons sit in a rounded square inset from the canvas edge, leaving room
// for the system's own drop shadow. 824pt of art on a 1024pt canvas.
let plateSide = 824.0
let plate = NSRect(
    x: (side - plateSide) / 2,
    y: (side - plateSide) / 2,
    width: plateSide,
    height: plateSide
)
let platePath = NSBezierPath(roundedRect: plate, xRadius: 186, yRadius: 186)

// Plate: a diagonal gradient with a soft light source in the upper left, which
// is what gives it dimension rather than looking like flat coloured paper.
NSGraphicsContext.saveGraphicsState()
platePath.addClip()

NSGradient(starting: rgb(139, 132, 255), ending: rgb(58, 42, 168))?
    .draw(in: plate, angle: -65)

NSGradient(colors: [NSColor(white: 1, alpha: 0.30), NSColor(white: 1, alpha: 0)])?
    .draw(
        fromCenter: NSPoint(x: plate.minX + 170, y: plate.maxY - 110), radius: 0,
        toCenter: NSPoint(x: plate.minX + 170, y: plate.maxY - 110), radius: 620,
        options: []
    )

// A deeper corner opposite the light keeps the plate from going flat.
NSGradient(colors: [rgb(30, 18, 110, 0.42), rgb(30, 18, 110, 0)])?
    .draw(
        fromCenter: NSPoint(x: plate.maxX, y: plate.minY), radius: 0,
        toCenter: NSPoint(x: plate.maxX, y: plate.minY), radius: 520,
        options: []
    )

NSGraphicsContext.restoreGraphicsState()

// Rim light along the top edge.
platePath.lineWidth = 3
NSColor(white: 1, alpha: 0.34).setStroke()
platePath.stroke()

// The tiles. Deliberately uneven — a narrow pane beside a wide one is what a
// real split looks like, and it is more legible than two equal halves.
let group = NSRect(x: 268, y: 344, width: 488, height: 336)
let gap = 34.0
let leftWidth = 176.0
let radius = 30.0

let left = NSRect(x: group.minX, y: group.minY, width: leftWidth, height: group.height)
let right = NSRect(
    x: group.minX + leftWidth + gap,
    y: group.minY,
    width: group.width - leftWidth - gap,
    height: group.height
)

func withShadow(_ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = rgb(20, 10, 70, 0.40)
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

// Solid pane: the one the window lands in.
withShadow {
    NSColor(white: 1, alpha: 0.97).setFill()
    NSBezierPath(roundedRect: left, xRadius: radius, yRadius: radius).fill()
}

// Glass pane: the space left over. Its opacity is set by what survives being
// downscaled to 16pt, not by what looks best at 1024 — too subtle there and the
// icon degrades into a lone white bar on a purple square.
withShadow {
    NSColor(white: 1, alpha: 0.46).setFill()
    NSBezierPath(roundedRect: right, xRadius: radius, yRadius: radius).fill()
}

let rightPath = NSBezierPath(roundedRect: right.insetBy(dx: 2, dy: 2), xRadius: radius - 2, yRadius: radius - 2)
rightPath.lineWidth = 7
NSColor(white: 1, alpha: 0.85).setStroke()
rightPath.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG")
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
