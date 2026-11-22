import Foundation
import GameCore
import RiftwingCore
import SpriteKit
import UIKit

// Riftwing's cavern: the roof, the tunnel mouths, the ledges of each layout, the Rift and its
// breath, the vents' motes, the lamps-out darkness, the sprite pools and the title backdrop.

extension RiftwingMode {
    /// Depths inside the gallery layer (which sits at z 10; the HUD is at 80). The darkness covers
    /// the rock and the opponents but not what gives light: the Rift's edge, a pod about to hatch,
    /// the rider, the gas and the glows in the tunnel mouths.
    enum Depth {
        static let roof: CGFloat = 0
        static let ledges: CGFloat = 1
        static let motes: CGFloat = 1.5
        static let riftGlow: CGFloat = 2
        static let link: CGFloat = 3
        static let mine: CGFloat = 3.1
        static let pod: CGFloat = 3.5
        static let darkness: CGFloat = 5
        static let riftLine: CGFloat = 5.2
        static let litPod: CGFloat = 5.3
        static let rider: CGFloat = 6
        static let shield: CGFloat = 6.1
        static let gas: CGFloat = 6.5
        static let gasTop: CGFloat = 6.6
        static let breathMark: CGFloat = 6.7
        static let effects: CGFloat = 7
        static let masks: CGFloat = 8
        static let mouths: CGFloat = 8.5
        static let arrivalGlow: CGFloat = 8.55
        static let arrival: CGFloat = 8.6
    }

    /// Each opponent role at its own depth, so sprites sharing a texture draw in one batch.
    static func depth(of role: RiftwingRole) -> CGFloat {
        switch role {
        case .glider: 4
        case .striker: 4.1
        case .warden: 4.2
        case .sower: 4.3
        case .gleaner: 4.4
        }
    }

    func buildNodes() {
        galleryLayer.zPosition = 10
        hud.zPosition = 80
        controls.zPosition = 100
        callouts.zPosition = 105
        root.addChild(galleryLayer)
        for node in [hud, controls, callouts] as [SKNode] {
            node.isHidden = true
            root.addChild(node)
        }
        let placed: [(SKSpriteNode, CGFloat)] = [
            (roofSprite, Depth.roof), (riftGlow, Depth.riftGlow), (riftLine, Depth.riftLine), (gasSprite, Depth.gas),
            (gasTop, Depth.gasTop), (breathMark, Depth.breathMark), (darkness, Depth.darkness), (mouthSprite, Depth.mouths),
        ]
        for (sprite, depth) in placed {
            sprite.zPosition = depth
            galleryLayer.addChild(sprite)
        }
        gasSprite.isHidden = true
        gasTop.isHidden = true
        breathMark.isHidden = true
        darkness.isHidden = true
        darkness.blendMode = .alpha
        gasSprite.blendMode = .add
        riftGlow.blendMode = .add
        for _ in 0..<4 {
            let mask = SKSpriteNode(color: .black, size: CGSize(width: 1, height: 1))
            mask.anchorPoint = .zero
            mask.blendMode = .replace
            mask.zPosition = Depth.masks
            galleryLayer.addChild(mask)
            masks.append(mask)
        }
        effects.zPosition = Depth.effects
        for node in [entityLayer, decorLayer, effects] as [SKNode] { galleryLayer.addChild(node) }
        for _ in RiftwingCavern.layouts {
            let sprite = SKSpriteNode()
            sprite.zPosition = Depth.ledges
            sprite.alpha = 0
            galleryLayer.addChild(sprite)
            ledgeSprites.append(sprite)
            ledgeAlpha.append(0)
        }

        func pool(_ count: Int, z: CGFloat) -> [PoolSprite] {
            (0..<count).map { _ in
                let sprite = PoolSprite()
                sprite.isHidden = true
                sprite.zPosition = z
                entityLayer.addChild(sprite)
                return sprite
            }
        }
        opponentSprites = pool(Self.opponentPool, z: 4)
        podSprites = pool(Self.podPool, z: Depth.pod)
        mineSprites = pool(Self.minePool, z: Depth.mine)
        arrivalSprites = pool(Self.arrivalPool, z: Depth.arrival)
        for sprite in arrivalSprites { sprite.colorBlendFactor = 1 }
        arrivalGlows = (0..<Self.arrivalPool).map { _ in
            let glow = SKSpriteNode(texture: RiftwingEffects.glowTexture, size: CGSize(width: 2, height: 2))
            glow.blendMode = .add
            glow.colorBlendFactor = 1
            glow.zPosition = Depth.arrivalGlow
            glow.isHidden = true
            entityLayer.addChild(glow)
            return glow
        }
        ghostSprites = pool(Self.ghostPool, z: 4)
        linkSprites = (0..<Self.linkPool).map { _ in
            let line = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))
            line.anchorPoint = CGPoint(x: 0, y: 0.5)
            line.blendMode = .add
            line.zPosition = Depth.link
            line.isHidden = true
            entityLayer.addChild(line)
            return line
        }
        moteSprites = (0..<(3 * Self.motesPerVent)).map { _ in
            let mote = SKSpriteNode()
            mote.zPosition = Depth.motes
            mote.isHidden = true
            galleryLayer.addChild(mote)
            return mote
        }
        var rng = SeededRNG(seed: 0x0A1E_5EED)
        motes = (0..<moteSprites.count).map { _ in
            (x: rng.range(-1...1), y: rng.range(0...1), speed: rng.range(0.7...1.3))
        }
        riderSprite.zPosition = Depth.rider
        riderSprite.isHidden = true
        shieldSprite.zPosition = Depth.shield
        shieldSprite.isHidden = true
        for node in [riderSprite, shieldSprite] as [SKNode] { entityLayer.addChild(node) }
    }

    /// Black covers just outside the gallery on every side (to the screen's edges), so figures
    /// and effects never show past it, and what crosses a side edge shows only on the other side.
    func layoutMasks(size: CGSize) {
        let ppu = max(pointsPerUnit, 0.01)
        let w = tuning.width, h = tuning.height
        let left = Double(galleryOrigin.x / ppu) + 50, right = Double((size.width - galleryOrigin.x) / ppu) - w + 50
        let below = Double(galleryOrigin.y / ppu) + 50, above = Double((size.height - galleryOrigin.y) / ppu) - h + 50
        let rects = [
            CGRect(x: -left, y: -below, width: left, height: h + below + above),
            CGRect(x: w, y: -below, width: right, height: h + below + above),
            CGRect(x: 0, y: h, width: w, height: above),
            CGRect(x: 0, y: -below, width: w, height: below),
        ]
        for (mask, rect) in zip(masks, rects) {
            mask.position = rect.origin
            mask.size = CGSize(width: max(rect.width, 1), height: max(rect.height, 1))
        }
    }

    /// The rock, the Rift and the mouths for the current scale, and the gradient textures.
    func buildCavern() {
        let ppu = pointsPerUnit
        let palette = theme.palette
        let w = tuning.width, h = tuning.height

        // The roof: a ragged line along the top, and short faint teeth hanging from it.
        let jag = [0.0, 4, 1, 6, 2, 5, 0, 3, 7, 2, 4, 1, 6, 3, 0, 5, 2, 6, 1, 4, 3, 7, 1, 5, 2, 4, 0, 6, 3, 1, 0]
        var roofLine: [Vec2] = []
        for (i, j) in jag.enumerated() { roofLine.append(Vec2(Double(i) * w / Double(jag.count - 1), h - j)) }
        var roof = [ShapeStroke(roofLine, color: palette.rock.scaled(0.8))]
        for (x, length) in [(60.0, 16.0), (175, 10), (300, 20), (410, 12), (555, 18), (690, 11), (790, 22), (860, 9)] {
            roof.append(ShapeStroke([Vec2(x - 6, h - 3), Vec2(x, h - length), Vec2(x + 5, h - 3)], color: palette.rockFaint))
        }
        RiftwingSprites.dress(roofSprite, with: glyphs.glyph(key: "roof", strokes: roof, pointsPerUnit: ppu), factory: factory)
        roofSprite.position = .zero

        // The tunnel mouths: each side edge opens into a tunnel receding into the rock beyond it.
        var mouths: [ShapeStroke] = []
        let faint = palette.rockFaint.lightened(0.2)
        for side in [-1.0, 1.0] {
            let edge = side < 0 ? 0.0 : w
            let depth = 46.0
            mouths.append(ShapeStroke([Vec2(edge, h), Vec2(edge + side * depth, h - 40), Vec2(edge + side * depth, 60),
                                       Vec2(edge, 0)], color: faint))
            mouths.append(ShapeStroke([Vec2(edge + side * depth * 0.5, h - 20), Vec2(edge + side * depth * 0.5, 30)],
                                      color: palette.rockFaint))
            for y in stride(from: 120.0, through: 480, by: 120) {
                mouths.append(ShapeStroke([Vec2(edge, y), Vec2(edge + side * depth, y + (300 - y) * 0.12)],
                                          color: palette.rockFaint.scaled(0.8)))
            }
        }
        RiftwingSprites.dress(mouthSprite, with: glyphs.glyph(key: "mouths", strokes: mouths, pointsPerUnit: ppu),
                              factory: factory)
        mouthSprite.position = .zero

        for (index, layout) in RiftwingCavern.layouts.enumerated() {
            RiftwingSprites.dress(ledgeSprites[index], with: glyphs.glyph(key: "ledges-\(index)",
                                                                          strokes: ledgeStrokes(layout), pointsPerUnit: ppu),
                                  factory: factory)
            ledgeSprites[index].position = .zero
        }

        // The Rift: a hot glow rising from the bottom, and a ragged fissure along its edge.
        riftGlow.texture = Self.gradientTexture(palette.rift, bottom: 0.55, top: 0)
        riftGlow.anchorPoint = .zero
        riftGlow.size = CGSize(width: w, height: 80)
        riftGlow.position = .zero
        var fissure: [Vec2] = []
        var crack: [Vec2] = []
        let level = tuning.riftLevel
        for i in 0...36 {
            let x = Double(i) * w / 36
            let wobble = [0.0, 3, -2, 4, -3, 1, -4, 2][i % 8]
            fissure.append(Vec2(x, level - 4 + wobble))
            crack.append(Vec2(x + 6, level - 12 - wobble * 0.6))
        }
        RiftwingSprites.dress(riftLine, with: glyphs.glyph(key: "rift", strokes: [
            ShapeStroke(crack, color: palette.rift.scaled(0.6)),
            ShapeStroke(fissure, color: palette.rift),
        ], pointsPerUnit: ppu), factory: factory)
        riftLine.position = .zero

        // The breath: a sickly glow up to the gas level with a rolling top, and the mark the
        // warning shows where it will reach.
        gasSprite.texture = Self.gradientTexture(palette.gas, bottom: 0.5, top: 0.18)
        gasSprite.anchorPoint = .zero
        gasSprite.position = .zero
        var wave: [Vec2] = []
        for i in 0...72 {
            let x = Double(i) * 2 * w / 72
            wave.append(Vec2(x, 5 * sin(Double(i) * Double.pi / 4.5)))
        }
        RiftwingSprites.dress(gasTop, with: glyphs.glyph(key: "gas-top", strokes: [ShapeStroke(wave, color: palette.gas)],
                                                         pointsPerUnit: ppu), factory: factory)
        var dashes: [ShapeStroke] = []
        for x in stride(from: 0.0, to: w, by: 30) {
            dashes.append(ShapeStroke([Vec2(x, 0), Vec2(x + 16, 0)], color: palette.gas))
        }
        RiftwingSprites.dress(breathMark, with: glyphs.glyph(key: "breath-mark", strokes: dashes, pointsPerUnit: ppu),
                              factory: factory)

        // The darkness: black everywhere but a soft pool of light at its centre, big enough to
        // cover the gallery from anywhere the rider can be.
        darkness.texture = Self.darknessTexture
        let span = 2 * (w + h)
        darkness.size = CGSize(width: span, height: span)

        let mote = glyphs.glyph(key: "mote", strokes: [ShapeStroke([Vec2(0, -2.5), Vec2(0, 2.5)], color: palette.vent)],
                                pointsPerUnit: ppu)
        for sprite in moteSprites { RiftwingSprites.dress(sprite, with: mote, factory: factory) }
    }

    /// A layout's ledges as rock in outline: a flat bright top (the standing surface), the ends
    /// rounding down to a ragged underside at the ledge's thickness, a few faint strata marks in
    /// the slab and short faint teeth hanging below.
    func ledgeStrokes(_ layout: RiftwingLayout) -> [ShapeStroke] {
        let palette = theme.palette
        let t = tuning.ledgeThickness
        var strokes: [ShapeStroke] = []
        for (n, ledge) in layout.ledges.enumerated() {
            let top = ledge.top
            var outline = [Vec2(ledge.minX, top), Vec2(ledge.maxX, top), Vec2(ledge.maxX - 2, top - t * 0.5),
                           Vec2(ledge.maxX - 8, top - t)]
            var x = ledge.maxX - 8 - 22
            var k = n
            while x > ledge.minX + 8 {
                k += 1
                outline.append(Vec2(x, top - t + [1.5, -1.5, 0.5, -2][k % 4]))
                x -= 22
            }
            outline.append(Vec2(ledge.minX + 8, top - t))
            outline.append(Vec2(ledge.minX + 2, top - t * 0.5))
            strokes.append(ShapeStroke(outline, closed: true, color: palette.rock))
            strokes.append(ShapeStroke([Vec2(ledge.minX + 1, top), Vec2(ledge.maxX - 1, top)], color: palette.rock.lightened(0.3)))
            var mark = ledge.minX + 18 + Double(n * 7 % 20)
            while mark < ledge.maxX - 26 {
                strokes.append(ShapeStroke([Vec2(mark, top - t * 0.45), Vec2(mark + 12, top - t * 0.55)],
                                           color: palette.rockFaint.lightened(0.15)))
                mark += 44
            }
            var tooth = ledge.minX + 26 + Double(n * 11 % 30)
            while tooth < ledge.maxX - 20 {
                strokes.append(ShapeStroke([Vec2(tooth - 4, top - t), Vec2(tooth, top - t - 7), Vec2(tooth + 3, top - t)],
                                           color: palette.rockFaint))
                tooth += 63
            }
        }
        return strokes
    }

    /// A vertical gradient of one colour, `bottom` alpha at the foot to `top` at the head.
    static func gradientTexture(_ color: RGB, bottom: Double, top: Double) -> SKTexture {
        let image = GlowShapeFactory.image(size: CGSize(width: 4, height: 128), scale: 1) { context in
            let colors = [color.cgColor(alpha: bottom), color.cgColor(alpha: top)] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            // Image space is y down: the foot is at the image's bottom.
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 128), end: CGPoint(x: 0, y: 0), options: [])
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    /// Black with a clear soft hole. The sprite is 3,000 units across, so the pool is fully lit
    /// out to about 70 units from the rider and dark from about 160.
    static let darknessTexture: SKTexture = {
        let side: CGFloat = 512
        let image = GlowShapeFactory.image(size: CGSize(width: side, height: side), scale: 1) { context in
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.35).cgColor,
                          UIColor(white: 0, alpha: 0.94).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.45, 1])!
            context.setFillColor(UIColor(white: 0, alpha: 0.94).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            context.setBlendMode(.copy)
            let c = CGPoint(x: side / 2, y: side / 2)
            context.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c,
                                       endRadius: side * 0.053, options: [])
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }()

    /// Gives every pooled sprite a texture for the current scale (they are re-dressed as needed).
    func dressPools() {
        for sprite in opponentSprites + podSprites + mineSprites + arrivalSprites + ghostSprites {
            sprite.look = PoolSprite.undressed
        }
        riderSprite.look = PoolSprite.undressed
        let arrival = glyphs.glyph(.arrival, scale: Self.arrivalGlyphScale, pointsPerUnit: pointsPerUnit)
        for sprite in arrivalSprites { RiftwingSprites.dress(sprite, with: arrival, factory: factory) }
        let fig = tuning.figureScale
        RiftwingSprites.dress(shieldSprite, with: factory.glyph(key: "riftwing-shield-x\(fig)", shape: ShapeDescription(
            scale: tuning.riderRadius * 1.35, strokes: [
                ShapeStroke(ShapeKit.arc(radius: 1, segments: 36), color: theme.palette.shield),
            ]), pointsPerUnit: pointsPerUnit), factory: factory)
        looks = makeLooks()
    }

    func hideAllPooled() {
        for sprite in opponentSprites + podSprites + mineSprites + arrivalSprites + ghostSprites { sprite.isHidden = true }
        for sprite in arrivalGlows + linkSprites { sprite.isHidden = true }
        riderSprite.isHidden = true
        shieldSprite.isHidden = true
        gasSprite.isHidden = true
        gasTop.isHidden = true
        breathMark.isHidden = true
        darkness.isHidden = true
        shownOpponents = 0
        shownPods = 0
        shownMines = 0
        shownArrivals = 0
        shownLinks = 0
        shownGhosts = 0
    }

    // MARK: The cavern each frame

    /// The current layout's ledges fade in (and the old ones out) when the cavern shifts; while
    /// it rumbles toward its next layout the old rock trembles and flickers.
    func syncLedges(_ run: RiftwingRun, dt: Double) {
        let current = run.layoutIndex
        if shownLayout < 0 {
            // A new run, or the first frame: no fade.
            for index in ledgeAlpha.indices { ledgeAlpha[index] = index == current ? 1 : 0 }
        }
        shownLayout = current
        for (index, sprite) in ledgeSprites.enumerated() {
            let target = index == current ? 1.0 : 0.0
            ledgeAlpha[index] += (target - ledgeAlpha[index]) * min(dt * 3.5, 1)
            if abs(ledgeAlpha[index] - target) < 0.01 { ledgeAlpha[index] = target }
            var alpha = ledgeAlpha[index]
            var offset = CGPoint.zero
            if isShifting, index == current {
                alpha *= sin(clock * 31) > -0.3 ? 1 : 0.45
                offset = CGPoint(x: CGFloat.random(in: -1.5...1.5), y: CGFloat.random(in: -1.5...1.5))
            } else if index != current, alpha > 0 {
                // The old rock flickers as it goes.
                alpha *= sin(clock * 40) > 0 ? 1 : 0.5
            }
            sprite.isHidden = alpha <= 0.005
            sprite.alpha = CGFloat(alpha) * (1 - 0.5 * CGFloat(darkMix))
            sprite.position = offset
        }
    }

    /// Motes rise through each vent's column, fading near its top.
    func syncMotes(_ run: RiftwingRun, dt: Double) {
        let vents = run.vents
        let half = tuning.ventHalfWidth
        let base = tuning.riftLevel
        var i = 0
        for vent in vents {
            let height = max(vent.top - base, 1)
            for _ in 0..<Self.motesPerVent {
                guard i < moteSprites.count else { break }
                var mote = motes[i]
                mote.y += dt * tuning.ventRise * 0.55 * mote.speed / height
                if mote.y > 1 { mote.y -= 1 }
                motes[i] = mote
                let sprite = moteSprites[i]
                sprite.isHidden = false
                let sway = 3 * sin(clock * 2 + Double(i))
                sprite.position = CGPoint(x: vent.x + mote.x * half * 0.85 + sway, y: base + mote.y * height)
                let fade = min(mote.y * 6, 1) * min((1 - mote.y) * 4, 1)
                sprite.alpha = CGFloat(0.65 * fade) * (1 - 0.6 * CGFloat(darkMix))
                i += 1
            }
        }
        while i < moteSprites.count {
            moteSprites[i].isHidden = true
            i += 1
        }
    }

    /// The Rift glows and flickers; while it breathes, the warning mark blinks where the gas will
    /// reach and the gas rises, holds and sinks.
    func syncRift(_ run: RiftwingRun) {
        let warning: Bool
        if case .warning = run.breath { warning = true } else { warning = false }
        let flicker = 0.75 + 0.12 * sin(clock * 3.1) + 0.08 * sin(clock * 7.7)
        riftGlow.alpha = CGFloat(warning ? flicker + 0.35 * abs(sin(clock * 9)) : flicker)
        riftGlow.yScale = warning ? CGFloat(1.4 + 0.3 * sin(clock * 9)) : 1
        riftLine.alpha = CGFloat(0.8 + 0.2 * sin(clock * 5))

        let level = run.gasLevel
        let gas = level > tuning.riftLevel + 0.5
        gasSprite.isHidden = !gas
        gasTop.isHidden = !gas
        if gas {
            gasSprite.size = CGSize(width: tuning.width, height: level)
            gasSprite.alpha = run.isBreathDeadly ? 1 : 0.7
            gasTop.position = CGPoint(x: -(clock * 40).truncatingRemainder(dividingBy: tuning.width), y: level)
            gasTop.alpha = run.isBreathDeadly ? 1 : 0.6
        }
        breathMark.isHidden = !warning
        if warning {
            breathMark.position = CGPoint(x: 0, y: run.breathLevel)
            breathMark.alpha = sin(clock * 12) > 0 ? 0.95 : 0.3
        }
    }

    /// The darkness when the lamps are out, centred on the rider (or where it was lost).
    func syncDarkness(_ run: RiftwingRun, dt: Double) {
        let target = run.isLampsOut ? 1.0 : 0.0
        // The lamps stutter out over about a second and come back faster.
        let rate = run.isLampsOut ? 1.6 : 2.5
        darkMix += (target - darkMix) * min(dt * rate, 1)
        if abs(darkMix - target) < 0.01 { darkMix = target }
        darkness.isHidden = darkMix <= 0
        if !darkness.isHidden {
            let lit = run.rider.pos
            darkness.position = CGPoint(x: lit.x, y: lit.y)
            let stutter = run.isLampsOut && darkMix < 0.9 && sin(clock * 37) > 0.4 ? 0.4 : 1.0
            darkness.alpha = CGFloat(darkMix * stutter)
        }
        roofSprite.alpha = CGFloat(1 - 0.7 * darkMix)
    }

    // MARK: Warm-up and the title backdrop

    /// SpriteKit builds a render pipeline the first time it draws each kind of node; hidden nodes
    /// never do. Draw one of each almost invisibly for a moment while a menu is up.
    func warmRenderer() {
        let warm = SKNode()
        warm.alpha = 0.02
        warm.zPosition = -1
        warm.position = CGPoint(x: 4, y: 4)
        var nodes: [SKNode] = []
        let sprite = SKSpriteNode()
        RiftwingSprites.dress(sprite, with: glyphs.glyph(.rider(.spread), pointsPerUnit: pointsPerUnit), factory: factory)
        nodes.append(sprite)
        let tinted = SKSpriteNode()
        RiftwingSprites.dress(tinted, with: glyphs.glyph(.arrival, scale: Self.arrivalGlyphScale, pointsPerUnit: pointsPerUnit),
                              factory: factory)
        tinted.color = theme.palette.warning.uiColor()
        tinted.colorBlendFactor = 1
        nodes.append(tinted)
        let dark = SKSpriteNode(texture: Self.darknessTexture, size: CGSize(width: 4, height: 4))
        dark.blendMode = .alpha
        nodes.append(dark)
        let mask = SKSpriteNode(color: .black, size: CGSize(width: 4, height: 4))
        mask.blendMode = .replace
        nodes.append(mask)
        nodes.append(GlowText.sprite("+500", style: .item(12), color: theme.palette.reward))
        for node in nodes {
            node.setScale(0.2)
            warm.addChild(node)
        }
        root.addChild(warm)
        warm.run(.sequence([.wait(forDuration: 0.5), .removeFromParent()]))
    }

    /// A few rigs gliding through the empty gallery behind the title. Decoration only.
    func buildDecor() {
        for item in decor { item.sprite.removeFromParent() }
        decor = []
        let cast: [(RiftwingShape, Double, Double, Double)] = [
            (.rider(.spread), 0, 70, 360), (.opponent(.glider, .spread), 2.0, -45, 470),
            (.opponent(.striker, .raised), 4.1, 60, 210), (.opponent(.gleaner, .raised), 1.3, -35, 300),
            (.pod, 5.2, 0, 0),
        ]
        for (thing, phase, speed, height) in cast {
            let sprite = SKSpriteNode()
            RiftwingSprites.dress(sprite, with: glyphs.glyph(thing, pointsPerUnit: pointsPerUnit), factory: factory)
            sprite.alpha = 0.85
            decorLayer.addChild(sprite)
            decor.append((sprite, phase, speed, height))
        }
    }

    func updateBackdrop(_ dt: Double) {
        let layout = RiftwingCavern.layouts[0]
        for (index, sprite) in ledgeSprites.enumerated() {
            sprite.isHidden = index != 0
            sprite.alpha = 1
            sprite.position = .zero
        }
        for item in decor {
            if item.speed == 0 {
                // A pod resting on a ledge.
                let ledge = layout.ledges[2]
                item.sprite.position = CGPoint(x: ledge.midX, y: ledge.top + tuning.podRadius)
                continue
            }
            let x = (item.phase * 150 + clock * item.speed).truncatingRemainder(dividingBy: tuning.width)
            item.sprite.position = CGPoint(x: x < 0 ? x + tuning.width : x,
                                           y: item.height + 30 * sin(clock * 0.9 + item.phase))
            item.sprite.xScale = item.speed < 0 ? -1 : 1
        }
        let run = session.run
        syncMotes(run, dt: dt)
        syncRift(run)
    }
}
