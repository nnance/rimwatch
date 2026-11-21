import Foundation
import GameCore
import RidgelineCore
import SpriteKit
import UIKit

/// Ridgeline plugged into the shell: keeps one node per entity in step with the simulation and
/// draws the world, scanner, HUD, callouts and touch controls for whichever screen is on.
///
/// Layout: a band across the top holds the scanner and the HUD (split either side of the crease
/// when the phone is open). The world layer's origin sits at the bottom centre of the screen and is
/// scaled so the whole world height fits below that band. Entities are placed at their wrap-aware
/// offset from the camera, so the seam needs no special casing.
@MainActor
final class RidgelineMode: GameMode {
    typealias Run = Simulation

    static let descriptor = ModeDescriptor.ridgeline
    static var shellStyle: ShellStyle { AlienFrontier().shellStyle }
    static var audio: ModeAudio {
        let theme = AlienFrontier()
        return ModeAudio(sounds: theme.allSounds, music: theme.music)
    }

    static func makeSession(seed: UInt64) -> GameSession {
        GameSession(seed: seed)
    }

    let services: ShellServices
    /// Reads the live session. Never keep a copy: it would make every step copy its arrays.
    let currentSession: () -> GameSession
    let root = SKNode()

    let theme: any Theme = AlienFrontier()
    var session: GameSession { currentSession() }
    /// The current run's world, kept so the per-entity code doesn't read it through the session
    /// closure. A run's world never changes; a new run brings a new one (see `startRun`).
    var world: World
    /// The session's tuning, which never changes, kept for the same reason.
    let tuning: Tuning
    /// Counts runs, so the scanner knows when the world (and its terrain) changed.
    var runID = 0

    let factory: GlowShapeFactory
    let glyphs: RidgelineGlyphs
    let starLayer = SKNode()
    let worldLayer = SKNode()
    var terrain: TerrainNode
    let entityLayer = SKNode()
    let linkLayer = SKNode()
    let decorLayer = SKNode()
    var effects: EffectsLayer
    let callouts: CalloutLayer
    let scanner: ScannerNode
    let hud: HUDNode
    let controls: TouchControls
    /// The input used for the last frame, for the engine exhaust.
    var lastInput = InputState()
    /// Screen shake: current strength in points, decaying. Off with Reduce Motion.
    var shake: CGFloat = 0
    /// 0 lit ... 1 Blackout, gliding so the lights go down and come back rather than switch.
    var blackoutMix = 0.0
    /// A bright line that sweeps across the playfield when a wave starts or the power returns.
    let sweep = SKSpriteNode()
    /// Covers the band above the playfield so effects never show behind the scanner and HUD.
    let bandMask = SKSpriteNode(color: .black, size: .zero)
    /// The next run's ground, drawn ahead of time, and the one being drawn now.
    var preparedTerrain: (seed: UInt64, art: PreparedTerrain)?
    /// Set when the display scale changed: glyphs and text are rendered again before play.
    var needsPrewarm = false
    var preparingTerrain: (seed: UInt64, ppu: CGFloat)?
    /// Decides calm or tension (or Blackout) from the state of play.
    var moodDirector = MusicMoodDirector()

    final class EntitySprite: SKSpriteNode {
        var role: EntityRole = .player
        var tint: RGB?
        /// Player shield ring.
        var accessory: SKSpriteNode?
        /// When the enemy was last hit, for the hit pulse.
        var hitAt: TimeInterval?
    }

    /// Lancer charge warning lines by enemy id. They live in the entity layer, not under the
    /// Lancer, so a line stays visible while the Lancer itself is off screen.
    var telegraphLines: [Int: SKSpriteNode] = [:]
    /// Thin lines between two things: a Harvester's grip on a colonist, a Sower's tether to its
    /// mines, an Anchor homing on an outpost, the tow line to carried colonists. Keyed by a
    /// string naming the pair; made when a link appears and removed when it ends.
    var links: [String: SKSpriteNode] = [:]
    /// Which Sower laid each mine (the simulation doesn't need to know; the tether shows it).
    var mineOwners: [Int: Int] = [:]
    /// Colonists being pulled in after a catch: where the catch happened and when.
    var catchBeams: [Int: (from: Vec2, at: TimeInterval)] = [:]
    /// How long a caught colonist takes to be drawn in to the ship.
    static let catchPull = 0.35
    /// Where carried colonists are drawn: trailing behind the ship, easing into place.
    var trailPositions: [Int: Vec2] = [:]
    let multiplierLabel = SKSpriteNode()
    var multiplierShown = 0
    var lastDrillSpark: [Int: TimeInterval] = [:]
    /// This frame's enemy positions by id, for links and for popups that follow an enemy.
    var enemyPositions: [Int: Vec2] = [:]
    /// Last frame's enemy velocities, so debris can keep an enemy's heading.
    var enemyVelocities: [Int: Vec2] = [:]

    var playerNode: EntitySprite?
    var enemyNodes: [Int: EntitySprite] = [:]
    var colonistNodes: [Int: EntitySprite] = [:]
    var projectileNodes: [Int: EntitySprite] = [:]
    var decorNodes: [(sprite: SKSpriteNode, kind: EntityRole, phase: Double, speed: Double)] = []

    /// Stars at three depths: `depth` is how fast each drifts against the camera.
    var stars: [(u: CGFloat, y: CGFloat, depth: CGFloat, node: SKSpriteNode)] = []
    /// A faint far-off mountain line behind the terrain, two copies side by side so it wraps.
    var ridges: [SKShapeNode] = []
    var ridgeSpan: CGFloat = 1
    static let ridgeDepth: CGFloat = 0.3
    var starScroll: CGFloat = 0

    var pointsPerUnit: CGFloat = 0
    /// Half the visible world width, in world units.
    var halfWidth = 0.0
    var cameraX = 0.0
    var bandHeight: CGFloat = 0

    /// Fraction of the screen width the camera leads the ship by, in the direction it faces.
    static let lookAhead = 0.22
    /// Hit pulse: grows for `hitRise` seconds to `hitPulse` times size, then settles over `hitFall`.
    static let hitPulse = 0.35, hitRise = 0.05, hitFall = 0.12
    /// How fast the title backdrop drifts, in world units per second.
    static let titleDrift = 38.0

    // The shell's geometry and clock, under the names the scene code used.
    var size: CGSize { services.geometry.size }
    var safeAreaInsets: UIEdgeInsets { services.geometry.safeArea }
    var keepClear: ClosedRange<CGFloat>? { services.geometry.keepClear }
    var clock: TimeInterval { services.clock }

    init(services: ShellServices, session: @escaping () -> GameSession) {
        self.services = services
        currentSession = session
        let initial = session()
        world = initial.simulation.world
        tuning = initial.tuning
        factory = services.factory
        glyphs = RidgelineGlyphs(factory: factory, theme: theme)
        terrain = TerrainNode(world: initial.simulation.world, glyphs: glyphs)
        effects = EffectsLayer(world: initial.simulation.world, factory: factory)
        callouts = CalloutLayer(world: initial.simulation.world, theme: theme)
        scanner = ScannerNode(theme: theme, factory: factory)
        hud = HUDNode(theme: theme, factory: factory)
        controls = TouchControls(factory: factory, palette: theme.palette)

        starLayer.zPosition = 0
        worldLayer.zPosition = 10
        scanner.zPosition = 80
        hud.zPosition = 80
        controls.zPosition = 100
        // Popups, banners and notices draw over the ship and the touch-control rings, so they
        // stay readable wherever they land.
        callouts.zPosition = 105
        root.addChild(starLayer)
        sweep.zPosition = 30
        sweep.blendMode = .add
        sweep.isHidden = true
        root.addChild(sweep)
        bandMask.zPosition = 70
        bandMask.anchorPoint = .zero
        root.addChild(bandMask)
        root.addChild(worldLayer)
        for node in [callouts, scanner, hud, controls] as [SKNode] {
            node.isHidden = true
            root.addChild(node)
        }
        worldLayer.addChild(terrain)
        linkLayer.zPosition = 0.5
        worldLayer.addChild(linkLayer)
        entityLayer.zPosition = 1
        worldLayer.addChild(entityLayer)
        decorLayer.zPosition = 1
        worldLayer.addChild(decorLayer)
        effects.zPosition = 2
        worldLayer.addChild(effects)
        multiplierLabel.zPosition = 6
        multiplierLabel.isHidden = true
        entityLayer.addChild(multiplierLabel)

        makeStars()
        cameraX = session().simulation.player.pos.x
    }

    var touchControls: (any TouchControlSurface)? { controls }

    var warmUpNodes: [SKNode] { [scanner, hud, controls] }

    // MARK: Layout

    /// The top band and the scanner and HUD rectangles inside it, in scene coordinates.
    ///
    /// Open (landscape): the scanner takes the half left of the crease and the HUD the half right
    /// of it, so neither crosses the fold. Closed (portrait): the scanner runs across the top and
    /// the HUD sits under it.
    func bandLayout() -> (band: CGRect, scanner: CGRect, hud: CGRect) {
        let landscape = size.width > size.height
        let margin = max(8, min(size.width, size.height) * 0.02)
        let height = landscape ? min(max(size.height * 0.135, 40), 74) : min(max(size.height * 0.15, 60), 110)
        let top = size.height - safeAreaInsets.top - 4
        let left = safeAreaInsets.left + margin
        let right = size.width - safeAreaInsets.right - margin
        let band = CGRect(x: left, y: top - height, width: max(right - left, 1), height: height)
        if landscape {
            let gap = margin
            let middleLow = keepClear?.lowerBound ?? size.width / 2
            let middleHigh = keepClear?.upperBound ?? size.width / 2
            let scanner = CGRect(x: left, y: band.minY, width: max(middleLow - gap - left, 1), height: height)
            let hud = CGRect(x: middleHigh + gap, y: band.minY + 2, width: max(right - middleHigh - gap, 1),
                             height: height - 4)
            return (band, scanner, hud)
        }
        let scannerHeight = height * 0.46
        let scanner = CGRect(x: left, y: top - scannerHeight, width: band.width, height: scannerHeight)
        let hud = CGRect(x: left, y: band.minY, width: band.width, height: height - scannerHeight - 6)
        return (band, scanner, hud)
    }

    /// The bottom of the top band: the pause button hangs below it.
    func playfieldTop(in geometry: ShellGeometry) -> CGFloat {
        let bandHeight = size.height - bandLayout().band.minY + 4
        return size.height - bandHeight
    }

    func layout(in geometry: ShellGeometry, pauseButtonFrame: CGRect) -> Bool {
        let layout = bandLayout()
        bandHeight = size.height - layout.band.minY + 4
        let ppu = max((size.height - bandHeight) / CGFloat(world.height), 0.1)
        halfWidth = Double(size.width / 2 / ppu)
        worldLayer.position = CGPoint(x: size.width / 2, y: 0)
        worldLayer.setScale(ppu)

        if abs(ppu - pointsPerUnit) > 0.0001 {
            pointsPerUnit = ppu
            factory.clear()
            terrain.rebuild(pointsPerUnit: ppu, screenScale: services.geometry.screenScale)
            preparedTerrain = nil
            prepareNextTerrain()
            effects.setPointsPerUnit(ppu)
            removeAllEntityNodes()
            buildDecor()
            needsPrewarm = true
        }
        bandMask.position = CGPoint(x: 0, y: size.height - bandHeight)
        bandMask.size = CGSize(width: size.width, height: bandHeight)
        controls.layout(size: size, safeArea: safeAreaInsets, keepClear: keepClear)
        scanner.layout(in: layout.scanner, world: world, worldID: runID)
        hud.layout(in: layout.hud, maxLives: session.tuning.maxLives, maxShockwaves: session.tuning.maxShockwaves)
        let playfield = CGRect(x: 0, y: 0, width: size.width, height: size.height - bandHeight)
        callouts.layout(size: size, playfield: playfield, pointsPerUnit: ppu, keepClear: keepClear,
                        pauseButtonFrame: pauseButtonFrame)
        for star in stars {
            star.node.position.y = star.y * size.height
        }
        buildRidges(playHeight: size.height - bandHeight)
        placeStars()
        if needsPrewarm {
            needsPrewarm = false
            return true
        }
        return false
    }

    // MARK: Screens

    /// Shows the layers the current screen needs. Cheap when nothing changed.
    func present(_ state: ScreenState?) {
        guard let state else {
            for node in [worldLayer, callouts, scanner, hud, controls] as [SKNode] {
                node.isHidden = true
            }
            return
        }
        let screen = state.screen
        let showsBackdrop = state.showsBackdrop
        let hasRun = state.hasRun
        let inPlay: Bool = switch screen {
        case .playing, .countdown: true
        default: false
        }

        if showsBackdrop {
            worldLayer.isHidden = false
            worldLayer.alpha = screen == .title ? 0.6 : 0.3
        } else {
            switch screen {
            case .playing, .countdown:
                worldLayer.isHidden = false
                worldLayer.alpha = 1
            case .paused, .gameOver, .options, .highScores:
                worldLayer.isHidden = !hasRun
                worldLayer.alpha = 0.22
            case .title, .madeForDuo:
                worldLayer.isHidden = true
            }
        }
        bandMask.isHidden = worldLayer.isHidden || showsBackdrop
        entityLayer.isHidden = showsBackdrop
        linkLayer.isHidden = showsBackdrop
        effects.isHidden = showsBackdrop
        decorLayer.isHidden = !showsBackdrop
        // The scanner, HUD and callouts belong to play; menus get the screen to themselves.
        scanner.isHidden = !inPlay
        hud.isHidden = !inPlay
        callouts.isHidden = !inPlay

        // The far mountains step back behind a menu.
        for ridge in ridges { ridge.alpha = state.hasMenu ? 0.35 : 1 }
    }

    /// A new simulation: new terrain (each run has its own seed), no leftover nodes.
    func startRun() {
        world = session.simulation.world
        runID += 1
        moodDirector.reset()
        #if DEBUG
        autopilotBot = Autopilot(skill: Self.autopilotSkill, seed: UInt64(runID))
        #endif
        replaceTerrain()
        self.effects.removeAll()
        callouts.removeAll()
        callouts.world = world
        removeAllEntityNodes()
        enemyPositions.removeAll()
        cameraX = session.simulation.player.pos.x
    }

    /// Renders every entity glyph (and the tinted ones) now, while a menu is up, so the first
    /// enemy, falling colonist or Lancer wind-up of a run doesn't stall a frame drawing it.
    func prewarm() {
        let palette = theme.palette
        for role in EntityRole.allCases {
            _ = glyphs.glyph(for: role, pointsPerUnit: pointsPerUnit)
            _ = glyphs.glyph(for: role, tint: palette.warning, pointsPerUnit: pointsPerUnit)
        }
        _ = glyphs.glyph(for: .colonist, tint: palette.falling, pointsPerUnit: pointsPerUnit)
        // The first banner and popup also pay for loading the font.
        _ = GlowText.texture("WAVE 1", style: .heading(24), color: palette.hud)
        callouts.prewarm(colors: [palette.falling, palette.warning, palette.hud]
            + EnemyKind.allCases.map { color(of: .enemy($0)).lightened(0.35) })
        // The popups every game shows early on, in the sizes and colours they use.
        let colonist = color(of: .colonist)
        callouts.prewarm(popups: [
            ("SAVED", 0.9, colonist), ("+500", 1.25, palette.falling), ("+1,000", 1.25, palette.falling),
            ("2 SAVED ×2", 0.9, colonist), ("+250", 0.9, palette.falling), ("CATCH!", 0.8, palette.falling),
            ("HELP!", 0.8, palette.warning), ("LOST", 0.8, palette.warning), ("OVERHEAT", 0.9, palette.warning),
            ("SHIELD READY", 0.95, palette.shield), ("SHIELD DOWN", 0.95, palette.warning), ("1UP", 1, palette.falling),
            ("HUSK", 0.9, color(of: .enemy(.husk))), ("!", 1.4, palette.warning),
        ])
        // Banners and the game-over screen that appear mid-play.
        callouts.prewarmBanner("BLACKOUT", subtitle: "Every colonist lost. Hold out for supplies.",
                               color: palette.warning)
        callouts.prewarmBanner("POWER RESTORED", subtitle: "Supplies landed", color: color(of: .outpost))
        callouts.prewarmBanner("WAVE 1 CLEAR", subtitle: "Survivor bonus +1,000", color: palette.hud,
                               subtitleColor: palette.falling)
        callouts.prewarmBanner("WAVE 1", subtitle: "10 colonists to protect", color: theme.terrain.ridge)
        // The HUD and scanner make their textures on first update; do it now, hidden.
        let sim = session.simulation
        hud.update(HUDReadout(sim), time: clock)
        scanner.update(sim, cameraX: cameraX, halfWidth: halfWidth, time: clock)
        warmRenderer()
    }

    // MARK: Frame

    func input(pad: PadReader?, options: GameOptions) -> InputState {
        lastInput = currentInput(pad: pad, options: options)
        return lastInput
    }

    func currentInput(pad: PadReader?, options: GameOptions) -> InputState {
        #if DEBUG
        // Launch with -autopilot to fly and fire without touches (for simulator checks).
        if Self.autopilot {
            // The competent test bot from GameCore flies the ship.
            return autopilotBot.input(for: session.simulation)
        }
        #endif
        if let pad { return pad.input(layout: options.gamepadLayout) }
        return controls.input
    }

    func update(events: [GameEvent], elapsed: Double, state: ScreenState) {
        if state.showsBackdrop {
            updateBackdrop(min(elapsed, 0.1))
        } else if !worldLayer.isHidden {
            updateCamera(elapsed)
            handle(events)
            sync(elapsed, screen: state.screen)
        }
    }

    func updateOverlays(elapsed: Double) {
        if !hud.isHidden {
            let sim = session.simulation
            hud.update(HUDReadout(sim), time: clock)
            scanner.update(sim, cameraX: cameraX, halfWidth: halfWidth, time: clock)
            callouts.update(cameraX: cameraX, elapsed: elapsed, positions: enemyPositions)
        }
    }

    // MARK: Sound and haptics

    func sound(for event: GameEvent) -> SoundPatch? {
        theme.sound(for: event)
    }

    func hapticCue(for event: GameEvent) -> HapticCue? {
        HapticCue.cue(for: event)
    }

    func musicMood(elapsed: Double) -> MusicMood {
        moodDirector.update(elapsed: elapsed, sim: session.simulation)
    }

    var currentMusicMood: MusicMood { moodDirector.mood }

    #if DEBUG
    // MARK: Debug

    static let autopilot = ProcessInfo.processInfo.arguments.contains("-autopilot")
    /// `-autopilot shooter` flies a pilot who fights well but never rescues anyone (it runs into
    /// Blackout); plain `-autopilot` flies the competent rescuer. `-autopilot idle` and
    /// `-autopilot novice` fly the weaker test pilots, which lose their lives quickly.
    static let autopilotSkill: Autopilot.Skill = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-autopilot"), arguments.indices.contains(flag + 1) else {
            return .competent
        }
        return Autopilot.Skill.allCases.first { "\($0)" == arguments[flag + 1] } ?? .competent
    }()
    var autopilotBot = Autopilot(skill: RidgelineMode.autopilotSkill, seed: 1)

    /// The autopilot waits for the next run's ground to be ready, as a person reading the title
    /// would.
    var isReadyToStartRun: Bool { preparedTerrain != nil }

    func debugStats() -> String {
        let sim = session.simulation
        return String(format: "%d particles, wave %d, enemies %d, score %d, lives %d",
                      effects.activeParticles, sim.wave, sim.enemies.count, sim.score, sim.player.lives)
    }
    #endif
}

extension TouchControls: TouchControlSurface {}
