import Foundation
import GameCore
import RiftwingCore
import SpriteKit
import UIKit

/// Short-lived feedback in the gallery, in gallery units: spark bursts, spinning shards, debris
/// falling inward, small pops, soft flashes of light and rings. Everything comes from pools made
/// up front and is moved by hand each frame, with no actions. When a pool is full the oldest
/// entry is reused. Particles leaving the gallery are dropped. (Redoubt's pattern, kept in
/// Riftwing's folder since modes never share app code; sized down for a duel, not a flood.)
///
/// The gallery's side edges join, so anything that starts near one (or can travel past it) is
/// made twice, the twin a gallery's width away: what flies off one side shows on the other,
/// as figures do. The masks outside the gallery hide whichever half is out of it.
@MainActor
final class RiftwingEffects: SKNode {
    private struct Particle {
        var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
        var life = 0.0, maxLife = 1.0, size = 1.0
        /// Length along the spark against its width (1 is the plain spark).
        var length = 1.0
        /// Turning speed in radians a second; 0 points the spark along its motion.
        var spin = 0.0, rotation = 0.0
        /// How fast it slows (per second).
        var drag = 2.6
        /// Downward pull (units a second squared): falling rubble, drifting feathers.
        var gravity = 0.0
        var active = false
    }

    private struct Flash {
        var x = 0.0, y = 0.0, radius = 20.0, life = 0.0, maxLife = 0.2, strength = 1.0
        var active = false
    }

    private struct Pop {
        var x = 0.0, y = 0.0, radius = 10.0, life = 0.0, maxLife = 0.25
        var active = false
    }

    private struct Ring {
        var x = 0.0, y = 0.0
        var from = 0.0, to = 0.0
        var age = 0.0, duration = 0.4
        var active = false
    }

    static let particleCount = 260
    static let popCount = 32
    static let flashCount = 24
    static let ringCount = 8
    static let colonistCount = 6

    /// A freed colonist climbing away from its pod.
    private struct Colonist {
        var x = 0.0, y = 0.0, age = 0.0, life = 1.2
        var active = false
    }

    private var colonists = [Colonist](repeating: Colonist(), count: RiftwingEffects.colonistCount)
    private var colonistSprites: [SKSpriteNode] = []
    private var colonistCursor = 0

    private var particles = [Particle](repeating: Particle(), count: RiftwingEffects.particleCount)
    private var sparkSprites: [SKSpriteNode] = []
    private var cursor = 0
    private var pops = [Pop](repeating: Pop(), count: RiftwingEffects.popCount)
    private var popSprites: [SKSpriteNode] = []
    private var popCursor = 0
    private var flashes = [Flash](repeating: Flash(), count: RiftwingEffects.flashCount)
    private var flashSprites: [SKSpriteNode] = []
    private var flashCursor = 0
    private var rings = [Ring](repeating: Ring(), count: RiftwingEffects.ringCount)
    private var ringShapes: [[SKShapeNode]] = []
    private var ringCursor = 0
    private var rng = SeededRNG(seed: 0x0DE5_7EFF)
    private var floorBounds = CGRect(x: 0, y: 0, width: 900, height: 600)
    private var galleryWidth = 900.0
    private var pointsPerUnit: CGFloat = 1

    override init() {
        super.init()
        for _ in 0..<Self.particleCount {
            let sprite = SKSpriteNode()
            sprite.isHidden = true
            sprite.blendMode = .add
            sprite.colorBlendFactor = 1
            addChild(sprite)
            sparkSprites.append(sprite)
        }
        for _ in 0..<Self.popCount {
            let sprite = SKSpriteNode()
            sprite.isHidden = true
            sprite.blendMode = .add
            sprite.colorBlendFactor = 1
            addChild(sprite)
            popSprites.append(sprite)
        }
        for _ in 0..<Self.flashCount {
            let sprite = SKSpriteNode(texture: Self.glowTexture, size: CGSize(width: 2, height: 2))
            sprite.isHidden = true
            sprite.blendMode = .add
            sprite.colorBlendFactor = 1
            addChild(sprite)
            flashSprites.append(sprite)
        }
        for _ in 0..<Self.colonistCount {
            let sprite = SKSpriteNode()
            sprite.isHidden = true
            sprite.blendMode = .add
            addChild(sprite)
            colonistSprites.append(sprite)
        }
        for _ in 0..<Self.ringCount {
            let passes = (0..<3).map { _ -> SKShapeNode in
                let shape = SKShapeNode()
                shape.fillColor = .clear
                shape.blendMode = .add
                shape.isAntialiased = true
                shape.isHidden = true
                addChild(shape)
                return shape
            }
            ringShapes.append(passes)
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    /// A soft white disc fading to nothing at its edge, tinted per use: a moment of light.
    static let glowTexture: SKTexture = {
        let side: CGFloat = 64
        let image = GlowShapeFactory.image(size: CGSize(width: side, height: side), scale: 1) { context in
            let colors = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0.35).cgColor,
                          UIColor(white: 1, alpha: 0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1])!
            let c = CGPoint(x: side / 2, y: side / 2)
            context.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: side / 2,
                                       options: [])
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }()

    /// White textures, tinted per use, at the gallery's scale. Sparks are drawn at the figure scale
    /// (`RiftwingTuning.figureScale`), so the debris matches the figures it comes from; a pop is
    /// drawn at the radius it is given.
    func setPointsPerUnit(_ ppu: CGFloat, factory: GlowShapeFactory, gallery: CGSize, figureScale: Double) {
        pointsPerUnit = ppu
        floorBounds = CGRect(origin: .zero, size: gallery).insetBy(dx: -60, dy: -20)
        galleryWidth = Double(gallery.width)
        let white = RGB(1, 1, 1)
        let spark = factory.glyph(key: "riftwing-spark-x\(figureScale)", shape: ShapeDescription(scale: 3 * figureScale, strokes: [
            ShapeStroke([Vec2(-1, 0), Vec2(1, 0)], color: white),
        ]), pointsPerUnit: ppu)
        for sprite in sparkSprites { RiftwingSprites.dress(sprite, with: spark, factory: factory) }
        let pop = factory.glyph(key: "riftwing-pop", shape: ShapeDescription(scale: 10, strokes: [
            ShapeStroke(ShapeKit.arc(radius: 1, segments: 24), color: white),
        ]), pointsPerUnit: ppu)
        for sprite in popSprites { RiftwingSprites.dress(sprite, with: pop, factory: factory) }
    }

    /// The figure a freed colonist is drawn with.
    func setColonistGlyph(_ glyph: GlowShapeFactory.Glyph, factory: GlowShapeFactory) {
        for sprite in colonistSprites { RiftwingSprites.dress(sprite, with: glyph, factory: factory) }
    }

    /// A gallery's width to shift a twin by when something at `x` reaching `reach` either way
    /// crosses a side edge, or nil.
    private func twinShift(_ x: Double, reach: Double) -> Double? {
        if x - reach < 0 { return galleryWidth }
        if x + reach > galleryWidth { return -galleryWidth }
        return nil
    }

    func removeAll() {
        for index in colonists.indices where colonists[index].active {
            colonists[index].active = false
            colonistSprites[index].isHidden = true
        }
        for index in particles.indices where particles[index].active {
            particles[index].active = false
            sparkSprites[index].isHidden = true
        }
        for index in pops.indices where pops[index].active {
            pops[index].active = false
            popSprites[index].isHidden = true
        }
        for index in flashes.indices where flashes[index].active {
            flashes[index].active = false
            flashSprites[index].isHidden = true
        }
        for index in rings.indices {
            rings[index].active = false
            for shape in ringShapes[index] { shape.isHidden = true }
        }
    }

    var activeParticles: Int { particles.count { $0.active } }

    /// Sparks flying out from a point.
    func burst(at pos: Vec2, color: RGB, count: Int, speed: Double = 150, life: Double = 0.45, size: Double = 1) {
        spray(at: pos, angle: 0, spread: Double.pi, color: color, count: count, speed: speed, life: life, size: size)
    }

    /// Sparks thrown out in a cone `spread` either side of `angle`.
    func spray(at pos: Vec2, angle: Double, spread: Double, color: RGB, count: Int, speed: Double = 150,
               life: Double = 0.45, size: Double = 1, length: Double = 1, drag: Double = 2.6, gravity: Double = 0) {
        let uiColor = color.uiColor()
        for _ in 0..<count {
            let a = angle + rng.range(-spread...spread)
            let v = rng.range(speed * 0.4...speed * 1.2)
            var p = Particle()
            p.x = pos.x
            p.y = pos.y
            p.vx = cos(a) * v
            p.vy = sin(a) * v
            p.maxLife = rng.range(life * 0.6...life)
            p.life = p.maxLife
            p.size = size * rng.range(0.8...1.2)
            p.length = length
            p.drag = drag
            p.gravity = gravity
            emit(p, color: uiColor)
        }
    }

    /// Broken pieces tumbling away: longer sparks that spin as they fly and slow hard.
    func shards(at pos: Vec2, color: RGB, count: Int, speed: Double = 120, life: Double = 0.7, size: Double = 1.4) {
        let uiColor = color.uiColor()
        for _ in 0..<count {
            let a = rng.range(0...(2 * Double.pi))
            let v = rng.range(speed * 0.5...speed * 1.1)
            var p = Particle()
            p.x = pos.x
            p.y = pos.y
            p.vx = cos(a) * v
            p.vy = sin(a) * v
            p.maxLife = rng.range(life * 0.7...life)
            p.life = p.maxLife
            p.size = size * rng.range(0.7...1.3)
            p.length = 1.6
            p.spin = rng.range(-14...14)
            p.rotation = a
            p.drag = 4
            emit(p, color: uiColor)
        }
    }

    /// Feathers of light shed by a rig knocked off: long slivers thrown out, then drifting down
    /// and turning slowly as they fall.
    func feathers(at pos: Vec2, color: RGB, count: Int, speed: Double = 110, life: Double = 1.2, size: Double = 1.2) {
        let uiColor = color.uiColor()
        for _ in 0..<count {
            let a = rng.range(0.15...(Double.pi - 0.15))
            let v = rng.range(speed * 0.5...speed)
            var p = Particle()
            p.x = pos.x
            p.y = pos.y
            p.vx = cos(a) * v
            p.vy = sin(a) * v * 0.8
            p.maxLife = rng.range(life * 0.7...life)
            p.life = p.maxLife
            p.size = size * rng.range(0.8...1.2)
            p.length = 2.4
            p.spin = rng.range(-5...5)
            p.rotation = a
            p.drag = 2.2
            p.gravity = 70
            emit(p, color: uiColor)
        }
    }

    /// A freed colonist climbing out of its pod and away, arms up, fading as it rises.
    func colonist(at pos: Vec2) {
        let index = colonistCursor
        colonistCursor = (colonistCursor + 1) % Self.colonistCount
        colonists[index] = Colonist(x: pos.x, y: pos.y, age: 0, life: 1.2, active: true)
        colonistSprites[index].isHidden = true
    }

    /// Debris falling in from a ring of `radius` to the centre over `life`: a collapse.
    func implode(at pos: Vec2, radius: Double, color: RGB, count: Int, life: Double = 0.45, size: Double = 1) {
        let uiColor = color.uiColor()
        for i in 0..<count {
            let a = 2 * Double.pi * (Double(i) + rng.range(0...0.6)) / Double(count)
            let r = radius * rng.range(0.8...1.15)
            var p = Particle()
            p.x = pos.x + cos(a) * r
            p.y = pos.y + sin(a) * r
            p.maxLife = life * rng.range(0.85...1)
            p.vx = -cos(a) * r / p.maxLife
            p.vy = -sin(a) * r / p.maxLife
            p.life = p.maxLife
            p.size = size * rng.range(0.8...1.2)
            p.drag = 0
            emit(p, color: uiColor)
        }
    }

    private func emit(_ p: Particle, color: UIColor) {
        // How far it can travel: its speed for as long as its drag lets it keep it.
        let speed = (p.vx * p.vx + p.vy * p.vy).squareRoot()
        let reach = speed * min(p.maxLife, p.drag > 0 ? 1 / p.drag : p.maxLife) + 6
        place(p, color: color)
        if let shift = twinShift(p.x, reach: reach) {
            var twin = p
            twin.x += shift
            place(twin, color: color)
        }
    }

    private func place(_ p: Particle, color: UIColor) {
        let index = cursor
        cursor = (cursor + 1) % Self.particleCount
        var p = p
        p.active = true
        particles[index] = p
        let sprite = sparkSprites[index]
        sprite.color = color
        sprite.isHidden = true
    }

    /// A soft glow of `radius` units that fades over `life`: a muzzle lighting the floor, a kill's
    /// flash.
    func flash(at pos: Vec2, radius: Double, color: RGB, life: Double = 0.18, strength: Double = 1) {
        if let shift = twinShift(pos.x, reach: radius) {
            placeFlash(at: Vec2(pos.x + shift, pos.y), radius: radius, color: color, life: life, strength: strength)
        }
        placeFlash(at: pos, radius: radius, color: color, life: life, strength: strength)
    }

    private func placeFlash(at pos: Vec2, radius: Double, color: RGB, life: Double, strength: Double) {
        let index = flashCursor
        flashCursor = (flashCursor + 1) % Self.flashCount
        flashes[index] = Flash(x: pos.x, y: pos.y, radius: radius, life: life, maxLife: life, strength: strength,
                               active: true)
        let sprite = flashSprites[index]
        sprite.color = color.uiColor()
        sprite.position = CGPoint(x: pos.x, y: pos.y)
        sprite.size = CGSize(width: 2 * radius, height: 2 * radius)
        sprite.alpha = CGFloat(strength)
        sprite.isHidden = false
    }

    /// A small ring that swells and fades where something died.
    func pop(at pos: Vec2, color: RGB, radius: Double, life: Double = 0.25) {
        if let shift = twinShift(pos.x, reach: radius * 1.8) {
            placePop(at: Vec2(pos.x + shift, pos.y), color: color, radius: radius, life: life)
        }
        placePop(at: pos, color: color, radius: radius, life: life)
    }

    private func placePop(at pos: Vec2, color: RGB, radius: Double, life: Double) {
        let index = popCursor
        popCursor = (popCursor + 1) % Self.popCount
        pops[index] = Pop(x: pos.x, y: pos.y, radius: radius, life: life, maxLife: life, active: true)
        let sprite = popSprites[index]
        sprite.color = color.uiColor()
        sprite.position = CGPoint(x: pos.x, y: pos.y)
        sprite.isHidden = false
    }

    /// A big ring growing from `from` to `to` units (shrinking with `to` < `from`), re-stroked each
    /// frame so the line stays thin at any size.
    func ring(at pos: Vec2, color: RGB, from: Double, to: Double, duration: Double = 0.45, width: CGFloat = 1) {
        if let shift = twinShift(pos.x, reach: max(from, to)) {
            placeRing(at: Vec2(pos.x + shift, pos.y), color: color, from: from, to: to, duration: duration, width: width)
        }
        placeRing(at: pos, color: color, from: from, to: to, duration: duration, width: width)
    }

    private func placeRing(at pos: Vec2, color: RGB, from: Double, to: Double, duration: Double, width: CGFloat) {
        let index = ringCursor
        ringCursor = (ringCursor + 1) % Self.ringCount
        rings[index] = Ring(x: pos.x, y: pos.y, from: from, to: to, age: 0, duration: duration, active: true)
        let ppu = max(pointsPerUnit, 0.01)
        let passes: [(CGFloat, UIColor)] = [
            (7 * width / ppu, color.uiColor(alpha: 0.2)),
            (2.4 * width / ppu, color.uiColor(alpha: 0.85)),
            (1.0 * width / ppu, color.lightened(0.65).uiColor()),
        ]
        for (shape, pass) in zip(ringShapes[index], passes) {
            shape.lineWidth = pass.0
            shape.strokeColor = pass.1
            shape.position = CGPoint(x: pos.x, y: pos.y)
            shape.isHidden = false
            shape.alpha = 1
        }
    }

    func update(elapsed: Double) {
        let dt = min(max(elapsed, 0), 0.1)
        for index in 0..<Self.particleCount where particles[index].active {
            var p = particles[index]
            p.life -= dt
            if p.life <= 0 || !floorBounds.contains(CGPoint(x: p.x, y: p.y)) {
                particles[index].active = false
                sparkSprites[index].isHidden = true
                continue
            }
            if p.drag > 0 {
                let damping = exp(-p.drag * dt)
                p.vx *= damping
                p.vy *= damping
            }
            if p.gravity != 0 { p.vy -= p.gravity * dt }
            p.x += p.vx * dt
            p.y += p.vy * dt
            if p.spin != 0 { p.rotation += p.spin * dt }
            particles[index] = p
            let sprite = sparkSprites[index]
            sprite.isHidden = false
            sprite.position = CGPoint(x: p.x, y: p.y)
            sprite.zRotation = CGFloat(p.spin != 0 ? p.rotation : atan2(p.vy, p.vx))
            let t = p.life / p.maxLife
            sprite.alpha = CGFloat(min(1, t * 1.6))
            sprite.xScale = CGFloat(p.size * p.length * (0.35 + 0.65 * t))
            sprite.yScale = CGFloat(p.size)
        }
        for index in 0..<Self.popCount where pops[index].active {
            pops[index].life -= dt
            let sprite = popSprites[index]
            guard pops[index].life > 0 else {
                pops[index].active = false
                sprite.isHidden = true
                continue
            }
            let t = 1 - pops[index].life / pops[index].maxLife
            sprite.setScale(CGFloat(pops[index].radius / 10 * (0.6 + 1.2 * t)))
            sprite.alpha = CGFloat(1 - t)
        }
        for index in 0..<Self.flashCount where flashes[index].active {
            flashes[index].life -= dt
            let sprite = flashSprites[index]
            guard flashes[index].life > 0 else {
                flashes[index].active = false
                sprite.isHidden = true
                continue
            }
            let t = flashes[index].life / flashes[index].maxLife
            sprite.alpha = CGFloat(flashes[index].strength * t * t)
        }
        for index in 0..<Self.colonistCount where colonists[index].active {
            colonists[index].age += dt
            let c = colonists[index]
            let sprite = colonistSprites[index]
            guard c.age < c.life else {
                colonists[index].active = false
                sprite.isHidden = true
                continue
            }
            let t = c.age / c.life
            sprite.isHidden = false
            // Steps up out of the pod, then climbs away, swaying a little as it goes.
            sprite.position = CGPoint(x: c.x + 3 * sin(c.age * 9), y: c.y + 8 + 56 * (1 - (1 - t) * (1 - t)))
            sprite.setScale(CGFloat(0.7 + 0.4 * min(t * 4, 1)))
            sprite.alpha = CGFloat(min(t * 8, 1) * (1 - t * t))
        }
        for index in 0..<Self.ringCount where rings[index].active {
            rings[index].age += dt
            let ring = rings[index]
            let t = min(ring.age / ring.duration, 1)
            let shapes = ringShapes[index]
            guard t < 1 else {
                rings[index].active = false
                for shape in shapes { shape.isHidden = true }
                continue
            }
            let eased = 1 - (1 - t) * (1 - t)
            let r = ring.from + (ring.to - ring.from) * eased
            let path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
            let alpha = CGFloat(ring.to < ring.from ? min(1, 0.3 + t) : 1 - t * t)
            for shape in shapes {
                shape.path = path
                shape.alpha = alpha
            }
        }
    }
}
