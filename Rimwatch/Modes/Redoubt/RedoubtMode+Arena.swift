import Foundation
import GameCore
import RedoubtCore
import SpriteKit
import UIKit

// Redoubt's floor, walls, airlock, the power cut's darkness, the sprite pools and the title
// backdrop.

extension RedoubtMode {
    /// Depths inside the arena layer. Burrows lie on the floor; the darkness covers the floor and
    /// enemies but not what gives light (shots, the orb, colonists, arrival markers, the airlock).
    enum Depth {
        static let floor: CGFloat = 0
        static let burrow: CGFloat = 2
        static let darkness: CGFloat = 6
        static let arrival: CGFloat = 6.4
        static let link: CGFloat = 6.45
        static let colonist: CGFloat = 6.5
        static let wall: CGFloat = 6.6
        static let airlockMask: CGFloat = 6.61
        static let airlock: CGFloat = 6.62
        static let enemyShot: CGFloat = 7
        static let orbShot: CGFloat = 7.1
        static let respawn: CGFloat = 7.9
        static let orb: CGFloat = 8
        static let effects: CGFloat = 9
    }

    /// Each enemy role at its own depth, so sprites sharing a texture draw in one batch.
    static func depth(of role: RedoubtRole) -> CGFloat {
        switch role {
        case .burrow: Depth.burrow
        case .skitter: 4
        case .gleaner: 4.1
        case .spitter: 4.2
        case .husk: 4.3
        case .thresher: 4.4
        }
    }

    /// A Spitter about to fire: white hot, so it can't be taken for a Thresher's crimson.
    var windUpColor: RGB { RGB(hex: 0xF4E8FF) }

    func buildNodes() {
        arenaLayer.zPosition = 10
        hud.zPosition = 80
        controls.zPosition = 100
        callouts.zPosition = 105
        root.addChild(arenaLayer)
        for node in [hud, controls, callouts] as [SKNode] {
            node.isHidden = true
            root.addChild(node)
        }
        floorSprite.zPosition = Depth.floor
        wallSprite.zPosition = Depth.wall
        airlockMask.zPosition = Depth.airlockMask
        airlockMask.blendMode = .alpha
        airlockSprite.zPosition = Depth.airlock
        beacon.zPosition = Depth.airlock
        beacon.isHidden = true
        darkness.zPosition = Depth.darkness
        darkness.blendMode = .alpha
        darkness.isHidden = true
        effects.zPosition = Depth.effects
        for node in [floorSprite, wallSprite, airlockMask, airlockSprite, beacon, darkness, entityLayer, decorLayer,
                     effects] as [SKNode] {
            arenaLayer.addChild(node)
        }

        func pool(_ count: Int, z: CGFloat, blend: SKBlendMode = .add) -> [PoolSprite] {
            (0..<count).map { _ in
                let sprite = PoolSprite()
                sprite.isHidden = true
                sprite.zPosition = z
                sprite.blendMode = blend
                entityLayer.addChild(sprite)
                return sprite
            }
        }
        enemySprites = pool(Self.enemyPool, z: 4)
        arrivalSprites = pool(Self.arrivalPool, z: Depth.arrival)
        for sprite in arrivalSprites { sprite.colorBlendFactor = 1 }
        shotSprites = pool(Self.shotPool, z: Depth.orbShot)
        colonistSprites = pool(Self.colonistPool, z: Depth.colonist, blend: .alpha)
        linkSprites = (0..<Self.linkPool).map { _ in
            let line = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))
            line.anchorPoint = CGPoint(x: 0, y: 0.5)
            line.blendMode = .add
            line.zPosition = Depth.link
            line.isHidden = true
            entityLayer.addChild(line)
            return line
        }
        orbSprite.zPosition = Depth.orb
        orbSprite.isHidden = true
        entityLayer.addChild(orbSprite)
        for child in [orbHalo, orbShield, muzzle] {
            child.isHidden = true
            orbSprite.addChild(child)
        }
        orbHalo.isHidden = false
        orbHalo.alpha = 0.32
        respawnMarker.zPosition = Depth.respawn
        respawnMarker.isHidden = true
        entityLayer.addChild(respawnMarker)
    }

    /// The floor and walls for the current scale, and the darkness texture.
    func buildArena() {
        let ppu = pointsPerUnit
        let w = tuning.arenaWidth, h = tuning.arenaHeight
        let palette = theme.palette
        var floor: [ShapeStroke] = []
        // A cross every 75 units: motion reads against them without them competing with the crowd.
        let marks = palette.floor
        var x = 75.0
        while x < w {
            var y = 75.0
            while y < h {
                floor.append(ShapeStroke([Vec2(x - 4, y), Vec2(x + 4, y)], color: marks))
                floor.append(ShapeStroke([Vec2(x, y - 4), Vec2(x, y + 4)], color: marks))
                y += 75
            }
            x += 75
        }
        // The respawn pad at the centre and the line of the dome's ring beam.
        let centre = Vec2(w / 2, h / 2)
        floor.append(ShapeStroke(ShapeKit.arc(center: centre, radius: 26, segments: 32), color: marks.scaled(1.4)))
        floor.append(ShapeStroke(ShapeKit.arc(center: centre, radius: 230, segments: 96), color: marks.scaled(0.8)))
        // An inner border, so the floor's edge reads even where the wall is under a thumb.
        floor.append(ShapeStroke([Vec2(10, 10), Vec2(w - 10, 10), Vec2(w - 10, h - 10), Vec2(10, h - 10)],
                                 closed: true, color: marks))
        RedoubtSprites.dress(floorSprite, with: factory.glyph(key: "redoubt-floor", shape: ShapeDescription(scale: 1, strokes: floor),
                                    pointsPerUnit: ppu), factory: factory)
        floorSprite.position = .zero

        let wall = palette.wall
        let corner = 40.0
        var walls = [ShapeStroke([Vec2(0, 0), Vec2(w, 0), Vec2(w, h), Vec2(0, h)], closed: true, color: wall)]
        // Brighter corner pieces, so the floor's shape reads at a glance.
        for (cx, cy, sx, sy) in [(0.0, 0.0, 1.0, 1.0), (w, 0, -1, 1), (0, h, 1, -1), (w, h, -1, -1)] {
            walls.append(ShapeStroke([Vec2(cx + sx * corner, cy + sy * 5), Vec2(cx + sx * 5, cy + sy * 5),
                                      Vec2(cx + sx * 5, cy + sy * corner)], color: wall.lightened(0.25)))
        }
        RedoubtSprites.dress(wallSprite, with: factory.glyph(key: "redoubt-walls", shape: ShapeDescription(scale: 1, strokes: walls),
                                    pointsPerUnit: ppu), factory: factory)
        wallSprite.position = .zero

        RedoubtSprites.dress(beacon, with: factory.glyph(key: "redoubt-beacon", shape: ShapeDescription(scale: 36, strokes: [
            ShapeStroke(ShapeKit.arc(radius: 1, from: 0.2, to: Double.pi - 0.2, segments: 24),
                        color: theme.color(of: .colonist)),
        ]), pointsPerUnit: ppu), factory: factory)

        // The darkness: black everywhere but a soft pool of light at its centre. It is drawn big
        // enough to cover the floor from anywhere the orb can be.
        darkness.texture = Self.darknessTexture
        let span = 2 * (w + h)
        darkness.size = CGSize(width: span, height: span)
    }

    /// Black with a clear soft hole. The sprite is 3,000 units across, so the pool is fully lit
    /// out to about 70 units from the orb and dark from about 160.
    static let darknessTexture: SKTexture = {
        let side: CGFloat = 512
        let image = GlowShapeFactory.image(size: CGSize(width: side, height: side), scale: 1) { context in
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.35).cgColor,
                          UIColor(white: 0, alpha: 0.95).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.45, 1])!
            context.setFillColor(UIColor(white: 0, alpha: 0.95).cgColor)
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
        airlockLook = -1
        for sprite in enemySprites + shotSprites + colonistSprites + arrivalSprites { sprite.look = PoolSprite.undressed }
        // One white texture for every arrival; the sync colours each by role on first use.
        let arrival = glyphs.glyph(.arrival, scale: Self.arrivalGlyphScale, pointsPerUnit: pointsPerUnit)
        for sprite in arrivalSprites { RedoubtSprites.dress(sprite, with: arrival, factory: factory) }
        RedoubtSprites.dress(orbSprite, with: glyphs.glyph(.orb, pointsPerUnit: pointsPerUnit), factory: factory)
        let cyan = theme.color(of: .orb)
        RedoubtSprites.dress(orbHalo, with: factory.glyph(key: "redoubt-orb-halo", shape: ShapeDescription(scale: 21, strokes: [
            ShapeStroke(ShapeKit.arc(radius: 1, segments: 40), color: cyan.scaled(0.8)),
        ]), pointsPerUnit: pointsPerUnit), factory: factory)
        RedoubtSprites.dress(orbShield, with: factory.glyph(key: "redoubt-orb-shield", shape: ShapeDescription(scale: 16, strokes: [
            ShapeStroke(ShapeKit.arc(radius: 1, segments: 36), color: theme.palette.shield),
        ]), pointsPerUnit: pointsPerUnit), factory: factory)
        RedoubtSprites.dress(muzzle, with: factory.glyph(key: "redoubt-muzzle", shape: ShapeDescription(scale: 5, strokes: [
            ShapeStroke([Vec2(-0.6, 0.8), Vec2(1, 0), Vec2(-0.6, -0.8)], color: RGB(hex: 0xE0FFFF)),
            ShapeStroke([Vec2(-0.2, 0), Vec2(1.4, 0)], color: RGB(hex: 0xE0FFFF)),
        ]), pointsPerUnit: pointsPerUnit), factory: factory)
        muzzle.position = CGPoint(x: 18, y: 0)
        RedoubtSprites.dress(respawnMarker, with: factory.glyph(key: "redoubt-respawn", shape: ShapeDescription(scale: 24, strokes: [
            ShapeStroke(ShapeKit.arc(radius: 1, segments: 40), color: cyan),
            ShapeStroke(ShapeKit.arc(radius: 0.55, from: 0, to: Double.pi * 1.5, segments: 24), color: cyan),
        ]), pointsPerUnit: pointsPerUnit), factory: factory)
        respawnMarker.position = CGPoint(x: tuning.arenaWidth / 2, y: tuning.arenaHeight / 2)
    }

    func hideAllPooled() {
        for sprite in enemySprites { sprite.isHidden = true }
        for sprite in arrivalSprites { sprite.isHidden = true }
        for sprite in shotSprites { sprite.isHidden = true }
        for sprite in colonistSprites { sprite.isHidden = true }
        for sprite in linkSprites { sprite.isHidden = true }
        shownEnemies = 0
        shownArrivals = 0
        shownShots = 0
        shownColonists = 0
        shownLinks = 0
        orbSprite.isHidden = true
        respawnMarker.isHidden = true
        beacon.isHidden = true
        darkness.isHidden = true
    }

    /// Shows the airlock where the run says it is: open in mint with its chevrons, or shut.
    func placeAirlock(_ airlock: Airlock, lineLength: Int, dt: Double) {
        placeAirlock(wall: airlock.wall, at: airlock.pos, width: airlock.width, isOpen: airlock.isOpen,
                     lineLength: lineLength, dt: dt)
    }

    func placeAirlock(wall: ArenaWall, at center: Vec2, width: Double, isOpen: Bool, lineLength: Int, dt: Double) {
        let rotation: CGFloat = switch wall {
        case .south: 0
        case .north: .pi
        case .east: .pi / 2
        case .west: -.pi / 2
        }
        let look = isOpen ? 1 : 0
        if airlockLook != look || airlockSprite.texture == nil {
            RedoubtSprites.dress(airlockSprite, with: glyphs.glyph(isOpen ? .airlockOpen : .airlockShut, pointsPerUnit: pointsPerUnit), factory: factory)
            airlockLook = look
        }
        let pos = CGPoint(x: center.x, y: center.y)
        airlockSprite.position = pos
        airlockSprite.zRotation = rotation
        // Cut the wall line where the opening is.
        airlockMask.position = pos
        airlockMask.zRotation = rotation
        airlockMask.size = CGSize(width: width - 2, height: 9)
        airlockMask.isHidden = !isOpen
        if isOpen {
            // It breathes; with colonists in tow it pulses harder and sends out beacon arcs.
            let towing = lineLength > 0
            airlockSprite.alpha = towing ? 0.75 + 0.25 * CGFloat(sin(clock * 9)) : 0.7 + 0.2 * CGFloat(sin(clock * 3))
            beaconPhase += dt / 0.9
            if beaconPhase >= 1 { beaconPhase -= 1 }
            beacon.isHidden = !towing
            beacon.position = pos
            beacon.zRotation = rotation
            beacon.setScale(CGFloat(1 + 2.4 * beaconPhase))
            beacon.alpha = CGFloat(0.8 * (1 - beaconPhase))
        } else {
            airlockSprite.alpha = 0.6
            beacon.isHidden = true
        }
    }

    /// SpriteKit builds a render pipeline the first time it draws each kind of node; hidden nodes
    /// never do. Draw one of each almost invisibly for a moment while a menu is up.
    func warmRenderer() {
        let warm = SKNode()
        warm.alpha = 0.02
        warm.zPosition = -1
        warm.position = CGPoint(x: 4, y: 4)
        var nodes: [SKNode] = []
        for (thing, blend) in [(RedoubtShape.orb, SKBlendMode.add), (.colonist, .alpha), (.enemy(.skitter), .add)] {
            let sprite = SKSpriteNode()
            RedoubtSprites.dress(sprite, with: glyphs.glyph(thing, pointsPerUnit: pointsPerUnit), factory: factory)
            sprite.blendMode = blend
            nodes.append(sprite)
        }
        let tinted = SKSpriteNode()
        RedoubtSprites.dress(tinted, with: glyphs.glyph(.arrival, scale: Self.arrivalGlyphScale, pointsPerUnit: pointsPerUnit), factory: factory)
        tinted.blendMode = .add
        tinted.color = theme.palette.warning.uiColor()
        tinted.colorBlendFactor = 1
        nodes.append(tinted)
        let dark = SKSpriteNode(texture: Self.darknessTexture, size: CGSize(width: 4, height: 4))
        dark.blendMode = .alpha
        nodes.append(dark)
        let ring = SKShapeNode(circleOfRadius: 3)
        ring.strokeColor = theme.palette.shockwave.uiColor()
        ring.fillColor = .clear
        ring.blendMode = .add
        nodes.append(ring)
        nodes.append(GlowText.sprite("+500", style: .item(12), color: theme.palette.reward))
        for node in nodes {
            node.setScale(0.2)
            warm.addChild(node)
        }
        root.addChild(warm)
        warm.run(.sequence([.wait(forDuration: 0.5), .removeFromParent()]))
    }

    // MARK: Title backdrop

    /// A few things circling the empty floor behind the title. Decoration only.
    func buildDecor() {
        for item in decor { item.sprite.removeFromParent() }
        decor = []
        let cast: [(RedoubtShape, Double, Double, Double)] = [
            (.orb, 0, 0.5, 150), (.enemy(.skitter), 1.2, 0.35, 230), (.enemy(.skitter), 1.5, 0.35, 238),
            (.enemy(.skitter), 1.8, 0.35, 226), (.enemy(.gleaner), 3.6, 0.25, 190), (.enemy(.spitter), 4.8, 0.2, 260),
            (.enemy(.husk), 2.5, 0.45, 110), (.colonist, 5.6, 0.12, 60),
        ]
        for (thing, phase, speed, radius) in cast {
            let sprite = SKSpriteNode()
            RedoubtSprites.dress(sprite, with: glyphs.glyph(thing, pointsPerUnit: pointsPerUnit), factory: factory)
            sprite.blendMode = thing == .colonist ? .alpha : .add
            sprite.alpha = 0.8
            decorLayer.addChild(sprite)
            decor.append((sprite, phase, speed, radius))
        }
    }

    func updateBackdrop(_ dt: Double) {
        let centre = Vec2(tuning.arenaWidth / 2, tuning.arenaHeight / 2)
        for item in decor {
            let a = clock * item.speed + item.phase
            item.sprite.position = CGPoint(x: centre.x + item.radius * 1.4 * cos(a), y: centre.y + item.radius * sin(a))
            item.sprite.zRotation = CGFloat(a + .pi / 2)
        }
        placeAirlock(wall: .north, at: Vec2(tuning.arenaWidth * 0.3, tuning.arenaHeight), width: tuning.airlockWidth,
                     isOpen: true, lineLength: 0, dt: dt)
    }
}
