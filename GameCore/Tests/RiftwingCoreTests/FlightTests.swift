import Testing
import GameCore
@testable import RiftwingCore

/// Gravity, flapping, glide and the lean, ledges, vents, the roof, the join at the sides, the
/// dive and the Rift.
@Suite struct RiftwingFlightTests {
    @Test func theRiderStartsStandingOnTheFirstLayoutsStartLedge() throws {
        let r = RiftwingRun(seed: 1)
        let ledge = RiftwingCavern.terraces.ledges[RiftwingCavern.terraces.startLedge]
        #expect(r.rider.body.ledge == RiftwingCavern.terraces.startLedge)
        #expect(r.rider.pos.y == ledge.top + r.tuning.riderRadius * r.tuning.feetShare)
        #expect(r.rider.lives == 3)
        // The rig is about 5% of the gallery's height across.
        #expect(abs(r.tuning.riderRadius * 2 / r.tuning.height - 0.05) < 0.001)
    }

    @Test func gravityPullsARiderInTheAirDown() throws {
        var r = quietRun()
        r.placeRider(at: Vec2(450, 500))
        run(&r, steps: seconds(0.5))
        // About half a second of free fall: g t^2 / 2 is 54 units at 430.
        #expect(r.rider.pos.y < 455 && r.rider.pos.y > 440, "\(r.rider.pos.y)")
        #expect(r.rider.vel.y < -200)
    }

    @Test func holdingFlapGivesOneFlapAndEachPressGivesOne() throws {
        var r = quietRun()
        r.placeRider(at: Vec2(450, 400))
        let held = run(&r, steps: seconds(1), input: flapPress)
        #expect(count(held, "flapped") == 1)
        _ = r.step(still)
        var presses = 0
        for step in 0..<seconds(1) {
            let down = step % 12 < 6
            presses += count(r.step(RiftwingInput(flap: down)), "flapped")
        }
        #expect(presses == 10)
    }

    @Test func aFlapPushesUpAndALittleAlongTheSteer() throws {
        var r = quietRun()
        r.placeRider(at: Vec2(450, 400))
        _ = r.step(RiftwingInput(stick: Vec2(1, 0), flap: true))
        #expect(r.rider.vel.y > r.tuning.flapImpulse - 10)
        // The flap's push along the steer, on top of a step of leaning.
        #expect(r.rider.vel.x >= r.tuning.flapThrust)
        // Rising speed is capped however fast the presses come.
        for step in 0..<seconds(1) { _ = r.step(RiftwingInput(flap: step % 2 == 0)) }
        #expect(r.rider.vel.y <= r.tuning.maxRise + 1e-9)
    }

    @Test func speedCarriesAndTurningLeansAgainstMomentum() throws {
        var r = quietRun()
        r.placeRider(at: Vec2(300, 500), vel: Vec2(200, 0))
        // Letting go glides: little speed is lost in half a second.
        run(&r, steps: seconds(0.5))
        #expect(r.rider.vel.x > 170)
        // Steering the other way takes time to turn it round.
        run(&r, steps: seconds(0.3), input: RiftwingInput(stick: Vec2(-1, 0)))
        #expect(r.rider.vel.x > 0, "still drifting the old way after 0.3 s: \(r.rider.vel.x)")
        run(&r, steps: seconds(0.8), input: RiftwingInput(stick: Vec2(-1, 0)))
        #expect(r.rider.vel.x < 0)
        // Never faster than the top speed across.
        run(&r, steps: seconds(3), input: RiftwingInput(stick: Vec2(-1, 0), flap: false))
        #expect(abs(r.rider.vel.x) <= r.tuning.maxAirSpeed + 1)
    }

    @Test func fallingWithTheWingsOpenHasALimit() throws {
        var r = quietRun()
        r.placeRider(at: Vec2(450, 590))
        r.rider.invulnerableTimer = .infinity
        run(&r, steps: seconds(1.2))
        #expect(r.rider.vel.y >= -r.tuning.terminalFall - 1e-9)
        #expect(r.rider.vel.y < -r.tuning.terminalFall + 5)
    }

    @Test func theRoofStopsTheRiderAndDoesNoHarm() throws {
        var r = quietRun()
        r.placeRider(at: Vec2(450, 560))
        var lost = 0
        for step in 0..<seconds(2) { lost += count(r.step(RiftwingInput(flap: step % 2 == 0)), "riderLost") }
        #expect(lost == 0)
        #expect(r.rider.isAlive)
        #expect(r.rider.pos.y <= r.tuning.roof - r.rider.body.radius + 1e-9)
        #expect(r.rider.pos.y > r.tuning.roof - r.rider.body.radius - 40)
    }

    @Test func flyingOffOneSideComesInAtTheOther() throws {
        var r = quietRun()
        r.placeRider(at: Vec2(890, 500), vel: Vec2(200, 0))
        r.tuningFlatGravity()
        run(&r, steps: seconds(0.2))
        #expect(r.rider.pos.x < 40 && r.rider.pos.x >= 0, "\(r.rider.pos.x)")
        r.placeRider(at: Vec2(5, 500), vel: Vec2(-200, 0))
        run(&r, steps: seconds(0.2))
        #expect(r.rider.pos.x > 860 && r.rider.pos.x < 900, "\(r.rider.pos.x)")
        // Distances are measured round the join.
        #expect(abs(r.wrapDistance(Vec2(5, 100), Vec2(895, 100)) - 10) < 1e-9)
        #expect(abs(r.dxWrap(895, 5) - 10) < 1e-9)
        #expect(abs(r.dxWrap(5, 895) + 10) < 1e-9)
    }

    @Test func aRiderLandsOnALedgeAndRunsAlongItAndOffTheEnd() throws {
        var r = quietRun()
        let ledge = r.ledges[1]
        r.placeRider(at: Vec2(ledge.midX, ledge.top + 60))
        let events = run(&r, steps: seconds(1), until: { $0.kind == "landed" })
        #expect(has(events, "landed"))
        #expect(r.rider.body.ledge == 1)
        let standing = ledge.top + r.rider.body.radius * r.tuning.feetShare
        #expect(abs(r.rider.pos.y - standing) < 1e-9)
        // Standing still, it stays put.
        run(&r, steps: seconds(1))
        #expect(r.rider.body.ledge == 1)
        #expect(abs(r.rider.pos.y - standing) < 1e-9)
        // Running: up to the run speed, along the ledge.
        run(&r, steps: seconds(0.4), input: RiftwingInput(stick: Vec2(1, 0)))
        #expect(r.rider.body.ledge == 1)
        #expect(abs(r.rider.vel.x - r.tuning.runSpeed) < 1)
        // Off the end it is in the air again.
        run(&r, steps: seconds(0.8), input: RiftwingInput(stick: Vec2(1, 0)))
        #expect(r.rider.body.ledge != 1)
        #expect(r.rider.pos.x > ledge.maxX)
        #expect(r.rider.pos.y < standing)
    }

    @Test func aFlapFromALedgeTakesOff() throws {
        var r = quietRun()
        #expect(r.rider.body.isGrounded)
        let events = r.step(flapPress)
        #expect(events.contains { if case .flapped(_, let fromLedge) = $0 { fromLedge } else { false } })
        #expect(!r.rider.body.isGrounded)
        #expect(r.rider.vel.y > 0)
    }

    @Test func climbingIntoALedgeBumpsTheHead() throws {
        var r = quietRun()
        let ledge = r.ledges[3]  // x 150...330, top 400
        r.placeRider(at: Vec2(ledge.midX, ledge.top - 60), vel: Vec2(0, 200))
        let events = run(&r, steps: seconds(0.5), until: { $0.kind == "bumpedLedge" })
        #expect(has(events, "bumpedLedge"))
        #expect(r.rider.vel.y <= 0)
        #expect(r.rider.pos.y < ledge.top - r.tuning.ledgeThickness)
    }

    /// Nothing clings to a ceiling: flying up into the roof knocks a rig down at least
    /// `ceilingKnock`, and into a ledge's underside at least `ledgeKnock`.
    @Test func nothingClingsToTheRoofOrALedgesUnderside() throws {
        var r = quietRun()
        r.placeRider(at: Vec2(450, r.tuning.roof - r.rider.body.radius - 1), vel: Vec2(0, 200))
        let events = r.step(still)
        #expect(has(events, "bumpedRoof"))
        #expect(r.rider.vel.y <= -r.tuning.ceilingKnock + 1e-9)
        // Under the first layout's middle shelf (345...505, top 250).
        let ledge = r.ledges[1]
        let under = ledge.top - r.tuning.ledgeThickness - r.rider.body.radius * r.tuning.headShare
        r.placeRider(at: Vec2(ledge.midX, under - 1), vel: Vec2(0, 150))
        #expect(has(r.step(still), "bumpedLedge"))
        #expect(r.rider.vel.y <= -r.tuning.ledgeKnock + 1e-9)
    }

    /// A rider that keeps pressing against rock is knocked down harder with each bump in a short
    /// time, so it cannot hold itself pressed there: it bobs well below the rock, where a rig
    /// holding steady under it can get above it. One bump now and then is knocked as usual.
    @Test func pressingAgainstRockAgainAndAgainKnocksHarder() throws {
        var r = quietRun()
        var knocks: [Double] = []
        for _ in 0..<4 {
            r.placeRider(at: Vec2(450, r.tuning.roof - r.rider.body.radius - 1), vel: Vec2(0, 200))
            #expect(has(r.step(still), "bumpedRoof"))
            knocks.append(-r.rider.vel.y)
            run(&r, steps: seconds(0.3))
        }
        #expect(knocks[0] < r.tuning.ceilingKnock + 5)
        #expect(knocks[1] > knocks[0] + 20 && knocks[2] > knocks[1] + 20, "\(knocks)")
        #expect(knocks[3] >= knocks[2] - 1)
        // After a pause the next bump is ordinary again.
        run(&r, steps: seconds(r.tuning.pinnedWindow + 0.5))
        r.placeRider(at: Vec2(450, r.tuning.roof - r.rider.body.radius - 1), vel: Vec2(0, 200))
        _ = r.step(still)
        #expect(-r.rider.vel.y < r.tuning.ceilingKnock + 5)
    }

    /// Vents lift opponents as they lift the rider.
    @Test func aVentCarriesAnOpponentUp() throws {
        var r = quietRun()
        r.removeRider()
        let vent = r.vents[0]
        let id = r.place(.glider, at: Vec2(vent.x, 200))
        r.freeze(id)
        run(&r, steps: seconds(0.6))
        let o = try r.req(opponent: id)
        #expect(o.pos.y > 230)
        #expect(o.vel.y > 100)
    }

    @Test func aVentCarriesTheRiderUpWithoutFlapping() throws {
        var r = quietRun()
        let vent = r.vents[0]
        r.placeRider(at: Vec2(vent.x, 120))
        let events = run(&r, steps: seconds(1.5))
        #expect(count(events, "ventEntered") == 1)
        #expect(r.rider.pos.y > 250, "\(r.rider.pos.y)")
        #expect(r.rider.vent == 0 || r.rider.pos.y >= vent.top - 30)
        // It is carried no higher than the top of the column (and a little coasting).
        run(&r, steps: seconds(4))
        #expect(r.rider.pos.y < vent.top + 80)
    }

    @Test func theDiveFallsFastAndTheWingsTakeAMomentToReopen() throws {
        var r = quietRun()
        r.placeRider(at: Vec2(450, 560))
        let diveStick = RiftwingInput(stick: Vec2(0, -1))
        var events = r.step(diveStick)
        #expect(has(events, "diveBegan"))
        #expect(r.rider.body.isDiving)
        run(&r, steps: seconds(0.4), input: diveStick)
        #expect(r.rider.vel.y < -r.tuning.terminalFall)
        // The B button dives too.
        #expect(RiftwingInput(dive: true).wantsDive(r.tuning))
        #expect(!RiftwingInput(stick: Vec2(0, -0.5)).wantsDive(r.tuning))
        // No flap while diving.
        events = r.step(RiftwingInput(stick: Vec2(0, -1), flap: true))
        #expect(!has(events, "flapped"))
        // Let go: the wings open after `wingReopen`, and only then will a flap take.
        events = r.step(still)
        #expect(has(events, "wingsOpening"))
        var flapped = false
        var opened = false
        var steps = 0
        while !opened, steps < seconds(1) {
            let e = r.step(RiftwingInput(flap: steps % 2 == 0))
            if has(e, "flapped") && !opened { flapped = true }
            opened = has(e, "wingsOpened")
            steps += 1
        }
        #expect(opened)
        #expect(!flapped)
        #expect(abs(Double(steps) / 120 - r.tuning.wingReopen) < 0.02)
    }

    @Test func aDiveBegunTooLowEndsInTheRift() throws {
        var r = quietRun()
        r.placeRider(at: Vec2(450, 170))
        var lost: RiftwingLossCause?
        // Dive for a moment, then flap as fast as a thumb can (ten a second).
        for step in 0..<seconds(2) {
            let input = step < seconds(0.3) ? RiftwingInput(dive: true) : RiftwingInput(flap: step % 12 < 6)
            for event in r.step(input) {
                if case .riderLost(_, _, let cause) = event { lost = cause }
            }
            if lost != nil { break }
        }
        #expect(lost == .rift)
    }

    @Test func theRiftTakesALifeEvenFromAProtectedRider() throws {
        var r = quietRun()
        r.placeRider(at: Vec2(450, 60))
        r.rider.invulnerableTimer = 10
        let events = run(&r, steps: seconds(1), until: { $0.kind == "riderLost" })
        #expect(events.contains { if case .riderLost(_, 2, .rift) = $0 { true } else { false } })
    }
}

extension RiftwingRun {
    /// A rider in flight with no gravity worth noticing over a few steps (for side-to-side tests).
    mutating func tuningFlatGravity() {
        rider.body.vel.y = 30
    }
}
