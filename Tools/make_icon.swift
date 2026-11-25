import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "Resources/icon_1024.png"
let size = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("Cannot create bitmap") }
guard let context = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("Cannot create context") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

// Canvas is transparent. The icon tile has the familiar macOS squircle silhouette.
let tileRect = NSRect(x: 62, y: 62, width: 900, height: 900)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 210, yRadius: 210)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowBlurRadius = 38
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()

let gradient = NSGradient(colorsAndLocations:
    (color(0x6D5DFB), 0.0),
    (color(0x4C6FFF), 0.48),
    (color(0x20B8F5), 1.0)
)!
gradient.draw(in: tile, angle: -55)

NSGraphicsContext.saveGraphicsState()
tile.addClip()

// Ambient highlights.
let topGlow = NSBezierPath(ovalIn: NSRect(x: 40, y: 520, width: 780, height: 560))
color(0xFFFFFF, 0.14).setFill()
topGlow.fill()

let bottomGlow = NSBezierPath(ovalIn: NSRect(x: 400, y: -180, width: 760, height: 650))
color(0x78F0FF, 0.18).setFill()
bottomGlow.fill()

// Faint grid lines give the tile a "lens / analysis" feeling.
for index in 0..<7 {
    let x = CGFloat(150 + index * 110)
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x, y: 100))
    path.line(to: NSPoint(x: x, y: 924))
    path.lineWidth = 1.5
    color(0xFFFFFF, 0.055).setStroke()
    path.stroke()
}
for index in 0..<7 {
    let y = CGFloat(150 + index * 110)
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 100, y: y))
    path.line(to: NSPoint(x: 924, y: y))
    path.lineWidth = 1.5
    color(0xFFFFFF, 0.055).setStroke()
    path.stroke()
}
NSGraphicsContext.restoreGraphicsState()

// Document sheet, slightly tilted.
NSGraphicsContext.saveGraphicsState()
let transform = NSAffineTransform()
transform.translateX(by: 445, yBy: 555)
transform.rotate(byDegrees: -7)
transform.concat()

let pageRect = NSRect(x: -178, y: -235, width: 356, height: 470)
let page = NSBezierPath(roundedRect: pageRect, xRadius: 38, yRadius: 38)
let pageShadow = NSShadow()
pageShadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
pageShadow.shadowBlurRadius = 32
pageShadow.shadowOffset = NSSize(width: 0, height: -14)
pageShadow.set()
color(0xFFFFFF, 0.985).setFill()
page.fill()

let fold = NSBezierPath()
fold.move(to: NSPoint(x: 88, y: 235))
fold.line(to: NSPoint(x: 178, y: 145))
fold.line(to: NSPoint(x: 88, y: 145))
fold.close()
color(0xDCE7FF, 1).setFill()
fold.fill()

// Code-like lines.
let lineSpecs: [(CGFloat, CGFloat, NSColor)] = [
    (140, 18, color(0x4F46E5, 0.78)),
    (98, 14, color(0x8A94A8, 0.55)),
    (205, 14, color(0x8A94A8, 0.55)),
    (150, 14, color(0x20B8F5, 0.65)),
    (182, 14, color(0x8A94A8, 0.50)),
    (110, 14, color(0x8A94A8, 0.50))
]
var y: CGFloat = 112
for (width, height, tint) in lineSpecs {
    let r = NSRect(x: -132, y: y, width: width, height: height)
    let p = NSBezierPath(roundedRect: r, xRadius: height / 2, yRadius: height / 2)
    tint.setFill()
    p.fill()
    y -= 42
}
NSGraphicsContext.restoreGraphicsState()

// Magnifying glass handle (behind the lens).
let handle = NSBezierPath()
handle.move(to: NSPoint(x: 770, y: 410))
handle.line(to: NSPoint(x: 906, y: 274))
handle.lineWidth = 48
handle.lineCapStyle = .round
let handleShadow = NSShadow()
handleShadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
handleShadow.shadowBlurRadius = 18
handleShadow.shadowOffset = NSSize(width: 0, height: -8)
handleShadow.set()
color(0xFFFFFF, 0.96).setStroke()
handle.stroke()

// Lens.
let lensRect = NSRect(x: 549, y: 361, width: 270, height: 270)
let lens = NSBezierPath(ovalIn: lensRect)
color(0x163A8C, 0.30).setFill()
lens.fill()

let lensShadow = NSShadow()
lensShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
lensShadow.shadowBlurRadius = 24
lensShadow.shadowOffset = NSSize(width: 0, height: -10)
lensShadow.set()
lens.lineWidth = 44
color(0xFFFFFF, 0.98).setStroke()
lens.stroke()

// A tiny highlighted line inside the lens.
let innerLine = NSBezierPath(roundedRect: NSRect(x: 610, y: 475, width: 146, height: 20),
                             xRadius: 10, yRadius: 10)
color(0x8DF0D0, 0.95).setFill()
innerLine.fill()
let innerLine2 = NSBezierPath(roundedRect: NSRect(x: 610, y: 436, width: 104, height: 15),
                              xRadius: 7.5, yRadius: 7.5)
color(0xFFFFFF, 0.62).setFill()
innerLine2.fill()

// Sparkle accent.
let sparkle = NSBezierPath()
sparkle.move(to: NSPoint(x: 760, y: 865))
sparkle.line(to: NSPoint(x: 778, y: 825))
sparkle.line(to: NSPoint(x: 818, y: 807))
sparkle.line(to: NSPoint(x: 778, y: 789))
sparkle.line(to: NSPoint(x: 760, y: 749))
sparkle.line(to: NSPoint(x: 742, y: 789))
sparkle.line(to: NSPoint(x: 702, y: 807))
sparkle.line(to: NSPoint(x: 742, y: 825))
sparkle.close()
color(0xFFFFFF, 0.72).setFill()
sparkle.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("Cannot encode PNG") }
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
