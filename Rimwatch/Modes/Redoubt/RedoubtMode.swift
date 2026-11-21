import Foundation
import GameCore
import RedoubtCore
import SpriteKit
import UIKit

/// Redoubt plugged into the shell: draws the dome floor, one pooled sprite per enemy, shot,
/// arrival and colonist, the HUD strip, callouts and twin-stick touch controls.
///
/// Layout: a thin HUD strip across the top (split either side of the crease when the phone is
/// open, with the shell's pause button at its right end). The 900 x 600 arena is scaled to fit
/// below it, centred, as large as it will go: the arena layer's origin is the floor's bottom-left
/// corner and its scale is points per arena unit, so entities are placed at their arena
/// positions directly. The arena may span the crease; text and controls stay out of it.
///
/// Every frame reads the live session once, then walks the run's arrays in plain loops, handing
/// each entity a sprite from a fixed pool by index. No per-entity work goes through a protocol
/// existential or a closure.
@MainActor
final class RedoubtMode: GameMode {
    typealias Run = RedoubtRun

    static let descriptor = ModeDescriptor.redoubt
    static var shellStyle: ShellStyle { CalderDome().shellStyle }
    /// Silent until step 13c fills in the theme's sounds and music; the routing is already live.
    static var audio: ModeAudio {
        let theme = CalderDome()
        return ModeAudio(sounds: theme.allSounds, music: theme.music)
    }

    static func makeSession(seed: UInt64) -> RedoubtSession {
        RedoubtSession(seed: seed)
    }

    // Pool sizes: the run caps enemies at 120; 13a measured up to 92 arrivals and 31 shots at once.
    static let enemyPool = 128
    static let arrivalPool = 112
    /// Worst case 53 at once: 8 Spitters each firing at most every 1.3 s (0.9 s fastest interval
    /// plus the 0.4 s wind-up) with 6 s shots is 40, plus the orb's 10 a second that reach a wall
    /// within 1.2 s, 13. Enemy shots are drawn first in any case.
    static let shotPool = 80
    static let colonistPool = 12
    static let linkPool = 24

    let services: ShellServices
    /// Reads the live session. Never keep what it returns: it would make every step copy the run.
    let currentSession: () -> RedoubtSession
    let root = SKNode()
    let theme = CalderDome()
    /// The session's tuning, which never changes, kept so frame code doesn't read it through the
    /// session closure.
    let tuning: RedoubtTuning
    let factory: GlowShapeFactory
    let glyphs: RedoubtGlyphs
    var session: RedoubtSession { currentSession() }
    var runID = 0

    // Layers. The arena layer is in arena units; the rest are in screen points.
    let arenaLayer = SKNode()
    let entityLayer = SKNode()
    let decorLayer = SKNode()
    let floorSprite = SKSpriteNode()
    let wallSprite = SKSpriteNode()
    let airlockMask = SKSpriteNode(color: .black, size: CGSize(width: 1, height: 1))
    let airlockSprite = SKSpriteNode()
    let beacon = SKSpriteNode()
    let darkness = SKSpriteNode()
    let effects = RedoubtEffects()
    let callouts: RedoubtCallouts
    let hud: RedoubtHUD
    let controls: RedoubtTouchControls

    /// A sprite that remembers what it was last dressed as, so textures change only on a change.
    final class PoolSprite: SKSpriteNode {
        /// Not yet given any look: the next sync always dresses it.
        static let undressed = -1
        var look = PoolSprite.undressed
    }

    var enemySprites: [PoolSprite] = []
    var arrivalSprites: [PoolSprite] = []
    var shotSprites: [PoolSprite] = []
    var colonistSprites: [PoolSprite] = []
    var linkSprites: [SKSpriteNode] = []
    let orbSprite = SKSpriteNode()
    /// A faint wide ring round the orb, so it can be found in a crowd at a glance.
    let orbHalo = SKSpriteNode()
    let orbShield = SKSpriteNode()
    let muzzle = SKSpriteNode()
    /// Shown at the centre while the orb is about to come back.
    let respawnMarker = SKSpriteNode()
    /// Sprites in use last frame, so the rest are hidden only when the count drops.
    var shownEnemies = 0, shownArrivals = 0, shownShots = 0, shownColonists = 0, shownLinks = 0

    /// When each enemy was last hit, for the hit pulse (only recently hit ones are kept).
    var hitAt: [Int: TimeInterval] = [:]
    var muzzleGlow: CGFloat = 0
    /// 0 lit ... 1 power cut, gliding so the lights go down and come back rather than switch.
    var darkMix = 0.0
    var shake: CGFloat = 0
    var beaconPhase = 0.0
    var airlockLook = -1
    /// Glyphs for the frame loop, looked up once per scale (see `makeLooks`).
    var looks = Looks()
    #if DEBUG
    /// Pools already reported as too small this run.
    var overflowedPools: Set<String> = []
    #endif
    var decor: [(sprite: SKSpriteNode, phase: Double, speed: Double, radius: Double)] = []

    var pointsPerUnit: CGFloat = 0
    /// The arena's bottom-left corner on screen.
    var arenaOrigin: CGPoint = .zero
    var stripRect: CGRect = .zero
    var needsPrewarm = false

    var size: CGSize { services.geometry.size }
    var safeAreaInsets: UIEdgeInsets { services.geometry.safeArea }
    var keepClear: ClosedRange<CGFloat>? { services.geometry.keepClear }
    var clock: TimeInterval { services.clock }

    init(services: ShellServices, session: @escaping () -> RedoubtSession) {
        self.services = services
        currentSession = session
        tuning = session().tuning
        factory = services.factory
        glyphs = RedoubtGlyphs(factory: factory, theme: theme)
        callouts = RedoubtCallouts(subtitleColor: theme.palette.hud)
        hud = RedoubtHUD(theme: theme, factory: factory)
        controls = RedoubtTouchControls(factory: factory, palette: theme.palette,
                                        chargeShape: theme.shape(for: .charge), maxCharges: tuning.maxCharges)
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
        let arena = CGSize(width: tuning.arenaWidth, height: tuning.arenaHeight)
        let ppu = max(min(available.width / arena.width, available.height / arena.height), 0.05)
        arenaOrigin = CGPoint(x: (available.midX - arena.width * ppu / 2).rounded(),
                              y: (available.minY + (available.height - arena.height * ppu) / 2).rounded())
        arenaLayer.position = arenaOrigin
        arenaLayer.setScale(ppu)

        if abs(ppu - pointsPerUnit) > 0.0001 {
            pointsPerUnit = ppu
            factory.clear()
            looks = Looks()
            buildArena()
            dressPools()
            effects.setPointsPerUnit(ppu, factory: factory, arena: arena)
            buildDecor()
            needsPrewarm = true
        }

        let middleLow = geometry.keepClear?.lowerBound ?? size.width / 2
        let middleHigh = geometry.keepClear?.upperBound ?? size.width / 2
        let gap: CGFloat = 10
        hud.layout(strip: stripRect, left: (stripRect.minX + 4)...(middleLow - gap),
                   right: (middleHigh + gap)...max(middleHigh + gap + 1, pauseButtonFrame.minX + 4),
                   maxLives: tuning.maxLives, maxCharges: tuning.maxCharges)
        controls.layout(size: size, safeArea: geometry.safeArea, keepClear: geometry.keepClear)
        callouts.layout(size: size, playfield: CGRect(origin: arenaOrigin, size: CGSize(width: arena.width * ppu,
                                                                                        height: arena.height * ppu)),
                        keepClear: geometry.keepClear)
        if needsPrewarm {
            needsPrewarm = false
            return true
        }
        return false
    }

    /// Screen point for an arena position.
    func screenPoint(_ p: Vec2) -> CGPoint {
        CGPoint(x: arenaOrigin.x + CGFloat(p.x) * pointsPerUnit, y: arenaOrigin.y + CGFloat(p.y) * pointsPerUnit)
    }

    // MARK: Screens

    func present(_ state: ScreenState?) {
        guard let state else {
            for node in [arenaLayer, callouts, hud, controls] as [SKNode] { node.isHidden = true }
            return
        }
        let screen = state.screen
        let inPlay: Bool = switch screen {
        case .playing, .countdown: true
        default: false
        }
        if state.showsBackdrop {
            arenaLayer.isHidden = false
            arenaLayer.alpha = screen == .title ? 0.32 : 0.22
        } else {
            switch screen {
            case .playing, .countdown:
                arenaLayer.isHidden = false
                arenaLayer.alpha = 1
            case .paused, .gameOver, .options, .highScores:
                arenaLayer.isHidden = !state.hasRun
                arenaLayer.alpha = 0.22
            case .title, .madeForDuo:
                arenaLayer.isHidden = true
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
        pilot = RedoubtPilot(skill: Self.autopilotSkill, seed: UInt64(runID))
        #endif
        effects.removeAll()
        callouts.removeAll()
        hitAt.removeAll()
        #if DEBUG
        overflowedPools.removeAll()
        #endif
        darkMix = 0
        shake = 0
        muzzleGlow = 0
        hideAllPooled()
    }

    func prewarm() {
        guard pointsPerUnit > 0 else { return }
        dressPools()
        let palette = theme.palette
        for role in RedoubtRole.allCases {
            _ = glyphs.glyph(.enemy(role), pointsPerUnit: pointsPerUnit)
        }
        _ = glyphs.glyph(.enemy(.spitter), tint: windUpColor, pointsPerUnit: pointsPerUnit)
        _ = glyphs.glyph(.colonist, tint: palette.warning, pointsPerUnit: pointsPerUnit)
        _ = glyphs.glyph(.airlockShut, pointsPerUnit: pointsPerUnit)
        _ = glyphs.glyph(.airlockOpen, pointsPerUnit: pointsPerUnit)
        _ = GlowText.texture("+500", style: .item(callouts.textSize * 1.3), color: palette.reward)
        for word in ["HELP!", "LOST", "CRUSHED", "FREED", "HUSK", "LINE SCATTERED"] {
            _ = GlowText.texture(word, style: .item(callouts.textSize * 0.9), color: palette.warning)
        }
        callouts.prewarmBanner("WAVE 1", subtitle: "6 colonists. Lead them to the airlock.", color: palette.heading)
        callouts.prewarmBanner("WAVE 1 CLEAR", subtitle: "Survivor bonus +1,500", color: palette.hud)
        callouts.prewarmBanner("POWER CUT", subtitle: "Deliver a colonist to bring the lights back", color: palette.warning)
        let run = session.run
        hud.update(readout(run), time: clock)
        warmRenderer()
    }

    // MARK: Frame

    func input(pad: PadReader?, options: GameOptions) -> RedoubtInput {
        #if DEBUG
        if Self.autopilot { return pilot.input(for: session.run) }
        #endif
        if let pad { return RedoubtInput(pad: pad) }
        return controls.input
    }

    func update(events: [RedoubtEvent], elapsed: Double, state: ScreenState) {
        if state.showsBackdrop {
            updateBackdrop(min(elapsed, 0.1))
        } else if !arenaLayer.isHidden {
            let run = session.run
            handle(events, run: run)
            sync(run, elapsed: min(elapsed, 0.1), screen: state.screen)
        }
    }

    func updateOverlays(elapsed: Double) {
        guard !hud.isHidden else { return }
        hud.update(readout(session.run), time: clock)
        callouts.update(elapsed: elapsed)
    }

    func readout(_ run: RedoubtRun) -> RedoubtHUD.Readout {
        // Before the first wave, the wave about to start.
        RedoubtHUD.Readout(score: run.score, wave: max(run.wave, 1), lives: run.orb.lives, charges: run.orb.charges,
                           colonists: run.colonistsLeft, colonistAlarm: Self.colonistAlarm(run))
    }

    /// The colonist count is shown as a warning only in danger: the power is out or due to fail
    /// when the next wave starts (`powerCutPending`), every colonist still in play is in a
    /// Gleaner's grip, or none are left and none got out this wave. None left after deliveries
    /// is calm.
    static func colonistAlarm(_ run: RedoubtRun) -> Bool {
        // Out, or due out when the next wave starts (through the break, when the next wave's
        // colonists are already on the floor).
        if run.isPowerCut || run.powerCutPending { return true }
        var inPlay = 0, seized = 0, delivered = 0
        for colonist in run.colonists {
            switch colonist.state {
            case .sheltering, .following: inPlay += 1
            case .seized:
                inPlay += 1
                seized += 1
            case .delivered: delivered += 1
            case .lost: break
            }
        }
        if inPlay > 0 { return seized == inPlay }
        return !run.colonists.isEmpty && delivered == 0
    }

    // MARK: Sound and haptics (filled in by step 13c)

    func sound(for event: RedoubtEvent) -> SoundPatch? {
        theme.sound(for: event)
    }

    func hapticCue(for event: RedoubtEvent) -> HapticCue? {
        HapticCue.cue(for: event)
    }

    /// Stereo position across the floor; everything on the floor is in view, so full loudness.
    func placement(for event: RedoubtEvent) -> (pan: Double, gain: Double) {
        guard let x = position(of: event)?.x else { return (0, 1) }
        return (min(max(x / tuning.arenaWidth * 2 - 1, -1), 1), 1)
    }

    /// A first mood rule until 13c brings a mood director: the power cut is the dark mood.
    func musicMood(elapsed: Double) -> MusicMood {
        currentMusicMood = session.run.isPowerCut ? .blackout : .calm
        return currentMusicMood
    }

    private(set) var currentMusicMood: MusicMood = .calm

    #if DEBUG
    // MARK: Debug

    static let autopilot = ProcessInfo.processInfo.arguments.contains("-autopilot")
    /// `-autopilot idle|novice|competent|shooter` picks the test pilot; anything else flies the competent one.
    static let autopilotSkill: RedoubtPilot.Skill = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-autopilot"), arguments.indices.contains(flag + 1) else {
            return .competent
        }
        return RedoubtPilot.Skill(rawValue: arguments[flag + 1]) ?? .competent
    }()
    var pilot = RedoubtPilot(skill: RedoubtMode.autopilotSkill, seed: 1)

    var isReadyToStartRun: Bool { pointsPerUnit > 0 }

    func debugStats() -> String {
        let run = session.run
        return String(format: "wave %d, enemies %d, arrivals %d, shots %d, particles %d, score %d, lives %d",
                      run.wave, run.enemies.count, run.arrivals.count, run.shots.count, effects.activeParticles,
                      run.score, run.orb.lives)
    }
    #endif
}
