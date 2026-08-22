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

// The split runs edge to edge: the plate *is* the screen, divided. No inner
// window floating in padding — the seam between the two panes is the only
// negative space, so the shape stays bold all the way down to 16pt.
NSGraphicsContext.saveGraphicsState()
platePath.addClip()

let seam = 20.0
let splitX = plate.minX + plate.width * 0.40

// Left pane: solid, the half the window lands in. Clipping to the plate gives
// it the plate's own rounded corners for free.
let leftPane = NSRect(
    x: plate.minX,
    y: plate.minY,
    width: splitX - plate.minX - seam / 2,
    height: plate.height
)
NSGradient(starting: NSColor(white: 1, alpha: 0.99), ending: rgb(214, 214, 240, 0.99))?
    .draw(in: leftPane, angle: -90)

// A soft shadow falling to the right of the seam, so the solid pane reads as
// sitting above the empty one rather than being a flat colour boundary.
let shadowBand = NSRect(x: splitX + seam / 2, y: plate.minY, width: 70, height: plate.height)
NSGradient(colors: [rgb(24, 12, 92, 0.30), rgb(24, 12, 92, 0)])?
    .draw(in: shadowBand, angle: 0)

NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()

// Rim light, stroked last so it traces the whole plate rather than being
// painted over by the solid pane.
platePath.lineWidth = 3
NSColor(white: 1, alpha: 0.30).setStroke()
platePath.stroke()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG")
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
