import Foundation
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
///   cliff when it returns after a wave away. Since 2026-11-22 the ease no longer slows or
///   gentles any opponent's flying (`withGentleDebuts` puts that back); it still eases the pods
///   an early opponent drops and the hatched rigs a diligent rider meets.
///
/// The numbers had a first tuning pass with the scripted pilots in `RiftwingPilot` (see
/// `RiftwingDifficultyTests` and the harness's `riftwing` mode).
public struct RiftwingWaves: Sendable {
    public init() {}

    /// How much of a role's ease is left in each of its appearances, first to last; 0 after
    /// the last entry. Small steps and a last step of 0.05, so it fades rather than stops: a
    /// role is at full strength from its thirteenth appearance.
    public var rampEase: [Double] = [1, 0.75, 0.62, 0.5, 0.4, 0.32, 0.25, 0.19, 0.14, 0.1, 0.06, 0.03]

    /// An opponent must be this many units more clearly above the rider than the clash margin
    /// to win a clash, at every strength (`clashLeniencyBase`), and `clashLeniency` more times
    /// its ease in its first appearances; otherwise the meeting bounces. Winning is unchanged.
    /// Contact comes at about 29 units between centres. Both are units at figure scale 1
    /// (`RiftwingTuning.figureScale`); the run scales them with the figures
    /// (`RiftwingRun.clashLeniency(ease:)`), since they are measured against a rig.
    ///
    /// `clashLeniencyBase` was 16.1 until 2026-11-22, when the owner reached wave 8 with little
    /// practice and asked for a typical game to end at wave 5 to 6. An even rule (0: the
    /// opponent needing only the clash margin, as the rider does) took the competent pilot from
    /// wave 12.8 to about 7.6 on its own, too far, so the rule was moved only part of the way to
    /// even: at 12, with every kind at full strength from its debut (see `withGentleDebuts`),
    /// the competent pilot reaches wave 8.7 (the owner had reached about 0.63 of its wave, so
    /// about wave 5.5 for the owner). `withGentleDebuts` puts 16.1 back.
    public var clashLeniency = 0.0
    public var clashLeniencyBase = 12.0
    /// In its first appearances an opponent that would win a clash may misjudge it, and the
    /// meeting bounces instead (`mercy(ease:)`): `clashMercy` of the time at its debut, fading
    /// with its ease as a ramp (`clashMercyCurve` shapes it so the share it wins at most doubles
    /// from one appearance to the next, with no step at its second), and never once its ease is
    /// down to `clashMercyFloor` (its eighth appearance). Drawn from the run's seeded random
    /// source, so a run still replays exactly.
    ///
    /// Off (0) since 2026-11-22: the owner played and never lost a life, and asked how hard it
    /// should be chose "No forgiveness at all: every lost clash costs a life in every wave." It
    /// was 0.85 (an opponent won only 15% of the clashes it should have won at its debut);
    /// `withBeginnerForgiveness` puts it back. The height leniency (`clashLeniencyBase`) is not
    /// forgiveness of a lost clash and stays: it decides which meetings are lost at all.
    public var clashMercy = 0.0
    public var clashMercyCurve = 0.45
    public var clashMercyFloor = 0.2
    /// In waves up to this one, an opponent always misjudges a clash it would win against a rider
    /// standing on a ledge, and any meeting with a standing rider leaves it on its ledge (the
    /// opponent alone is thrown away): a beginner standing still to work out the controls is
    /// neither beaten nor knocked into the Rift for it.
    ///
    /// Off (0) since 2026-11-22, for the same reason as `clashMercy` ("No forgiveness at all:
    /// every lost clash costs a life in every wave."): a rider standing in wave 1 is beaten and
    /// bounced like any other. It was 1; `withBeginnerForgiveness` puts it back.
    public var standingGraceWaves = 0

    /// The waves as they were between the two changes of 2026-11-22. In the second, the owner
    /// had reached wave 8 with little practice and asked for a typical game to end at wave 5 to
    /// 6, so: the clash leniency went from 16.1 to 12 (`clashLeniencyBase`); each kind flies at
    /// full strength from its first appearance (the `...Ease` numbers for Gliders, Strikers,
    /// Wardens, Sowers and Gleaners, set to 0); and early Warden dives no longer misjudge their
    /// line (`wardenMissEase` 55 to 0). The wave table and each kind's debut wave are unchanged.
    /// This puts all of that back; the beginner's forgiveness of lost clashes (the first change)
    /// stays out.
    public static var withGentleDebuts: RiftwingWaves {
        var waves = RiftwingWaves()
        waves.clashLeniencyBase = 16.1
        waves.gleanerDelayEase = 14
        waves.gleanerSlowdown = 2
        waves.gleanerGrabEase = 1.5
        waves.gleanerCarryEase = 4
        waves.gliderSpeedEase = 0.25
        waves.gliderSkipEase = 0.15
        waves.gliderBandEase = 140
        waves.gliderShyEase = 1
        waves.strikerSpeedEase = 0.3
        waves.strikerClimbEase = 0.6
        waves.strikerReachEase = 0.3
        waves.strikerReplanEase = 0.35
        waves.strikerRecoverEase = 1
        waves.wardenSpeedEase = 0.3
        waves.wardenDiveEase = 0.6
        waves.wardenReplanEase = 0.3
        waves.wardenMissEase = 55
        waves.sowerIntervalEase = 0.8
        waves.sowerMinesEase = 2
        waves.sowerSpeedEase = 0.25
        return waves
    }

    /// The waves with the beginner's forgiveness of lost clashes that was taken out on
    /// 2026-11-22: an opponent in its first appearances misjudging most clashes it would win
    /// (`clashMercy` 0.85), and a rider standing on a ledge in wave 1 never beaten and keeping
    /// its footing (`standingGraceWaves` 1), on top of `withGentleDebuts`. With this the game is
    /// exactly the one before both changes of that day.
    public static var withBeginnerForgiveness: RiftwingWaves {
        var waves = RiftwingWaves.withGentleDebuts
        waves.clashMercy = 0.85
        waves.standingGraceWaves = 1
        return waves
    }

    /// The chance that an opponent with `ease` left misjudges a clash it would have won:
    /// `clashMercy` times ((ease - floor) / (1 - floor)) raised to `clashMercyCurve`, 0 at or
    /// under the floor. With `withBeginnerForgiveness` (`clashMercy` 0.85) it wins 15%, 28%, 36%,
    /// 45%, 54%, 64%, 76% and then all of the clashes it would win in its first, second, third ...
    /// appearances; with the default (0) it wins all of them from its debut.
    public func mercy(ease: Double) -> Double {
        let floor = min(max(clashMercyFloor, 0), 0.99)
        let e = (min(max(ease, 0), 1) - floor) / (1 - floor)
        guard e > 0, clashMercy > 0 else { return 0 }
        let shaped = clashMercyCurve == 1 ? e : power(e, clashMercyCurve)
        return min(clashMercy * shaped, 1)
    }

    /// The extra height an opponent with `ease` left must have over the rider to win a clash.
    public func leniency(ease: Double) -> Double {
        clashLeniencyBase + clashLeniency * min(max(ease, 0), 1)
    }

    /// A rig hatched from a pod keeps its kind's early ease only for a rider who frees colonists:
    /// all of it once the rider has freed at least `hatchedEaseFullShare` of the colonists
    /// settled (freed or lost) in this wave and the last, none at or under `hatchedEaseNoShare`
    /// (a rider who leaves nearly every pod to hatch), in proportion between. A beginner slow to
    /// reach pods still frees about half of them or more and meets gentle hatchlings; a rider who
    /// leaves pods to hatch meets them at full strength. A full share of 0 gives every hatched
    /// rig its kind's full ease.
    public var hatchedEaseFullShare = 0.4
    public var hatchedEaseNoShare = 0.2

    /// The share of its kind's ease a hatched rig keeps, for a rider who has freed `freed` of the
    /// `settled` colonists of this wave and the last (`hatchedEaseFullShare`, `hatchedEaseNoShare`).
    public func hatchedEaseShare(freed: Int, settled: Int) -> Double {
        guard hatchedEaseFullShare > 0 else { return 1 }
        guard settled > 0 else { return 0 }
        let none = min(max(hatchedEaseNoShare, 0), hatchedEaseFullShare)
        let share = Double(freed) / Double(settled)
        guard share > none else { return 0 }
        return min((share - none) / max(hatchedEaseFullShare - none, 1e-9), 1)
    }

    /// A pod from a role in its first appearances falls this share more slowly (times the
    /// role's ease), so an early mid-air catch is within reach and fewer early pods reach the
    /// Rift.
    public var podFallEase = 0.9
    /// ... and drifts toward the nearest ledge below it at up to this speed across (times the
    /// role's ease), so fewer early pods are lost to the Rift while a new player is learning.
    public var podDriftEase = 150.0
    /// ... and, sinking near the Rift, is held up by its heat for this many seconds (times the
    /// role's ease) before it falls in.
    public var podHoverEase = 5.0
    /// The height above the Rift at which an eased pod is held up over open Rift (one dropped
    /// lower is held where it is). Chosen clear of every ledge's rock in all three layouts, with
    /// room for the pod: the gap between the low shelves (tops up to 175) and the middle ones
    /// (undersides from 221).
    public var podHoverHeight = 178.0

    /// Rigs in the gallery (or on their way in) at once, by wave (wave 1 first; the last entry
    /// holds for every later wave).
    public var concurrency: [Int] = [2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 6, 7, 7, 8, 8]
    /// Seconds between one rig's place coming free and the next being sent.
    public var sendGap = 1.2
    /// Seconds between the opening rigs' telegraphs.
    public var openingGap = 0.6

    // The opponents' early flying. Since 2026-11-22 every kind flies at full strength from its
    // first appearance (the owner reached wave 8 with little practice and asked for a typical
    // game to end at wave 5 to 6), so each number below is 0 (1 for `gleanerSlowdown`);
    // `withGentleDebuts` puts back the values given as "was", with which each kind flew more
    // slowly and gently in its first appearances, by its ease.

    /// Gleaners: the first comes `gleanerDelayBase` plus `gleanerDelayEase` times its ease
    /// seconds into the wave (8 s; was 14, for 22 s at a debut); a later one in the same wave
    /// `gleanerGap` seconds after the one before left.
    public var gleanerDelayBase = 8.0
    public var gleanerDelayEase = 0.0
    public var gleanerGap = 8.0
    /// At its fullest ease a Gleaner flies `gleanerSlowdown` times more slowly (was 2), holds a
    /// pod `gleanerGrabEase` seconds longer before lifting it (was 1.5), and a carry takes at
    /// least `gleanerCarryEase` seconds longer (was 4).
    public var gleanerSlowdown = 1.0
    public var gleanerGrabEase = 0.0
    public var gleanerCarryEase = 0.0

    /// Glider: at its fullest ease, this much slower (was 0.25) and skipping this much more of
    /// its flaps (was 0.15) ...
    public var gliderSpeedEase = 0.0
    public var gliderSkipEase = 0.0
    /// ... wandering no higher than this much below the top of its band (was 140), and this
    /// much more likely to skip a flap that would lift it into a rider just above it (was 1).
    public var gliderBandEase = 0.0
    public var gliderShyEase = 0.0
    /// Striker: at its fullest ease, this much slower (was 0.3), climbing this share less high
    /// above the rider before coming down (was 0.6), reaching this share less far across to come
    /// down (was 0.3), and taking this many seconds longer over each decision (was 0.35) ...
    public var strikerSpeedEase = 0.0
    public var strikerClimbEase = 0.0
    public var strikerReachEase = 0.0
    public var strikerReplanEase = 0.0
    /// ... and recovering this share longer after each strike (was 1).
    public var strikerRecoverEase = 0.0
    /// Warden: at its fullest ease, this much slower (was 0.3), this share less likely to dive
    /// when it could (was 0.6), and this much slower to decide (was 0.3) ...
    public var wardenSpeedEase = 0.0
    public var wardenDiveEase = 0.0
    public var wardenReplanEase = 0.0
    /// ... and misjudging its line by up to this many units across at its fullest ease (at
    /// least half of that, either side, drawn afresh for each dive), so that it dives beside the
    /// rider and fewer of its dives reach it. Contact comes at about 30 units. Units at figure
    /// scale 1: the run scales it with the figures. 0 since 2026-11-22, every Warden dive aimed
    /// at the rider (was 55).
    public var wardenMissEase = 0.0
    /// Sower: at its fullest ease, its mines come this share less often (was 0.8), it holds
    /// this many fewer at once (was 2), and it drifts this much more slowly (was 0.25).
    public var sowerIntervalEase = 0.0
    public var sowerMinesEase = 0.0
    public var sowerSpeedEase = 0.0

    // MARK: The table

    /// The opponents a wave sends, all roles: the single table every count and ease is derived
    /// from. Waves 1 to 10 are written out; from wave 11 every role grows to a cap. No two
    /// roles debut in the same wave.
    public func composition(forWave wave: Int) -> [(role: RiftwingRole, count: Int)] {
        let early: [[(RiftwingRole, Int)]] = [
            [(.glider, 4)],                                                  // 1
            [(.glider, 5)],                                                  // 2
            [(.glider, 3), (.striker, 2)],                                   // 3: Strikers
            [(.glider, 2), (.striker, 3), (.gleaner, 1)],                    // 4: Gleaners
            [(.glider, 2), (.striker, 3), (.gleaner, 1)],                    // 5
            [(.glider, 2), (.striker, 3), (.warden, 1), (.gleaner, 1)],      // 6: Wardens
            [(.glider, 2), (.striker, 3), (.warden, 1), (.gleaner, 1)],      // 7
            [(.glider, 2), (.striker, 3), (.warden, 1), (.sower, 1), (.gleaner, 1)], // 8: Sowers
            [(.glider, 2), (.striker, 3), (.warden, 2), (.gleaner, 1)],      // 9
            [(.glider, 2), (.striker, 4), (.warden, 2), (.sower, 1), (.gleaner, 2)], // 10
        ]
        guard wave >= 1 else { return [] }
        if wave <= early.count {
            return early[wave - 1].map { (role: $0.0, count: $0.1) }
        }
        let past = wave - 11
        let strikers: Int = min(4 + (past + 1) / 2, 8)
        let wardens: Int = min(4 + past / 2, 8)
        let sowers: Int = min(1 + past / 3, 2)
        let gleaners: Int = min(2 + past / 3, 3)
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
    /// floor (20 s in wave 1, 1.2 s less a wave, 7 s from wave 12).
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
