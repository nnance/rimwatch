import Testing
import GameCore
@testable import RiftwingCore

/// The clash: the higher wins, near level bounces both apart, the roof is level, the stoop, and
/// the meetings with Gleaners, Sowers and mines.
@Suite struct RiftwingClashTests {
    /// The rider at `riderAt` and a still opponent of `role` at `at`, one step.
    private func meet(_ role: RiftwingRole, riderAt: Vec2, at: Vec2, ease: Double = 0,
                      input: RiftwingInput = still, prepare: (inout RiftwingRun) -> Void = { _ in })
        -> (run: RiftwingRun, id: Int, events: [RiftwingEvent]) {
        var r = quietRun()
        r.placeRider(at: riderAt)
        let id = r.place(role, at: at, ease: ease)
        r.freeze(id)
        prepare(&r)
        let events = r.step(input)
        return (r, id, events)
    }

    @Test func theHigherRigWins() throws {
        let (r, id, events) = meet(.glider, riderAt: Vec2(450, 330), at: Vec2(450, 305))
        #expect(events.contains { if case .clashWon(id, .glider, _, false) = $0 { true } else { false } })
        #expect(events.contains { if case .opponentDestroyed(id, .glider, _, 250, 0) = $0 { true } else { false } })
        #expect(events.contains { if case .podDropped(_, _, .glider) = $0 { true } else { false } })
        #expect(r.opponent(id) == nil)
        #expect(r.score == 250)
        #expect(r.waveDropped == 1)
        #expect(r.rider.isAlive)
        // The winner springs up.
        #expect(r.rider.vel.y >= r.tuning.winLift - 1)
    }

    @Test func theLowerRigLosesALife() throws {
        // Clearly above: more than the margin and the lasting leniency (`aMeetingNeedsAClearHeightToWin`).
        let (r, id, events) = meet(.striker, riderAt: Vec2(450, 305), at: Vec2(450, 305 + fig(28)))
        #expect(events.contains { if case .clashLost(id, .striker, _) = $0 { true } else { false } })
        #expect(events.contains { if case .riderLost(_, 2, .clash(id, .striker)) = $0 { true } else { false } })
        #expect(!r.rider.isAlive)
        #expect(r.opponent(id) != nil)
    }

    @Test func nearLevelBothBounceApartUnhurt() throws {
        let (r, id, events) = meet(.glider, riderAt: Vec2(440, 300), at: Vec2(460, 303))
        #expect(events.contains { if case .clashBounced(id, .glider, _) = $0 { true } else { false } })
        #expect(r.rider.isAlive)
        let o = try r.req(opponent: id)
        #expect(r.rider.vel.x < -100)
        #expect(o.vel.x > 100)
        #expect(r.score == 0)
        // The margin is the rule: just outside it on either side, the meeting is decided.
        let edge = r.tuning.clashMargin
        #expect(r.clashOutcome(rider: body(y: 300 + edge + 0.5), opponent: body(y: 300)) == .win)
        #expect(r.clashOutcome(rider: body(y: 300 + edge - 0.5), opponent: body(y: 300)) == .bounce)
        #expect(r.clashOutcome(rider: body(y: 300 - edge + 0.5), opponent: body(y: 300)) == .bounce)
        #expect(r.clashOutcome(rider: body(y: 300 - edge - 0.5), opponent: body(y: 300)) == .lose)
    }

    /// To win, an opponent must be more than the margin and the lasting leniency above the rider
    /// (23 units at figure scale 1 since 2026-11-22, when the leniency went from 16.1 to 12:
    /// contact comes at about 29, so it must still come down well above the rider; both grow
    /// with the figures). Winning for the rider is the margin alone. With
    /// `RiftwingWaves.withGentleDebuts` it is 27.1, nearly squarely on top, as before.
    @Test func aMeetingNeedsAClearHeightToWin() throws {
        let r = quietRun()
        let leniency = r.clashLeniency(ease: 0)
        let lose = r.tuning.clashMargin + leniency
        #expect(lose > fig(22) && lose < fig(24))
        let gentle = quietRun(waves: .withGentleDebuts)
        let gentleLose = gentle.tuning.clashMargin + gentle.clashLeniency(ease: 0)
        #expect(gentleLose > fig(24) && gentleLose < fig(29))
        #expect(lose < r.tuning.riderRadius + r.tuning.stats(for: .striker).radius)
        #expect(r.clashOutcome(rider: body(y: 300), opponent: body(y: 300 + lose - 0.5), leniency: leniency) == .bounce)
        #expect(r.clashOutcome(rider: body(y: 300), opponent: body(y: 300 + lose + 0.5), leniency: leniency) == .lose)
        #expect(r.clashOutcome(rider: body(y: 300 + r.tuning.clashMargin + 0.5), opponent: body(y: 300),
                               leniency: leniency) == .win)
        // 20 units above (at figure scale 1) is not enough, even at full strength.
        let near = meet(.striker, riderAt: Vec2(450, 300), at: Vec2(450, 300 + fig(20)), ease: 0)
        #expect(has(near.events, "clashBounced"))
    }

    /// With the beginner's forgiveness (`RiftwingWaves.withBeginnerForgiveness`, off by default
    /// since 2026-11-22), an opponent in its first appearances that would win a clash usually
    /// misjudges it and bounces: in its debut it wins only a few, and its chance to win grows with
    /// its appearances as a ramp, never more than doubling from one appearance to the next
    /// (`RiftwingWaves.mercy(ease:)`); at full strength it always wins.
    @Test func withForgivenessAnOpponentInItsFirstAppearancesMisjudgesClashesItWouldWin() throws {
        let w = RiftwingWaves.withBeginnerForgiveness
        var wins: [Double] = []
        for k in 0...w.rampEase.count {
            let ease = k < w.rampEase.count ? w.rampEase[k] : 0
            wins.append(1 - w.mercy(ease: ease))
        }
        #expect(wins[0] > 0.05 && wins[0] < 0.35, "\(wins)")
        for k in 1..<wins.count {
            #expect(wins[k] >= wins[k - 1], "\(wins)")
            #expect(wins[k] <= wins[k - 1] * 2.05, "appearance \(k + 1): \(wins)")
        }
        #expect(wins.last == 1)
        func losses(ease: Double) -> Int {
            (0..<200).count { i in
                var r = quietRun(seed: UInt64(100 + i), waves: w)
                r.placeRider(at: Vec2(450, 300))
                let id = r.place(.striker, at: Vec2(450, 300 + fig(28)), ease: ease)
                r.freeze(id)
                return has(r.step(still), "riderLost")
            }
        }
        let debut = losses(ease: 1)
        #expect(debut > 0 && debut < 70, "\(debut) of 200")
        #expect(losses(ease: 0) == 200)
        let half = losses(ease: 0.5)
        #expect((60...140).contains(half), "\(half) of 200")
    }

    /// No forgiveness (the default since 2026-11-22: "every lost clash costs a life in every
    /// wave"): an opponent never misjudges a clash it would win, even in its first appearance,
    /// so every lost clash costs a life.
    @Test func everyLostClashCostsALifeEvenInAnOpponentsFirstAppearance() throws {
        let w = RiftwingWaves()
        for k in 0...w.rampEase.count {
            let ease = k < w.rampEase.count ? w.rampEase[k] : 0
            #expect(w.mercy(ease: ease) == 0, "appearance \(k + 1)")
        }
        func losses(ease: Double) -> Int {
            (0..<200).count { i in
                var r = quietRun(seed: UInt64(100 + i))
                r.placeRider(at: Vec2(450, 300))
                let id = r.place(.striker, at: Vec2(450, 300 + fig(28)), ease: ease)
                r.freeze(id)
                return has(r.step(still), "riderLost")
            }
        }
        #expect(losses(ease: 1) == 200)
        #expect(losses(ease: 0.5) == 200)
        #expect(losses(ease: 0) == 200)
        // A debut glider of wave 1 squarely on top of a rider in the air wins every time.
        var lost = 0
        for i in 0..<60 {
            var r = quietRun(seed: UInt64(700 + i))
            r.placeRider(at: Vec2(450, 300))
            let id = r.place(.glider, at: Vec2(452, 300 + fig(28.5)), ease: r.director.ease(of: .glider, inWave: 1))
            r.freeze(id)
            if has(r.step(still), "riderLost") { lost += 1 }
        }
        #expect(lost == 60, "\(lost) of 60")
    }

    /// With the beginner's forgiveness (`RiftwingWaves.withBeginnerForgiveness`), wave 1 is for
    /// learning the controls: a rider standing on a ledge in it is never beaten in a clash (the
    /// opponent always misjudges). In the air, or standing in a later wave, the ordinary chances
    /// apply.
    @Test func withForgivenessARiderStandingOnALedgeInTheFirstWaveIsNeverBeaten() throws {
        func losses(wave: Int, standing: Bool) -> Int {
            (0..<60).count { i in
                var r = quietRun(seed: UInt64(500 + i), waves: .withBeginnerForgiveness)
                r.wave = wave
                let ledge = r.ledges[1]
                let stand = RiftwingRun.standingPoint(on: ledge, radius: r.rider.body.radius, tuning: r.tuning)
                r.placeRider(at: standing ? stand : Vec2(stand.x, stand.y + 40))
                if standing { r.rider.body.ledge = 1 }
                let id = r.place(.glider, at: Vec2(r.rider.pos.x + 2, r.rider.pos.y + fig(28.5)),
                                 ease: r.director.ease(of: .glider, inWave: wave))
                r.freeze(id)
                return has(r.step(still), "riderLost")
            }
        }
        #expect(losses(wave: 1, standing: true) == 0)
        #expect(losses(wave: 1, standing: false) > 0)
        #expect(losses(wave: 2, standing: true) > 0)
    }

    /// No forgiveness (the default since 2026-11-22): a rider standing on a ledge in wave 1 is
    /// beaten by an opponent squarely on top of it like any other, and a level meeting throws it
    /// off its ledge.
    @Test func aRiderStandingOnALedgeInTheFirstWaveCanBeBeaten() throws {
        var lost = 0
        for i in 0..<60 {
            var r = quietRun(seed: UInt64(500 + i))
            #expect(r.wave == 1)
            #expect(r.rider.body.ledge == r.layout.startLedge)
            let p = r.rider.body.pos
            let id = r.place(.glider, at: Vec2(p.x + 2, p.y + fig(28.5)), ease: r.director.ease(of: .glider, inWave: 1))
            r.freeze(id)
            if has(r.step(still), "riderLost") { lost += 1 }
        }
        #expect(lost == 60, "\(lost) of 60")
        var r = quietRun()
        let p = r.rider.body.pos
        let id = r.place(.striker, at: Vec2(p.x + 2, p.y + 3), ease: 0)
        r.freeze(id)
        #expect(has(r.step(still), "clashBounced"))
        #expect(r.rider.body.ledge == nil)
        #expect(abs(r.rider.vel.x) >= r.tuning.bounceSpeed - 1)
    }

    /// A rider pressed against rock for long (clinging to a ceiling) loses the early mercy meant
    /// for beginners, but never more than that: an opponent squarely on top of it wins even at
    /// its debut, and one only a little above it still only bounces, as under the ordinary rule.
    @Test func aClingingRiderLosesTheMercyButNotTheOrdinaryRule() throws {
        func outcome(above: Double) -> [RiftwingEvent] {
            // Pinned anywhere (an opponent cannot be squarely above a rider pressed under real
            // rock: the rock is in the way), so the rule itself is tested in open air.
            var tuning = RiftwingTuning()
            tuning.pinnedBand = 1000
            var r = quietRun(tuning: tuning)
            let y = 300.0
            r.placeRider(at: Vec2(600, y))
            r.riderPinnedFor = r.tuning.pinnedPatience + 1
            r.riderBumpTicks = Array(repeating: r.tick, count: r.tuning.pinnedBumps)
            #expect(r.isRiderClinging)
            #expect(r.isRiderCamping)
            let id = r.place(.striker, at: Vec2(602, y + above), ease: 1)
            r.freeze(id)
            return r.step(still)
        }
        // Squarely on top, at its debut: no mercy for a rider clinging to a ceiling.
        #expect(has(outcome(above: fig(28.5)), "riderLost"))
        // A little above: the ordinary rule bounces it (it once lost here).
        #expect(has(outcome(above: fig(5)), "clashBounced"))
        #expect(has(outcome(above: fig(20)), "clashBounced"))
    }

    /// A rider camping by staying in one place draws opponents, but the clash rule is unchanged
    /// for it: early opponents still misjudge, and one only a little above still bounces.
    @Test func aStillRiderKeepsTheClashRuleAndTheMercy() throws {
        var lost = 0
        for i in 0..<40 {
            var r = quietRun(seed: UInt64(300 + i))
            r.placeRider(at: Vec2(450, 300))
            r.riderStillFor = 1000
            r.stillAnchor = Vec2(450, 300)
            #expect(r.isRiderCamping)
            #expect(!r.isRiderClinging)
            let id = r.place(.striker, at: Vec2(452, 300 + 28.5), ease: 1)
            r.freeze(id)
            if has(r.step(still), "riderLost") { lost += 1 }
        }
        // At its debut a striker squarely on top usually misjudges.
        #expect(lost < 20, "\(lost) of 40")
        var r = quietRun()
        r.placeRider(at: Vec2(450, 300))
        r.riderStillFor = 1000
        r.stillAnchor = Vec2(450, 300)
        let id = r.place(.striker, at: Vec2(452, 305), ease: 0)
        r.freeze(id)
        #expect(has(r.step(still), "clashBounced"))
    }

    /// Bouncing off the same opponent again and again changes nothing: every meeting is judged
    /// by the same rule. (A rule that let an opponent win from the bounce margin after two
    /// bounces within about 3 s is gone: it counted bounces the rider did not cause, such as an
    /// opponent diving on it twice, and the rider was never told.)
    @Test func bouncingOffTheSameOpponentAgainAndAgainChangesNothing() throws {
        var r = quietRun()
        let id = r.place(.striker, at: Vec2(460, 300), ease: 0)
        r.freeze(id)
        for _ in 0..<5 {
            r.placeRider(at: Vec2(440, 302))
            r.opponents[r.index(of: id)].body.pos = Vec2(460, 300)
            r.opponents[r.index(of: id)].clashCooldown = 0
            #expect(has(r.step(still), "clashBounced"))
        }
        // 20 units above, straight after five bounces: still only a bounce.
        r.placeRider(at: Vec2(450, 300))
        r.opponents[r.index(of: id)].body.pos = Vec2(450, 320)
        r.opponents[r.index(of: id)].body.vel = .zero
        r.opponents[r.index(of: id)].clashCooldown = 0
        #expect(has(r.step(still), "clashBounced"))
        #expect(r.rider.isAlive)
    }

    /// With the beginner's forgiveness (`RiftwingWaves.withBeginnerForgiveness`), in wave 1 a
    /// rider standing on a ledge is never beaten, and a meeting with it does not throw it off its
    /// ledge either: it keeps its footing and the opponent alone is thrown away (it was once
    /// thrown off, often into the Rift). From wave 2 a bounce throws both apart as usual.
    @Test func withForgivenessAStandingRiderSparedInWaveOneKeepsItsFooting() throws {
        func standing(wave: Int, above: Double) -> (RiftwingRun, Int, [RiftwingEvent]) {
            var r = quietRun(waves: .withBeginnerForgiveness)
            r.wave = wave
            let start = r.layout.startLedge
            #expect(r.rider.body.ledge == start)
            let p = r.rider.body.pos
            let id = r.place(.striker, at: Vec2(p.x + 2, p.y + above), ease: 0)
            r.freeze(id)
            let events = r.step(still)
            return (r, id, events)
        }
        for above in [28.5, 3.0] {
            let (r, id, events) = standing(wave: 1, above: above)
            #expect(has(events, "clashBounced"), "\(above)")
            #expect(r.rider.isAlive)
            #expect(r.rider.body.ledge == r.layout.startLedge, "\(above)")
            #expect(abs(r.rider.vel.x) < 1e-9 && abs(r.rider.vel.y) < 1e-9, "\(above): \(r.rider.vel)")
            #expect(abs(try r.req(opponent: id).vel.x) >= r.tuning.bounceSpeed - 1, "\(above)")
        }
        // Wave 2: a level bounce throws the standing rider off as usual.
        let (r, _, events) = standing(wave: 2, above: 3)
        #expect(has(events, "clashBounced"))
        #expect(r.rider.body.ledge == nil)
        #expect(abs(r.rider.vel.x) >= r.tuning.bounceSpeed - 1)
    }

    /// With the beginner's forgiveness, the opponent that bounces off a standing rider in wave 1
    /// is thrown up and away, off the ledge, and does not meet the rider again at once. (It once
    /// landed straight back on the same ledge, walked into the rider and bounced off it every
    /// 0.35 s: 8 bounces in 4 s.)
    @Test func withForgivenessTheOpponentThatBouncesOffAStandingRiderInWaveOneIsThrownClear() throws {
        var r = quietRun(waves: .withBeginnerForgiveness)
        r.wave = 1
        let p = r.rider.body.pos
        let id = r.place(.glider, at: Vec2(p.x + 10, p.y), ease: 1)
        var bounces = 0
        var liftedOff = false
        for _ in 0..<Int(4 / RiftwingRun.timeStep) {
            let events = r.step(still)
            if has(events, "clashBounced") {
                bounces += 1
                if bounces == 1, let o = r.opponents.first(where: { $0.id == id }) {
                    liftedOff = o.body.ledge == nil && o.vel.y > 0
                }
            }
        }
        #expect(bounces >= 1)
        #expect(liftedOff)
        #expect(bounces <= 2, "\(bounces) bounces in 4 s")
        #expect(r.rider.isAlive)
        #expect(r.rider.body.ledge == r.layout.startLedge)
    }

    @Test func aBounceThrowsBothApartAcrossOnly() throws {
        let (r, id, _) = meet(.glider, riderAt: Vec2(440, 300), at: Vec2(460, 303))
        let o = try r.req(opponent: id)
        // No vertical part: a bounce never sets up a win on the next meeting.
        #expect(abs(r.rider.vel.y - (-r.tuning.gravity * RiftwingRun.timeStep)) < 1)
        #expect(o.vel.y <= 0.5)
    }

    @Test func pressedAgainstTheRoofBothAreLevel() throws {
        let t = RiftwingTuning()
        let riderTop = t.roof - t.riderRadius
        let strikerTop = t.roof - t.stats(for: .striker).radius
        let (r, id, events) = meet(.striker, riderAt: Vec2(440, riderTop), at: Vec2(462, strikerTop))
        #expect(events.contains { if case .clashBounced(id, .striker, _) = $0 { true } else { false } })
        #expect(r.rider.isAlive)
        // At the roof, the rider still wins against one clearly below.
        let below = meet(.striker, riderAt: Vec2(450, riderTop), at: Vec2(450, riderTop - 26))
        #expect(has(below.events, "opponentDestroyed"))
    }

    @Test func aStoopKnocksAWardenOffInOneBlowAndScoresTheDrop() throws {
        let (r, id, events) = meet(.warden, riderAt: Vec2(450, 330), at: Vec2(450, 305), input: RiftwingInput(dive: true)) {
            $0.rider.body.isDiving = true
            $0.rider.body.diveStart = 530
        }
        #expect(events.contains { if case .clashWon(id, .warden, _, true) = $0 { true } else { false } })
        let fallen = 530 - 330.0
        let bonus = r.stoopBonus(fallen: fallen)
        #expect(bonus == 400)
        #expect(events.contains { if case .opponentDestroyed(id, .warden, _, 750 + 400, 400) = $0 { true } else { false } })
        #expect(r.opponent(id) == nil)
        // The bonus grows with the drop in 50s and is capped.
        #expect(r.stoopBonus(fallen: 0) == 0)
        #expect(r.stoopBonus(fallen: 60) == 100)
        #expect(r.stoopBonus(fallen: 74) == 100)
        #expect(r.stoopBonus(fallen: 5000) == r.tuning.stoopBonusCap)
    }

    @Test func aWardenTakesTwoBlowsWithoutAStoop() throws {
        var r = quietRun()
        r.placeRider(at: Vec2(450, 330))
        let id = r.place(.warden, at: Vec2(450, 305))
        r.freeze(id)
        let first = r.step(still)
        #expect(first.contains { if case .opponentHit(id, .warden, _, 1) = $0 { true } else { false } })
        let hit = try r.req(opponent: id)
        #expect(hit.blows == 1)
        if case .staggered = hit.state {} else { Issue.record("a hit Warden tumbles: \(hit.state)") }
        #expect(r.score == r.tuning.hitPoints)
        // After the clash cooldown, a second blow from above knocks it off.
        run(&r, steps: seconds(r.tuning.clashCooldown) + 2)
        let w = try r.req(opponent: id)
        r.placeRider(at: Vec2(w.pos.x, w.pos.y + 22))
        r.freeze(id)
        let second = r.step(still)
        #expect(second.contains { if case .opponentDestroyed(id, .warden, _, 750, 0) = $0 { true } else { false } })
    }

    @Test func aProtectedRiderBouncesInsteadOfLosing() throws {
        let (r, _, events) = meet(.striker, riderAt: Vec2(450, 300), at: Vec2(450, 325)) { $0.rider.invulnerableTimer = 1 }
        #expect(has(events, "clashBounced"))
        #expect(!has(events, "riderLost"))
        #expect(r.rider.isAlive)
        #expect(r.rider.lives == 3)
    }

    @Test func clashesHappenAcrossTheJoin() throws {
        let (r, id, events) = meet(.glider, riderAt: Vec2(4, 330), at: Vec2(894, 305))
        #expect(events.contains { if case .clashWon(id, .glider, _, _) = $0 { true } else { false } })
        // The meeting point is reported at the join, not across the gallery.
        if case .clashWon(_, _, let at, _) = events.first(where: { $0.kind == "clashWon" })! {
            #expect(at.x < 10 || at.x > 890, "\(at)")
        }
        #expect(r.waveDropped == 1)
    }

    @Test func aGleanerMetFromAboveOrLevelIsDestroyedAndLetsGoOfItsPod() throws {
        var r = quietRun()
        let pod = r.dropPod(at: Vec2(300, 280), vel: .zero, from: .glider)
        let g = r.place(.gleaner, at: Vec2(300, 300))
        let p = r.pods.firstIndex { $0.id == pod }!
        r.pods[p].state = .seized(by: g)
        r.opponents[r.index(of: g)].state = .carrying(pod: pod, exitX: 0)
        r.placeRider(at: Vec2(300, 303))
        let events = r.step(still)
        #expect(events.contains { if case .opponentDestroyed(g, .gleaner, _, 300, 0) = $0 { true } else { false } })
        #expect(events.contains { if case .podFreed(pod, _, 1, 500) = $0 { true } else { false } })
        #expect(r.opponent(g) == nil)
        #expect(r.colonistsSaved == 1)
    }

    @Test func aGleanerMetFromBelowBumpsTheRiderAwayUnhurt() throws {
        var r = quietRun()
        let g = r.place(.gleaner, at: Vec2(300, 300))
        r.opponents[r.index(of: g)].state = .leaving(exitX: 900)
        r.placeRider(at: Vec2(300, 280))
        let events = r.step(still)
        #expect(events.contains { if case .gleanerBumped(g, _) = $0 { true } else { false } })
        #expect(r.rider.isAlive)
        #expect(r.rider.vel.y < 0)
        #expect(r.opponent(g) != nil)
    }

    @Test func strikingASowerFromAboveClearsAllItsMines() throws {
        var r = quietRun()
        let s = r.place(.sower, at: Vec2(600, 400))
        r.freeze(s)
        for x in [200.0, 300] {
            r.mines.append(RiftwingMine(id: r.takeID(), sower: s, anchor: Vec2(x, 450), pos: Vec2(x, 416)))
        }
        r.placeRider(at: Vec2(600, 425))
        let events = r.step(still)
        #expect(has(events, "opponentDestroyed"))
        #expect(events.count { if case .mineCleared(_, _, .sowerDown) = $0 { true } else { false } } == 2)
        #expect(r.mines.isEmpty)
    }

    @Test func touchingAMineCostsALife() throws {
        var r = quietRun()
        let id = r.takeID()
        r.mines.append(RiftwingMine(id: id, sower: 999, anchor: Vec2(450, 334), pos: Vec2(450, 300)))
        r.placeRider(at: Vec2(455, 305))
        let events = r.step(still)
        #expect(events.contains { if case .riderLost(_, 2, .mine(id)) = $0 { true } else { false } })
        #expect(events.contains { if case .mineCleared(id, _, .struck) = $0 { true } else { false } })
        #expect(r.mines.isEmpty)
    }

    private func body(y: Double) -> RiftwingBody {
        RiftwingBody(pos: Vec2(100, y), radius: 15)
    }
}
