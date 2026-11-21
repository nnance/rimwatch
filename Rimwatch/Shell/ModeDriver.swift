import GameCore
import UIKit

/// What the scene talks to: one running mode with its screen flow.
@MainActor
protocol ModeDriver: AnyObject {
    var descriptor: ModeDescriptor { get }
    /// Adds the mode and the shell's chrome to the scene, starts listening, lays out.
    func attach()
    func layout()
    func setPose(_ pose: FoldPose)
    func appWillResignActive()
    func frame(currentTime: TimeInterval)
    #if DEBUG
    func didFinishUpdate()
    #endif
    func touchesBegan(_ touches: Set<UITouch>)
    func touchesMoved(_ touches: Set<UITouch>)
    func touchesEnded(_ touches: Set<UITouch>, cancelled: Bool)
}
