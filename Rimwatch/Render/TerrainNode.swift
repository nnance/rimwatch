import Foundation
import GameCore
import SpriteKit
import UIKit

/// The ground and the outposts. Lives inside the world layer, whose x origin is the camera and
/// whose units are world units.
///
/// The heightmap is pre-rendered into a ring of tiles once per display scale. Each frame the tiles
/// and outposts are placed by their wrap-aware offset from the camera, so the seam is invisible.
@MainActor
final class TerrainNode: SKNode {
    static let tileWidth = 600.0
    /// Ground lines are sampled this often, in world units.
    private static let sampleStep = 4.0

    private let world: World
    private let factory: GlowShapeFactory
    private var theme: any Theme { factory.theme }

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

    init(world: World, factory: GlowShapeFactory) {
        self.world = world
        self.factory = factory
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

    /// Re-renders everything for a new display scale.
    func rebuild(pointsPerUnit: CGFloat, screenScale: CGFloat) {
        self.pointsPerUnit = pointsPerUnit
        (tiles + blackoutTiles).forEach { $0.removeFromParent() }
        tiles = []
        blackoutTiles = []

        var maxGround = 0.0
        for x in stride(from: 0.0, to: world.width, by: Self.sampleStep) {
            maxGround = max(maxGround, world.groundHeight(at: x))
        }
        let tileHeight = maxGround + 24
        let count = Int((world.width / Self.tileWidth).rounded(.up))
        for index in 0..<count {
            let x0 = Double(index) * Self.tileWidth
            let width = min(Self.tileWidth, world.width - x0)
            let sprite = SKSpriteNode(texture: renderTile(from: x0, width: width, height: tileHeight,
                                                          screenScale: min(screenScale, 2)))
            sprite.size = CGSize(width: width, height: tileHeight)
            sprite.anchorPoint = .zero
            sprite.blendMode = .add
            sprite.userData = ["x0": x0, "width": width]
            groundLayer.addChild(sprite)
            tiles.append(sprite)

            let dark = SKSpriteNode(texture: renderTile(from: x0, width: width, height: tileHeight,
                                                        screenScale: 1, blackout: true))
            dark.size = sprite.size
            dark.anchorPoint = .zero
            dark.blendMode = .add
            dark.userData = sprite.userData
            blackoutLayer.addChild(dark)
            blackoutTiles.append(dark)
        }

        let integrityWidth = 40.0
        for node in outposts {
            factory.apply(factory.glyph(for: .outpost, pointsPerUnit: pointsPerUnit), to: node.dome)
            factory.apply(factory.glyph(for: .ruin, pointsPerUnit: pointsPerUnit), to: node.ruin)
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
    func update(cameraX: Double, halfWidth: Double, integrity: [Double], isBlackout: Bool, time: TimeInterval) {
        groundLayer.isHidden = isBlackout
        blackoutLayer.isHidden = !isBlackout
        for tile in isBlackout ? blackoutTiles : tiles {
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
            node.alpha = isBlackout ? 0.4 : 1
        }
    }

    private func renderTile(from x0: Double, width: Double, height: Double, screenScale: CGFloat,
                            blackout: Bool = false) -> SKTexture {
        let ppu = pointsPerUnit
        let size = CGSize(width: width * ppu, height: height * ppu)
        let style = theme.terrain
        // Sample a little past each edge so a halo crosses tile joins without a seam.
        let overlap = 24.0
        let xs = Array(stride(from: -overlap, through: width + overlap, by: Self.sampleStep))
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
        return SKTexture(image: image)
    }
}
