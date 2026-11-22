import Foundation
import GameCore
import RiftwingCore
import SpriteKit
import UIKit

/// Riftwing plugged into the shell: draws the cavern gallery (ledges, the Rift, vents, the roof
/// and the tunnel mouths), one pooled sprite per opponent, pod and mine, the rider's rig, the
/// HUD strip, callouts and the touch controls (a floating steering stick and a flap half).
///
/// Layout: a thin HUD strip across the top (split either side of the crease when the phone is
/// open, with the shell's pause button at its right end). The 900 x 600 gallery is scaled to fit
/// below it, centred, as large as it will go: the gallery layer's origin is its bottom-left
/// corner and its scale is points per gallery unit, so entities are placed at their run
/// positions directly. Black masks cover everything just outside the gallery, so a figure
/// crossing a side edge (drawn on both sides, `mirrorAcrossJoin`) never shows past it.
///
/// Every frame reads the live session once, then walks the run's arrays in plain loops, handing
/// each entity a sprite from a fixed pool by index.
@MainActor
final class RiftwingMode: GameMode {
    typealias Run = RiftwingRun

    static let descriptor = ModeDescriptor.riftwing
    static var shellStyle: ShellStyle { RiftCaves().shellStyle }
    /// The Rift Caves' sound patches (`Themes/RiftCavesSounds.swift` in RiftwingCore) and music.
    static var audio: ModeAudio {
        let theme = RiftCaves()
        return ModeAudio(sounds: theme.allSounds, music: theme.music)
    }

    static func makeSession(seed: UInt64) -> RiftwingSession {
        var config = RiftwingRun.Config()
        #if DEBUG
        config.lampsOutAtWave = Self.debugInt("-lampsOutAtWave")
        config.startAtWave = Self.debugInt("-startAtWave")
        config.breathAfter = Self.debugDouble("-breathAfter")
        #endif
        return RiftwingSession(seed: seed, config: config)
    }

    // Pool sizes: at most 6 rigs at once plus Gleaners and hatched rigs; pods are this wave's
    // (freed and lost ones stay, but are not drawn); at most 2 Sowers of 4 mines each.
    static let opponentPool = 20
    static let podPool = 24
    static let minePool = 16
    static let arrivalPool = 8
    static let linkPool = 24
    static let ghostPool = 24
    static let motesPerVent = 14

    let services: ShellServices
    /// Reads the live session. Never keep what it returns: it would make every step copy the run.
    let currentSession: () -> RiftwingSession
    let root = SKNode()
    let theme = RiftCaves()
    let tuning: RiftwingTuning
    let factory: GlowShapeFactory
    let glyphs: RiftwingGlyphs
    var session: RiftwingSession { currentSession() }
    var runID = 0
    var soundDirector = RiftwingSoundDirector()
    var moodDirector = RiftwingMoodDirector()

    // Layers. The gallery layer is in gallery units; the rest are in screen points.
    let galleryLayer = SKNode()
    let entityLayer = SKNode()
    let decorLayer = SKNode()
    let roofSprite = SKSpriteNode()
    let mouthSprite = SKSpriteNode()
    let riftGlow = SKSpriteNode()
    /// The Rift's glow running on past the left and right edges, fading out.
    let riftGlowSides = [SKSpriteNode(), SKSpriteNode()]
    let riftLine = SKSpriteNode()
    let gasSprite = SKSpriteNode()
    let gasTop = SKSpriteNode()
    let breathMark = SKSpriteNode()
    /// The lamps-out darkness: two tiles side by side, each a gallery wide with a pool of light at
    /// its centre, so the pool reaches across the join (`syncDarkness`).
    let darkness = SKSpriteNode()
    let darknessTwin = SKSpriteNode()
    /// Where the pool of light is (the rider, or where it was lost).
    var lightCentre = Vec2(450, 300)
    /// The Rift's living glow: hot spots drifting along it, and a sickly glow that swells while
    /// it is about to breathe.
    var riftSpots: [SKSpriteNode] = []
    let breathGlow = SKSpriteNode()
    /// Red bars up both side walls while the Rift is about to fill the gallery.
    var fillBars: [SKSpriteNode] = []
    /// The rider was being hunted for staying put, last frame (for the cue when it starts).
    var wasCamping = false
    var campingCueAt = -100.0
    /// A faint column over each vent up to the height it lifts to.
    var ventColumns: [SKSpriteNode] = []
    /// Time to the next wisp of gas or falling pebble (seconds of animation time).
    var wispDue = 0.0
    var pebbleDue = 0.0
    var trailDue = 0.0
    var masks: [SKSpriteNode] = []
    /// One outline sprite per ledge, by layout: when the cavern shifts the old ledges crumble and
    /// fall and the new ones rise into place, one after another.
    var ledgeSprites: [[SKSpriteNode]] = []
    let effects = RiftwingEffects()
    let callouts: RiftwingCallouts
    let hud: RiftwingHUD
    let controls: RiftwingTouchControls

    /// A sprite that remembers what it was last dressed as, so textures change only on a change.
    final class PoolSprite: SKSpriteNode {
        /// Not yet given any look: the next sync always dresses it.
        static let undressed = -1
        var look = PoolSprite.undressed
        var glyph: GlowShapeFactory.Glyph?
    }

    let riderSprite = PoolSprite()
    let shieldSprite = PoolSprite()
    var opponentSprites: [PoolSprite] = []
    var podSprites: [PoolSprite] = []
    var mineSprites: [PoolSprite] = []
    var arrivalSprites: [PoolSprite] = []
    var arrivalGlows: [SKSpriteNode] = []
    var linkSprites: [SKSpriteNode] = []
    var ghostSprites: [PoolSprite] = []
    var moteSprites: [SKSpriteNode] = []
    var motes: [(x: Double, y: Double, speed: Double)] = []
    var shownOpponents = 0, shownPods = 0, shownMines = 0, shownArrivals = 0, shownLinks = 0, shownGhosts = 0
    /// Sprites to draw again across the join this frame, when they overlap a side edge.
    var wrapCandidates: [SKSpriteNode] = []

    /// When each opponent was last hit, for the hit pulse.
    var hitAt: [Int: TimeInterval] = [:]
    /// 0 lit ... 1 lamps out, gliding so the lamps fail and come back rather than switch.
    var darkMix = 0.0
    var shake: CGFloat = 0
    /// The cavern is rumbling toward its next layout (between `cavernShifting` and
    /// `cavernShifted`).
    var isShifting = false
    var shownLayout = -1
    /// The layout the cavern last shifted from, and when (animation time) the new one arrived.
    var fallingLayout = -1
    var layoutArrivedAt = -100.0
    /// When the rider last recoiled from a clash (animation time), and how hard.
    var riderKickAt = -100.0
    var riderKick: CGFloat = 0
    /// Pods knocked loose that cannot be taken yet (to show the moment they can).
    var uncatchablePods: Set<Int> = []
    /// When each pod landed, for its squash.
    var podLandedAt: [Int: TimeInterval] = [:]
    /// Time that runs only while a run is played (or the title's backdrop shows), so effects,
    /// motes, the shake and every pulse freeze on the pause screen and the other menus.
    var animationClock: TimeInterval = 0
    /// Glyphs for the frame loop, looked up once per scale.
    var looks = Looks()
    #if DEBUG
    var overflowedPools: Set<String> = []
    #endif
    var decor: [(sprite: SKSpriteNode, phase: Double, speed: Double, height: Double)] = []

    var pointsPerUnit: CGFloat = 0
    /// The gallery's bottom-left corner on screen.
    var galleryOrigin: CGPoint = .zero
    var stripRect: CGRect = .zero
    var needsPrewarm = false

    var size: CGSize { services.geometry.size }
    /// The mode's animation time (`animationClock`), not the shell's, so a paused game stands still.
    var clock: TimeInterval { animationClock }

    init(services: ShellServices, session: @escaping () -> RiftwingSession) {
        self.services = services
        currentSession = session
        tuning = session().tuning
        factory = services.factory
        // Figures are drawn at 3 pixels a point: they are small, and crispness is what they need.
        glyphs = RiftwingGlyphs(factory: factory, theme: theme, figureScale: tuning.figureScale, screenScale: 3)
        callouts = RiftwingCallouts(subtitleColor: theme.palette.hud)
        hud = RiftwingHUD(theme: theme, factory: factory)
        controls = RiftwingTouchControls(factory: factory, palette: theme.palette,
                                         diveThreshold: tuning.diveStickThreshold)
        buildNodes()
    }

    var touchControls: (any TouchControlSurface)? { controls }
    var warmUpNodes: [SKNode] { [hud, controls] }

    // MARK: Layout

    /// The HUD strip: a thin band across the top of the safe area.
    func strip(in geometry: ShellGeometry) -> CGRect {
        let size = geometry.size
        let height = min(max(size.height * 0.062, 26), 40)
        let top = size.height - geometry.safeArea.top - 3
        let left = geometry.safeArea.left + 8
        let right = size.width - geometry.safeArea.right - 8
        return CGRect(x: left, y: top - height, width: max(right - left, 1), height: height)
    }

    /// Puts the pause button in the strip's right end: the shell hangs it 30 points below this.
    func playfieldTop(in geometry: ShellGeometry) -> CGFloat {
        strip(in: geometry).midY + 30
    }

    func layout(in geometry: ShellGeometry, pauseButtonFrame: CGRect) -> Bool {
        let size = geometry.size
        stripRect = strip(in: geometry)
        let available = CGRect(x: geometry.safeArea.left + 4, y: geometry.safeArea.bottom + 4,
                               width: size.width - geometry.safeArea.left - geometry.safeArea.right - 8,
                               height: stripRect.minY - 3 - geometry.safeArea.bottom - 4)
        let gallery = CGSize(width: tuning.width, height: tuning.height)
        let ppu = max(min(available.width / gallery.width, available.height / gallery.height), 0.05)
        galleryOrigin = CGPoint(x: (available.midX - gallery.width * ppu / 2).rounded(),
                                y: (available.minY + (available.height - gallery.height * ppu) / 2).rounded())
        galleryLayer.position = galleryOrigin
        galleryLayer.setScale(ppu)

        if abs(ppu - pointsPerUnit) > 0.0001 {
            pointsPerUnit = ppu
            factory.clear()
            glyphs.clearFigures()
            looks = Looks()
            buildCavern()
            dressPools()
            effects.setPointsPerUnit(ppu, factory: factory, gallery: gallery, figureScale: tuning.figureScale)
            effects.setColonistGlyph(glyphs.glyph(.freedColonist, pointsPerUnit: ppu), factory: factory)
            buildDecor()
            needsPrewarm = true
        }
        layoutMasks(size: size)

        let middleLow = geometry.keepClear?.lowerBound ?? size.width / 2
        let middleHigh = geometry.keepClear?.upperBound ?? size.width / 2
        let gap: CGFloat = 10
        hud.layout(strip: stripRect, left: (stripRect.minX + 4)...(middleLow - gap),
                   right: (middleHigh + gap)...max(middleHigh + gap + 1, pauseButtonFrame.minX + 4),
                   maxLives: tuning.maxLives)
        let galleryRect = CGRect(origin: galleryOrigin, size: CGSize(width: gallery.width * ppu, height: gallery.height * ppu))
        controls.layout(size: size, safeArea: geometry.safeArea, keepClear: geometry.keepClear, gallery: galleryRect)
        callouts.figureClearance = CGFloat(tuning.riderRadius) * ppu * 1.3
        callouts.layout(size: size, playfield: galleryRect, keepClear: geometry.keepClear)
        if needsPrewarm {
            needsPrewarm = false
            return true
        }
        return false
    }

    /// Screen point for a gallery position.
    func screenPoint(_ p: Vec2) -> CGPoint {
        CGPoint(x: galleryOrigin.x + CGFloat(p.x) * pointsPerUnit, y: galleryOrigin.y + CGFloat(p.y) * pointsPerUnit)
    }

    // MARK: Screens

    func present(_ state: ScreenState?) {
        guard let state else {
            for node in [galleryLayer, callouts, hud, controls] as [SKNode] { node.isHidden = true }
            return
        }
        let screen = state.screen
        let inPlay: Bool = switch screen {
        case .playing, .countdown: true
        default: false
        }
        if state.showsBackdrop {
            galleryLayer.isHidden = false
            galleryLayer.alpha = screen == .title ? 0.32 : 0.22
        } else {
            switch screen {
            case .playing, .countdown:
                galleryLayer.isHidden = false
                galleryLayer.alpha = 1
            case .paused, .gameOver, .options, .highScores:
                galleryLayer.isHidden = !state.hasRun
                galleryLayer.alpha = 0.22
            case .title, .madeForDuo:
                galleryLayer.isHidden = true
            }
        }
        entityLayer.isHidden = state.showsBackdrop
        effects.isHidden = state.showsBackdrop
        decorLayer.isHidden = !state.showsBackdrop
        hud.isHidden = !inPlay
        callouts.isHidden = !inPlay
    }

    func startRun() {
        runID += 1
        #if DEBUG
        pilot = RiftwingPilot(skill: Self.autopilotSkill, seed: UInt64(runID))
        pilotTick = 0
        overflowedPools.removeAll()
        #endif
        effects.removeAll()
        callouts.removeAll()
        hitAt.removeAll()
        podLandedAt.removeAll()
        uncatchablePods.removeAll()
        fallingLayout = -1
        layoutArrivedAt = -100
        riderKickAt = -100
        campingCueAt = -100
        wasCamping = false
        soundDirector.reset()
        moodDirector.reset()
        darkMix = 0
        shake = 0
        isShifting = false
        shownLayout = -1
        hideAllPooled()
    }

    func prewarm() {
        guard pointsPerUnit > 0 else { return }
        dressPools()
        if looks.riders.isEmpty { looks = makeLooks() }
        let palette = theme.palette
        for scale in [0.8, 1.0, 1.15, 1.3] as [CGFloat] {
            _ = GlowText.texture("+500", style: .item(callouts.textSize * scale), color: palette.reward)
        }
        // Every word a popup shows, at the size and in the colour it is shown in.
        for word in PopupWord.allCases {
            let look = popupLook(word)
            _ = GlowText.texture(look.text, style: .item(callouts.textSize * look.scale), color: look.color)
        }
        callouts.prewarmBanner("WAVE 1", subtitle: "Win by height. Free the colonists in the pods.", color: palette.heading)
        callouts.prewarmBanner("LAMPS OUT", subtitle: "Free a colonist to bring them back", color: palette.warning)
        hud.update(readout(session.run), time: clock)
        warmRenderer()
    }

    // MARK: Frame

    func input(pad: PadReader?, options: GameOptions) -> RiftwingInput {
        #if DEBUG
        if Self.autopilot { return autopilotInput() }
        #endif
        if let pad { return RiftwingInput(pad: pad) }
        return controls.nextInput()
    }

    func update(events: [RiftwingEvent], elapsed: Double, state: ScreenState) {
        // Animation time runs while a game is played and behind the title; on the pause screen,
        // game over and the other menus everything stands still where it was.
        let animating = state.showsBackdrop || state.screen == .playing
        let dt = animating ? min(max(elapsed, 0), 0.1) : 0
        animationClock += dt
        if state.showsBackdrop {
            updateBackdrop(dt)
        } else if !galleryLayer.isHidden {
            let run = session.run
            handle(events, run: run)
            sync(run, elapsed: dt, screen: state.screen)
        }
    }

    func updateOverlays(elapsed: Double) {
        guard !hud.isHidden else { return }
        let run = session.run
        hud.update(readout(run), time: clock)
        // Text keeps clear of the rider: anything over it fades right down.
        var avoid: CGRect?
        if run.rider.isAlive {
            let centre = screenPoint(run.rider.pos)
            let r = CGFloat(tuning.riderRadius) * pointsPerUnit * 1.6
            avoid = CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r)
        }
        callouts.update(elapsed: elapsed, avoid: avoid)
    }

    func readout(_ run: RiftwingRun) -> RiftwingHUD.Readout {
        // Before the first wave, the wave about to start.
        RiftwingHUD.Readout(score: run.score, wave: max(run.wave, 1), lives: run.rider.lives,
                            saved: run.colonistsSaved, lampsOut: run.isLampsOut)
    }

    // MARK: Sound and haptics

    /// The director thins a frame's events (one sound per kind per frame, flaps and the other
    /// small sounds of flight spaced and hushed after an urgent cue) and picks a flap's pitch;
    /// the theme names the patch. The synth then applies each patch's cooldown, copy limit and
    /// priority.
    func sound(for event: RiftwingEvent) -> SoundPatch? {
        guard let variant = soundDirector.variant(for: event, in: session.run) else { return nil }
        return theme.sound(for: event, variant: variant)
    }

    /// Nothing for a flap or the rest of flight; see `HapticCue.cue(for:)` in RiftwingCore.
    func hapticCue(for event: RiftwingEvent) -> HapticCue? {
        HapticCue.cue(for: event)
    }

    /// Stereo position across the gallery; everything is in view, so full loudness, except
    /// flaps, which vary a little in level (by the run's tick, so the same every run) and with
    /// their three pitches never sound like a machine.
    func placement(for event: RiftwingEvent) -> (pan: Double, gain: Double) {
        guard let x = position(of: event)?.x else { return (0, 1) }
        let pan = min(max(x / tuning.width * 2 - 1, -1), 1)
        if case .flapped(_, false) = event {
            let tick = session.run.tick
            return (pan, 0.84 + 0.16 * Double((tick &* 2_654_435_761) >> 7 & 0xFF) / 255)
        }
        return (pan, 1)
    }

    /// Tension while a wave is fought, calm in the break, the dark mood with the lamps out
    /// (`RiftwingMoodDirector`).
    func musicMood(elapsed: Double) -> MusicMood {
        moodDirector.update(run: session.run)
    }

    var currentMusicMood: MusicMood { moodDirector.mood }

    #if DEBUG
    // MARK: Debug

    static let autopilot = ProcessInfo.processInfo.arguments.contains("-autopilot")
    /// `-autopilot idle|novice|competent` picks the test pilot, or any other `RiftwingPilot.Skill`
    /// by name (the exploit bots, e.g. `ventRider`). `shooter`, the other modes' fighting bot
    /// that never rescues, has no Riftwing twin and flies the competent pilot, as does anything
    /// unknown.
    static let autopilotSkill: RiftwingPilot.Skill = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-autopilot"), arguments.indices.contains(flag + 1) else {
            return .competent
        }
        return RiftwingPilot.Skill(rawValue: arguments[flag + 1]) ?? .competent
    }()
    var pilot = RiftwingPilot(skill: RiftwingMode.autopilotSkill, seed: 1)
    /// The run's tick when the pilot was last asked.
    var pilotTick = 0

    /// The pilot keeps its own time in steps, one call a step (as the harness drives it), but the
    /// shell asks for one input a frame and steps the run two or more times with it. So it is
    /// asked once for each step the last frame took (the same this frame, at a steady rate), and
    /// a flap from any of those calls is pressed for the frame. It lets go between flaps for
    /// longer than a frame, so each flap still reaches the run as a separate press.
    func autopilotInput() -> RiftwingInput {
        let run = session.run
        let steps = min(max(run.tick - pilotTick, 1), 4)
        pilotTick = run.tick
        var input = RiftwingInput()
        var flap = false
        for _ in 0..<steps {
            input = pilot.input(for: run)
            flap = flap || input.flap
        }
        input.flap = flap
        return input
    }

    /// A whole-number launch argument (`-lampsOutAtWave 2`, `-startAtWave 7`), 1 or more.
    static func debugInt(_ name: String) -> Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: name), arguments.indices.contains(flag + 1),
              let value = Int(arguments[flag + 1]), value >= 1 else { return nil }
        return value
    }

    /// A seconds launch argument (`-breathAfter 5`), above 0.
    static func debugDouble(_ name: String) -> Double? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: name), arguments.indices.contains(flag + 1),
              let value = Double(arguments[flag + 1]), value > 0 else { return nil }
        return value
    }

    var isReadyToStartRun: Bool { pointsPerUnit > 0 }

    func debugStats() -> String {
        let run = session.run
        return String(format: "wave %d, opponents %d, pods %d, mines %d, particles %d, score %d, lives %d",
                      run.wave, run.opponents.count, run.podsInPlay, run.mines.count, effects.activeParticles,
                      run.score, run.rider.lives)
    }
    #endif
}
