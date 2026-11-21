import Foundation
import GameCore
import SpriteKit
import UIKit

/// Holds a mode's front end, so the mode can read the live session through a closure.
@MainActor
final class FlowBox<Run: ModeRun> {
    var frontEnd: ModeFrontEnd<Run>

    init(frontEnd: ModeFrontEnd<Run>) {
        self.frontEnd = frontEnd
    }
}

/// Values the host needs that a generic type cannot store as statics.
private enum HostConstants {
    static let warmAlpha: CGFloat = 0.02
    #if DEBUG
    static let logsPerformance = ProcessInfo.processInfo.arguments.contains("-showStats")
    static let autopilot = ProcessInfo.processInfo.arguments.contains("-autopilot")
    static let fixedFrame = ProcessInfo.processInfo.arguments.contains("-fixedFrame")
    /// `-seed <n>`: the session's first seed, in place of one from the clock.
    static let debugSeed: UInt64? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-seed"), arguments.indices.contains(flag + 1) else { return nil }
        return UInt64(arguments[flag + 1])
    }()
    #endif
}

/// Drives a `ModeFrontEnd` (and through it the `ModeSession`) with real frame time for one mode,
/// and shows whichever screen the front end is on: menus, pause button, countdown, the
/// controller hint, with the mode's own layers underneath. Routes the mode's sound and haptics
/// through the scene's shared devices, reads the gamepad, and saves options, high scores and the
/// mode last played.
@MainActor
final class ModeHost<Mode: GameMode>: ModeDriver {
    let descriptor: ModeDescriptor
    let services: ShellServices
    let devices: ShellDevices
    let flow: FlowBox<Mode.Run>
    let mode: Mode

    private let settings = Settings.shared
    private var frontEnd: ModeFrontEnd<Mode.Run> {
        get { flow.frontEnd }
        _modify { yield &flow.frontEnd }
    }
    /// False until the fold gate has said how the phone is held; nothing is shown before that.
    private var isPoseKnown = false
    private var session: ModeSession<Mode.Run> { frontEnd.session }

    private let menuNode: MenuNode
    private let pauseButton: PauseButton
    private let countdown: CountdownNode
    private let madeForDuo: MadeForDuoNode
    private let feedback: FeedbackRouter
    private var synth: Synth { devices.synth }
    /// Until when play-only layers are drawn faintly to warm the renderer (see the mode's prewarm).
    private var warmUntil: TimeInterval = 0
    /// Layers dimmed for the warm-up, with the alpha each had before.
    private var warmDimmed: [ObjectIdentifier: CGFloat] = [:]
    private var gamepad: GamepadInput { devices.gamepad }
    /// A short line saying a controller connected or disconnected.
    private let padHint = SKNode()
    private var pauseTouch: UITouch?
    /// The front end's screen the gamepad last saw.
    private var padScreenID = -1

    private var lastTime: TimeInterval?
    private var clock: TimeInterval {
        get { services.clock }
        set { services.clock = newValue }
    }
    private var gameOverAt: TimeInterval?
    private var isSetUp = false
    #if DEBUG
    private var lastLoggedScreen = ""
    #endif

    /// The scene this host draws into. The scene owns the host, so it is always there.
    private var scene: ShellScene { services.scene! }
    private var size: CGSize { scene.size }
    private var safeAreaInsets: UIEdgeInsets { scene.safeAreaInsets }
    private var keepClear: ClosedRange<CGFloat>? { scene.keepClear }

    /// `descriptor` names this mode (usually `Mode.descriptor`); `modes` are every registered mode,
    /// for the title.
    init(descriptor: ModeDescriptor, modes: [ModeDescriptor], services: ShellServices, devices: ShellDevices) {
        self.descriptor = descriptor
        self.services = services
        self.devices = devices
        let settings = Settings.shared
        let options = settings.options
        var tables: [ModeID: HighScoreTable] = [:]
        for other in modes where other.id != descriptor.id {
            tables[other.id] = settings.highScores(for: other.id)
        }
        let catalog = ModeCatalog(modes: modes, loaded: descriptor.id, tables: tables)
        let clockSeed = UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFF_FFFF
        #if DEBUG
        // Launch with -seed <n> for the same runs every time (for comparing builds).
        let seed = HostConstants.debugSeed ?? clockSeed
        #else
        let seed = clockSeed
        #endif
        let flow = FlowBox(frontEnd: ModeFrontEnd(session: Mode.makeSession(seed: seed),
                                                  pose: .closed, options: options,
                                                  highScores: settings.highScores(for: descriptor.id),
                                                  catalog: catalog))
        self.flow = flow
        mode = Mode(services: services, session: { [flow] in flow.frontEnd.session })
        mode.touchControls?.handedness = options.handedness
        let style = services.style
        menuNode = MenuNode(style: style)
        pauseButton = PauseButton(style: style)
        countdown = CountdownNode(style: style)
        madeForDuo = MadeForDuoNode(style: style)
        feedback = FeedbackRouter(style: style, options: options, sound: devices.synth, haptics: devices.haptics)
    }

    func attach() {
        guard !isSetUp else { return }
        isSetUp = true
        scene.view?.isMultipleTouchEnabled = true

        pauseButton.zPosition = 110
        countdown.zPosition = 120
        menuNode.zPosition = 200
        madeForDuo.zPosition = 200
        padHint.zPosition = 210
        scene.addChild(padHint)
        mode.root.zPosition = 0
        scene.addChild(mode.root)
        for node in [pauseButton, countdown, menuNode, madeForDuo] as [SKNode] {
            node.isHidden = true
            scene.addChild(node)
        }

        synth.load(sounds: Mode.audio.sounds, music: Mode.audio.music)
        layoutForSize()
        presentScreen()
        #if DEBUG
        DebugMenuCommands.listen { [weak self] command in self?.runMenuCommand(command) }
        #endif
    }

    #if DEBUG
    deinit {
        debugLog("[Rimwatch mode] released \(descriptor.id.rawValue)")
    }
    #endif

    func detach() {
        guard isSetUp else { return }
        isSetUp = false
        mode.touchControls?.releaseAll()
        pauseTouch = nil
        for node in [padHint, mode.root, pauseButton, countdown, menuNode, madeForDuo] as [SKNode] {
            node.removeAllActions()
            node.removeFromParent()
        }
        menuNode.hide()
        warmDimmed = [:]
    }

    func startRun() {
        guard isPoseKnown else { return }
        apply(frontEnd.perform(.play))
        menuActivationMayHaveStartedPlay()
        noteScreenForGamepad()
        presentScreen()
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

    func gamepadChanged(_ change: GamepadInput.Change) {
        mode.touchControls?.releaseAll()
        switch change {
        case .connected(let name, _):
            debugLog("[Rimwatch pad] connected: \(name)")
            showPadHint("Controller connected")
        case .disconnected(let name):
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
        let sprite = GlowText.sprite(text, style: .item(textSize), color: services.style.text)
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
        mode.touchControls?.releaseAll()
        presentScreen()
    }

    /// The app is losing focus or going to the background.
    func appWillResignActive() {
        mode.touchControls?.releaseAll()
        frontEnd.appWillResignActive()
        presentScreen()
    }

    // MARK: Layout

    func layout() {
        layoutForSize()
    }

    private func layoutForSize() {
        services.refreshGeometry()
        guard isSetUp, size.width > 0, size.height > 0 else { return }
        let geometry = services.geometry
        pauseButton.layout(size: size, safeArea: safeAreaInsets, topY: mode.playfieldTop(in: geometry))
        if mode.layout(in: geometry, pauseButtonFrame: pauseButton.hitFrame) {
            prewarm()
        }
        presentScreen()
    }

    /// The mode's glyphs and layers, and the game-over screen that appears mid-play, made now
    /// while a menu is up.
    private func prewarm() {
        mode.prewarm()
        let menus = MenuNode(style: services.style)
        for live in [false, true] {
            if let menu = ModeFrontEnd<Mode.Run>.menu(for: .gameOver(score: 0), session: session, pose: .open,
                                                      options: frontEnd.options, highScores: frontEnd.highScores,
                                                      gameOverLive: live) {
                menus.show(menu, size: size, safeArea: safeAreaInsets, keepClear: keepClear)
            }
        }
        // Made is not uploaded: send them all to the GPU now, so their first draw is free.
        SKTexture.preload(services.factory.cachedTextures + GlowText.cachedTextures) {}
        // And the play-only layers (HUD, scanner, controls), which draw shapes and textures of
        // their own: presentScreen shows them faintly until this time.
        warmUntil = clock + 0.4
    }

    // MARK: Screens

    /// True while the screens have no run behind them (title, or options and high scores opened
    /// from the title). The mode then shows its backdrop instead of a game.
    private var showsBackdrop: Bool {
        guard isPoseKnown else { return false }
        if session.isInGame { return false }
        if case .gameOver = session.phase { return false }
        switch frontEnd.screen {
        case .title, .options, .highScores: return true
        default: return false
        }
    }

    private var screenState: ScreenState {
        let hasRun = session.isInGame || { if case .gameOver = session.phase { true } else { false } }()
        return ScreenState(screen: frontEnd.screen, hasRun: hasRun, showsBackdrop: showsBackdrop,
                           hasMenu: frontEnd.menu != nil)
    }

    /// Shows the layers the current screen needs. Cheap when nothing changed.
    private func presentScreen() {
        guard isSetUp else { return }
        guard isPoseKnown else {
            mode.present(nil)
            for node in [pauseButton, countdown, menuNode, madeForDuo] as [SKNode] {
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
        let state = screenState
        let inPlay: Bool = switch screen {
        case .playing, .countdown: true
        default: false
        }

        mode.present(state)

        // The touch controls show during play, except while a controller is connected.
        if let controls = mode.touchControls {
            let touchControls = screen == .playing && !gamepad.isConnected
            if !touchControls, !controls.isHidden { controls.releaseAll() }
            controls.isHidden = !touchControls
        }
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

        if let menu = frontEnd.menu {
            menuNode.isHidden = false
            menuNode.show(menu, size: size, safeArea: safeAreaInsets, keepClear: keepClear)
        } else {
            menuNode.isHidden = true
            menuNode.hide()
        }
        applyWarmUp()
    }

    private func apply(_ effects: [FlowEffect]) {
        for effect in effects {
            switch effect {
            case .newRun:
                if settings.lastMode != descriptor.id { settings.lastMode = descriptor.id }
                startRunVisuals()
            case .optionsChanged:
                settings.options = frontEnd.options
                mode.touchControls?.handedness = frontEnd.options.handedness
                feedback.options = frontEnd.options
            case .highScoresChanged:
                settings.setHighScores(frontEnd.highScores, for: descriptor.id)
            case .switchMode(let id):
                scene.requestModeSwitch(to: id)
            }
        }
    }

    /// A new run: the mode swaps in its visuals, nothing stays held.
    private func startRunVisuals() {
        #if DEBUG
        runStartedAt = clock
        debugLog("[Rimwatch run] start seed \(session.runSeed)")
        #endif
        mode.startRun()
        mode.touchControls?.releaseAll()
        layoutForSize()
    }

    /// While warming, play-only layers that would be hidden are drawn at a trace of alpha.
    /// `presentScreen` decides each layer's real visibility first; this only ever dims a layer it
    /// would have hidden, and remembers the alpha it had, so the layer is put back exactly as it
    /// was the moment warming ends (never by comparing alphas, which SpriteKit rounds).
    private func applyWarmUp() {
        let warming = clock < warmUntil
        for node in mode.warmUpNodes + [pauseButton as SKNode] {
            let key = ObjectIdentifier(node)
            if warming, node.isHidden {
                if warmDimmed[key] == nil { warmDimmed[key] = node.alpha }
                node.isHidden = false
                node.alpha = HostConstants.warmAlpha
            } else if let original = warmDimmed.removeValue(forKey: key) {
                // Warming is over, or the layer is really wanted now: back to its own alpha,
                // with the visibility presentScreen just gave it.
                node.alpha = original
            }
        }
    }

    #if DEBUG
    private var finishedAt: CFTimeInterval = 0
    func didFinishUpdate() {
        finishedAt = CACurrentMediaTime()
    }
    #endif

    // MARK: Frame

    func frame(currentTime: TimeInterval) {
        #if DEBUG
        let began = CACurrentMediaTime()
        if HostConstants.logsPerformance, finishedAt > 0, began - finishedAt > 0.02 {
            NSLog("[Rimwatch perf] SpriteKit took %.1f ms between frames on %@", (began - finishedAt) * 1000,
                  "\(frontEnd.screen)".components(separatedBy: "(").first ?? "")
        }
        defer {
            let spent = CACurrentMediaTime() - began
            if HostConstants.logsPerformance, spent > 0.02 {
                NSLog("[Rimwatch perf] update took %.1f ms on %@", spent * 1000,
                      "\(frontEnd.screen)".components(separatedBy: "(").first ?? "")
            }
        }
        #endif
        let realElapsed = lastTime.map { currentTime - $0 } ?? 0
        #if DEBUG
        // Launch with -fixedFrame to make every frame after the first 1/60 s of game time,
        // whatever the real time, so a run plays out the same way every time.
        let elapsed = HostConstants.fixedFrame && lastTime != nil ? 1.0 / 60 : realElapsed
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
        let stepsBefore = session.stepCount
        let input = mode.input(pad: gamepad.isConnected ? gamepad.reader : nil, options: frontEnd.options)
        #if DEBUG
        let wasInGame = session.isInGame
        #endif
        let frame = frontEnd.update(elapsed: elapsed, input: input)
        #if DEBUG
        if wasInGame, case .gameOver(let score) = session.phase {
            let result = session.run.result
            debugLog("[Rimwatch run] over score \(score) wave \(result.wave) saved \(result.saved)")
        }
        #endif
        // A tap that came and went between frames has now reached a simulation step.
        if session.stepCount != stepsBefore {
            mode.touchControls?.consumePresses()
            gamepad.reader.consumePlayPresses()
        }
        // Presses made in a menu or during the countdown are not shots or Blinks.
        if frontEnd.screen != .playing { gamepad.reader.consumePlayPresses() }
        apply(frame.effects)
        updateAudio(elapsed: elapsed)
        feedback.route(frame.events, sound: mode.sound(for:), cue: mode.hapticCue(for:),
                       placement: mode.placement(for:))
        mode.update(events: frame.events, elapsed: elapsed, state: screenState)
        presentScreen()
        mode.updateOverlays(elapsed: elapsed)
    }

    #if DEBUG
    private var runStartedAt: TimeInterval = 0
    private var perfFrames = 0
    private var perfTime = 0.0
    private var perfWorst = 0.0

    /// With -showStats: every 10 seconds, the frame rate, the slowest frame, the node count and
    /// the mode's own figures, for checking stability from the log.
    private func logPerformance(_ elapsed: Double) {
        guard HostConstants.logsPerformance, elapsed > 0 else { return }
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
        count(scene)
        NSLog("[Rimwatch perf] %.1f fps, worst frame %.1f ms, %d nodes, %@",
              Double(perfFrames) / perfTime, perfWorst * 1000, nodes, mode.debugStats())
        perfFrames = 0
        perfTime = 0
        perfWorst = 0
    }

    private var titleSince: TimeInterval?

    /// With -autopilot: go straight from the title into a game, and from game over back to the
    /// title after a few seconds. The pause menu is left alone, so fold tests see it.
    private func runAutopilotMenus() {
        guard HostConstants.autopilot else { return }
        switch frontEnd.screen {
        case .title:
            // Waits for the next run's ground to be ready, as a person reading the title would.
            if titleSince == nil { titleSince = clock }
            if frontEnd.pose == .open, mode.isReadyToStartRun, clock - (titleSince ?? clock) > 1.5 {
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

    // MARK: Audio state

    /// Gameplay sounds only during play (and the game-over sting); music by screen and game
    /// state. Called each frame before the frame's events are routed.
    private func updateAudio(elapsed: Double) {
        let gameplay: Bool
        let music: MusicMood?
        switch frontEnd.screen {
        case .playing:
            gameplay = true
            music = mode.musicMood(elapsed: min(elapsed, 0.1))
        case .countdown:
            // Coming back from a pause: the music fades in under the countdown, as it was.
            gameplay = false
            music = mode.currentMusicMood
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

    // MARK: Touches

    func touchesBegan(_ touches: Set<UITouch>) {
        guard isPoseKnown else { return }
        if !menuNode.isHidden {
            for touch in touches { menuNode.touchBegan(touch) }
            return
        }
        var forControls = touches
        if !pauseButton.isHidden, pauseTouch == nil,
           let touch = touches.first(where: { pauseButton.hitFrame.contains($0.location(in: scene)) }) {
            pauseTouch = touch
            pauseButton.setPressed(true)
            forControls.remove(touch)
        }
        if let controls = mode.touchControls, !controls.isHidden { controls.touchesBegan(forControls) }
    }

    func touchesMoved(_ touches: Set<UITouch>) {
        if let controls = mode.touchControls, !controls.isHidden { controls.touchesMoved(touches) }
    }

    func touchesEnded(_ touches: Set<UITouch>, cancelled: Bool) {
        mode.touchControls?.touchesEnded(touches)
        for touch in touches {
            if touch === pauseTouch {
                pauseTouch = nil
                pauseButton.setPressed(false)
                if !cancelled, pauseButton.hitFrame.contains(touch.location(in: scene)) {
                    frontEnd.requestPause()
                    mode.touchControls?.releaseAll()
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
