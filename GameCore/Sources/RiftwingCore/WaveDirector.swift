import GameCore

/// Decides what each Riftwing wave sends and how gently each role flies in it.
///
/// - **One table.** `composition(forWave:)` is the only record of who comes in which wave.
///   Everything else is derived from it: each role's debut wave, and how many times a role has
///   been sent before (`appearance(of:inWave:)`), which sets its ease.
/// - **A handful at a time.** A wave's rigs are sent through the tunnel mouths a few at a time:
///   at most `concurrency(forWave:)` rigs in the gallery or on their way in (hatched ones
///   included), the next sent `sendGap` seconds after a place comes free.
/// - **Gleaners come late and singly.** Each wave's Gleaners are sent one at a time, the first
///   `gleanerDelay(forWave:)` seconds into the wave, and only while a pod rests on a ledge.
/// - **Each role's early appearances are gentler,** counted in that role's own appearances
///   (first, second, third time sent): `ease(of:inWave:)` steps down `rampEase`, so no role is a
///   cliff when it returns after a wave away.
///
/// The numbers had a first tuning pass with the scripted pilots in `RiftwingPilot` (see
/// `RiftwingDifficultyTests` and the harness's `riftwing` mode).
public struct RiftwingWaves: Sendable {
    public init() {}

    /// How much of a role's ease is left in each of its appearances, first to last; 0 after
    /// the last entry. Steps of at most 0.3 and a last step of 0.1, so it fades rather than
    /// stops: a role is at full strength from its seventh appearance.
    public var rampEase: [Double] = [1, 0.7, 0.5, 0.35, 0.2, 0.1]

    /// In a role's first appearances it must be this many units more clearly above the rider to
    /// win a clash (times its ease: the full amount in its first appearance, none at full
    /// strength); otherwise the meeting bounces. Winning is unchanged.
    public var clashLeniency = 16.0

    /// A pod from a role in its first appearances falls this share more slowly (times the
    /// role's ease), so an early mid-air catch is within reach and fewer early pods reach the
    /// Rift.
    public var podFallEase = 0.8

    /// Rigs in the gallery (or on their way in) at once, by wave (wave 1 first; the last entry
    /// holds for every later wave).
    public var concurrency: [Int] = [2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6]
    /// Seconds between one rig's place coming free and the next being sent.
    public var sendGap = 1.2
    /// Seconds between the opening rigs' telegraphs.
    public var openingGap = 0.6

    /// Gleaners: the first comes `gleanerDelayBase` plus `gleanerDelayEase` times its ease
    /// seconds into the wave (22 s in its debut, 8 s at full strength); a later one in the same
    /// wave `gleanerGap` seconds after the one before left.
    public var gleanerDelayBase = 8.0
    public var gleanerDelayEase = 14.0
    public var gleanerGap = 8.0
    /// At its fullest ease a Gleaner flies `gleanerSlowdown` times more slowly, holds a pod
    /// `gleanerGrabEase` seconds longer before lifting it, and a carry takes at least
    /// `gleanerCarryEase` seconds longer.
    public var gleanerSlowdown = 2.0
    public var gleanerGrabEase = 1.5
    public var gleanerCarryEase = 4.0

    /// Glider: at its fullest ease, this much slower and skipping this much more of its flaps.
    public var gliderSpeedEase = 0.25
    public var gliderSkipEase = 0.15
    /// ... wandering no higher than this much below the top of its band, and this much more
    /// likely to skip a flap that would lift it into a rider just above it.
    public var gliderBandEase = 140.0
    public var gliderShyEase = 1.0
    /// Striker: at its fullest ease, this much slower, climbing this share less high above the
    /// rider before coming down, reaching this share less far across to come down, and taking
    /// this many seconds longer over each decision.
    public var strikerSpeedEase = 0.3
    public var strikerClimbEase = 0.6
    public var strikerReachEase = 0.3
    public var strikerReplanEase = 0.35
    /// ... and recovering this share longer after each strike.
    public var strikerRecoverEase = 1.0
    /// Warden: at its fullest ease, this much slower, this share less likely to dive when it
    /// could, and this much slower to decide.
    public var wardenSpeedEase = 0.3
    public var wardenDiveEase = 0.6
    public var wardenReplanEase = 0.3
    /// Sower: at its fullest ease, its mines come this share less often, it holds this many
    /// fewer at once, and it drifts this much more slowly.
    public var sowerIntervalEase = 0.8
    public var sowerMinesEase = 2.0
    public var sowerSpeedEase = 0.25

    // MARK: The table

    /// The opponents a wave sends, all roles: the single table every count and ease is derived
    /// from. Waves 1 to 10 are written out; from wave 11 every role grows slowly to a cap. No two
    /// roles debut in the same wave.
    public func composition(forWave wave: Int) -> [(role: RiftwingRole, count: Int)] {
        let early: [[(RiftwingRole, Int)]] = [
            [(.glider, 4)],                                                  // 1
            [(.glider, 5)],                                                  // 2
            [(.glider, 3), (.striker, 2)],                                   // 3: Strikers
            [(.glider, 2), (.striker, 3), (.gleaner, 1)],                    // 4: Gleaners
            [(.glider, 3), (.striker, 3), (.gleaner, 1)],                    // 5
            [(.glider, 2), (.striker, 2), (.warden, 1), (.gleaner, 1)],      // 6: Wardens
            [(.glider, 2), (.striker, 3), (.warden, 1), (.gleaner, 1)],      // 7
            [(.glider, 2), (.striker, 3), (.warden, 1), (.sower, 1), (.gleaner, 1)], // 8: Sowers
            [(.glider, 2), (.striker, 3), (.warden, 2), (.gleaner, 1)],      // 9
            [(.glider, 2), (.striker, 3), (.warden, 2), (.sower, 1), (.gleaner, 2)], // 10
        ]
        guard wave >= 1 else { return [] }
        if wave <= early.count {
            return early[wave - 1].map { (role: $0.0, count: $0.1) }
        }
        let past = wave - 11
        let strikers: Int = min(3 + past / 3, 5)
        let wardens: Int = min(2 + (past + 1) / 3, 4)
        let sowers: Int = min(1 + past / 4, 2)
        let gleaners: Int = min(2 + past / 4, 3)
        let late: [(role: RiftwingRole, count: Int)] = [
            (role: .glider, count: 2), (role: .striker, count: strikers), (role: .warden, count: wardens),
            (role: .sower, count: sowers), (role: .gleaner, count: gleaners),
        ]
        return late
    }

    /// How many of `role` a wave sends.
    public func count(of role: RiftwingRole, inWave wave: Int) -> Int {
        composition(forWave: wave).first { $0.role == role }?.count ?? 0
    }

    /// The first wave that sends `role`, from the table.
    public func debut(of role: RiftwingRole) -> Int? {
        (1...60).first { count(of: role, inWave: $0) > 0 }
    }

    /// Which of `role`'s appearances a wave is: 0 the first wave that sends it, 1 the next wave
    /// that sends it, and so on; nil for a wave that does not send it.
    public func appearance(of role: RiftwingRole, inWave wave: Int) -> Int? {
        guard count(of: role, inWave: wave) > 0 else { return nil }
        return (1..<max(wave, 1)).count { count(of: role, inWave: $0) > 0 }
    }

    /// How much of a role's ease is left in a wave: 1 in its first appearance, stepping down
    /// `rampEase` to 0. A role not sent in the wave (one hatched from a pod) flies at the ease of
    /// its next appearance, or 0.
    public func ease(of role: RiftwingRole, inWave wave: Int) -> Double {
        let index = appearance(of: role, inWave: wave)
            ?? (1..<max(wave, 1)).count { count(of: role, inWave: $0) > 0 }
        guard index < rampEase.count else { return 0 }
        return min(max(rampEase[index], 0), 1)
    }

    /// The rigs a wave sends, in the order they are sent: round the roles in table order, so a
    /// newcomer comes in among the others.
    public func rigs(forWave wave: Int) -> [RiftwingRole] {
        var left = composition(forWave: wave).filter { $0.role.isRig }
        var order: [RiftwingRole] = []
        while left.contains(where: { $0.count > 0 }) {
            for index in left.indices where left[index].count > 0 {
                order.append(left[index].role)
                left[index].count -= 1
            }
        }
        return order
    }

    /// Rigs at once in a wave.
    public func concurrency(forWave wave: Int) -> Int {
        guard !concurrency.isEmpty else { return 4 }
        return max(concurrency[min(max(wave - 1, 0), concurrency.count - 1)], 1)
    }

    // MARK: Pods

    /// Seconds a pod rests before hatching in a wave: long at first, shrinking each wave to a
    /// floor (15 s in wave 1, 0.8 s less a wave, 7 s from wave 11).
    public func podLife(forWave wave: Int, tuning: RiftwingTuning) -> Double {
        max(tuning.podLifeFloor, tuning.podLifeFirst - tuning.podLifeShrink * Double(max(wave - 1, 0)))
    }

    // MARK: Gleaners

    /// Seconds into a wave its first Gleaner is sent.
    public func gleanerDelay(forWave wave: Int) -> Double {
        gleanerDelayBase + gleanerDelayEase * ease(of: .gleaner, inWave: wave)
    }

    /// Gleaner flying speed in a wave, as a multiple of the tuning's.
    public func gleanerSpeedScale(forWave wave: Int) -> Double {
        1 / (1 + (max(gleanerSlowdown, 1) - 1) * ease(of: .gleaner, inWave: wave))
    }

    /// Seconds a Gleaner holds a pod before lifting it in a wave.
    public func gleanerGrab(forWave wave: Int, tuning: RiftwingTuning) -> Double {
        tuning.gleanerGrab + gleanerGrabEase * ease(of: .gleaner, inWave: wave)
    }

    /// The least time a carry takes from the lift to the tunnel mouth in a wave.
    public func gleanerMinCarry(forWave wave: Int, tuning: RiftwingTuning) -> Double {
        tuning.gleanerMinCarry + gleanerCarryEase * ease(of: .gleaner, inWave: wave)
    }
}
