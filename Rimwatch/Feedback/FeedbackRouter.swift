import Foundation
import GameCore

/// Plays a theme's sound patch. Step 7 provides the synthesiser; until then `SilentSoundOutput`
/// takes every call and does nothing.
@MainActor
protocol SoundOutput: AnyObject {
    /// `volume` is 0...1 (the options' sound level); `pan` is -1 (left) ... 1 (right).
    func play(_ patch: SoundPatch, volume: Double, pan: Double)
}

/// Plays a haptic cue. Step 6 provides Core Haptics; until then `SilentHapticOutput` does nothing.
@MainActor
protocol HapticOutput: AnyObject {
    func play(_ cue: HapticCue)
}

@MainActor
final class SilentSoundOutput: SoundOutput {
    func play(_ patch: SoundPatch, volume: Double, pan: Double) {}
}

@MainActor
final class SilentHapticOutput: HapticOutput {
    func play(_ cue: HapticCue) {}
}

/// Routes simulation events to sound and haptics: the theme names the sound for each event,
/// `HapticCue` names the feel, and the options decide whether and how loud. Nothing here knows
/// how a sound or a haptic is produced.
@MainActor
final class FeedbackRouter {
    var sound: any SoundOutput
    var haptics: any HapticOutput
    var options: GameOptions
    private let theme: any Theme

    #if DEBUG
    /// Launch with -logFeedback to log every routed sound and haptic (for simulator checks).
    private static let logs = ProcessInfo.processInfo.arguments.contains("-logFeedback")
    #endif

    init(theme: any Theme, options: GameOptions,
         sound: any SoundOutput = SilentSoundOutput(), haptics: any HapticOutput = SilentHapticOutput()) {
        self.theme = theme
        self.options = options
        self.sound = sound
        self.haptics = haptics
    }

    /// `pan` gives the stereo position of an event (from where it happened relative to the view).
    func route(_ events: [GameEvent], pan: (GameEvent) -> Double) {
        for event in events {
            if let patch = theme.sound(for: event), options.soundLevel > 0 {
                let side = pan(event)
                sound.play(patch, volume: options.soundLevel, pan: side)
                #if DEBUG
                if Self.logs, patch.name != "frontier.lance.fire" {
                    NSLog("[Rimwatch feedback] sound %@ pan %.2f", patch.name, side)
                }
                #endif
            }
            if options.hapticsEnabled, let cue = HapticCue.cue(for: event) {
                haptics.play(cue)
                #if DEBUG
                if Self.logs { NSLog("[Rimwatch feedback] haptic %@", cue.rawValue) }
                #endif
            }
        }
    }
}
