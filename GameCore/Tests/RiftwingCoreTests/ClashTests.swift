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
        let (r, id, events) = meet(.striker, riderAt: Vec2(450, 305), at: Vec2(450, 333))
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
    /// (about 27 units: contact comes at about 29, so it must come down nearly squarely on top).
    /// Winning for the rider is the margin alone.
    @Test func aMeetingNeedsAClearHeightToWin() throws {
        let r = quietRun()
        let lose = r.tuning.clashMargin + r.director.leniency(ease: 0)
        #expect(lose > 24 && lose < 29)
        #expect(r.clashOutcome(rider: body(y: 300), opponent: body(y: 300 + lose - 0.5), leniency: r.director.leniency(ease: 0)) == .bounce)
        #expect(r.clashOutcome(rider: body(y: 300), opponent: body(y: 300 + lose + 0.5), leniency: r.director.leniency(ease: 0)) == .lose)
        #expect(r.clashOutcome(rider: body(y: 300 + r.tuning.clashMargin + 0.5), opponent: body(y: 300),
                               leniency: r.director.leniency(ease: 0)) == .win)
        // 20 units above is not enough, even at full strength.
        let near = meet(.striker, riderAt: Vec2(450, 300), at: Vec2(450, 320), ease: 0)
        #expect(has(near.events, "clashBounced"))
    }

    /// In its debut an opponent that would win a clash misjudges it and bounces; its chance to
    /// win grows with its appearances (`RiftwingWaves.clashMercy`), and at full strength it
    /// always wins.
    @Test func anOpponentInItsFirstAppearancesMisjudgesClashesItWouldWin() throws {
        func losses(ease: Double) -> Int {
            (0..<200).count { i in
                var r = quietRun(seed: UInt64(100 + i))
                r.placeRider(at: Vec2(450, 300))
                let id = r.place(.striker, at: Vec2(450, 328), ease: ease)
                r.freeze(id)
                return has(r.step(still), "riderLost")
            }
        }
        #expect(losses(ease: 1) == 0)
        #expect(losses(ease: 0) == 200)
        let half = losses(ease: 0.5)
        #expect((60...140).contains(half), "\(half) of 200")
    }

    /// A rider camping in one place gets no leniency or mercy: a debut opponent only a little
    /// above it wins.
    @Test func aCampingRiderGetsNoLeniency() throws {
        var r = quietRun()
        r.placeRider(at: Vec2(450, 300))
        r.riderStillFor = r.tuning.gliderDrawAfter + 1
        r.stillAnchor = Vec2(450, 300)
        #expect(r.isRiderCamping)
        let id = r.place(.striker, at: Vec2(462, 300 + r.tuning.campingMargin + 3), ease: 1)
        r.freeze(id)
        #expect(has(r.step(still), "riderLost"))
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
