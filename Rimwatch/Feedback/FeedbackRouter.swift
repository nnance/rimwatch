import Foundation
import GameCore

/// Plays a theme's sound patches and music. `Synth` is the real one; `SilentSoundOutput` takes
/// every call and does nothing.
@MainActor
protocol SoundOutput: AnyObject {
    /// A gameplay sound. `gain` is 0...1 for where it happened (quieter off screen), on top of
    /// the sound option; `pan` is -1 (left) ... 1 (right).
    func play(_ patch: SoundPatch, gain: Double, pan: Double)
    /// A menu sound. Plays whether or not gameplay sound is on.
    func playMenu(_ patch: SoundPatch)
    /// The options' sound and music levels, 0...1. Takes effect at once.
    func setLevels(sound: Double, music: Double)
    /// Whether gameplay sounds may play. Off fades out whatever is sounding.
    func setGameplayActive(_ active: Bool)
    /// The music mood, or nil for silence. Changes fade.
    func setMusic(_ mood: MusicMood?)
    /// Called every frame, for fades.
    func update(elapsed: Double)
}

/// Plays a haptic cue. `HapticRouter` plays it with Core Haptics on a controller or the phone;
/// `SilentHapticOutput` does nothing. Returns where the cue went, for the debug log.
@MainActor
protocol HapticOutput: AnyObject {
    @discardableResult
    func play(_ cue: HapticCue) -> HapticRoute
}

@MainActor
final class SilentSoundOutput: SoundOutput {
    func play(_ patch: SoundPatch, gain: Double, pan: Double) {}
    func playMenu(_ patch: SoundPatch) {}
    func setLevels(sound: Double, music: Double) {}
    func setGameplayActive(_ active: Bool) {}
    func setMusic(_ mood: MusicMood?) {}
    func update(elapsed: Double) {}
}

@MainActor
final class SilentHapticOutput: HapticOutput {
    func play(_ cue: HapticCue) -> HapticRoute { HapticRoute(device: "none", note: "silent") }
}

/// Routes simulation events to sound and haptics: the theme names the sound for each event,
/// `HapticCue` names the feel, and the options decide whether and how loud. Nothing here knows
/// how a sound or a haptic is produced.
@MainActor
final class FeedbackRouter {
    var sound: any SoundOutput
    var haptics: any HapticOutput
    var options: GameOptions {
        didSet { sound.setLevels(sound: options.soundLevel, music: options.musicLevel) }
    }
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
        sound.setLevels(sound: options.soundLevel, music: options.musicLevel)
    }

    /// `placement` gives the stereo position of an event and how loud it should be for where it
    /// happened relative to the view. The synth logs what it actually starts or drops.
    func route(_ events: [GameEvent], placement: (GameEvent) -> (pan: Double, gain: Double)) {
        for event in events {
            if let patch = theme.sound(for: event), options.soundLevel > 0 {
                let place = placement(event)
                sound.play(patch, gain: place.gain, pan: place.pan)
            }
            if let cue = HapticCue.cue(for: event) { feel(cue, for: "\(event)") }
        }
    }

    /// Menu feedback for an accepted command: a sound, and a haptic tick when the selection or an
    /// option moves or a tap on activation.
    func menu(_ cue: HapticCue, sound menuSound: MenuSound) {
        if let patch = theme.menuSound(menuSound), options.soundLevel > 0 {
            sound.playMenu(patch)
        }
        feel(cue, for: "menu \(menuSound.rawValue)")
    }

    private func feel(_ cue: HapticCue, for reason: @autoclosure () -> String) {
        guard options.hapticsEnabled else {
            #if DEBUG
            if Self.logs {
                NSLog("[Rimwatch feedback] haptic %@ -> none (option off) [%@]", cue.rawValue, Self.short(reason()))
            }
            #endif
            return
        }
        let route = haptics.play(cue)
        #if DEBUG
        if Self.logs {
            NSLog("[Rimwatch feedback] haptic %@ -> %@ [%@]", cue.rawValue, route.description, Self.short(reason()))
        }
        #else
        _ = route
        #endif
    }

    #if DEBUG
    /// An event's case name without its payload.
    private static func short(_ text: String) -> String {
        String(text.prefix { $0 != "(" })
    }
    #endif
}
