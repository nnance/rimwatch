import GameCore
import UIKit

/// What the scene talks to: one running mode with its screen flow.
@MainActor
protocol ModeDriver: AnyObject {
    var descriptor: ModeDescriptor { get }
    /// Adds the mode and the shell's chrome to the scene, gives the synth the mode's sounds, lays out.
    func attach()
    /// Takes everything `attach` added back out of the scene and lets go of input. The scene
    /// drops the driver afterwards.
    func detach()
    func layout()
    func setPose(_ pose: FoldPose)
    /// Starts a run from the title, as choosing the mode there does (after a mode switch).
    func startRun()
    /// A controller connected or went away.
    func gamepadChanged(_ change: GamepadInput.Change)
    func appWillResignActive()
    func frame(currentTime: TimeInterval)
    #if DEBUG
    func didFinishUpdate()
    #endif
    func touchesBegan(_ touches: Set<UITouch>)
    func touchesMoved(_ touches: Set<UITouch>)
    func touchesEnded(_ touches: Set<UITouch>, cancelled: Bool)
}
