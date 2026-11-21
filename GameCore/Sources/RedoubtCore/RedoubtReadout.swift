import GameCore

/// What the HUD reads from a run beyond its plain counters. Kept here, apart from drawing, so a
/// test can pin the rules.
extension RedoubtRun {
    /// The colonist count shows as a warning (red, blinking) only in danger: the power is out,
    /// or due to fail when the next wave starts (`powerCutPending`, through the break, when the
    /// next wave's colonists are already on the floor); every colonist still in play is in a
    /// Gleaner's grip; or none are left and none got out this wave. None left after deliveries
    /// is calm.
    public var colonistAlarm: Bool {
        if isPowerCut || powerCutPending { return true }
        var inPlay = 0, seized = 0, delivered = 0
        for colonist in colonists {
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
        return !colonists.isEmpty && delivered == 0
    }
}
