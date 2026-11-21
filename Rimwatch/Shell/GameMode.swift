import GameCore
import SpriteKit
import UIKit

/// A mode's touch controls, as far as the shell drives them: visibility, handedness, touches,
/// and letting go.
protocol TouchControlSurface: SKNode {
    var handedness: GameOptions.Handedness { get set }
    func touchesBegan(_ touches: Set<UITouch>)
    func touchesMoved(_ touches: Set<UITouch>)
    func touchesEnded(_ touches: Set<UITouch>)
    /// Forgets presses that have reached a simulation step.
    func consumePresses()
    func releaseAll()
}

/// The scene's size and the parts of it to keep clear, in scene points.
struct ShellGeometry {
    var size: CGSize
    var safeArea: UIEdgeInsets
    /// Scene x range of the crease on an open Duo, kept clear of controls and menu items.
    var keepClear: ClosedRange<CGFloat>?
    var screenScale: CGFloat
}

/// What the shell is showing, for the mode to show its layers to match.
struct ScreenState {
    let screen: FlowScreen
    /// A run is on or has just ended (its world stays dimly behind the menus).
    let hasRun: Bool
    /// The screens have no run behind them: the mode draws its backdrop instead of a game.
    let showsBackdrop: Bool
    let hasMenu: Bool
}

/// The sound patches and music a mode plays.
struct ModeAudio {
    let sounds: [SoundPatch]
    let music: MusicStyle?
}

/// A game mode as the shell runs it. The shell owns the session, the screen flow, menus, pause,
/// audio, haptics and input devices; the mode draws its run and says how it sounds and feels.
protocol GameMode: AnyObject {
    associatedtype Run: ModeRun

    static var descriptor: ModeDescriptor { get }
    /// The shell's look while this mode runs.
    static var shellStyle: ShellStyle { get }
    static var audio: ModeAudio { get }
    static func makeSession(seed: UInt64) -> ModeSession<Run>

    /// `session` reads the live session. Never store what it returns: holding a copy would make
    /// every step copy the run's arrays.
    init(services: ShellServices, session: @escaping () -> ModeSession<Run>)

    /// Added to the scene at z 0; its children stay below the shell's chrome (z 110 and up).
    var root: SKNode { get }
    var touchControls: (any TouchControlSurface)? { get }
    /// Play-only layers drawn faintly while the renderer warms up.
    var warmUpNodes: [SKNode] { get }

    /// The top of the playfield; the pause button hangs below it.
    func playfieldTop(in geometry: ShellGeometry) -> CGFloat
    /// Lays the mode out for the scene's geometry. True when its drawing scale changed and it
    /// should prewarm.
    func layout(in geometry: ShellGeometry, pauseButtonFrame: CGRect) -> Bool
    /// Renders glyphs and text and draws one of each kind of node now, while a menu is up.
    func prewarm()
    /// Shows the layers the screen needs; nil while the pose is unknown (show nothing).
    func present(_ state: ScreenState?)
    /// A new run has started.
    func startRun()
    /// This frame's input: from `pad` when a controller is connected, otherwise touch.
    func input(pad: PadReader?, options: GameOptions) -> Run.Input
    /// The backdrop, or the camera, this frame's events and the entity nodes.
    func update(events: [Run.Event], elapsed: Double, state: ScreenState)
    /// HUD, scanner and callouts, after the screen is presented.
    func updateOverlays(elapsed: Double)

    func sound(for event: Run.Event) -> SoundPatch?
    func hapticCue(for event: Run.Event) -> HapticCue?
    /// Stereo position and loudness for where an event happened.
    func placement(for event: Run.Event) -> (pan: Double, gain: Double)
    /// The music while playing.
    func musicMood(elapsed: Double) -> MusicMood
    /// The music during the resume countdown.
    var currentMusicMood: MusicMood { get }

    #if DEBUG
    /// The autopilot waits for this before starting a run.
    var isReadyToStartRun: Bool { get }
    /// The mode's part of the performance log line.
    func debugStats() -> String
    #endif
}
