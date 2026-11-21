import Foundation
import GameCore
import RidgelineCore
import SpriteKit
import UIKit

/// Drives a `FrontEnd` (and through it the `GameSession`) with real frame time, keeps one node per
/// entity in step with the simulation, and shows whichever screen the front end is on.
///
/// Layout: a band across the top holds the scanner and the HUD (split either side of the crease
/// when the phone is open). The world layer's origin sits at the bottom centre of the screen and is
/// scaled so the whole world height fits below that band. Entities are placed at their wrap-aware
/// offset from the camera, so the seam needs no special casing.
@MainActor
final class GameScene: SKScene {
    var safeAreaInsets: UIEdgeInsets = .zero {
        didSet { if safeAreaInsets != oldValue { layoutForSize() } }
    }

    /// Scene x range of the crease on an open Duo, kept clear of controls and menu items.
    var keepClear: ClosedRange<CGFloat>? {
        didSet { if keepClear != oldValue { layoutForSize() } }
    }

    private let theme: any Theme = AlienFrontier()
    private let settings = Settings.shared
    private var frontEnd: FrontEnd
    /// False until the fold gate has said how the phone is held; nothing is shown before that.
    private var isPoseKnown = false
    private var session: GameSession { frontEnd.session }
    private var world: World { session.simulation.world }
    /// Counts runs, so the scanner knows when the world (and its terrain) changed.
    private var runID = 0

    private let factory: GlowShapeFactory
    private let starLayer = SKNode()
    private let worldLayer = SKNode()
    private var terrain: TerrainNode
    private let entityLayer = SKNode()
    private let linkLayer = SKNode()
    private let decorLayer = SKNode()
    private var effects: EffectsLayer
    private let callouts: CalloutLayer
    private let scanner: ScannerNode
    private let hud: HUDNode
    private let controls: TouchControls
    private let menuNode: MenuNode
    private let pauseButton: PauseButton
    private let countdown: CountdownNode
    private let madeForDuo: MadeForDuoNode
    private let feedback: FeedbackRouter
    private let synth: Synth
    private let hapticRouter: HapticRouter
    /// The input used for the last frame, for the engine exhaust.
    private var lastInput = InputState()
    /// Screen shake: current strength in points, decaying. Off with Reduce Motion.
    private var shake: CGFloat = 0
    /// 0 lit ... 1 Blackout, gliding so the lights go down and come back rather than switch.
    private var blackoutMix = 0.0
    /// A bright line that sweeps across the playfield when a wave starts or the power returns.
    private let sweep = SKSpriteNode()
    /// Covers the band above the playfield so effects never show behind the scanner and HUD.
    private let bandMask = SKSpriteNode(color: .black, size: .zero)
    /// The next run's ground, drawn ahead of time, and the one being drawn now.
    private var preparedTerrain: (seed: UInt64, art: PreparedTerrain)?
    /// Until when play-only layers are drawn faintly to warm the renderer (see warmRenderer).
    private var warmUntil: TimeInterval = 0
    /// Layers dimmed for the warm-up, with the alpha each had before.
    private var warmDimmed: [ObjectIdentifier: CGFloat] = [:]
    /// Set when the display scale changed: glyphs and text are rendered again before play.
    private var needsPrewarm = false
    private var preparingTerrain: (seed: UInt64, ppu: CGFloat)?
    /// Decides calm or tension (or Blackout) from the state of play.
    private var moodDirector = MusicMoodDirector()
    private let gamepad = GamepadInput()
    /// A short line saying a controller connected or disconnected.
    private let padHint = SKNode()
    private var pauseTouch: UITouch?
    /// The front end's screen the gamepad last saw.
    private var padScreenID = -1

    private final class EntitySprite: SKSpriteNode {
        var role: EntityRole = .player
        var tint: RGB?
        /// Player shield ring.
        var accessory: SKSpriteNode?
        /// When the enemy was last hit, for the hit pulse.
        var hitAt: TimeInterval?
    }

    /// Lancer charge warning lines by enemy id. They live in the entity layer, not under the
    /// Lancer, so a line stays visible while the Lancer itself is off screen.
    private var telegraphLines: [Int: SKSpriteNode] = [:]
    /// Thin lines between two things: a Harvester's grip on a colonist, a Sower's tether to its
    /// mines, an Anchor homing on an outpost, the tow line to carried colonists. Keyed by a
    /// string naming the pair; made when a link appears and removed when it ends.
    private var links: [String: SKSpriteNode] = [:]
    /// Which Sower laid each mine (the simulation doesn't need to know; the tether shows it).
    private var mineOwners: [Int: Int] = [:]
    /// Colonists being pulled in after a catch: where the catch happened and when.
    private var catchBeams: [Int: (from: Vec2, at: TimeInterval)] = [:]
    /// How long a caught colonist takes to be drawn in to the ship.
    private static let catchPull = 0.35
    /// Where carried colonists are drawn: trailing behind the ship, easing into place.
    private var trailPositions: [Int: Vec2] = [:]
    private let multiplierLabel = SKSpriteNode()
    private var multiplierShown = 0
    private var lastDrillSpark: [Int: TimeInterval] = [:]
    /// This frame's enemy positions by id, for links and for popups that follow an enemy.
    private var enemyPositions: [Int: Vec2] = [:]
    /// Last frame's enemy velocities, so debris can keep an enemy's heading.
    private var enemyVelocities: [Int: Vec2] = [:]

    private var playerNode: EntitySprite?
    private var enemyNodes: [Int: EntitySprite] = [:]
    private var colonistNodes: [Int: EntitySprite] = [:]
    private var projectileNodes: [Int: EntitySprite] = [:]
    private var decorNodes: [(sprite: SKSpriteNode, kind: EntityRole, phase: Double, speed: Double)] = []

    /// Stars at three depths: `depth` is how fast each drifts against the camera.
    private var stars: [(u: CGFloat, y: CGFloat, depth: CGFloat, node: SKSpriteNode)] = []
    /// A faint far-off mountain line behind the terrain, two copies side by side so it wraps.
    private var ridges: [SKShapeNode] = []
    private var ridgeSpan: CGFloat = 1
    private static let ridgeDepth: CGFloat = 0.3
    private var starScroll: CGFloat = 0

    private var pointsPerUnit: CGFloat = 0
    /// Half the visible world width, in world units.
    private var halfWidth = 0.0
    private var cameraX = 0.0
    private var lastTime: TimeInterval?
    private var clock: TimeInterval = 0
    private var gameOverAt: TimeInterval?
    private var isSetUp = false
    private var bandHeight: CGFloat = 0
    #if DEBUG
    private var lastLoggedScreen = ""
    #endif

    /// Fraction of the screen width the camera leads the ship by, in the direction it faces.
    private static let lookAhead = 0.22
    /// Hit pulse: grows for `hitRise` seconds to `hitPulse` times size, then settles over `hitFall`.
    private static let hitPulse = 0.35, hitRise = 0.05, hitFall = 0.12
    /// How fast the title backdrop drifts, in world units per second.
    private static let titleDrift = 38.0

    override init(size: CGSize) {
        let options = Settings.shared.options
        let clockSeed = UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFF_FFFF
        #if DEBUG
        // Launch with -seed <n> for the same runs every time (for comparing builds).
        let seed = Self.debugSeed ?? clockSeed
        #else
        let seed = clockSeed
        #endif
        frontEnd = FrontEnd(session: GameSession(seed: seed),
                            pose: .closed, options: options, highScores: Settings.shared.highScores)
        factory = GlowShapeFactory(theme: theme, screenScale: 2)
        terrain = TerrainNode(world: frontEnd.session.simulation.world, factory: factory)
        effects = EffectsLayer(world: frontEnd.session.simulation.world, factory: factory)
        callouts = CalloutLayer(world: frontEnd.session.simulation.world, theme: theme)
        scanner = ScannerNode(theme: theme, factory: factory)
        hud = HUDNode(theme: theme, factory: factory)
        controls = TouchControls(factory: factory)
        controls.handedness = options.handedness
        menuNode = MenuNode(theme: theme)
        pauseButton = PauseButton(theme: theme)
        countdown = CountdownNode(theme: theme)
        madeForDuo = MadeForDuoNode(theme: theme)
        hapticRouter = HapticRouter()
        synth = Synth(theme: theme, options: options)
        feedback = FeedbackRouter(theme: theme, options: options, sound: synth, haptics: hapticRouter)
        super.init(size: size)
        backgroundColor = theme.palette.background.uiColor()
        anchorPoint = .zero
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    override func didMove(to view: SKView) {
        guard !isSetUp else { return }
        isSetUp = true
        view.isMultipleTouchEnabled = true

        starLayer.zPosition = 0
        worldLayer.zPosition = 10
        scanner.zPosition = 80
        hud.zPosition = 80
        controls.zPosition = 100
        // Popups, banners and notices draw over the ship and the touch-control rings, so they
        // stay readable wherever they land.
        callouts.zPosition = 105
        pauseButton.zPosition = 110
        countdown.zPosition = 120
        menuNode.zPosition = 200
        madeForDuo.zPosition = 200
        padHint.zPosition = 210
        addChild(padHint)
        addChild(starLayer)
        sweep.zPosition = 30
        sweep.blendMode = .add
        sweep.isHidden = true
        addChild(sweep)
        bandMask.zPosition = 70
        bandMask.anchorPoint = .zero
        addChild(bandMask)
        addChild(worldLayer)
        for node in [callouts, scanner, hud, controls, pauseButton, countdown, menuNode, madeForDuo] as [SKNode] {
            node.isHidden = true
            addChild(node)
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
        cameraX = session.simulation.player.pos.x
        layoutForSize()
        presentScreen()
        #if DEBUG
        DebugMenuCommands.listen { [weak self] command in self?.runMenuCommand(command) }
        #endif
        gamepad.onChange = { [weak self] change in self?.gamepadChanged(change) }
        gamepad.start()
    }

    // MARK: Gamepad and menu commands

    /// A device-neutral menu command, from the gamepad or the debug notifications. Gives a light
    /// haptic tick when the selection or an option moves and a tap when an item is activated.
    private func runMenuCommand(_ command: MenuCommand) {
        guard isPoseKnown else { return }
        let wasInPlay = isInPlay
        let result = frontEnd.handle(command)
        apply(result.effects)
        if !wasInPlay { menuActivationMayHaveStartedPlay() }
        noteScreenForGamepad()
        // Only commands that did something are confirmed; one held back by the activation grace
        // (or with nothing to do) stays silent.
        if result.accepted {
            switch command {
            case .up, .down: feedback.menu(.tick, sound: .move)
            case .left, .right: feedback.menu(.tick, sound: .change)
            case .back: feedback.menu(.tick, sound: .back)
            case .activate: feedback.menu(.tap, sound: .activate)
            case .pause: break
            }
        }
        presentScreen()
    }

    private var isInPlay: Bool {
        switch frontEnd.screen {
        case .playing, .countdown: true
        default: false
        }
    }

    /// After a menu activation (Play, Resume, by pad or touch): if it started play or the
    /// countdown, the buttons that made the choice are not also gameplay presses. Buttons
    /// pressed later, during the countdown, are, so the end of the countdown suppresses nothing.
    private func menuActivationMayHaveStartedPlay() {
        if isInPlay { gamepad.reader.suppressHeldButtons() }
    }

    /// Reads the controller's presses for this frame: the menu button during play, menu commands
    /// on a menu.
    private func readGamepad(elapsed: Double) {
        gamepad.poll()
        noteScreenForGamepad()
        guard gamepad.isConnected else { return }
        switch frontEnd.screen {
        case .playing, .countdown:
            if gamepad.reader.takePausePress() { runMenuCommand(.pause) }
        default:
            if frontEnd.menu != nil {
                for command in gamepad.reader.menuCommands(elapsed: elapsed) { runMenuCommand(command) }
            } else {
                _ = gamepad.reader.takePausePress()
            }
        }
    }

    /// Tells the gamepad reader when the screen changed, so presses made on the old screen are
    /// dropped.
    private func noteScreenForGamepad() {
        guard frontEnd.screenID != padScreenID else { return }
        padScreenID = frontEnd.screenID
        gamepad.reader.screenChanged()
    }

    private func gamepadChanged(_ change: GamepadInput.Change) {
        controls.releaseAll()
        switch change {
        case .connected(let name, _):
            hapticRouter.setController(connected: true, player: gamepad.haptics)
            debugLog("[Rimwatch pad] connected: \(name)")
            showPadHint("Controller connected")
        case .disconnected(let name):
            hapticRouter.setController(connected: false, player: nil)
            debugLog("[Rimwatch pad] disconnected: \(name)")
            // The player has lost their controls: pause, and the touch controls come back.
            frontEnd.controllerDisconnected()
            showPadHint("Controller disconnected")
        }
        presentScreen()
    }

    private func showPadHint(_ text: String) {
        padHint.removeAllActions()
        padHint.removeAllChildren()
        guard size.width > 0 else { return }
        let landscape = size.width > size.height
        let textSize = min(max(min(size.width, size.height) * 0.034, 11), 16)
        let sprite = GlowText.sprite(text, style: .item(textSize), color: theme.palette.hud)
        padHint.addChild(sprite)
        // Low down, in the left half when open so it stays clear of the crease.
        let leftHalf = (keepClear?.lowerBound ?? size.width / 2) - safeAreaInsets.left
        let x = landscape ? safeAreaInsets.left + leftHalf / 2 : size.width / 2
        padHint.position = CGPoint(x: x, y: safeAreaInsets.bottom + 14 + sprite.size.height / 2)
        padHint.alpha = 0
        padHint.run(.sequence([
            .fadeIn(withDuration: 0.15),
            .wait(forDuration: 2.2),
            .fadeOut(withDuration: 0.5),
            .run { [weak padHint] in padHint?.removeAllChildren() },
        ]))
    }

    /// The fold gate's verdict. The first call reveals the game.
    func setPose(_ pose: FoldPose) {
        isPoseKnown = true
        frontEnd.setPose(pose)
        controls.releaseAll()
        presentScreen()
    }

    /// The app is losing focus or going to the background.
    func appWillResignActive() {
        controls.releaseAll()
        frontEnd.appWillResignActive()
        presentScreen()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutForSize()
    }

    // MARK: Layout

    /// The top band and the scanner and HUD rectangles inside it, in scene coordinates.
    ///
    /// Open (landscape): the scanner takes the half left of the crease and the HUD the half right
    /// of it, so neither crosses the fold. Closed (portrait): the scanner runs across the top and
    /// the HUD sits under it.
    private func bandLayout() -> (band: CGRect, scanner: CGRect, hud: CGRect) {
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

    private func layoutForSize() {
        guard isSetUp, size.width > 0, size.height > 0 else { return }
        let layout = bandLayout()
        bandHeight = size.height - layout.band.minY + 4
        let ppu = max((size.height - bandHeight) / CGFloat(world.height), 0.1)
        halfWidth = Double(size.width / 2 / ppu)
        worldLayer.position = CGPoint(x: size.width / 2, y: 0)
        worldLayer.setScale(ppu)

        if abs(ppu - pointsPerUnit) > 0.0001 {
            pointsPerUnit = ppu
            factory.clear()
            terrain.rebuild(pointsPerUnit: ppu, screenScale: view?.contentScaleFactor ?? 2)
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
        pauseButton.layout(size: size, safeArea: safeAreaInsets, topY: size.height - bandHeight)
        scanner.layout(in: layout.scanner, world: world, worldID: runID)
        hud.layout(in: layout.hud, maxLives: session.tuning.maxLives, maxShockwaves: session.tuning.maxShockwaves)
        let playfield = CGRect(x: 0, y: 0, width: size.width, height: size.height - bandHeight)
        callouts.layout(size: size, playfield: playfield, pointsPerUnit: ppu, keepClear: keepClear,
                        pauseButtonFrame: pauseButton.hitFrame)
        for star in stars {
            star.node.position.y = star.y * size.height
        }
        buildRidges(playHeight: size.height - bandHeight)
        placeStars()
        if needsPrewarm {
            needsPrewarm = false
            prewarmGlyphs()
        }
        presentScreen()
    }

    // MARK: Screens

    /// True while the screens have no run behind them (title, or options and high scores opened
    /// from the title). The world layer then shows the drifting backdrop instead of a game.
    private var showsBackdrop: Bool {
        guard isPoseKnown else { return false }
        if session.isInGame { return false }
        if case .gameOver = session.phase { return false }
        switch frontEnd.screen {
        case .title, .options, .highScores: return true
        default: return false
        }
    }

    /// Shows the layers the current screen needs. Cheap when nothing changed.
    private func presentScreen() {
        guard isSetUp else { return }
        guard isPoseKnown else {
            for node in [worldLayer, callouts, scanner, hud, controls, pauseButton, countdown, menuNode,
                         madeForDuo] as [SKNode] {
                node.isHidden = true
            }
            return
        }
        let screen = frontEnd.screen
        #if DEBUG
        let screenName = "\(screen)".components(separatedBy: "(").first ?? ""
        if screenName != lastLoggedScreen {
            lastLoggedScreen = screenName
            NSLog("[Rimwatch screen] %@", screenName)
        }
        #endif
        let hasRun = session.isInGame || { if case .gameOver = session.phase { true } else { false } }()
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

        // The touch controls show during play, except while a controller is connected.
        let touchControls = screen == .playing && !gamepad.isConnected
        if !touchControls, !controls.isHidden { controls.releaseAll() }
        controls.isHidden = !touchControls
        if case .countdown(let remaining) = screen {
            countdown.isHidden = false
            countdown.show(remaining: remaining, size: size)
        } else {
            countdown.isHidden = true
            countdown.hide()
        }
        pauseButton.isHidden = !inPlay
        if pauseButton.isHidden {
            pauseTouch = nil
            pauseButton.setPressed(false)
        }

        madeForDuo.isHidden = screen != .madeForDuo
        if screen == .madeForDuo { madeForDuo.layout(size: size) }

        // The far mountains step back behind a menu.
        for ridge in ridges { ridge.alpha = frontEnd.menu == nil ? 1 : 0.35 }
        if let menu = frontEnd.menu {
            menuNode.isHidden = false
            menuNode.show(menu, size: size, safeArea: safeAreaInsets, keepClear: keepClear)
        } else {
            menuNode.isHidden = true
            menuNode.hide()
        }
        applyWarmUp()
    }

    private func apply(_ effects: [FrontEnd.Effect]) {
        for effect in effects {
            switch effect {
            case .newRun:
                startRunVisuals()
            case .optionsChanged:
                settings.options = frontEnd.options
                controls.handedness = frontEnd.options.handedness
                feedback.options = frontEnd.options
            case .highScoresChanged:
                settings.highScores = frontEnd.highScores
            }
        }
    }

    /// A new simulation: new terrain (each run has its own seed), no leftover nodes.
    private func startRunVisuals() {
        runID += 1
        moodDirector.reset()
        #if DEBUG
        runStartedAt = clock
        debugLog("[Rimwatch run] start seed \(session.runSeed)")
        #endif
        #if DEBUG
        autopilotBot = Autopilot(skill: Self.autopilotSkill, seed: UInt64(runID))
        #endif
        replaceTerrain()
        self.effects.removeAll()
        callouts.removeAll()
        callouts.world = world
        removeAllEntityNodes()
        enemyPositions.removeAll()
        controls.releaseAll()
        cameraX = session.simulation.player.pos.x
        layoutForSize()
    }

    /// Swaps in terrain for the current run's world.
    private func replaceTerrain() {
        terrain.removeFromParent()
        terrain = TerrainNode(world: world, factory: factory)
        worldLayer.addChild(terrain)
        effects.world = world
        if pointsPerUnit > 0 {
            // Normally the ground for this run was drawn in the background while the last one
            // was on (see prepareNextTerrain); drawing it here would stall the first frames.
            let ready = preparedTerrain.flatMap { $0.seed == session.runSeed ? $0.art : nil }
            terrain.rebuild(pointsPerUnit: pointsPerUnit, screenScale: view?.contentScaleFactor ?? 2, prepared: ready)
            preparedTerrain = nil
        }
        prepareNextTerrain()
    }

    /// Renders every entity glyph (and the tinted ones) now, while a menu is up, so the first
    /// enemy, falling colonist or Lancer wind-up of a run doesn't stall a frame drawing it.
    private func prewarmGlyphs() {
        let palette = theme.palette
        for role in EntityRole.allCases {
            _ = factory.glyph(for: role, pointsPerUnit: pointsPerUnit)
            _ = factory.glyph(for: role, tint: palette.warning, pointsPerUnit: pointsPerUnit)
        }
        _ = factory.glyph(for: .colonist, tint: palette.falling, pointsPerUnit: pointsPerUnit)
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
        let menus = MenuNode(theme: theme)
        for live in [false, true] {
            if let menu = FrontEnd.menu(for: .gameOver(score: 0), session: session, pose: .open,
                                        options: frontEnd.options, highScores: frontEnd.highScores,
                                        gameOverLive: live) {
                menus.show(menu, size: size, safeArea: safeAreaInsets, keepClear: keepClear)
            }
        }
        // The HUD and scanner make their textures on first update; do it now, hidden.
        let sim = session.simulation
        hud.update(HUDReadout(sim), time: clock)
        scanner.update(sim, cameraX: cameraX, halfWidth: halfWidth, time: clock)
        // Made is not uploaded: send them all to the GPU now, so their first draw is free.
        SKTexture.preload(factory.cachedTextures + GlowText.cachedTextures) {}
        warmRenderer()
    }

    /// SpriteKit builds a render pipeline the first time it draws each kind of node (tinted
    /// additive sprites, alpha-blended plates, stroked shapes...), and hidden nodes never do.
    /// Draw one of each, almost invisibly, for a moment while a menu is up, so the first frame of
    /// play doesn't pay for them.
    private func warmRenderer() {
        let warm = SKNode()
        warm.alpha = 0.02
        warm.zPosition = -1
        warm.position = CGPoint(x: 4, y: 4)
        let palette = theme.palette
        var sprites: [SKNode] = []
        for (role, blend) in [(EntityRole.player, SKBlendMode.add), (.colonist, .alpha), (.enemy(.harvester), .add)] {
            let sprite = SKSpriteNode()
            factory.apply(factory.glyph(for: role, pointsPerUnit: pointsPerUnit), to: sprite)
            sprite.blendMode = blend
            sprites.append(sprite)
        }
        let tinted = SKSpriteNode()
        factory.apply(factory.glyph(for: .player, pointsPerUnit: pointsPerUnit), to: tinted)
        tinted.blendMode = .add
        tinted.color = palette.shield.uiColor()
        tinted.colorBlendFactor = 1
        sprites.append(tinted)
        let flat = SKSpriteNode(color: palette.warning.uiColor(), size: CGSize(width: 4, height: 4))
        flat.blendMode = .add
        sprites.append(flat)
        let plate = SKSpriteNode(color: .black, size: CGSize(width: 4, height: 4))
        plate.blendMode = .alpha
        sprites.append(plate)
        let ring = SKShapeNode(circleOfRadius: 3)
        ring.strokeColor = palette.shield.uiColor()
        ring.fillColor = .clear
        ring.blendMode = .add
        sprites.append(ring)
        let text = GlowText.sprite("+150", style: .item(12), color: palette.falling)
        sprites.append(text)
        for node in sprites {
            node.setScale(0.2)
            warm.addChild(node)
        }
        addChild(warm)
        warm.run(.sequence([.wait(forDuration: 0.5), .removeFromParent()]))
        // And the play-only layers (HUD, scanner, controls), which draw shapes and textures of
        // their own: presentScreen shows them faintly until this time.
        warmUntil = clock + 0.4
    }

    /// While warming, play-only layers that would be hidden are drawn at a trace of alpha.
    /// `presentScreen` decides each layer's real visibility first; this only ever dims a layer it
    /// would have hidden, and remembers the alpha it had, so the layer is put back exactly as it
    /// was the moment warming ends (never by comparing alphas, which SpriteKit rounds).
    private func applyWarmUp() {
        let warming = clock < warmUntil
        for node in [scanner, hud, controls, pauseButton] as [SKNode] {
            let key = ObjectIdentifier(node)
            if warming, node.isHidden {
                if warmDimmed[key] == nil { warmDimmed[key] = node.alpha }
                node.isHidden = false
                node.alpha = Self.warmAlpha
            } else if let original = warmDimmed.removeValue(forKey: key) {
                // Warming is over, or the layer is really wanted now: back to its own alpha,
                // with the visibility presentScreen just gave it.
                node.alpha = original
            }
        }
    }

    private static let warmAlpha: CGFloat = 0.02

    #if DEBUG
    private var finishedAt: CFTimeInterval = 0
    override func didFinishUpdate() {
        finishedAt = CACurrentMediaTime()
    }
    #endif

    /// Draws the ground for the next run in the background. The next run's seed is known in
    /// advance, so starting it only swaps in textures that are already made and uploaded.
    private func prepareNextTerrain() {
        guard pointsPerUnit > 0 else { return }
        let seed = session.nextRunSeed
        let ppu = pointsPerUnit
        if let ready = preparedTerrain, ready.seed == seed, ready.art.pointsPerUnit == ppu { return }
        if let pending = preparingTerrain, pending.seed == seed, pending.ppu == ppu { return }
        preparingTerrain = (seed, ppu)
        let tuning = session.tuning
        let style = theme.terrain
        let scale = view?.contentScaleFactor ?? 2
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let art = TerrainArt.render(world: World(tuning: tuning, seed: seed), style: style,
                                        pointsPerUnit: ppu, screenScale: scale)
            let prepared = PreparedTerrain(art)
            prepared.preload {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.preparingTerrain?.seed == seed, self.preparingTerrain?.ppu == ppu else {
                            return
                        }
                        self.preparingTerrain = nil
                        self.preparedTerrain = (seed, prepared)
                    }
                }
            }
        }
    }

    private func makeStars() {
        var rng = SeededRNG(seed: 42)
        // Far: many, faint and nearly still. Mid: the old field. Near: a few brighter motes.
        let layers: [(count: Int, depth: CGFloat, size: CGFloat, alpha: ClosedRange<Double>)] = [
            (70, 0.04, 1.2, 0.12...0.4), (40, 0.12, 1.6, 0.25...0.65), (14, 0.45, 2.4, 0.35...0.8),
        ]
        for layer in layers {
            for _ in 0..<layer.count {
                let node = SKSpriteNode(color: theme.palette.stars.uiColor(),
                                        size: CGSize(width: layer.size, height: layer.size))
                node.alpha = CGFloat(rng.range(layer.alpha))
                node.blendMode = .add
                starLayer.addChild(node)
                stars.append((CGFloat(rng.range(0...1)), CGFloat(rng.range(0.12...1)), layer.depth, node))
            }
        }
    }

    /// Distant mountains: a periodic ridge line, filled black below so the stars sit behind it.
    private func buildRidges(playHeight: CGFloat) {
        ridges.forEach { $0.removeFromParent() }
        ridges = []
        guard playHeight > 0, size.width > 0 else { return }
        ridgeSpan = size.width * 2
        var rng = SeededRNG(seed: 77)
        let waves: [(amplitude: CGFloat, cycles: CGFloat, phase: CGFloat)] = [(0.07, 3, 0), (0.04, 7, 0), (0.02, 17, 0)]
            .map { ($0.0, $0.1, CGFloat(rng.range(0...(2 * .pi)))) }
        let base = playHeight * 0.3
        let line = CGMutablePath()
        let steps = 160
        for i in 0...steps {
            let x = ridgeSpan * CGFloat(i) / CGFloat(steps)
            var y = base
            for w in waves { y += w.amplitude * playHeight * sin(2 * .pi * w.cycles * x / ridgeSpan + w.phase) }
            if i == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
        }
        // The fill (no outline, so its sides never show) hides the stars behind the mountains;
        // only the open ridge line is stroked.
        let fill = CGMutablePath()
        fill.addPath(line)
        fill.addLine(to: CGPoint(x: ridgeSpan, y: 0))
        fill.addLine(to: CGPoint(x: 0, y: 0))
        fill.closeSubpath()
        for _ in 0..<2 {
            let ridge = SKShapeNode(path: fill)
            ridge.fillColor = .black
            ridge.strokeColor = .clear
            ridge.lineWidth = 0
            ridge.zPosition = 1
            let edge = SKShapeNode(path: line)
            edge.strokeColor = theme.terrain.strata.uiColor(alpha: 0.3)
            edge.lineWidth = 1
            ridge.addChild(edge)
            starLayer.addChild(ridge)
            ridges.append(ridge)
        }
    }

    // MARK: Title backdrop

    /// A few craft gliding over the drifting terrain behind the title. Purely decorative: they
    /// are animated here and have nothing to do with a simulation.
    private func buildDecor() {
        for decor in decorNodes { decor.sprite.removeFromParent() }
        decorNodes = []
        let cast: [(EntityRole, Double, Double)] = [
            (.player, 0.0, 1.0), (.enemy(.harvester), 1.9, 0.55), (.enemy(.sower), 3.7, 0.4),
            (.enemy(.lancer), 5.1, 0.8), (.enemy(.brood), 2.6, 0.3),
        ]
        for (role, phase, speed) in cast {
            let sprite = SKSpriteNode()
            factory.apply(factory.glyph(for: role, pointsPerUnit: pointsPerUnit), to: sprite)
            sprite.alpha = 0.55
            decorLayer.addChild(sprite)
            decorNodes.append((sprite, role, phase, speed))
        }
    }

    private func updateBackdrop(_ dt: Double) {
        let previous = cameraX
        cameraX = world.wrap(cameraX + Self.titleDrift * dt)
        starScroll += CGFloat(world.delta(from: previous, to: cameraX)) * pointsPerUnit
        placeStars()
        terrain.update(cameraX: cameraX, halfWidth: halfWidth,
                       integrity: Array(repeating: 1, count: world.outposts.count), blackout: 0, time: clock)
        let span = halfWidth * 2 + 200
        for decor in decorNodes {
            // Each crosses the screen on its own slow loop, bobbing gently.
            let travel = (clock * 60 * decor.speed + decor.phase * 400).truncatingRemainder(dividingBy: span)
            let direction: Double = decor.phase.truncatingRemainder(dividingBy: 2) < 1 ? 1 : -1
            let x = direction * (travel - span / 2)
            // Low over the ground, below the title text and the menu.
            let ground = world.groundHeight(at: world.wrap(cameraX + x))
            let y = ground + 34 + 14 * sin(clock * 0.4 + decor.phase * 2) + decor.phase * 5
            decor.sprite.position = CGPoint(x: x, y: y)
            decor.sprite.xScale = CGFloat(direction)
        }
    }

    // MARK: Frame

    override func update(_ currentTime: TimeInterval) {
        #if DEBUG
        let began = CACurrentMediaTime()
        if Self.logsPerformance, finishedAt > 0, began - finishedAt > 0.02 {
            NSLog("[Rimwatch perf] SpriteKit took %.1f ms between frames on %@", (began - finishedAt) * 1000,
                  "\(frontEnd.screen)".components(separatedBy: "(").first ?? "")
        }
        defer {
            let spent = CACurrentMediaTime() - began
            if Self.logsPerformance, spent > 0.02 {
                NSLog("[Rimwatch perf] update took %.1f ms on %@", spent * 1000,
                      "\(frontEnd.screen)".components(separatedBy: "(").first ?? "")
            }
        }
        #endif
        let realElapsed = lastTime.map { currentTime - $0 } ?? 0
        #if DEBUG
        // Launch with -fixedFrame to make every frame after the first 1/60 s of game time,
        // whatever the real time, so a run plays out the same way every time.
        let elapsed = Self.fixedFrame && lastTime != nil ? 1.0 / 60 : realElapsed
        #else
        let elapsed = realElapsed
        #endif
        lastTime = currentTime
        clock += elapsed

        guard isPoseKnown else { return }
        #if DEBUG
        runAutopilotMenus()
        logPerformance(elapsed)
        #endif

        readGamepad(elapsed: elapsed)
        let tickBefore = session.simulation.tick
        lastInput = currentInput()
        #if DEBUG
        let wasInGame = session.isInGame
        #endif
        let frame = frontEnd.update(elapsed: elapsed, input: lastInput)
        #if DEBUG
        if wasInGame, case .gameOver(let score) = session.phase {
            debugLog("[Rimwatch run] over score \(score) wave \(session.simulation.wave) saved \(session.simulation.colonistsSaved)")
        }
        #endif
        // A tap that came and went between frames has now reached a simulation step.
        if session.simulation.tick != tickBefore {
            controls.consumePresses()
            gamepad.reader.consumePlayPresses()
        }
        // Presses made in a menu or during the countdown are not shots or Blinks.
        if frontEnd.screen != .playing { gamepad.reader.consumePlayPresses() }
        apply(frame.effects)
        updateAudio(elapsed: elapsed)
        feedback.route(frame.events) { [unowned self] event in placement(for: event) }
        if showsBackdrop {
            updateBackdrop(min(elapsed, 0.1))
        } else if !worldLayer.isHidden {
            updateCamera(elapsed)
            handle(frame.events)
            sync(elapsed)
        }
        presentScreen()
        if !hud.isHidden {
            let sim = session.simulation
            hud.update(HUDReadout(sim), time: clock)
            scanner.update(sim, cameraX: cameraX, halfWidth: halfWidth, time: clock)
            callouts.update(cameraX: cameraX, elapsed: elapsed, positions: enemyPositions)
        }
    }

    private func currentInput() -> InputState {
        #if DEBUG
        // Launch with -autopilot to fly and fire without touches (for simulator checks).
        if Self.autopilot {
            // The competent test bot from GameCore flies the ship.
            return autopilotBot.input(for: session.simulation)
        }
        #endif
        if gamepad.isConnected { return gamepad.reader.input(layout: frontEnd.options.gamepadLayout) }
        return controls.input
    }

    #if DEBUG
    private static let logsPerformance = ProcessInfo.processInfo.arguments.contains("-showStats")
    private var runStartedAt: TimeInterval = 0
    private var perfFrames = 0
    private var perfTime = 0.0
    private var perfWorst = 0.0

    /// With -showStats: every 10 seconds, the frame rate, the slowest frame, the node count and
    /// the particles in use, for checking stability from the log.
    private func logPerformance(_ elapsed: Double) {
        guard Self.logsPerformance, elapsed > 0 else { return }
        // Any frame over two refreshes is logged with what was on screen.
        if elapsed > 0.034, lastTime != nil {
            NSLog("[Rimwatch perf] slow frame %.1f ms on %@, %.2f s into the run", elapsed * 1000,
                  "\(frontEnd.screen)".components(separatedBy: "(").first ?? "", clock - runStartedAt)
        }
        perfFrames += 1
        perfTime += elapsed
        perfWorst = max(perfWorst, elapsed)
        guard perfTime >= 10 else { return }
        var nodes = 0
        func count(_ node: SKNode) {
            nodes += 1
            for child in node.children { count(child) }
        }
        count(self)
        let sim = session.simulation
        NSLog("[Rimwatch perf] %.1f fps, worst frame %.1f ms, %d nodes, %d particles, wave %d, enemies %d, score %d, lives %d",
              Double(perfFrames) / perfTime, perfWorst * 1000, nodes, effects.activeParticles, sim.wave,
              sim.enemies.count, sim.score, sim.player.lives)
        perfFrames = 0
        perfTime = 0
        perfWorst = 0
    }

    private static let autopilot = ProcessInfo.processInfo.arguments.contains("-autopilot")
    private static let fixedFrame = ProcessInfo.processInfo.arguments.contains("-fixedFrame")
    /// `-seed <n>`: the session's first seed, in place of one from the clock.
    private static let debugSeed: UInt64? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-seed"), arguments.indices.contains(flag + 1) else { return nil }
        return UInt64(arguments[flag + 1])
    }()
    /// `-autopilot shooter` flies a pilot who fights well but never rescues anyone (it runs into
    /// Blackout); plain `-autopilot` flies the competent rescuer. `-autopilot idle` and
    /// `-autopilot novice` fly the weaker test pilots, which lose their lives quickly.
    private static let autopilotSkill: Autopilot.Skill = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-autopilot"), arguments.indices.contains(flag + 1) else {
            return .competent
        }
        return Autopilot.Skill.allCases.first { "\($0)" == arguments[flag + 1] } ?? .competent
    }()
    private var autopilotBot = Autopilot(skill: GameScene.autopilotSkill, seed: 1)
    private var titleSince: TimeInterval?

    /// With -autopilot: go straight from the title into a game, and from game over back to the
    /// title after a few seconds. The pause menu is left alone, so fold tests see it.
    private func runAutopilotMenus() {
        guard Self.autopilot else { return }
        switch frontEnd.screen {
        case .title:
            // Waits for the next run's ground to be ready, as a person reading the title would.
            if titleSince == nil { titleSince = clock }
            if frontEnd.pose == .open, preparedTerrain != nil, clock - (titleSince ?? clock) > 1.5 {
                titleSince = nil
                apply(frontEnd.perform(.play))
            }
        case .gameOver:
            if gameOverAt == nil { gameOverAt = clock }
            if let start = gameOverAt, clock - start > 5 {
                gameOverAt = nil
                apply(frontEnd.perform(.proceed))
            }
        default:
            gameOverAt = nil
        }
    }
    #endif

    private func updateCamera(_ dt: Double) {
        let player = session.simulation.player
        let target = world.wrap(player.pos.x + player.facing * halfWidth * 2 * Self.lookAhead)
        let previous = cameraX
        cameraX = world.wrap(cameraX + world.delta(from: cameraX, to: target) * (1 - exp(-2.5 * dt)))
        // Never let the ship slip off screen, however fast it flies.
        let limit = halfWidth * 0.7
        let offset = world.delta(from: cameraX, to: player.pos.x)
        if offset > limit { cameraX = world.wrap(player.pos.x - limit) }
        if offset < -limit { cameraX = world.wrap(player.pos.x + limit) }

        // Distant stars drift slowly against the camera.
        starScroll += CGFloat(world.delta(from: previous, to: cameraX)) * pointsPerUnit
        placeStars()

        // Shake moves only the world, never the HUD, and settles in about a third of a second.
        shake *= CGFloat(exp(-9 * dt))
        if shake < 0.2 { shake = 0 }
        let jolt = shake > 0
            ? CGPoint(x: CGFloat.random(in: -1...1) * shake, y: CGFloat.random(in: -1...1) * shake) : .zero
        worldLayer.position = CGPoint(x: size.width / 2 + jolt.x, y: jolt.y)
    }

    /// A jolt for a big moment, in points. Restrained, and nothing with Reduce Motion on.
    private func addShake(_ amount: CGFloat) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        shake = min(max(shake, amount), 8)
    }

    /// A bright line that crosses the playfield: a wave arriving, the power coming back.
    private func sweepAcross(_ color: RGB, duration: TimeInterval = 0.7) {
        let playHeight = size.height - bandHeight
        guard playHeight > 0, !UIAccessibility.isReduceMotionEnabled else { return }
        sweep.removeAllActions()
        sweep.color = color.uiColor()
        sweep.size = CGSize(width: 3, height: playHeight)
        sweep.anchorPoint = CGPoint(x: 0.5, y: 0)
        sweep.position = CGPoint(x: -10, y: 0)
        sweep.alpha = 0.7
        sweep.isHidden = false
        let move = SKAction.moveTo(x: size.width + 10, duration: duration)
        move.timingMode = .easeInEaseOut
        sweep.run(.sequence([.group([move, .sequence([.wait(forDuration: duration * 0.6),
                                                      .fadeOut(withDuration: duration * 0.4)])]),
                             .hide()]))
    }

    private func placeStars() {
        let span = size.width * 1.4
        for star in stars {
            var x = (star.u * span - starScroll * star.depth).truncatingRemainder(dividingBy: span)
            if x < 0 { x += span }
            star.node.position.x = x - (span - size.width) / 2
        }
        var offset = (-starScroll * Self.ridgeDepth).truncatingRemainder(dividingBy: ridgeSpan)
        if offset > 0 { offset -= ridgeSpan }
        for (index, ridge) in ridges.enumerated() {
            ridge.position = CGPoint(x: offset + CGFloat(index) * ridgeSpan, y: 0)
        }
    }

    // MARK: Events

    private func color(of role: EntityRole) -> RGB {
        theme.shape(for: role).strokes.first?.color ?? theme.palette.spark
    }

    /// Where an event happened, if it has a place.
    private func position(of event: GameEvent) -> Vec2? {
        let sim = session.simulation
        func enemy(_ id: Int) -> Vec2? { sim.enemies.first { $0.id == id }?.pos }
        func colonist(_ id: Int) -> Vec2? { sim.colonists.first { $0.id == id }?.pos }
        func outpost(_ id: Int) -> Vec2? {
            sim.world.outposts.indices.contains(id) ? Vec2(sim.world.outposts[id].x, sim.world.outposts[id].groundY) : nil
        }
        switch event {
        case .playerFired(let at, _), .shockwave(let at), .playerDestroyed(let at, _), .enemyFired(let at),
             .enemyHit(_, let at), .enemyDestroyed(_, _, let at, _), .huskFormed(_, let at), .mineLaid(_, let at),
             .colonistLost(_, let at):
            return at
        case .playerBlinked(_, let to):
            return to
        case .enemySpawned(let id, _), .lancerTelegraph(let id), .lancerCharged(let id):
            return enemy(id)
        case .anchorLanded(_, let id), .outpostDestroyed(let id), .outpostRestored(let id),
             .colonistDelivered(_, let id, _):
            return outpost(id)
        case .colonistGrabbed(let id), .colonistDropped(let id), .colonistCaught(let id), .colonistLanded(let id):
            return colonist(id)
        case .playerOverheated, .shieldCharged, .shieldBroken, .playerRespawned, .extraLife:
            return sim.player.pos
        case .waveStarted, .waveCleared, .blackoutBegan, .blackoutEnded, .gameOver:
            return nil
        }
    }

    /// Stereo position for an event (-1 at the left edge of the view, 1 at the right) and its
    /// loudness for where it happened: full in view, fading to 30% two screens away.
    private func placement(for event: GameEvent) -> (pan: Double, gain: Double) {
        guard let pos = position(of: event), halfWidth > 0 else { return (0, 1) }
        let offset = world.delta(from: cameraX, to: pos.x) / halfWidth
        let beyond = max(abs(offset) - 1, 0)
        return (min(max(offset, -1), 1), max(0.3, 1 - beyond * 0.35))
    }

    // MARK: Audio state

    /// Gameplay sounds only during play (and the game-over sting); music by screen and game
    /// state. Called each frame before the frame's events are routed.
    private func updateAudio(elapsed: Double) {
        let gameplay: Bool
        let music: MusicMood?
        switch frontEnd.screen {
        case .playing:
            gameplay = true
            music = moodDirector.update(elapsed: min(elapsed, 0.1), sim: session.simulation)
        case .countdown:
            // Coming back from a pause: the music fades in under the countdown, as it was.
            gameplay = false
            music = moodDirector.mood
        case .gameOver:
            // Let the last sounds and the game-over sting ring out; the music falls away.
            gameplay = true
            music = nil
        case .title, .options, .highScores:
            gameplay = false
            music = session.isInGame ? nil : .title
        case .paused, .madeForDuo:
            gameplay = false
            music = nil
        }
        synth.setGameplayActive(gameplay)
        synth.setMusic(music)
        synth.update(elapsed: elapsed)
    }


    private func isOnScreen(_ pos: Vec2, margin: Double = 0) -> Bool {
        abs(world.delta(from: cameraX, to: pos.x)) < halfWidth + margin
    }

    /// "◀" or "▶" toward a point off screen, or "" when it is in view.
    private func pointer(to pos: Vec2) -> String {
        guard !isOnScreen(pos, margin: -20) else { return "" }
        return world.delta(from: cameraX, to: pos.x) < 0 ? "◀ " : " ▶"
    }

    private func pointed(_ text: String, toward pos: Vec2) -> String {
        let arrow = pointer(to: pos)
        if arrow.hasPrefix("◀") { return arrow + text }
        return text + arrow
    }

    private func handle(_ events: [GameEvent]) {
        guard !events.isEmpty else { return }
        let palette = theme.palette
        let sim = session.simulation
        let tuning = session.tuning
        var delivered: (count: Int, points: Int, outpost: Int)?

        for event in events {
            switch event {
            // Waves
            case .waveStarted(let wave):
                sweepAcross(theme.terrain.ridge)
                callouts.banner("WAVE \(wave)", subtitle: "\(sim.survivingColonists) colonists to protect",
                                color: theme.terrain.ridge)
            case .waveCleared(let wave, let bonus):
                callouts.banner("WAVE \(wave) CLEAR",
                                subtitle: bonus > 0 ? "Survivor bonus +\(groupedDigits(bonus))" : "No survivors",
                                color: palette.hud, subtitleColor: bonus > 0 ? palette.falling : palette.warning)
                hud.flash(.score, at: clock)

            // The ship
            case .playerFired:
                break
            case .playerOverheated:
                callouts.popup("OVERHEAT", at: sim.player.pos, color: palette.warning, scale: 0.9)
                hud.flash(.heat, at: clock)
            case .playerBlinked(let from, let to):
                // A streak, fading afterimages along it, and a pop of sparks at each end.
                effects.trail(from: from, to: to, color: palette.shield, width: 3.5)
                effects.afterimages(of: factory.glyph(for: .player, pointsPerUnit: pointsPerUnit), from: from, to: to,
                                    facing: sim.player.facing, color: palette.shield)
                effects.ring(at: to, color: palette.shield, radius: 38, duration: 0.25)
                effects.emit(at: from, EffectsLayer.Emission(count: 10, color: palette.shield, speed: 40...120, life: 0.2...0.35))
                effects.emit(at: to, EffectsLayer.Emission(count: 14, color: palette.shield.lightened(0.4), speed: 90...220,
                                               life: 0.2...0.4))
            case .shockwave(let at):
                // A double ring, a flat blast of sparks racing out, a white flash and a jolt.
                effects.ring(at: at, color: palette.shield, radius: tuning.shockwaveRange, duration: 0.8, width: 2)
                effects.ring(at: at, color: palette.shield.lightened(0.5), radius: tuning.shockwaveRange * 0.6,
                             duration: 0.5, width: 1.4)
                effects.emit(at: at, EffectsLayer.Emission(count: 64, color: palette.shield.lightened(0.3),
                                               speed: 450...800, life: 0.5...0.8, drag: 1.2, size: 1.2...1.8))
                effects.emit(at: at, EffectsLayer.Emission(count: 24, color: RGB(1, 1, 1), look: .dot, speed: 60...220,
                                               life: 0.5...0.8, size: 1.2...2))
                callouts.flash(palette.shield, strength: 0.3)
                addShake(6)
                hud.flash(.shockwaves, at: clock)
            case .shieldCharged:
                effects.ring(at: sim.player.pos, color: palette.shield, radius: 44, duration: 0.5)
                callouts.popup("SHIELD READY", at: sim.player.pos, color: palette.shield, scale: 0.95, life: 1.2)
                hud.flash(.shield, at: clock)
            case .shieldBroken:
                effects.ring(at: sim.player.pos, color: palette.shield, radius: 60)
                effects.emit(at: sim.player.pos, EffectsLayer.Emission(count: 16, color: palette.shield, look: .shard, speed: 80...200,
                                                           life: 0.4...0.6, drag: 2))
                addShake(3)
                callouts.popup("SHIELD DOWN", at: sim.player.pos, color: palette.warning, scale: 0.95, life: 1.1)
                callouts.flash(palette.shield, strength: 0.15)
                hud.flash(.shield, at: clock)
            case .playerDestroyed(let at, _):
                // The hull breaks into tumbling pieces inside a hot burst, with a slow ring.
                let hull = color(of: .player)
                effects.emit(at: at, EffectsLayer.Emission(count: 16, color: hull, look: .shard, speed: 60...220, life: 0.8...1.3,
                                               drag: 1.2, gravity: 90, size: 1...1.5))
                effects.emit(at: at, EffectsLayer.Emission(count: 40, color: palette.spark, speed: 120...380, life: 0.4...0.9))
                effects.emit(at: at, EffectsLayer.Emission(count: 14, color: RGB(1, 1, 1), look: .dot, speed: 20...90,
                                               life: 0.5...0.9, size: 1.2...2))
                effects.ring(at: at, color: hull, radius: 90, duration: 0.6)
                effects.ring(at: at, color: palette.warning, radius: 150, duration: 0.9)
                callouts.flash(palette.warning, strength: 0.28, duration: 0.6)
                addShake(7)
                hud.flash(.lives, at: clock)
            case .playerRespawned:
                // Drawn back in: a ring closes on the ship and sparks gather.
                let spot = sim.player.pos
                effects.ring(at: spot, color: color(of: .player), radius: 16, duration: 0.45, inward: true)
                for index in 0..<12 {
                    let angle = Double(index) / 12 * 2 * .pi
                    let from = Vec2(world.wrap(spot.x + cos(angle) * 70), spot.y + sin(angle) * 70)
                    effects.emit(at: from, EffectsLayer.Emission(count: 1, color: color(of: .player), speed: 150...160, life: 0.4...0.42,
                                                     angle: angle + .pi, spread: 0, drag: 0))
                }
            case .extraLife:
                callouts.notice("EXTRA LIFE", color: palette.falling)
                callouts.popup("1UP", at: sim.player.pos, color: palette.falling, life: 1.2)
                hud.flash(.lives, at: clock)

            // Enemies
            case .enemySpawned(let id, let kind):
                // A warp-in ring, if it arrives where it can be seen. Motes hatch in the Brood's burst.
                if kind != .mote, let pos = sim.enemies.first(where: { $0.id == id })?.pos, isOnScreen(pos, margin: 40) {
                    effects.ring(at: pos, color: color(of: .enemy(kind)), radius: 26, duration: 0.35)
                }
            case .enemyFired:
                break
            case .enemyHit(let id, let at):
                effects.emit(at: at, EffectsLayer.Emission(count: 6, color: palette.spark, speed: 60...160, life: 0.15...0.3))
                // The pulse is applied in updateEnemy, on top of facing and charge stretch.
                enemyNodes[id]?.hitAt = clock
            case .enemyDestroyed(let id, let kind, let at, let points):
                let tint = color(of: .enemy(kind))
                explode(kind, id: id, at: at, tint: tint)
                callouts.popup("+\(groupedDigits(points))", at: at, color: tint.lightened(0.35),
                               scale: kind == .mine || kind == .mote ? 0.7 : 0.85, life: 0.75)
                mineOwners[id] = nil
            case .huskFormed(_, let at):
                effects.emit(at: at, EffectsLayer.Emission(count: 20, color: color(of: .enemy(.husk)), speed: 80...240,
                                               life: 0.4...0.7, drag: 3))
                effects.ring(at: at, color: color(of: .enemy(.husk)), radius: 55, duration: 0.5)
                callouts.popup("HUSK", at: at, color: color(of: .enemy(.husk)), scale: 0.9, life: 1.1)
            case .mineLaid(let id, let at):
                effects.ring(at: at, color: color(of: .enemy(.mine)), radius: 16, duration: 0.3)
                // The Sower that laid it is the one sitting on that spot.
                if let sower = sim.enemies
                    .filter({ $0.kind == .sower })
                    .min(by: { world.distance($0.pos, at) < world.distance($1.pos, at) }),
                    world.distance(sower.pos, at) < 30 {
                    mineOwners[id] = sower.id
                }
            case .lancerTelegraph(let id):
                if let pos = sim.enemies.first(where: { $0.id == id })?.pos {
                    effects.ring(at: pos, color: palette.warning, radius: 36, duration: 0.35)
                    callouts.popup("!", at: pos, color: palette.warning, scale: 1.4, life: 0.7, followID: id)
                }
            case .lancerCharged(let id):
                if let lancer = sim.enemies.first(where: { $0.id == id }) {
                    let reach = tuning.lancerChargeSpeed * tuning.lancerChargeTime
                    let direction = lancer.vel.x >= 0 ? 1.0 : -1.0
                    effects.trail(from: lancer.pos, to: Vec2(lancer.pos.x + direction * reach, lancer.pos.y),
                                  color: color(of: .enemy(.lancer)), duration: tuning.lancerChargeTime)
                    effects.burst(at: lancer.pos, color: color(of: .enemy(.lancer)), count: 8, speed: 120, life: 0.3)
                }
            case .anchorLanded(_, let outpostID):
                let outpost = world.outposts[outpostID]
                let spot = Vec2(outpost.x, outpost.groundY)
                effects.burst(at: spot, color: theme.terrain.ridge, count: 14, speed: 110, life: 0.5)
                effects.ring(at: spot, color: palette.warning, radius: 50, duration: 0.45)
                callouts.notice(pointed("OUTPOST UNDER ATTACK", toward: spot), color: palette.warning, life: 2.6)

            // Colonists
            case .colonistGrabbed(let id):
                if let pos = sim.colonists.first(where: { $0.id == id })?.pos {
                    callouts.popup("HELP!", at: pos, color: palette.warning, scale: 0.8, life: 1.0)
                    if !isOnScreen(pos) {
                        callouts.notice(pointed("COLONIST TAKEN", toward: pos), color: palette.warning)
                    }
                }
            case .colonistDropped(let id):
                if let pos = sim.colonists.first(where: { $0.id == id })?.pos {
                    callouts.popup("CATCH!", at: pos, color: palette.falling, scale: 0.8, life: 0.9)
                }
            case .colonistCaught(let id):
                effects.ring(at: sim.player.pos, color: color(of: .colonist), radius: 30, duration: 0.3)
                effects.emit(at: sim.player.pos, EffectsLayer.Emission(count: 10, color: color(of: .colonist), look: .dot,
                                                           speed: 30...90, life: 0.4...0.7, angle: .pi / 2,
                                                           spread: 2, drag: 2))
                callouts.popup("+\(tuning.catchPoints)", at: sim.player.pos, color: palette.falling, scale: 0.9)
                if let pos = sim.colonists.first(where: { $0.id == id })?.pos {
                    trailPositions[id] = pos
                    // Drawn in on a beam from where it was caught, so the catch radius reads as
                    // a deliberate pull rather than a snap.
                    catchBeams[id] = (from: pos, at: clock)
                }
            case .colonistDelivered(let id, let outpost, let points):
                delivered = (count: (delivered?.count ?? 0) + 1, points: points, outpost: outpost)
                trailPositions[id] = nil
                catchBeams[id] = nil
            case .colonistLanded(let id):
                if let pos = sim.colonists.first(where: { $0.id == id })?.pos {
                    effects.emit(at: pos, EffectsLayer.Emission(count: 6, color: theme.terrain.ridge, look: .dot, speed: 20...50,
                                                    life: 0.25...0.4, angle: .pi / 2, spread: 2.4, gravity: 120))
                }
            case .colonistLost(let id, let at):
                // A little figure's worth of light falls away and dims to red.
                effects.emit(at: at, EffectsLayer.Emission(count: 12, color: color(of: .colonist), look: .dot, speed: 20...80,
                                               life: 0.6...1, drag: 1, gravity: 140))
                effects.emit(at: at, EffectsLayer.Emission(count: 8, color: palette.warning, speed: 40...120, life: 0.3...0.5))
                effects.ring(at: at, color: palette.warning, radius: 24, duration: 0.35)
                callouts.popup("LOST", at: at, color: palette.warning, scale: 0.8, life: 1.0)
                trailPositions[id] = nil
                catchBeams[id] = nil
                hud.flash(.colonists, at: clock)

            // Outposts and Blackout
            case .outpostDestroyed(let id):
                let outpost = world.outposts[id]
                // The dome blows apart: pieces thrown up that fall back, smoke-coloured sparks.
                let dome = Vec2(outpost.x, outpost.groundY + 10)
                effects.emit(at: dome, EffectsLayer.Emission(count: 22, color: color(of: .outpost), look: .shard, speed: 120...300,
                                                 life: 0.9...1.4, angle: .pi / 2, spread: 2.2, drag: 0.6,
                                                 gravity: 320, size: 1...1.6))
                effects.emit(at: dome, EffectsLayer.Emission(count: 30, color: theme.terrain.ridge, speed: 80...260, life: 0.5...0.9,
                                                 angle: .pi / 2, spread: 3))
                addShake(isOnScreen(dome) ? 6 : 2)
                effects.ring(at: Vec2(outpost.x, outpost.groundY), color: palette.warning, radius: 90, duration: 0.6)
                callouts.notice(pointed("OUTPOST LOST", toward: Vec2(outpost.x, outpost.groundY)),
                                color: palette.warning, life: 2.4)
            case .outpostRestored(let id):
                let outpost = world.outposts[id]
                let ground = Vec2(outpost.x, outpost.groundY)
                effects.emit(at: ground, EffectsLayer.Emission(count: 24, color: color(of: .outpost), look: .dot, speed: 60...180,
                                                   life: 0.6...1, angle: .pi / 2, spread: 1.2, drag: 1.5, gravity: 80))
                // The drop comes straight down from the top of the sky.
                effects.trail(from: Vec2(outpost.x, world.ceiling), to: ground, color: color(of: .outpost), duration: 0.9)
                effects.ring(at: ground, color: color(of: .outpost), radius: 70)
                callouts.notice(pointed("SUPPLY DROP", toward: ground), color: color(of: .outpost), life: 2.4)
            case .blackoutBegan:
                callouts.banner("BLACKOUT", subtitle: "Every colonist lost. Hold out for supplies.",
                                color: palette.warning, life: 2.8)
                callouts.flash(palette.warning, strength: 0.35, duration: 0.9)
                addShake(5)
            case .blackoutEnded:
                sweepAcross(color(of: .outpost), duration: 1.0)
                callouts.banner("POWER RESTORED", subtitle: "Supplies landed", color: color(of: .outpost),
                                life: 2.2)
                callouts.flash(color(of: .outpost), strength: 0.2, duration: 0.6)
            case .gameOver:
                break
            }
        }

        if let delivered, world.outposts.indices.contains(delivered.outpost) {
            // One callout for the whole group brought home: the points and the multiplier.
            let outpost = world.outposts[delivered.outpost]
            let spot = Vec2(outpost.x, outpost.groundY + 30)
            effects.ring(at: Vec2(outpost.x, outpost.groundY), color: color(of: .colonist), radius: 60, duration: 0.5)
            // A fountain of light from the pad, bigger for more colonists.
            effects.emit(at: Vec2(outpost.x, outpost.groundY + 4), EffectsLayer.Emission(count: 12 + 8 * delivered.count,
                                                                           color: color(of: .colonist), look: .dot,
                                                                           speed: 120...260, life: 0.6...1,
                                                                           angle: .pi / 2, spread: 0.7, drag: 1,
                                                                           gravity: 200))
            callouts.popup("+\(groupedDigits(delivered.points * delivered.count))", at: spot,
                           color: palette.falling, scale: 1.25, life: 1.3)
            let note = delivered.count > 1 ? "\(delivered.count) SAVED ×\(delivered.count)" : "SAVED"
            callouts.popup(note, at: spot, color: color(of: .colonist), scale: 0.9, life: 1.3)
        }
    }

    /// Each enemy goes out its own way.
    private func explode(_ kind: EnemyKind, id: Int, at: Vec2, tint: RGB) {
        typealias E = EffectsLayer.Emission
        let spark = theme.palette.spark
        switch kind {
        case .harvester:
            // The pod cracks: hull pieces and a burst of green.
            effects.emit(at: at, E(count: 7, color: tint, look: .shard, speed: 60...160, life: 0.5...0.8,
                                   drag: 1.5, gravity: 120))
            effects.emit(at: at, E(count: 14, color: tint, speed: 90...220, life: 0.3...0.55))
        case .husk:
            // A hard, fast star of magenta spikes.
            effects.emit(at: at, E(count: 14, color: tint, speed: 260...420, life: 0.2...0.35, drag: 4,
                                   size: 1.2...1.6))
            effects.ring(at: at, color: tint, radius: 34, duration: 0.25)
        case .sower:
            // Seeds scatter and fall.
            effects.emit(at: at, E(count: 10, color: tint.lightened(0.4), look: .dot, speed: 40...140,
                                   life: 0.6...0.9, drag: 1, gravity: 160))
            effects.emit(at: at, E(count: 12, color: tint, speed: 80...200, life: 0.3...0.5))
        case .mine:
            effects.emit(at: at, E(count: 10, color: tint, speed: 120...240, life: 0.15...0.3, drag: 5))
            effects.ring(at: at, color: tint, radius: 22, duration: 0.2)
        case .brood:
            // The sac bursts: slow wet blobs, a big ring the Motes scatter out of.
            effects.emit(at: at, E(count: 16, color: tint, look: .dot, speed: 30...120, life: 0.7...1.1,
                                   drag: 2, gravity: 60, size: 1.4...2.2))
            effects.emit(at: at, E(count: 12, color: color(of: .enemy(.mote)), speed: 100...220, life: 0.3...0.5))
            effects.ring(at: at, color: color(of: .enemy(.mote)), radius: 70, duration: 0.45)
        case .mote:
            effects.emit(at: at, E(count: 6, color: tint, look: .dot, speed: 40...110, life: 0.15...0.3))
        case .lancer:
            // It was going fast: the debris keeps going.
            let heading = enemyVelocities[id]?.x ?? 0
            effects.emit(at: at, E(count: 16, color: tint, speed: 160...360, life: 0.3...0.55,
                                   angle: heading < 0 ? .pi : 0, spread: 1.2, drag: 2))
            effects.emit(at: at, E(count: 5, color: tint, look: .shard, speed: 60...140, life: 0.5...0.8))
        case .anchor:
            // Heavy metal: big pieces thrown up and falling, hot sparks, a jolt.
            effects.emit(at: at, E(count: 12, color: tint, look: .shard, speed: 80...220, life: 0.8...1.2,
                                   angle: .pi / 2, spread: 2.4, drag: 0.8, gravity: 300, size: 1.2...1.8))
            effects.emit(at: at, E(count: 26, color: spark, speed: 120...300, life: 0.4...0.8))
            effects.ring(at: at, color: tint, radius: 60, duration: 0.5)
            addShake(isOnScreen(at) ? 4 : 0)
        }
    }

    // MARK: Node sync

    private func removeAllEntityNodes() {
        playerNode?.removeFromParent()
        playerNode = nil
        for node in enemyNodes.values { node.removeFromParent() }
        for node in colonistNodes.values { node.removeFromParent() }
        for node in projectileNodes.values { node.removeFromParent() }
        for line in telegraphLines.values { line.removeFromParent() }
        for line in links.values { line.removeFromParent() }
        enemyNodes.removeAll()
        colonistNodes.removeAll()
        projectileNodes.removeAll()
        telegraphLines.removeAll()
        links.removeAll()
        mineOwners.removeAll()
        trailPositions.removeAll()
        catchBeams.removeAll()
        lastDrillSpark.removeAll()
        multiplierShown = 0
        multiplierLabel.isHidden = true
    }

    /// Gives a sprite the texture for a role and tint, if it doesn't have it already.
    private func dress(_ sprite: EntitySprite, as role: EntityRole, tint: RGB? = nil) {
        guard sprite.texture == nil || sprite.role != role || sprite.tint != tint else { return }
        sprite.role = role
        sprite.tint = tint
        factory.apply(factory.glyph(for: role, tint: tint, pointsPerUnit: pointsPerUnit), to: sprite)
    }

    private func makeSprite(_ role: EntityRole, z: CGFloat) -> EntitySprite {
        let sprite = EntitySprite()
        sprite.zPosition = z
        dress(sprite, as: role)
        entityLayer.addChild(sprite)
        return sprite
    }

    /// Positions a node at a world point and hides it when it is well off screen.
    private func place(_ node: SKNode, at pos: Vec2, margin: Double = 60) {
        let dx = world.delta(from: cameraX, to: pos.x)
        node.isHidden = abs(dx) > halfWidth + margin
        node.position = CGPoint(x: dx, y: pos.y)
    }

    /// Generic create / update / remove pass over a list of entities, keyed by id.
    private func syncNodes<Entity: Identifiable>(
        _ nodes: inout [Int: EntitySprite],
        with entities: [Entity],
        include: (Entity) -> Bool = { _ in true },
        make: (Entity) -> EntitySprite,
        update: (Entity, EntitySprite) -> Void
    ) where Entity.ID == Int {
        var seen = Set<Int>()
        seen.reserveCapacity(entities.count)
        for entity in entities where include(entity) {
            seen.insert(entity.id)
            let node = nodes[entity.id] ?? {
                let made = make(entity)
                nodes[entity.id] = made
                return made
            }()
            update(entity, node)
        }
        for (id, node) in nodes where !seen.contains(id) {
            node.removeFromParent()
            nodes[id] = nil
        }
    }

    /// Draws (or updates) a thin line between two world points, keyed by `key`. Lines not
    /// touched in a frame are removed by `sync`.
    private func link(_ key: String, from a: Vec2, to b: Vec2, color: RGB, alpha: CGFloat, width: CGFloat = 1.2,
                      seen: inout Set<String>) {
        seen.insert(key)
        let line = links[key] ?? {
            let line = SKSpriteNode(color: color.uiColor(), size: CGSize(width: 1, height: 1))
            line.anchorPoint = CGPoint(x: 0, y: 0.5)
            line.blendMode = .add
            linkLayer.addChild(line)
            links[key] = line
            return line
        }()
        let ax = world.delta(from: cameraX, to: a.x)
        let dx = world.delta(from: a.x, to: b.x)
        let dy = b.y - a.y
        let bx = ax + dx
        line.isHidden = (ax < -halfWidth - 40 && bx < -halfWidth - 40) || (ax > halfWidth + 40 && bx > halfWidth + 40)
        line.position = CGPoint(x: ax, y: a.y)
        line.size = CGSize(width: max(hypot(dx, dy), 0.1), height: width / pointsPerUnit)
        line.zRotation = CGFloat(atan2(dy, dx))
        line.color = color.uiColor()
        line.alpha = alpha
    }

    private func sync(_ dt: Double) {
        guard pointsPerUnit > 0 else { return }
        let sim = session.simulation
        // The lights go down over a second and come back over a little more.
        blackoutMix += ((sim.isBlackout ? 1 : 0) - blackoutMix) * min(dt * (sim.isBlackout ? 2.2 : 1.6), 1)
        if abs(blackoutMix - (sim.isBlackout ? 1 : 0)) < 0.01 { blackoutMix = sim.isBlackout ? 1 : 0 }
        terrain.update(cameraX: cameraX, halfWidth: halfWidth, integrity: sim.outpostIntegrity,
                       blackout: blackoutMix, time: clock)
        starLayer.alpha = CGFloat(1 - 0.75 * blackoutMix)
        effects.update(cameraX: cameraX, halfWidth: halfWidth, elapsed: dt)
        syncPlayer(sim.player)
        if sim.player.isAlive, frontEnd.screen == .playing {
            let p = sim.player
            let tail = Vec2(world.wrap(p.pos.x - p.facing * 14), p.pos.y)
            effects.exhaust(at: tail, thrust: lastInput.move, shipVelocity: p.vel, facing: p.facing,
                            color: p.isOverheated ? theme.palette.warning : theme.palette.shield, elapsed: dt)
        }

        let palette = theme.palette
        let player = sim.player
        var telegraphing = Set<Int>()
        var seenLinks = Set<String>()
        enemyPositions.removeAll(keepingCapacity: true)
        enemyVelocities.removeAll(keepingCapacity: true)
        for enemy in sim.enemies {
            enemyPositions[enemy.id] = enemy.pos
            enemyVelocities[enemy.id] = enemy.vel
        }

        syncNodes(&enemyNodes, with: sim.enemies, make: { makeSprite(.enemy($0.kind), z: 3) }) { enemy, node in
            place(node, at: enemy.pos)
            if updateEnemy(enemy, node, player: player, dt: dt) { telegraphing.insert(enemy.id) }
            switch (enemy.kind, enemy.state) {
            case (.harvester, .lifting(let colonistID)):
                // The grip: a flickering beam from the pod down to the colonist.
                if let colonist = sim.colonists.first(where: { $0.id == colonistID }) {
                    link("grip-\(enemy.id)", from: enemy.pos, to: colonist.pos, color: palette.warning,
                         alpha: 0.35 + 0.35 * CGFloat(abs(sin(clock * 20))), width: 2, seen: &seenLinks)
                }
            case (.mine, _):
                // The tether back to the Sower that laid it, fading with distance.
                if let owner = mineOwners[enemy.id], let sower = enemyPositions[owner] {
                    let distance = world.distance(enemy.pos, sower)
                    if distance < 520 {
                        link("tether-\(enemy.id)", from: enemy.pos, to: sower, color: color(of: .enemy(.sower)),
                             alpha: CGFloat(0.3 * (1 - distance / 520)), width: 1, seen: &seenLinks)
                    }
                }
            case (.anchor, .descending(let outpostID)):
                // Homing on its target: a faint plumb line down to the outpost.
                let outpost = world.outposts[outpostID]
                if abs(world.delta(from: enemy.pos.x, to: outpost.x)) < 220 {
                    link("anchor-\(enemy.id)", from: enemy.pos, to: Vec2(outpost.x, outpost.groundY),
                         color: palette.warning, alpha: 0.18 + 0.12 * CGFloat(abs(sin(clock * 6))), width: 1,
                         seen: &seenLinks)
                }
            case (.anchor, .drilling):
                // Sparks fly from the drill bit.
                if isOnScreen(enemy.pos, margin: 40), clock - (lastDrillSpark[enemy.id] ?? 0) > 0.16 {
                    lastDrillSpark[enemy.id] = clock
                    effects.burst(at: Vec2(enemy.pos.x, enemy.pos.y - enemy.radius), color: palette.spark,
                                  count: 3, speed: 70, life: 0.3)
                }
            default:
                break
            }
        }
        for (id, line) in telegraphLines where !telegraphing.contains(id) {
            line.removeFromParent()
            telegraphLines[id] = nil
        }
        for id in lastDrillSpark.keys where enemyPositions[id] == nil { lastDrillSpark[id] = nil }
        for id in mineOwners.keys where enemyPositions[id] == nil { mineOwners[id] = nil }

        // Carried colonists trail behind the ship in a short line, easing into place.
        var trailTargets: [Int: Vec2] = [:]
        if player.isAlive {
            for (slot, id) in player.carried.enumerated() {
                let s = Double(slot)
                let x = world.wrap(player.pos.x - player.facing * (20 + 13 * s))
                // Never below the ground line, however low the ship flies.
                trailTargets[id] = Vec2(x, max(player.pos.y - 13 - 3 * s, world.groundHeight(at: x) + 1))
            }
        }
        let ease = 1 - exp(-10 * dt)
        syncNodes(&colonistNodes, with: sim.colonists, include: { $0.state != .lost },
                  make: { _ in makeSprite(.colonist, z: 2) }) { colonist, node in
            let tint: RGB? = switch colonist.state {
            case .held: palette.warning
            case .falling: palette.falling
            default: nil
            }
            dress(node, as: .colonist, tint: tint)
            // Drawn with normal blending, so a colonist over an outpost pad stays a figure, not a
            // white blob.
            node.blendMode = .alpha
            // A colonist in trouble flashes for attention.
            node.alpha = tint == nil ? 1 : (sin(clock * 18) > 0 ? 1 : 0.45)
            var pos = colonist.pos
            if let target = trailTargets[colonist.id] {
                let current = trailPositions[colonist.id] ?? colonist.pos
                let x = world.wrap(current.x + world.delta(from: current.x, to: target.x) * ease)
                pos = Vec2(x, max(current.y + (target.y - current.y) * ease, world.groundHeight(at: x) + 1))
                if let beam = catchBeams[colonist.id] {
                    let t = (clock - beam.at) / Self.catchPull
                    if t >= 1 {
                        catchBeams[colonist.id] = nil
                    } else {
                        // Eased from the catch point toward the ship, with a bright beam between.
                        let eased = t * t * (3 - 2 * t)
                        let bx = world.wrap(beam.from.x + world.delta(from: beam.from.x, to: pos.x) * eased)
                        pos = Vec2(bx, beam.from.y + (pos.y - beam.from.y) * eased)
                        link("beam-\(colonist.id)", from: player.pos, to: Vec2(pos.x, pos.y + 8),
                             color: color(of: .colonist), alpha: CGFloat(0.9 - 0.6 * t), width: 2.5, seen: &seenLinks)
                    }
                }
                trailPositions[colonist.id] = pos
                link("tow-\(colonist.id)", from: player.pos, to: Vec2(pos.x, pos.y + 12), color: color(of: .colonist),
                     alpha: 0.3, width: 1, seen: &seenLinks)
            } else {
                trailPositions[colonist.id] = nil
            }
            place(node, at: pos)
        }
        syncNodes(&projectileNodes, with: sim.projectiles,
                  make: { makeSprite(.projectile($0.owner), z: 4) }) { shot, node in
            place(node, at: shot.pos, margin: 20)
            switch shot.owner {
            case .player: node.xScale = shot.vel.x < 0 ? -1 : 1
            case .enemy: node.zRotation += CGFloat(dt * 8)
            }
        }
        for (key, line) in links where !seenLinks.contains(key) {
            line.removeFromParent()
            links[key] = nil
        }

        // The carry multiplier rides with the ship once it is worth something.
        let multiplier = player.isAlive ? player.carried.count : 0
        if multiplier >= 2 {
            if multiplier != multiplierShown {
                let (texture, size) = GlowText.texture("×\(multiplier)",
                                                       style: GlowText.Style(size: 17, weight: .bold, tracking: 0.04),
                                                       color: palette.falling)
                multiplierLabel.texture = texture
                multiplierLabel.size = size
                multiplierLabel.blendMode = .add
            }
            multiplierLabel.isHidden = false
            multiplierLabel.setScale((1 + 0.08 * CGFloat(sin(clock * 6))) / pointsPerUnit)
            multiplierLabel.position = CGPoint(x: world.delta(from: cameraX, to: player.pos.x), y: player.pos.y + 26)
        } else {
            multiplierLabel.isHidden = true
        }
        multiplierShown = multiplier

        controls.setAvailable(.blink, player.isAlive && player.blinkCooldown <= 0)
        controls.setAvailable(.shockwave, player.isAlive && player.shockwaves > 0)
        controls.setAvailable(.fire, player.isAlive && !player.isOverheated)
        let readout = HUDReadout(sim)
        controls.setStatus(TouchControls.Status(heat: readout.heat, isOverheated: readout.isOverheated,
                                                blinkReadiness: readout.blinkReadiness,
                                                shockwaves: readout.shockwaves, maxShockwaves: readout.maxShockwaves),
                           time: clock)
    }

    private func syncPlayer(_ player: Player) {
        let node = playerNode ?? {
            let made = makeSprite(.player, z: 5)
            let ring = SKSpriteNode()
            factory.apply(factory.glyph(key: "shield-ring", shape: ShapeDescription(scale: 24, strokes: [
                ShapeStroke(ShapeKit.arc(radius: 1, segments: 40), color: theme.palette.shield),
            ]), pointsPerUnit: pointsPerUnit), to: ring)
            made.addChild(ring)
            made.accessory = ring
            playerNode = made
            return made
        }()
        node.isHidden = !player.isAlive
        guard player.isAlive else { return }
        node.position = CGPoint(x: world.delta(from: cameraX, to: player.pos.x), y: player.pos.y)
        node.xScale = player.facing < 0 ? -1 : 1
        node.zRotation = CGFloat(player.vel.y / session.tuning.verticalSpeed * 0.18 * player.facing)

        let invulnerable = player.invulnerableTimer > 0
        // Invulnerable: the hull strobes and the shield ring pulses. A charged shield shows a
        // steady ring that breathes gently.
        node.alpha = invulnerable ? (sin(clock * 38) > 0 ? 1 : 0.3) : 1
        if let ring = node.accessory {
            ring.isHidden = !invulnerable && player.shield < 1
            ring.alpha = invulnerable ? 0.5 + 0.4 * CGFloat(sin(clock * 12)) : 0.4 + 0.15 * CGFloat(sin(clock * 3))
        }
    }

    /// Dresses and poses an enemy. Returns true if it is a Lancer showing its charge line.
    @discardableResult
    private func updateEnemy(_ enemy: Enemy, _ node: EntitySprite, player: Player, dt: Double) -> Bool {
        let palette = theme.palette
        var tint: RGB?
        var alpha: CGFloat = 1
        var xScale: CGFloat = 1
        var yScale: CGFloat = 1
        var showLine = false
        var lineDirection: CGFloat = 1

        switch enemy.kind {
        case .husk:
            node.zRotation += CGFloat(dt * 4)
        case .mine:
            node.zRotation += CGFloat(dt * 1.5)
            alpha = 0.65 + 0.35 * CGFloat(abs(sin(clock * 4 + Double(enemy.id))))
        case .mote:
            node.zRotation = CGFloat(atan2(enemy.vel.y, enemy.vel.x))
        case .brood:
            // The sac breathes; it swells harder once it has been hit.
            let tense = enemy.hp < session.tuning.stats(for: .brood).hp
            let breathe = CGFloat(sin(clock * (tense ? 9 : 3) + Double(enemy.id))) * (tense ? 0.09 : 0.05)
            xScale = 1 + breathe
            yScale = 1 - breathe
        case .lancer:
            let towardPlayer: CGFloat = world.delta(from: enemy.pos.x, to: player.pos.x) >= 0 ? 1 : -1
            switch enemy.state {
            case .telegraphing:
                // Winding up: turns red, strobes, and shows the line it will charge along.
                tint = palette.warning
                xScale = towardPlayer
                alpha = sin(clock * 30) > 0 ? 1 : 0.5
                showLine = true
                lineDirection = towardPlayer
            case .charging:
                xScale = enemy.vel.x < 0 ? -1.3 : 1.3
            case .recovering:
                xScale = enemy.vel.x < 0 ? -1 : 1
                alpha = 0.45
            default:
                xScale = enemy.vel.x < 0 ? -1 : 1
            }
        case .anchor:
            if case .drilling = enemy.state {
                node.position.x += CGFloat.random(in: -0.8...0.8)
                tint = sin(clock * 10) > 0 ? nil : palette.warning
            }
        case .harvester:
            if case .lifting = enemy.state { tint = sin(clock * 8) > 0 ? nil : palette.warning }
        case .sower:
            break
        }

        dress(node, as: .enemy(enemy.kind), tint: tint)
        node.alpha = alpha
        // The hit pulse multiplies the scale, so facing and the charge stretch survive it.
        let pulse = hitPulse(node)
        node.xScale = xScale * pulse
        node.yScale = yScale * pulse
        if enemy.kind != .husk, enemy.kind != .mine, enemy.kind != .mote { node.zRotation = 0 }

        guard showLine else { return false }
        let line = telegraphLines[enemy.id] ?? {
            let line = SKSpriteNode(color: palette.warning.uiColor(), size: .zero)
            line.anchorPoint = CGPoint(x: 0, y: 0.5)
            line.blendMode = .add
            line.zPosition = 2.5
            entityLayer.addChild(line)
            telegraphLines[enemy.id] = line
            return line
        }()
        // The line starts just ahead of the Lancer and runs the length of the charge. It is shown
        // whenever any part of it crosses the view, even with the Lancer itself off screen.
        let length = session.tuning.lancerChargeSpeed * session.tuning.lancerChargeTime
        let start = world.delta(from: cameraX, to: enemy.pos.x) + 20 * Double(lineDirection)
        let end = start + length * Double(lineDirection)
        let visible = max(start, end) > -halfWidth && min(start, end) < halfWidth
        line.isHidden = !visible
        line.size = CGSize(width: length, height: 1.5 / pointsPerUnit)
        line.position = CGPoint(x: start, y: enemy.pos.y)
        line.xScale = lineDirection
        line.alpha = 0.3 + 0.3 * CGFloat(abs(sin(clock * 15)))
        return true
    }

    private func hitPulse(_ node: EntitySprite) -> CGFloat {
        guard let hitAt = node.hitAt else { return 1 }
        let t = clock - hitAt
        if t < Self.hitRise { return 1 + CGFloat(Self.hitPulse * t / Self.hitRise) }
        if t < Self.hitRise + Self.hitFall {
            return 1 + CGFloat(Self.hitPulse * (1 - (t - Self.hitRise) / Self.hitFall))
        }
        node.hitAt = nil
        return 1
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isPoseKnown else { return }
        if !menuNode.isHidden {
            for touch in touches { menuNode.touchBegan(touch) }
            return
        }
        var forControls = touches
        if !pauseButton.isHidden, pauseTouch == nil,
           let touch = touches.first(where: { pauseButton.hitFrame.contains($0.location(in: self)) }) {
            pauseTouch = touch
            pauseButton.setPressed(true)
            forControls.remove(touch)
        }
        if !controls.isHidden { controls.touchesBegan(forControls) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !controls.isHidden { controls.touchesMoved(touches) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, cancelled: true)
    }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        controls.touchesEnded(touches)
        for touch in touches {
            if touch === pauseTouch {
                pauseTouch = nil
                pauseButton.setPressed(false)
                if !cancelled, pauseButton.hitFrame.contains(touch.location(in: self)) {
                    frontEnd.requestPause()
                    controls.releaseAll()
                }
            } else if let choice = menuNode.touchEnded(touch, cancelled: cancelled) {
                if !menuNode.isAdjustable(choice.index) {
                    // Ignored just after game over or a forced pause (see acceptsTouchActivation).
                    guard frontEnd.acceptsTouchActivation else { continue }
                    let wasInPlay = isInPlay
                    let isBack = frontEnd.menu?.items.indices.contains(choice.index) == true
                        && frontEnd.menu?.items[choice.index].command == .back
                    apply(frontEnd.choose(choice.index))
                    if !wasInPlay { menuActivationMayHaveStartedPlay() }
                    feedback.menu(.tap, sound: isBack ? .back : .activate)
                } else if frontEnd.select(choice.index), choice.step != 0 {
                    // An arrow steps the option like a gamepad's left and right.
                    apply(frontEnd.adjust(by: choice.step))
                    feedback.menu(.tick, sound: .change)
                }
            }
        }
        presentScreen()
    }
}
