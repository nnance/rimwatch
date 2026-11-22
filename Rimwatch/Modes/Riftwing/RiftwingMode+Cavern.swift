import Foundation
import GameCore
import RiftwingCore
import SpriteKit
import UIKit

// Riftwing's cavern: the roof, the tunnel mouths, the ledges of each layout, the Rift and its
// breath, the vents' motes, the lamps-out darkness, the sprite pools and the title backdrop.

extension RiftwingMode {
    /// Depths inside the gallery layer (which sits at z 10; the HUD is at 80). The darkness covers
    /// the rock and resting pods but not what gives light (the Rift's edge, a pod about to hatch,
    /// the rider, the gas and the glows in the tunnel mouths) nor what can hurt: opponents and
    /// mines are drawn over it, faint outside the pool of light (`darkVisibility`), so nothing
    /// that takes a life in the dark is unseen.
    enum Depth {
        static let roof: CGFloat = 0
        static let ledges: CGFloat = 1
        static let ventColumn: CGFloat = 1.4
        static let motes: CGFloat = 1.5
        static let riftGlow: CGFloat = 2
        static let riftSpot: CGFloat = 2.05
        static let breathGlow: CGFloat = 5.25
        static let link: CGFloat = 3
        static let mine: CGFloat = 5.35
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
        case .glider: 5.4
        case .striker: 5.41
        case .warden: 5.42
        case .sower: 5.43
        case .gleaner: 5.44
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
            (gasTop, Depth.gasTop), (breathMark, Depth.breathMark), (darkness, Depth.darkness),
            (darknessTwin, Depth.darkness), (mouthSprite, Depth.mouths), (breathGlow, Depth.breathGlow),
        ]
        for (sprite, depth) in placed {
            sprite.zPosition = depth
            galleryLayer.addChild(sprite)
        }
        gasSprite.isHidden = true
        gasTop.isHidden = true
        breathMark.isHidden = true
        for sheet in [darkness, darknessTwin] {
            sheet.isHidden = true
            sheet.blendMode = .alpha
        }
        breathGlow.isHidden = true
        breathGlow.blendMode = .add
        breathGlow.colorBlendFactor = 0
        gasSprite.colorBlendFactor = 0
        riftSpots = (0..<5).map { _ in
            let spot = SKSpriteNode(texture: RiftwingEffects.glowTexture, size: CGSize(width: 2, height: 2))
            spot.blendMode = .add
            spot.colorBlendFactor = 1
            spot.color = theme.palette.rift.lightened(0.15).uiColor()
            spot.zPosition = Depth.riftSpot
            galleryLayer.addChild(spot)
            return spot
        }
        fillBars = (0..<2).map { _ in
            let bar = SKSpriteNode(color: theme.palette.warning.uiColor(), size: CGSize(width: 1, height: 1))
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.blendMode = .add
            bar.zPosition = Depth.breathMark
            bar.isHidden = true
            galleryLayer.addChild(bar)
            return bar
        }
        ventColumns = (0..<3).map { _ in
            let column = SKSpriteNode()
            column.anchorPoint = CGPoint(x: 0.5, y: 0)
            column.blendMode = .add
            column.zPosition = Depth.ventColumn
            column.isHidden = true
            galleryLayer.addChild(column)
            return column
        }
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
        for layout in RiftwingCavern.layouts {
            ledgeSprites.append(layout.ledges.map { _ in
                let sprite = SKSpriteNode()
                sprite.zPosition = Depth.ledges
                sprite.isHidden = true
                galleryLayer.addChild(sprite)
                return sprite
            })
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
            for (n, ledge) in layout.ledges.enumerated() {
                let sprite = ledgeSprites[index][n]
                RiftwingSprites.dress(sprite, with: glyphs.glyph(key: "ledge-\(index)-\(n)",
                                                                 strokes: ledgeStrokes(ledge, number: n), pointsPerUnit: ppu),
                                      factory: factory)
                sprite.position = .zero
            }
        }

        // The Rift: a hot glow rising from the bottom, and a ragged fissure along its edge.
        riftGlow.texture = Self.gradientTexture(palette.rift, bottom: 0.55, top: 0)
        riftGlow.anchorPoint = .zero
        riftGlow.size = CGSize(width: w, height: 80)
        riftGlow.position = .zero
        // The breath gathering: a sickly glow that climbs out of the Rift while it warns.
        breathGlow.texture = Self.gradientTexture(palette.gas, bottom: 0.6, top: 0.04)
        breathGlow.anchorPoint = .zero
        breathGlow.size = CGSize(width: w, height: 1)
        breathGlow.position = .zero
        let column = Self.columnTexture(palette.vent)
        for sprite in ventColumns { sprite.texture = column }
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

        // The darkness: two tiles, each a gallery wide, black but for a soft pool of light at its
        // centre, and tall enough to cover the gallery from anywhere the rider can be.
        for sheet in [darkness, darknessTwin] {
            sheet.texture = Self.darknessTexture
            sheet.size = Self.darknessSize
        }

        let mote = glyphs.glyph(key: "mote", strokes: [ShapeStroke([Vec2(0, -2.5), Vec2(0, 2.5)], color: palette.vent)],
                                pointsPerUnit: ppu)
        for sprite in moteSprites { RiftwingSprites.dress(sprite, with: mote, factory: factory) }
    }

    /// A ledge as rock in outline: a flat bright top (the standing surface), the ends rounding
    /// down to a ragged underside at the ledge's thickness, a few faint strata marks in the slab
    /// and short faint teeth hanging below. `number` varies the marks from ledge to ledge.
    func ledgeStrokes(_ ledge: RiftwingLedge, number n: Int) -> [ShapeStroke] {
        let palette = theme.palette
        let t = tuning.ledgeThickness
        var strokes: [ShapeStroke] = []
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
        return strokes
    }

    /// A vent's column of rising air: faint, brightest at its foot and along its middle, fading
    /// out to its sides and its top, so it reads as air, not a box.
    static func columnTexture(_ color: RGB) -> SKTexture {
        let size = CGSize(width: 32, height: 128)
        let image = GlowShapeFactory.image(size: size, scale: 1) { context in
            let space = CGColorSpaceCreateDeviceRGB()
            let across = CGGradient(colorsSpace: space, colors: [color.cgColor(alpha: 0), color.cgColor(alpha: 0.11),
                                                                 color.cgColor(alpha: 0)] as CFArray,
                                    locations: [0, 0.5, 1])!
            context.drawLinearGradient(across, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
            // Fade toward the top (image space is y down).
            context.setBlendMode(.destinationIn)
            let up = CGGradient(colorsSpace: space, colors: [UIColor(white: 1, alpha: 1).cgColor,
                                                             UIColor(white: 1, alpha: 0).cgColor] as CFArray,
                                locations: [0, 1])!
            context.drawLinearGradient(up, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
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

    /// One darkness tile in gallery units: a gallery wide (two side by side tile the gallery's
    /// width exactly) and tall enough to cover it from any height.
    static let darknessSize = CGSize(width: 900, height: 1400)
    /// The pool of light: fully lit out to `litRadius` units from the rider, dark from
    /// `darkRadius`. (The first version was lit to 70 and dark from 160.)
    static let litRadius = 115.0
    static let darkRadius = 250.0

    /// Black with a clear soft hole in the middle (see `darknessSize`, `litRadius`).
    static let darknessTexture: SKTexture = {
        let k: CGFloat = 0.5
        let size = CGSize(width: darknessSize.width * k, height: darknessSize.height * k)
        let image = GlowShapeFactory.image(size: size, scale: 1) { context in
            let space = CGColorSpaceCreateDeviceRGB()
            let edge = CGFloat(litRadius / darkRadius)
            let colors = [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0).cgColor,
                          UIColor(white: 0, alpha: 0.4).cgColor, UIColor(white: 0, alpha: 0.93).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, edge, (edge + 1) / 2, 1])!
            context.setFillColor(UIColor(white: 0, alpha: 0.93).cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            context.setBlendMode(.copy)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            context.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c,
                                       endRadius: CGFloat(darkRadius) * k, options: [])
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }()

    /// How visible something at `p` is with the lamps out, 0 to 1: fully in the pool of light,
    /// and outside it never below a faint outline that glints now and then (`seed` staggers the
    /// glints), so a threat in the dark can always be seen. 1 with the lamps lit.
    func darkVisibility(at p: Vec2, seed: Int) -> CGFloat {
        guard darkMix > 0 else { return 1 }
        let dx = abs(session.run.dxWrap(lightCentre.x, p.x)), dy = p.y - lightCentre.y
        let d = (dx * dx + dy * dy).squareRoot()
        let lit = min(max((Self.darkRadius - d) / (Self.darkRadius - Self.litRadius), 0), 1)
        let glint = pow(max(sin(clock * 1.7 + Double(seed) * 2.3), 0), 12)
        let seen = max(lit * lit * (3 - 2 * lit), 0.32 + 0.4 * glint)
        return CGFloat(1 - darkMix * (1 - seen))
    }

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
        darknessTwin.isHidden = true
        breathGlow.isHidden = true
        for bar in fillBars { bar.isHidden = true }
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

    /// The current layout's ledges. While the cavern rumbles toward its next layout the rock
    /// trembles and sheds pebbles; when the new layout arrives the old ledges crack, crumble and
    /// fall away one after another, and the new ones rise into place from below in a cloud of
    /// dust, so the change is seen rather than cross-faded.
    func syncLedges(_ run: RiftwingRun, dt: Double) {
        let current = run.layoutIndex
        if shownLayout >= 0, current != shownLayout {
            fallingLayout = shownLayout
            layoutArrivedAt = clock
            crumble(RiftwingCavern.layouts[shownLayout], rising: RiftwingCavern.layouts[current])
        }
        shownLayout = current
        let t = clock - layoutArrivedAt
        let lampsDim = 1 - 0.5 * CGFloat(darkMix)
        for (index, sprites) in ledgeSprites.enumerated() {
            for (n, sprite) in sprites.enumerated() {
                var alpha: CGFloat = 0
                var offset = CGPoint.zero
                if index == current {
                    // Rising into place: each ledge a little after the one before.
                    let local = (t - 0.15 - 0.09 * Double(n)) / 0.5
                    if local >= 1 {
                        alpha = 1
                    } else if local > 0 {
                        let eased = 1 - (1 - local) * (1 - local) * (1 - local)
                        alpha = CGFloat(min(local * 2, 1))
                        offset.y = CGFloat(-46 * (1 - eased))
                    }
                    if isShifting, dt > 0 {
                        alpha *= sin(clock * 31 + Double(n)) > -0.3 ? 1 : 0.55
                        offset.x += CGFloat.random(in: -1.5...1.5)
                        offset.y += CGFloat.random(in: -1.5...1.5)
                    }
                } else if index == fallingLayout {
                    // Crumbling: a tremble, then the ledge drops and fades as it falls.
                    let local = t - 0.07 * Double(n)
                    if local < 0.12 {
                        alpha = 1
                        offset.x = CGFloat(sin(clock * 90 + Double(n)) * 1.6)
                    } else if local < 0.85 {
                        let fall = local - 0.12
                        alpha = CGFloat(1 - fall / 0.73)
                        offset.y = CGFloat(-0.5 * 520 * fall * fall)
                        offset.x = CGFloat(sin(clock * 70 + Double(n)) * 1.2)
                    }
                }
                sprite.isHidden = alpha <= 0.005
                sprite.alpha = alpha * lampsDim
                sprite.position = offset
            }
        }
        if fallingLayout >= 0, t > 2 { fallingLayout = -1 }
        // Pebbles falling from the trembling rock.
        if isShifting, dt > 0 {
            pebbleDue -= dt
            if pebbleDue <= 0 {
                pebbleDue = 0.07
                let ledges = RiftwingCavern.layouts[current].ledges
                let ledge = ledges[Int.random(in: 0..<ledges.count)]
                let x = Double.random(in: (ledge.minX + 6)...(ledge.maxX - 6))
                effects.spray(at: Vec2(x, ledge.top - tuning.ledgeThickness), angle: -Double.pi / 2, spread: 0.2,
                              color: theme.palette.rock, count: 1, speed: 70, life: 0.7, size: 0.8, drag: 0.3, gravity: 380)
            }
        }
    }

    /// The cavern has shifted: rubble from every old ledge, dust where each new one rises.
    private func crumble(_ old: RiftwingLayout, rising new: RiftwingLayout) {
        let rock = theme.palette.rock
        for ledge in old.ledges {
            var x = ledge.minX + 8
            while x < ledge.maxX - 4 {
                effects.spray(at: Vec2(x, ledge.top - tuning.ledgeThickness * 0.5), angle: -Double.pi / 2, spread: 0.9,
                              color: rock, count: 2, speed: 80, life: 0.9, size: 1.3, length: 1.6, drag: 0.5, gravity: 420)
                x += 26
            }
        }
        for ledge in new.ledges {
            var x = ledge.minX + 10
            while x < ledge.maxX - 6 {
                effects.spray(at: Vec2(x, ledge.top), angle: Double.pi / 2, spread: 1.2, color: rock.lightened(0.2),
                              count: 1, speed: 45, life: 0.8, size: 0.8, drag: 2)
                x += 34
            }
        }
    }

    /// Motes rise through each vent's column, fading near the height it lifts to, over a faint
    /// column of light that shows the vent's reach.
    func syncMotes(_ vents: [RiftwingVent], dt: Double) {
        let half = tuning.ventHalfWidth
        let base = tuning.riftLevel
        let dim = 1 - 0.6 * CGFloat(darkMix)
        var i = 0
        for (v, vent) in vents.enumerated() {
            let height = max(vent.top - base, 1)
            if v < ventColumns.count {
                let column = ventColumns[v]
                column.isHidden = false
                column.position = CGPoint(x: vent.x, y: base)
                column.size = CGSize(width: half * 2.6, height: height + 30)
                column.alpha = CGFloat(0.8 + 0.2 * sin(clock * 1.3 + Double(v))) * dim
            }
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
                sprite.alpha = CGFloat(0.7 * fade) * dim
                i += 1
            }
        }
        while i < moteSprites.count {
            moteSprites[i].isHidden = true
            i += 1
        }
        for v in min(vents.count, ventColumns.count)..<ventColumns.count { ventColumns[v].isHidden = true }
    }

    /// What the Rift shows: a calm Rift (`.calm`, as behind the title), or a run's breath.
    struct RiftState {
        var warning = false
        /// The breath's last step: the gas will fill the whole gallery.
        var filling = false
        /// 0 at the warning's start to 1 as the gas rises.
        var warningProgress = 0.0
        var breathLevel = 0.0
        var gasLevel = 0.0
        var deadly = false

        static let calm = RiftState()

        init() {}

        init(_ run: RiftwingRun, tuning: RiftwingTuning) {
            filling = run.isBreathFilling
            if case .warning(let remaining) = run.breath {
                warning = true
                let whole = filling ? tuning.breathFillWarning : tuning.breathWarning
                warningProgress = min(max(1 - remaining / max(whole, 0.01), 0), 1)
            }
            breathLevel = run.breathLevel
            gasLevel = run.gasLevel
            deadly = run.isBreathDeadly
        }
    }

    /// The Rift lives: its glow flickers and hot spots drift along it. Before it breathes it reads
    /// as dangerous: it pulses, a sickly glow climbs out of it toward the mark (which blinks where
    /// the gas will reach) and wisps of gas rise; then the gas rises, holds and sinks. The last
    /// step, which fills the gallery, is worse in every way: the glow climbs all the way to the
    /// roof and burns red, the mark blinks red along the roof itself, red bars pulse up both
    /// sides of the gallery, the wisps come thick and fast, and the gas itself is a darker,
    /// redder poison.
    func syncRift(_ state: RiftState, dt: Double) {
        let warning = state.warning
        let filling = state.filling
        let flicker = 0.75 + 0.12 * sin(clock * 3.1) + 0.08 * sin(clock * 7.7)
        let beat = filling ? 14.0 : 9.0
        riftGlow.alpha = CGFloat(warning ? flicker + 0.35 * abs(sin(clock * beat)) : flicker)
        riftGlow.yScale = warning ? CGFloat((filling ? 1.9 : 1.4) + 0.3 * sin(clock * beat)) : CGFloat(1 + 0.08 * sin(clock * 1.1))
        riftLine.alpha = CGFloat(0.8 + 0.2 * sin(clock * 5))
        for (i, spot) in riftSpots.enumerated() {
            let phase = Double(i) * 1.7
            let x = (Double(i) * 190 + 40 * sin(clock * 0.23 + phase) + clock * (i.isMultiple(of: 2) ? 9 : -7))
                .truncatingRemainder(dividingBy: tuning.width)
            spot.position = CGPoint(x: x < 0 ? x + tuning.width : x, y: tuning.riftLevel - 6)
            let size = 70 + 25 * sin(clock * 0.9 + phase)
            spot.size = CGSize(width: size * 1.8, height: size * 0.7)
            spot.alpha = CGFloat(0.22 + 0.12 * sin(clock * 2.3 + phase * 2))
        }

        let red = theme.palette.warning.uiColor()
        breathGlow.isHidden = !warning
        if warning {
            let reach = filling
                ? tuning.riftLevel + (tuning.height - tuning.riftLevel) * (0.3 + 0.7 * state.warningProgress)
                : tuning.riftLevel + (state.breathLevel - tuning.riftLevel) * (0.25 + 0.6 * state.warningProgress)
            breathGlow.size = CGSize(width: tuning.width, height: max(reach, 1))
            breathGlow.color = red
            breathGlow.colorBlendFactor = filling ? CGFloat(0.35 + 0.25 * abs(sin(clock * beat))) : 0
            breathGlow.alpha = CGFloat((filling ? 0.5 : 0.35) + 0.35 * state.warningProgress + 0.2 * sin(clock * beat))
            if dt > 0 {
                wispDue -= dt
                let gap = filling ? 0.02 : 0.05
                while wispDue <= 0 {
                    wispDue += gap
                    let x = Double.random(in: 0...tuning.width)
                    effects.spray(at: Vec2(x, tuning.riftLevel), angle: Double.pi / 2, spread: 0.25,
                                  color: filling && Bool.random() ? theme.palette.warning : theme.palette.gas,
                                  count: 1, speed: (filling ? 110 : 50) + 60 * state.warningProgress, life: filling ? 1.6 : 1.1,
                                  size: 1.1, length: 2.2, drag: 0.6)
                }
            }
        }
        syncFillBars(show: warning && filling, progress: state.warningProgress)

        let level = state.gasLevel
        let gas = level > tuning.riftLevel + 0.5
        gasSprite.isHidden = !gas
        gasTop.isHidden = !gas
        if gas {
            gasSprite.size = CGSize(width: tuning.width, height: level)
            gasSprite.color = red
            gasSprite.colorBlendFactor = filling ? 0.45 : 0
            gasSprite.alpha = state.deadly ? 1 : 0.7
            gasTop.position = CGPoint(x: -(clock * (filling ? 90 : 40)).truncatingRemainder(dividingBy: tuning.width), y: level)
            gasTop.alpha = state.deadly ? 1 : 0.6
        }
        breathMark.isHidden = !warning
        if warning {
            // Along the roof itself for the fill, a little under it so it shows.
            breathMark.position = CGPoint(x: 0, y: filling ? tuning.height - 10 : state.breathLevel)
            breathMark.color = red
            breathMark.colorBlendFactor = filling ? 1 : 0
            breathMark.alpha = sin(clock * (filling ? 18 : 12)) > 0 ? 0.95 : 0.3
        }
    }

    /// Red bars climbing both side walls while the Rift is about to fill the gallery: the whole
    /// height is coming.
    private func syncFillBars(show: Bool, progress: Double) {
        for (side, bar) in fillBars.enumerated() {
            bar.isHidden = !show
            guard show else { continue }
            bar.position = CGPoint(x: side == 0 ? 3 : tuning.width - 3, y: tuning.riftLevel)
            let height = (tuning.height - tuning.riftLevel) * (0.35 + 0.65 * progress)
            bar.size = CGSize(width: 6, height: height)
            bar.alpha = CGFloat(0.45 + 0.4 * abs(sin(clock * 14)))
        }
    }

    /// The darkness when the lamps are out: two tiles, one centred on the pool of light (the
    /// rider, or where it was lost) and its twin a gallery's width to the side nearer the join,
    /// so the pool reaches across the join as figures do.
    func syncDarkness(_ run: RiftwingRun, dt: Double) {
        let target = run.isLampsOut ? 1.0 : 0.0
        // The lamps stutter out over about a second and come back faster.
        let rate = run.isLampsOut ? 1.6 : 2.5
        darkMix += (target - darkMix) * min(dt * rate, 1)
        if abs(darkMix - target) < 0.01 { darkMix = target }
        if run.rider.isAlive { lightCentre = run.rider.pos }
        let shown = darkMix > 0
        darkness.isHidden = !shown
        darknessTwin.isHidden = !shown
        if shown {
            let lit = lightCentre
            darkness.position = CGPoint(x: lit.x, y: lit.y)
            let side = lit.x < tuning.width / 2 ? 1.0 : -1.0
            darknessTwin.position = CGPoint(x: lit.x + side * tuning.width, y: lit.y)
            let stutter = run.isLampsOut && darkMix < 0.9 && sin(clock * 37) > 0.4 ? 0.4 : 1.0
            darkness.alpha = CGFloat(darkMix * stutter)
            darknessTwin.alpha = darkness.alpha
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
        let dark = SKSpriteNode(texture: Self.darknessTexture, size: CGSize(width: 4, height: 6))
        dark.blendMode = .alpha
        nodes.append(dark)
        let mask = SKSpriteNode(color: .black, size: CGSize(width: 4, height: 4))
        mask.blendMode = .replace
        nodes.append(mask)
        nodes.append(GlowText.sprite("+500", style: .item(12), color: theme.palette.reward))
        // A ring (a shape node) and a tinted additive gradient (the breath's glow, the gas).
        let ring = SKShapeNode(circleOfRadius: 6)
        ring.strokeColor = .white
        ring.blendMode = .add
        nodes.append(ring)
        let tintedGlow = SKSpriteNode(texture: Self.gradientTexture(theme.palette.gas, bottom: 0.5, top: 0), size: CGSize(width: 4, height: 4))
        tintedGlow.blendMode = .add
        tintedGlow.color = theme.palette.warning.uiColor()
        tintedGlow.colorBlendFactor = 0.5
        nodes.append(tintedGlow)
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

    /// The title's backdrop: always the same clean cavern (the first layout, its vents, a calm
    /// Rift, the lamps lit), whatever state the last run ended in.
    func updateBackdrop(_ dt: Double) {
        let layout = RiftwingCavern.layouts[0]
        for (index, sprites) in ledgeSprites.enumerated() {
            for sprite in sprites {
                sprite.isHidden = index != 0
                sprite.alpha = 1
                sprite.position = .zero
            }
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
        // Nothing of the last run: no darkness, no gas, no shake, the roof at full strength.
        darkMix = 0
        darkness.isHidden = true
        darknessTwin.isHidden = true
        roofSprite.alpha = 1
        shake = 0
        isShifting = false
        fallingLayout = -1
        galleryLayer.position = galleryOrigin
        syncMotes(layout.vents, dt: dt)
        syncRift(.calm, dt: 0)
    }
}
