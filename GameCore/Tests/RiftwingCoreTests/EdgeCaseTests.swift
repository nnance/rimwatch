import Foundation
import Testing
import GameCore
@testable import RiftwingCore

/// The edge cases an independent check of the logic found: the cavern shifting under a rider,
/// catches that happened by themselves, anything after game over, respawning under the gas, a
/// rider camping the side seam, and hatching ahead of a debut.
@Suite struct RiftwingEdgeCaseTests {
    // MARK: The cavern shift

    /// True when a body of `radius` at `p` overlaps any ledge's rock in `layout`.
    private func insideRock(_ p: Vec2, radius: Double, _ layout: RiftwingLayout, _ tuning: RiftwingTuning) -> Bool {
        let feet = radius * tuning.feetShare, head = radius * tuning.headShare
        return layout.ledges.contains { ledge in
            ledge.spans(p.x) && p.y - feet < ledge.top - 0.5 && p.y + head > ledge.top - tuning.ledgeThickness + 0.5
        }
    }

    /// Every ledge of every layout, three places along each: a rider standing there when the
    /// cavern shifts to the next layout ends standing on a ledge of the new one, and loses no
    /// life through the break that follows.
    @Test func aRiderStandingWhenTheCavernShiftsEndsStandingOnTheNewLayout() throws {
        let tuning = RiftwingTuning()
        for from in RiftwingCavern.layouts.indices {
            let to = (from + 1) % RiftwingCavern.layouts.count
            for (i, ledge) in RiftwingCavern.layouts[from].ledges.enumerated() {
                for share in [0.1, 0.5, 0.9] {
                    var r = quietRun()
                    r.layoutIndex = from
                    let x = ledge.minX + ledge.length * share
                    r.rider.body.pos = Vec2(x, ledge.top + r.rider.body.radius * tuning.feetShare)
                    r.rider.body.vel = .zero
                    r.rider.body.ledge = i
                    r.applyLayout(to)
                    let where_ = "layout \(from) ledge \(i) at \(share) -> layout \(to)"
                    let on = try #require(r.rider.body.ledge, "\(where_): not standing")
                    let new = r.ledges[on]
                    #expect(new.spans(r.rider.pos.x), "\(where_)")
                    #expect(abs(r.rider.pos.y - (new.top + r.rider.body.radius * tuning.feetShare)) < 1e-6, "\(where_)")
                    // The nearest ledge of the new layout.
                    let gap = { (l: RiftwingLedge) in
                        hypot(clamp(x, l.minX, l.maxX) - x, l.top - ledge.top)
                    }
                    let best = r.ledges.map(gap).min()!
                    #expect(abs(gap(new) - best) < 1e-6, "\(where_)")
                    // Standing still through the rest of the break costs nothing.
                    let events = run(&r, steps: seconds(3))
                    #expect(!has(events, "riderLost"), "\(where_)")
                    #expect(r.rider.body.isGrounded, "\(where_)")
                }
            }
        }
    }

    @Test func aFlyingRiderIsLeftInFreeSpaceAndPodsAndRigsAreMovedTheSameWay() throws {
        let tuning = RiftwingTuning()
        var r = quietRun()
        r.removeRider()
        // A pod resting on Terraces' right shelf (640...850, top 175), and a rig standing on it.
        let resting = r.dropPod(at: Vec2(820, 200), vel: .zero, from: .glider)
        run(&r, steps: seconds(1))
        #expect(r.pod(resting)?.state == .resting(ledge: 2))
        let rig = r.place(.striker, at: Vec2(660, 175 + 14 * tuning.feetShare))
        r.freeze(rig)
        r.opponents[r.index(of: rig)].body.ledge = 2
        // The rider and a falling pod hang where Spur's long ledge (520...790, top 235) will be.
        r.rider.isAlive = true
        r.placeRider(at: Vec2(600, 230))
        let pod = r.dropPod(at: Vec2(700, 232), vel: .zero, from: .glider)
        r.applyLayout(1)
        #expect(!insideRock(r.rider.pos, radius: r.rider.body.radius, r.layout, tuning))
        #expect(r.rider.body.ledge == nil)
        let p = try r.req(pod: pod)
        #expect(p.state == .falling)
        #expect(!r.ledges.contains { $0.spans(p.pos.x) && p.pos.y - tuning.podRadius < $0.top - 0.5 && p.pos.y + tuning.podRadius > $0.top - tuning.ledgeThickness + 0.5 })
        // The resting pod and the standing rig end on a ledge of the new layout.
        let rp = try r.req(pod: resting)
        guard case .resting(let ledge) = rp.state else {
            Issue.record("a resting pod still rests after the shift: \(rp.state)")
            return
        }
        #expect(r.ledges[ledge].spans(rp.pos.x))
        #expect(abs(rp.pos.y - (r.ledges[ledge].top + tuning.podRadius)) < 1e-6)
        let o = try r.req(opponent: rig)
        let on = try #require(o.body.ledge)
        #expect(r.ledges[on].spans(o.pos.x))
        #expect(abs(o.pos.y - (r.ledges[on].top + o.body.radius * tuning.feetShare)) < 1e-6)
    }

    // MARK: Catches

    /// The rider strikes a Glider flying across and keeps going: the pod is thrown clear and
    /// cannot be taken at once, so it is not caught by flying on.
    @Test func aCatchNeedsPursuit() throws {
        var r = quietRun()
        let id = r.place(.glider, at: Vec2(450, 300))
        r.freeze(id)
        r.placeRider(at: Vec2(432, 318), vel: Vec2(160, -20))
        var podID: Int?
        var caughtAt: Int?
        for step in 0..<seconds(1.5) {
            for event in r.step(RiftwingInput(stick: Vec2(1, 0))) {
                if case .podDropped(let p, _, _) = event { podID = p }
                if case .podCaught = event { caughtAt = step }
            }
        }
        #expect(podID != nil)
        #expect(caughtAt == nil, "caught by flying on, \(caughtAt ?? 0) steps after the blow")
        // Going after it does catch it (double points) once the moment has passed.
        var c = quietRun()
        let pod = c.dropPod(at: Vec2(570, 400), vel: .zero, from: .glider)
        c.placeRider(at: Vec2(575, 380))
        #expect(!has(c.step(still), "podCaught"))
        #expect(c.pod(pod)?.isCatchable == false)
        run(&c, steps: seconds(c.tuning.podCatchDelay))
        let p = try c.req(pod: pod)
        #expect(p.isCatchable)
        c.placeRider(at: Vec2(p.pos.x + 5, p.pos.y - 10))
        #expect(c.step(still).contains { if case .podCaught(pod, _, 1, 1000) = $0 { true } else { false } })
    }

    @Test func aKnockedPodIsThrownClearOfTheWinner() throws {
        var r = quietRun()
        let id = r.place(.glider, at: Vec2(450, 300))
        r.freeze(id)
        r.placeRider(at: Vec2(450 - fig(10), 300 + fig(18)))
        var podID: Int?
        for _ in 0..<seconds(0.1) {
            for event in r.step(still) {
                if case .podDropped(let p, _, _) = event { podID = p }
            }
        }
        let pod = try r.req(pod: try #require(podID))
        // Thrown away from the rider (who came from the left) and downward.
        #expect(pod.vel.x > 0)
        #expect(pod.vel.y < 0)
        #expect(r.wrapDistance(pod.pos, r.rider.pos) > r.rider.body.radius + r.tuning.podRadius + r.tuning.podSlack)
    }

    // MARK: Game over

    /// The last life goes in the step the wave clears: nothing follows the game over, and the
    /// score it announced is the final score.
    @Test func nothingHappensAfterGameOver() throws {
        var r = RiftwingRun(seed: 3)
        run(&r, steps: seconds(r.tuning.firstWaveDelay + 0.1))
        r.sendIndex = r.toSend.count
        r.opponents.removeAll()
        r.arrivals.removeAll()
        r.waveFreed = 2
        r.waveDropped = 2
        // The last rig and the rider both drop into the Rift in the same step.
        let id = r.place(.glider, at: Vec2(600, r.tuning.riftLevel + 0.5), vel: Vec2(0, -200))
        r.freeze(id)
        r.rider.lives = 1
        r.placeRider(at: Vec2(300, r.tuning.riftLevel + 0.5), vel: Vec2(0, -200))
        let events = r.step(still)
        let over = try #require(events.firstIndex { $0.kind == "gameOver" })
        #expect(over == events.count - 1, "\(events)")
        guard case .gameOver(let announced) = events[over] else { return }
        #expect(announced == r.score)
        #expect(r.isGameOver)
    }

    // MARK: Respawning

    /// Every ledge is under the gas: the rider still returns, and the gas does not take it.
    @Test func aRespawnIsNeverLostToTheBreathAlreadyInTheGallery() throws {
        var tuning = RiftwingTuning()
        tuning.breathLevel = 560
        var r = quietRun(tuning: tuning)
        r.breathsThisWave = 1
        r.breath = .holding(remaining: 6)
        r.placeRider(at: Vec2(450, 580))
        r.loseRider(cause: .rift)
        var respawned = false
        var lost = false
        for _ in 0..<seconds(12) {
            for event in r.step(still) {
                if case .riderRespawned = event { respawned = true }
                if case .riderLost = event { lost = true }
            }
        }
        #expect(respawned)
        #expect(!lost)
        #expect(r.rider.isAlive)
    }

    // MARK: Arrivals

    /// A rider hovering at the join, at mid-height, is within the safe distance of every place
    /// in both mouths. After a short wait an arrival comes anyway, at the farthest place, with a
    /// longer glow.
    @Test func campingTheSideSeamDoesNotStopArrivals() throws {
        var r = RiftwingRun(seed: 5)
        let camp = Vec2(0, 340)
        var glowStart: [Int: Int] = [:]
        var arrived: (id: Int, at: Vec2, glow: Int)?
        var forced = false
        for _ in 0..<seconds(12) {
            r.placeRider(at: camp)
            r.rider.invulnerableTimer = .infinity
            for event in r.step(still) {
                if case .arrivalTelegraphed(let id, _, _, _) = event { glowStart[id] = r.tick }
                if case .opponentArrived(let id, _, let at) = event, arrived == nil, let start = glowStart[id] {
                    arrived = (id, at, r.tick - start)
                }
            }
            if r.arrivals.contains(where: \.isForced) { forced = true }
            if arrived != nil { break }
        }
        let a = try #require(arrived, "nothing arrived")
        #expect(forced)
        #expect(a.glow > seconds(r.tuning.telegraphTime) + 10)
        // At the farthest place in the mouths.
        let top = r.tuning.arrivalHeights.upperBound, bottom = r.tuning.arrivalHeights.lowerBound
        let far = max(abs(top - camp.y), abs(bottom - camp.y))
        #expect(abs(abs(a.at.y - camp.y) - far) < 1)
    }

    // MARK: Hatching

    /// Until the tougher kind has had its debut, a pod hatches into its own kind.
    @Test func aPodHatchesIntoItsOwnKindBeforeTheTougherKindsDebut() throws {
        func hatchedRole(from: RiftwingRole, wave: Int) throws -> RiftwingRole {
            var r = quietRun()
            r.wave = wave
            r.removeRider()
            let ledge = r.ledges[1]
            let id = r.dropPod(at: Vec2(ledge.midX, ledge.top + 20), vel: .zero, from: from)
            var warned: RiftwingRole?
            var hatched: RiftwingRole?
            for _ in 0..<seconds(30) {
                for event in r.step(still) {
                    if case .hatchWarning(id, _, let becomes) = event { warned = becomes }
                    if case .podHatched(id, _, let role, _) = event { hatched = role }
                }
                if hatched != nil { break }
            }
            #expect(warned == hatched)
            return try #require(hatched)
        }
        #expect(try hatchedRole(from: .glider, wave: 1) == .glider)
        #expect(try hatchedRole(from: .glider, wave: 2) == .glider)
        #expect(try hatchedRole(from: .glider, wave: 3) == .striker)
        #expect(try hatchedRole(from: .striker, wave: 5) == .striker)
        #expect(try hatchedRole(from: .striker, wave: 6) == .warden)
    }
}
