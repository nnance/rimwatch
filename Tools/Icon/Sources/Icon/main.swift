// Draws the Rimwatch app icon: the player's ship over glowing orange ridges, on true black.
//
// Usage (from the repo root):
//   swift run --package-path Tools/Icon Icon Rimwatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
// Output is 1024x1024, sRGB, fully opaque (no alpha channel), full-bleed with square corners;
// iOS applies the rounded mask itself. Line weights are much heavier than in game so the icon
// still reads at home-screen size.
import CoreGraphics
import Foundation
import GameCore
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let side = CGFloat(size)
let theme = AlienFrontier()
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func cg(_ c: RGB, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [CGFloat(c.r), CGFloat(c.g), CGFloat(c.b), alpha])!
}

guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("could not create bitmap context")
}
// CoreGraphics is y-up with the origin at the bottom left, the same way up as the theme's shapes.
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setFillColor(cg(theme.palette.background))
ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

/// Strokes a path as a neon line: wide faint halos, the coloured line, then a pale hot core.
func neon(_ path: CGPath, color: RGB, width: CGFloat, glow: CGFloat = 1, core: Bool = true) {
    ctx.saveGState()
    let halos: [(width: CGFloat, alpha: CGFloat, blur: CGFloat)] = [
        (width * 4, 0.045, 90), (width * 2.2, 0.13, 40), (width * 1.3, 0.4, 18),
    ]
    for halo in halos {
        ctx.addPath(path)
        ctx.setLineWidth(halo.width)
        ctx.setStrokeColor(cg(color, halo.alpha * glow))
        ctx.setShadow(offset: .zero, blur: halo.blur, color: cg(color, 0.9 * glow))
        ctx.strokePath()
    }
    ctx.setShadow(offset: .zero, blur: 10, color: cg(color, 1))
    ctx.addPath(path)
    ctx.setLineWidth(width)
    ctx.setStrokeColor(cg(color))
    ctx.strokePath()
    if core {
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.addPath(path)
        ctx.setLineWidth(width * 0.38)
        ctx.setStrokeColor(cg(color.lightened(0.7)))
        ctx.strokePath()
    }
    ctx.restoreGState()
}

/// The strokes of a theme shape as one path each, placed by `transform` (unit coordinates in).
func paths(of shape: ShapeDescription, _ transform: CGAffineTransform) -> [(CGPath, RGB)] {
    shape.strokes.map { stroke in
        let path = CGMutablePath()
        path.addLines(between: stroke.points.map { CGPoint(x: $0.x, y: $0.y) }, transform: transform)
        if stroke.closed { path.closeSubpath() }
        return (path, stroke.color)
    }
}

// MARK: Stars

let stars: [(x: CGFloat, y: CGFloat, r: CGFloat, a: CGFloat)] = [
    (150, 880, 7, 0.9), (300, 790, 4, 0.6), (452, 925, 5, 0.7), (612, 860, 4, 0.5),
    (790, 920, 6, 0.85), (900, 780, 4, 0.55), (110, 640, 5, 0.6), (880, 560, 5, 0.65),
    (205, 450, 4, 0.5), (720, 420, 4, 0.45), (950, 360, 4, 0.4), (60, 370, 4, 0.4),
]
for star in stars {
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: star.r * 3, color: cg(theme.palette.stars, star.a))
    ctx.setFillColor(cg(theme.palette.stars.lightened(0.3), star.a))
    ctx.fillEllipse(in: CGRect(x: star.x - star.r, y: star.y - star.r, width: star.r * 2, height: star.r * 2))
    ctx.restoreGState()
}

// MARK: Terrain

/// The height of a wavy ridge at `x`.
func ridgeHeight(_ x: CGFloat, base: CGFloat, amp: CGFloat, phase: CGFloat) -> CGFloat {
    let t = x / side * 2 * .pi
    return base + amp * (sin(t * 1.0 + phase) * 0.6 + sin(t * 2.3 + phase * 1.7) * 0.3
        + sin(t * 4.1 + phase * 0.6) * 0.1)
}

/// A wavy line right across the icon (and a little past each edge).
func ridge(base: CGFloat, amp: CGFloat, phase: CGFloat) -> CGMutablePath {
    let path = CGMutablePath()
    for i in 0...128 {
        let x = -40 + (side + 80) * CGFloat(i) / 128
        let y = ridgeHeight(x, base: base, amp: amp, phase: phase)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    return path
}

let topRidge = ridge(base: 236, amp: 46, phase: 0.4)
// Ground below the top ridge: a faint warm wash so the ridges sit on land, not in space.
do {
    let ground = topRidge.mutableCopy()!
    ground.addLine(to: CGPoint(x: side + 40, y: -40))
    ground.addLine(to: CGPoint(x: -40, y: -40))
    ground.closeSubpath()
    ctx.saveGState()
    ctx.addPath(ground)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: srgb, colors: [
        cg(theme.terrain.strata, 0.30), cg(theme.terrain.strata, 0.05),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 290), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()
}
neon(ridge(base: 66, amp: 26, phase: 2.6), color: theme.terrain.strata.lightened(0.15), width: 11, glow: 0.7,
     core: false)
neon(ridge(base: 146, amp: 36, phase: 1.3), color: theme.terrain.ridge.scaled(0.75), width: 14, glow: 0.8,
     core: false)
neon(topRidge, color: theme.terrain.ridge, width: 20)

// A colonist waiting on the ridge, below and ahead of the ship.
let colonistX: CGFloat = 805
let colonistPlace = CGAffineTransform(translationX: colonistX,
                                      y: ridgeHeight(colonistX, base: 236, amp: 46, phase: 0.4) + 10)
    .scaledBy(x: 66, y: 66)
for (path, color) in paths(of: theme.shape(for: .colonist), colonistPlace) {
    neon(path, color: color, width: 13, glow: 0.8)
}

// MARK: Ship

let ship = theme.shape(for: .player)
let shipScale: CGFloat = 275
let shipAngle: CGFloat = 6 * .pi / 180
let shipPlace = CGAffineTransform(translationX: 535, y: 590).rotated(by: shipAngle)
    .scaledBy(x: shipScale, y: shipScale)

// Engine trail: tapering streaks out of the engine (the middle of the ship's rearmost points),
// faded out along their length by a gradient mask.
let shipTint = ship.strokes[0].color
let rearmost = ship.strokes.flatMap(\.points).filter { $0.x <= ship.bounds.min.x + 0.001 }
let engineX = CGFloat(ship.bounds.min.x)
let engineY = CGFloat(rearmost.map(\.y).reduce(0, +) / Double(max(rearmost.count, 1)))
for (offset, length, weight) in [(0.0, 1.7, 1.0), (0.2, 1.15, 0.6), (-0.2, 1.15, 0.6)] as
    [(CGFloat, CGFloat, CGFloat)] {
    let start = CGPoint(x: engineX - 0.02, y: engineY + offset * 0.5).applying(shipPlace)
    let end = CGPoint(x: engineX - 0.12 - length, y: engineY + offset * 0.75).applying(shipPlace)
    let half = 30 * weight
    let dx = end.x - start.x, dy = end.y - start.y
    let len = (dx * dx + dy * dy).squareRoot()
    let nx = -dy / len, ny = dx / len
    let wedge = CGMutablePath()
    wedge.addLines(between: [CGPoint(x: start.x + nx * half, y: start.y + ny * half), end,
                             CGPoint(x: start.x - nx * half, y: start.y - ny * half)])
    wedge.closeSubpath()
    let core = CGMutablePath()
    core.addLines(between: [start, end])

    ctx.saveGState()
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setShadow(offset: .zero, blur: 50, color: cg(shipTint, 1))
    ctx.addPath(wedge)
    ctx.setFillColor(cg(shipTint, 0.55))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(core)
    ctx.setLineWidth(half * 0.35)
    ctx.setStrokeColor(cg(shipTint.lightened(0.6)))
    ctx.strokePath()
    // Keep the trail where the mask is opaque: solid at the tail, gone at the far end.
    ctx.setBlendMode(.destinationIn)
    let fade = CGGradient(colorsSpace: srgb, colors: [
        CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 0.45), CGColor(gray: 0, alpha: 0),
    ] as CFArray, locations: [0, 0.45, 1])!
    ctx.drawLinearGradient(fade, start: start, end: end, options: [.drawsBeforeStartLocation])
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

for (path, color) in paths(of: ship, shipPlace) {
    neon(path, color: color, width: 20)
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
