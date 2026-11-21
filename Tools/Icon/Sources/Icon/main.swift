// Draws the Rimwatch app icon: the game's emblem, "The Rim" (`Emblem` in GameCore), as neon
// lines on true black. The title screen draws the same emblem.
//
// Usage (from the repo root):
//   swift run --package-path Tools/Icon Icon Rimwatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
// Output is 1024x1024, sRGB, fully opaque (no alpha channel), full-bleed with square corners;
// iOS applies the rounded mask itself. The emblem fills the icon edge to edge, its line widths
// scaled with it, which is much heavier than in game so the icon still reads at home-screen size.
import CoreGraphics
import Foundation
import GameCore
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let side = CGFloat(size)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
/// Icon pixels per emblem unit.
let unit = side / CGFloat(Emblem.side)

func cg(_ c: RGB, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [CGFloat(c.r), CGFloat(c.g), CGFloat(c.b), alpha])!
}

/// An emblem point (y down, 0...100) in CoreGraphics' y-up pixel space.
func place(_ v: Vec2) -> CGPoint {
    CGPoint(x: CGFloat(v.x) * unit, y: side - CGFloat(v.y) * unit)
}

guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("could not create bitmap context")
}
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setFillColor(cg(Emblem.background))
ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

/// Strokes a path as a neon line: wide faint halos, the coloured line, then a pale hot core.
func neon(_ path: CGPath, color: RGB, width: CGFloat) {
    ctx.saveGState()
    let halos: [(width: CGFloat, alpha: CGFloat, blur: CGFloat)] = [
        (width * 4, 0.045, 90), (width * 2.2, 0.13, 40), (width * 1.3, 0.4, 18),
    ]
    for halo in halos {
        ctx.addPath(path)
        ctx.setLineWidth(halo.width)
        ctx.setStrokeColor(cg(color, halo.alpha))
        ctx.setShadow(offset: .zero, blur: halo.blur, color: cg(color, 0.9))
        ctx.strokePath()
    }
    ctx.setShadow(offset: .zero, blur: 10, color: cg(color, 1))
    ctx.addPath(path)
    ctx.setLineWidth(width)
    ctx.setStrokeColor(cg(color))
    ctx.strokePath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(path)
    ctx.setLineWidth(width * 0.38)
    ctx.setStrokeColor(cg(color.lightened(0.7)))
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: Stars

for star in Emblem.stars {
    let r = CGFloat(star.radius) * unit
    let c = place(star.center)
    let alpha = CGFloat(star.alpha)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: r * 3, color: cg(Emblem.starColor, alpha))
    ctx.setFillColor(cg(Emblem.starColor.lightened(0.3), alpha))
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    ctx.restoreGState()
}

// MARK: Rings and ship

for line in Emblem.lines {
    let path = CGMutablePath()
    path.addLines(between: line.points.map(place))
    if line.closed { path.closeSubpath() }
    neon(path, color: line.color, width: CGFloat(line.width) * unit)
}

// MARK: Write

guard let image = ctx.makeImage() else { fatalError("could not make image") }
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("could not write \(outPath)")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(outPath)") }
print("wrote \(url.path)")
