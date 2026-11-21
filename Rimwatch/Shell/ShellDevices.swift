import GameCore

/// The devices the app keeps for its whole life, whichever mode is loaded: one audio engine, the
/// game controller and the haptic players. The scene owns them; the running mode's host borrows
/// them and gives the synth its mode's sounds. Keeping them here means switching modes never
/// restarts the audio engine, re-registers controller observers or flashes "Controller connected".
@MainActor
final class ShellDevices {
    let synth: Synth
    let gamepad = GamepadInput()
    let haptics = HapticRouter()

    init(options: GameOptions) {
        synth = Synth(options: options)
    }
}
