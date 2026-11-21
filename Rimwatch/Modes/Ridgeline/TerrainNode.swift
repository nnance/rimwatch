import Foundation
import GameCore
import RidgelineCore
import SpriteKit
import UIKit

/// The ground and the outposts. Lives inside the world layer, whose x origin is the camera and
/// whose units are world units.
///
/// The heightmap is pre-rendered into a ring of tiles once per display scale. Each frame the tiles
/// and outposts are placed by their wrap-aware offset from the camera, so the seam is invisible.
@MainActor
final class TerrainNode: SKNode {

    private let world: World
    private let glyphs: RidgelineGlyphs
    private var factory: GlowShapeFactory { glyphs.factory }
    private var theme: any Theme { glyphs.theme }

    private var tiles: [SKSpriteNode] = []
    /// The same ground drawn as a single dim ridge in the theme's Blackout colour, at half
    /// resolution (it is dark and soft). Shown instead of `tiles` during a Blackout.
    private var blackoutTiles: [SKSpriteNode] = []
    private let groundLayer = SKNode()
    private let blackoutLayer = SKNode()
    private var outposts: [OutpostNode] = []
    private var pointsPerUnit: CGFloat = 0

    private final class OutpostNode: SKNode {
        let dome = SKSpriteNode()
        let ruin = SKSpriteNode()
        let integrityBar = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))
        let integrityFrame = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))
    }

    init(world: World, glyphs: RidgelineGlyphs) {
        self.world = world
        self.glyphs = glyphs
        super.init()
        addChild(groundLayer)
        addChild(blackoutLayer)
        blackoutLayer.isHidden = true
        for _ in world.outposts {
            let node = OutpostNode()
            node.addChild(node.dome)
            node.addChild(node.ruin)
            for bar in [node.integrityFrame, node.integrityBar] {
                bar.anchorPoint = CGPoint(x: 0, y: 0.5)
                bar.blendMode = .add
                node.addChild(bar)
            }
            outposts.append(node)
            addChild(node)
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    /// Re-renders everything for a new display scale. `prepared` is ground art already made in
    /// the background for this world and scale; without it the tiles are drawn here, which
    /// takes several frames' worth of time.
    func rebuild(pointsPerUnit: CGFloat, screenScale: CGFloat, prepared: PreparedTerrain? = nil) {
        self.pointsPerUnit = pointsPerUnit
        (tiles + blackoutTiles).forEach { $0.removeFromParent() }
        tiles = []
        blackoutTiles = []

        let art = prepared.flatMap { $0.pointsPerUnit == pointsPerUnit ? $0 : nil }
            ?? PreparedTerrain(TerrainArt.render(world: world, style: theme.terrain, pointsPerUnit: pointsPerUnit,
                                                 screenScale: screenScale))
        for index in art.lit.indices {
            let x0 = Double(index) * TerrainArt.tileWidth
            let width = min(TerrainArt.tileWidth, world.width - x0)
            let sprite = SKSpriteNode(texture: art.lit[index])
            sprite.size = CGSize(width: width, height: art.tileHeight)
            sprite.anchorPoint = .zero
            sprite.blendMode = .add
            sprite.userData = ["x0": x0, "width": width]
            groundLayer.addChild(sprite)
            tiles.append(sprite)

            let dark = SKSpriteNode(texture: art.dark[index])
            dark.size = sprite.size
            dark.anchorPoint = .zero
            dark.blendMode = .add
            dark.userData = sprite.userData
            blackoutLayer.addChild(dark)
            blackoutTiles.append(dark)
        }

        let integrityWidth = 40.0
        for node in outposts {
            factory.apply(glyphs.glyph(for: .outpost, pointsPerUnit: pointsPerUnit), to: node.dome)
            factory.apply(glyphs.glyph(for: .ruin, pointsPerUnit: pointsPerUnit), to: node.ruin)
            let barHeight = 3 / pointsPerUnit
            node.integrityFrame.size = CGSize(width: integrityWidth, height: barHeight)
            node.integrityFrame.position = CGPoint(x: -integrityWidth / 2, y: 22)
            node.integrityFrame.color = theme.palette.warning.uiColor()
            node.integrityFrame.alpha = 0.2
            node.integrityBar.size = CGSize(width: integrityWidth, height: barHeight)
            node.integrityBar.position = node.integrityFrame.position
            node.integrityBar.color = theme.palette.warning.uiColor()
        }
    }

    /// Places tiles and outposts around the camera and shows outpost damage.
    /// `blackout` runs from 0 (lit) to 1 (Blackout); in between, the two looks cross-fade.
    func update(cameraX: Double, halfWidth: Double, integrity: [Double], blackout: Double, time: TimeInterval) {
        let mix = CGFloat(min(max(blackout, 0), 1))
        groundLayer.isHidden = mix >= 1
        blackoutLayer.isHidden = mix <= 0
        groundLayer.alpha = 1 - mix
        blackoutLayer.alpha = mix
        let shown = (mix < 1 ? tiles : []) + (mix > 0 ? blackoutTiles : [])
        for tile in shown {
            guard let x0 = tile.userData?["x0"] as? Double, let width = tile.userData?["width"] as? Double
            else { continue }
            let left = world.delta(from: cameraX, to: x0 + width / 2) - width / 2
            let visible = left < halfWidth + 20 && left + width > -halfWidth - 20
            tile.isHidden = !visible
            if visible { tile.position = CGPoint(x: left, y: 0) }
        }

        for (id, node) in outposts.enumerated() {
            let outpost = world.outposts[id]
            let dx = world.delta(from: cameraX, to: outpost.x)
            node.isHidden = abs(dx) > halfWidth + 80
            node.position = CGPoint(x: dx, y: outpost.groundY)
            let health = id < integrity.count ? integrity[id] : 1
            let standing = health > 0
            node.dome.isHidden = !standing
            node.ruin.isHidden = standing
            let damaged = standing && health < 0.999
            node.integrityBar.isHidden = !damaged
            node.integrityFrame.isHidden = !damaged
            node.integrityBar.xScale = CGFloat(max(health, 0.02))
            // A dome under the drill flickers.
            node.dome.alpha = damaged ? 0.6 + 0.4 * CGFloat(abs(sin(time * 9))) : 1
            node.alpha = 1 - 0.6 * mix
        }
    }
}

/// The ground drawn into images, one lit and one Blackout image per tile. Pure drawing with no
/// main-thread state, so the next run's ground can be made in the background.
nonisolated struct TerrainArt: @unchecked Sendable {
    static let tileWidth = 600.0
    /// Ground lines are sampled this often, in world units.
    static let sampleStep = 4.0

    let pointsPerUnit: CGFloat
    let tileHeight: Double
    let lit: [UIImage]
    let dark: [UIImage]

    static func render(world: World, style: TerrainStyle, pointsPerUnit: CGFloat, screenScale: CGFloat) -> TerrainArt {
        var maxGround = 0.0
        for x in stride(from: 0.0, to: world.width, by: sampleStep) {
            maxGround = max(maxGround, world.groundHeight(at: x))
        }
        let tileHeight = maxGround + 24
        let count = Int((world.width / tileWidth).rounded(.up))
        var lit: [UIImage] = []
        var dark: [UIImage] = []
        for index in 0..<count {
            let x0 = Double(index) * tileWidth
            let width = min(tileWidth, world.width - x0)
            lit.append(tile(world: world, style: style, from: x0, width: width, height: tileHeight,
                            pointsPerUnit: pointsPerUnit, screenScale: min(screenScale, 2), blackout: false))
            // Dark and soft, so half resolution is plenty.
            dark.append(tile(world: world, style: style, from: x0, width: width, height: tileHeight,
                             pointsPerUnit: pointsPerUnit, screenScale: 1, blackout: true))
        }
        return TerrainArt(pointsPerUnit: pointsPerUnit, tileHeight: tileHeight, lit: lit, dark: dark)
    }

    static func tile(world: World, style: TerrainStyle, from x0: Double, width: Double, height: Double,
                     pointsPerUnit ppu: CGFloat, screenScale: CGFloat, blackout: Bool) -> UIImage {
        let size = CGSize(width: width * ppu, height: height * ppu)
        // Sample a little past each edge so a halo crosses tile joins without a seam.
        let overlap = 24.0
        let xs = Array(stride(from: -overlap, through: width + overlap, by: sampleStep))
        let heights = xs.map { world.groundHeight(at: world.wrap(x0 + $0)) }

        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: x * ppu, y: size.height - y * ppu)
        }

        let image = GlowShapeFactory.image(size: size, scale: screenScale) { context in
            if blackout {
                // Lights out: only the ridge remains, in the theme's dark Blackout colour.
                let ridge = CGMutablePath()
                ridge.addLines(between: zip(xs, heights).map { point($0, $1) })
                // No white core here: the point is that the ground has gone dark.
                context.setLineJoin(.round)
                context.setLineCap(.round)
                context.setShadow(offset: .zero, blur: 6, color: style.blackoutRidge.cgColor())
                context.setStrokeColor(style.blackoutRidge.lightened(0.15).cgColor())
                context.setLineWidth(1.6)
                context.addPath(ridge)
                context.strokePath()
                return
            }
            // A faint wash below the ridge gives the ground some body.
            let fill = CGMutablePath()
            fill.move(to: point(xs[0], 0))
            for (x, h) in zip(xs, heights) { fill.addLine(to: point(x, h)) }
            fill.addLine(to: point(xs[xs.count - 1], 0))
            fill.closeSubpath()
            context.addPath(fill)
            context.setFillColor(style.strata.cgColor(alpha: 0.12))
            context.fillPath()

            for (index, offset) in style.strataOffsets.enumerated() {
                let path = CGMutablePath()
                path.addLines(between: zip(xs, heights).map { point($0, max($1 - offset, 2)) })
                GlowShapeFactory.strokeGlow(path, color: style.strata,
                                            strength: 0.7 / Double(index + 1), in: context)
            }

            let ridge = CGMutablePath()
            ridge.addLines(between: zip(xs, heights).map { point($0, $1) })
            GlowShapeFactory.strokeGlow(ridge, color: style.ridge, in: context)
        }
        return image
    }
}

/// Ground art turned into textures, ready to hand to a TerrainNode. Made in the background for
/// the next run (texture creation and upload happen there too); only handed over on the main
/// thread.
nonisolated final class PreparedTerrain: @unchecked Sendable {
    let pointsPerUnit: CGFloat
    let tileHeight: Double
    let lit: [SKTexture]
    let dark: [SKTexture]

    init(_ art: TerrainArt) {
        pointsPerUnit = art.pointsPerUnit
        tileHeight = art.tileHeight
        lit = art.lit.map { SKTexture(cgImage: $0.cgImage!) }
        dark = art.dark.map { SKTexture(cgImage: $0.cgImage!) }
    }

    /// Uploads the textures ahead of first use, so the first frame that draws them doesn't wait.
    /// Calls back when done, on an arbitrary thread.
    func preload(_ done: @escaping @Sendable () -> Void) {
        SKTexture.preload(lit + dark, withCompletionHandler: done)
    }
}
