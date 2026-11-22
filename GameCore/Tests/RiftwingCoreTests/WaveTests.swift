import Testing
import GameCore
@testable import RiftwingCore

/// The wave table and eases, arrivals, the cavern's layouts, the Rift's breath, lives and the
/// lamps.
@Suite struct RiftwingWaveTests {
    let waves = RiftwingWaves()

    // MARK: The table

    @Test func eachRoleDebutsInAWaveOfItsOwn() throws {
        #expect(waves.debut(of: .glider) == 1)
        #expect(waves.debut(of: .striker) == 3)
        #expect(waves.debut(of: .gleaner) == 4)
        #expect(waves.debut(of: .warden) == 6)
        #expect(waves.debut(of: .sower) == 8)
        for wave in 1...40 {
            let newcomers = RiftwingRole.allCases.filter { waves.debut(of: $0) == wave }
            #expect(newcomers.count <= 1, "wave \(wave): \(newcomers)")
        }
        // Wave 1 is Gliders only; later waves never send none.
        #expect(waves.composition(forWave: 1).map(\.role) == [.glider])
        for wave in 1...40 { #expect(!waves.rigs(forWave: wave).isEmpty) }
    }

    @Test func aRolesAppearancesAreCountedFromTheSameTable() throws {
        for role in RiftwingRole.allCases {
            var seen = 0
            for wave in 1...30 {
                if waves.count(of: role, inWave: wave) > 0 {
                    #expect(waves.appearance(of: role, inWave: wave) == seen)
                    seen += 1
                } else {
                    #expect(waves.appearance(of: role, inWave: wave) == nil)
                }
            }
        }
    }

    /// The fault found three times in Redoubt: an ease counted in wave numbers that ends
    /// abruptly. Here each role's ease steps down across its own appearances to wave 20 and
    /// beyond, never rising, in small steps, and fading out rather than stopping.
    @Test func eachRolesEaseRampsDownAcrossItsOwnAppearances() throws {
        for role in RiftwingRole.allCases {
            let eases = (1...24).filter { waves.count(of: role, inWave: $0) > 0 }.map { waves.ease(of: role, inWave: $0) }
            #expect(!eases.isEmpty)
            #expect(eases.first == 1, "\(role): \(eases)")
            for (a, b) in zip(eases, eases.dropFirst()) {
                #expect(b <= a, "\(role) rises: \(eases)")
                #expect(a - b <= 0.3 + 1e-9, "\(role) cliff: \(eases)")
            }
            let lastNonZero = eases.last { $0 > 0 } ?? 0
            #expect(lastNonZero <= 0.1 + 1e-9, "\(role) ends abruptly: \(eases)")
            #expect(eases.last == 0, "\(role) still eased at wave 24: \(eases)")
        }
    }

    /// Since 2026-11-22 every kind flies at full strength from its first appearance: the ease
    /// left in its first waves no longer slows it, and the clash leniency is 12 at every
    /// strength. `RiftwingWaves.withGentleDebuts` puts back the slower, gentler debuts.
    @Test func everyKindFliesAtFullStrengthFromItsDebut() throws {
        let plain = quietRun(), gentle = quietRun(waves: .withGentleDebuts)
        for role in RiftwingRole.allCases where role != .gleaner {
            #expect(plain.speedScale(role, ease: 1) == 1, "\(role)")
            #expect(gentle.speedScale(role, ease: 1) < 1, "\(role)")
        }
        #expect(waves.leniency(ease: 1) == 12)
        #expect(waves.leniency(ease: 0) == 12)
        #expect(RiftwingWaves.withGentleDebuts.leniency(ease: 0) == 16.1)
        // The ease itself still steps down (it still eases pods and hatched rigs).
        #expect(waves.ease(of: .warden, inWave: 6) == 1)
        // The table and each kind's debut are as they were.
        for wave in 1...30 {
            let a = waves.composition(forWave: wave), b = RiftwingWaves.withGentleDebuts.composition(forWave: wave)
            #expect(a.map(\.role) == b.map(\.role) && a.map(\.count) == b.map(\.count), "wave \(wave)")
        }
    }

    @Test func aRoleBetweenItsAppearancesFliesAtTheEaseOfItsNext() throws {
        // Wardens debut in wave 6; a Warden hatched in wave 4 flies at its first-appearance ease.
        #expect(waves.ease(of: .warden, inWave: 4) == 1)
        // Sowers come in waves 8 and 10: between them, wave 9 reads as their second appearance.
        #expect(waves.ease(of: .sower, inWave: 9) == waves.rampEase[1])
    }

    @Test func opponentsInARunFlyAtTheirRolesEaseForTheWave() throws {
        var r = RiftwingRun(seed: 11)
        var pilot = RiftwingPilot(skill: .competent, seed: 11)
        var checked = 0
        while r.tick < seconds(240), !r.isGameOver {
            _ = r.step(pilot.input(for: r))
            for o in r.opponents where !o.hatched {
                #expect(o.ease == waves.ease(of: o.role, inWave: r.wave))
                checked += 1
            }
        }
        #expect(checked > 1000)
    }

    @Test func theGalleryHoldsOnlyAHandfulOfRigsAtOnce() throws {
        for seed: UInt64 in [1, 2, 3] {
            var r = RiftwingRun(seed: seed)
            var pilot = RiftwingPilot(skill: .competent, seed: seed)
            var most = 0
            while r.tick < seconds(300), !r.isGameOver {
                _ = r.step(pilot.input(for: r))
                guard r.phase == .fighting else { continue }
                let sent = r.opponents.count { $0.role.isRig && !$0.hatched } + r.arrivals.count { $0.role.isRig }
                #expect(sent <= waves.concurrency(forWave: r.wave), "wave \(r.wave): \(sent)")
                most = max(most, r.opponents.count)
            }
            // Four to ten on screen, never ninety.
            #expect(most <= 12)
        }
    }

    // MARK: Arrivals

    @Test func arrivalsGlowInAMouthForASecondThenFlyOut() throws {
        var r = RiftwingRun(seed: 4)
        var glowed: [Int: (Int, Vec2)] = [:]
        var arrived = 0
        while r.tick < seconds(30) {
            for event in r.step(still) {
                if case .arrivalTelegraphed(let id, _, let side, let at) = event {
                    glowed[id] = (r.tick, at)
                    let r0 = r.tuning.stats(for: .striker).radius
                    #expect(side == .left ? at.x < r0 + 1 : at.x > r.tuning.width - r0 - 1)
                    #expect(r.tuning.arrivalHeights.contains(at.y))
                }
                if case .opponentArrived(let id, _, let at) = event {
                    let (tick, pos) = try #require(glowed[id])
                    #expect(r.tick - tick == seconds(r.tuning.telegraphTime))
                    #expect(pos == at)
                    arrived += 1
                }
            }
            if r.isGameOver { break }
        }
        #expect(arrived >= 2)
    }

    @Test func nothingArrivesWithinTheSafeDistanceOfTheRider() throws {
        var landings = 0
        var forced = 0
        for skill in [RiftwingPilot.Skill.novice, .competent, .levelBouncer] {
            for seed: UInt64 in 1...4 {
                var r = RiftwingRun(seed: seed)
                var pilot = RiftwingPilot(skill: skill, seed: seed)
                while r.tick < seconds(200), !r.isGameOver {
                    let before = r
                    for event in r.step(pilot.input(for: before)) {
                        guard case .opponentArrived(let id, _, let at) = event, before.rider.isAlive else { continue }
                        landings += 1
                        let gap = r.wrapDistance(at, r.rider.pos)
                        // A forced arrival (the rider camped where nothing was clear) comes out
                        // at the farthest place instead (`campingTheSideSeamDoesNotStopArrivals`),
                        // never closer than its own least distance.
                        if before.arrivals.first(where: { $0.id == id })?.isForced == true {
                            forced += 1
                            #expect(gap >= r.tuning.forcedClearance - 2, "forced, \(skill) seed \(seed): \(gap)")
                        } else {
                            #expect(gap >= r.tuning.safeDistance - 2, "\(skill) seed \(seed): \(gap)")
                        }
                    }
                }
            }
        }
        #expect(landings > 100)
        print("RIFTWING ARRIVALS \(landings), forced \(forced)")
    }

    /// The farthest place in the mouths is always at least `forcedClearance` from the rider, so a
    /// forced arrival can always keep that far away: if the rider comes that close to where it
    /// glows, the glow moves to the farthest place.
    @Test func aForcedArrivalKeepsItsLeastDistance() throws {
        var r = quietRun()
        let t = r.tuning
        for x in stride(from: 0.0, to: 900, by: 15) {
            for y in stride(from: 40.0, to: 580, by: 15) {
                r.placeRider(at: Vec2(x, y))
                #expect(r.wrapDistance(r.farthestMouthPlace(for: .striker).pos, Vec2(x, y)) >= t.forcedClearance,
                        "rider at \(x), \(y)")
            }
        }
        // A rider camping the seam forces an arrival, then flies at its glow: it comes out away.
        r = RiftwingRun(seed: 5)
        var arrivedAt: Vec2?
        var moved = 0
        for _ in 0..<seconds(14) {
            let glow = r.arrivals.first(where: \.isForced)
            let spot = glow.map { Vec2($0.side == .left ? 30 : 870, $0.pos.y) } ?? Vec2(0, 340)
            r.placeRider(at: spot)
            r.rider.invulnerableTimer = .infinity
            for event in r.step(still) {
                if case .arrivalTelegraphed(let id, _, _, _) = event, glow?.id == id { moved += 1 }
                if case .opponentArrived(let id, _, let at) = event, glow?.id == id {
                    arrivedAt = at
                    #expect(r.wrapDistance(at, r.rider.pos) >= t.forcedClearance - 2)
                }
            }
            if arrivedAt != nil { break }
        }
        #expect(arrivedAt != nil)
        #expect(moved >= 1)
    }

    @Test func anArrivalWhoseMouthTheRiderReachesGlowsAgainElsewhere() throws {
        var r = quietRun()
        r.placeRider(at: Vec2(450, 300))
        let telegraphed = r.telegraph(.striker)
        #expect(telegraphed)
        let arrival = try #require(r.arrivals.first)
        // The rider flies to the mouth before it lands.
        r.placeRider(at: Vec2(arrival.side == .left ? 30 : 870, arrival.pos.y))
        r.rider.invulnerableTimer = .infinity
        var events: [RiftwingEvent] = []
        for _ in 0..<seconds(3) {
            r.rider.body.vel = Vec2(0, 0)
            r.rider.body.pos = Vec2(arrival.side == .left ? 30 : 870, arrival.pos.y)
            events += r.step(still)
        }
        // While the rider sits at the mouths it never comes out near it: it glows again at a
        // clear height, or waits.
        for event in events {
            if case .opponentArrived(arrival.id, _, let at) = event {
                #expect(r.wrapDistance(at, r.rider.pos) >= r.tuning.safeDistance)
            }
        }
        // Once the rider is back in the middle, it comes out.
        r.placeRider(at: Vec2(450, 560))
        r.rider.invulnerableTimer = .infinity
        let later = run(&r, steps: seconds(2))
        #expect(r.opponent(arrival.id) != nil || later.contains { if case .opponentArrived(arrival.id, _, _) = $0 { true } else { false } })
    }

    #if DEBUG
    @Test func gleanersComeLateInAWaveAndSingly() throws {
        var seen = 0
        for seed: UInt64 in 1...6 {
            var config = RiftwingRun.Config()
            config.startAtWave = 4
            var r = RiftwingRun(seed: seed, config: config)
            var pilot = RiftwingPilot(skill: .novice, seed: seed)
            while r.tick < seconds(200), !r.isGameOver {
                for event in r.step(pilot.input(for: r)) {
                    if case .arrivalTelegraphed(_, .gleaner, _, _) = event {
                        seen += 1
                        #expect(r.waveClock >= waves.gleanerDelay(forWave: r.wave) - 1e-9, "wave \(r.wave) at \(r.waveClock)")
                    }
                }
                let gleaners = r.opponents.count { $0.role == .gleaner } + r.arrivals.count { $0.role == .gleaner }
                #expect(gleaners <= 1)
            }
        }
        #expect(seen >= 3)
        // With `withGentleDebuts` (the early flying taken out on 2026-11-22): late and slow at
        // first, sooner and faster with each appearance.
        let gentle = RiftwingWaves.withGentleDebuts
        #expect(gentle.gleanerDelay(forWave: 4) > gentle.gleanerDelay(forWave: 5))
        #expect(gentle.gleanerSpeedScale(forWave: 4) < gentle.gleanerSpeedScale(forWave: 7))
        #expect(gentle.gleanerMinCarry(forWave: 4, tuning: RiftwingTuning()) > gentle.gleanerMinCarry(forWave: 12, tuning: RiftwingTuning()))
        #expect(gentle.gleanerMinCarry(forWave: 30, tuning: RiftwingTuning()) == RiftwingTuning().gleanerMinCarry)
        // By default a Gleaner is at full strength from its debut: 8 s into the wave, at full
        // speed, with the shortest grab and carry.
        for wave in 4...30 {
            #expect(waves.gleanerDelay(forWave: wave) == waves.gleanerDelayBase)
            #expect(waves.gleanerSpeedScale(forWave: wave) == 1)
            #expect(waves.gleanerGrab(forWave: wave, tuning: RiftwingTuning()) == RiftwingTuning().gleanerGrab)
            #expect(waves.gleanerMinCarry(forWave: wave, tuning: RiftwingTuning()) == RiftwingTuning().gleanerMinCarry)
        }
    }
    #endif

    @Test func gleanersDoNotHoldAWaveOpenAndLeaveWithIt() throws {
        var r = RiftwingRun(seed: 3)
        run(&r, steps: seconds(r.tuning.firstWaveDelay + 0.1))
        r.sendIndex = r.toSend.count
        r.opponents.removeAll()
        r.arrivals.removeAll()
        let g = r.place(.gleaner, at: Vec2(300, 400))
        let events = r.step(still)
        #expect(events.contains { if case .opponentWithdrew(g, .gleaner, _) = $0 { true } else { false } })
        #expect(has(events, "waveCleared"))
        #expect(r.opponents.isEmpty)
    }

    // MARK: The cavern

    @Test func theLayoutsAreOriginalUnevenAndOpenOverTheRift() throws {
        let layouts = RiftwingCavern.layouts
        #expect(layouts.count == 3)
        let t = RiftwingTuning()
        for layout in layouts {
            #expect((4...6).contains(layout.ledges.count), "\(layout.name)")
            #expect((2...3).contains(layout.vents.count), "\(layout.name)")
            let tops = layout.ledges.map(\.top)
            #expect(Set(tops).count == tops.count, "\(layout.name): uneven heights")
            #expect((tops.max() ?? 0) - (tops.min() ?? 0) >= 250, "\(layout.name)")
            for ledge in layout.ledges {
                #expect(ledge.minX >= 0 && ledge.maxX <= t.width && ledge.minX < ledge.maxX, "\(layout.name)")
                #expect(ledge.top > t.riftLevel + 70 && ledge.top < t.roof - 80, "\(layout.name)")
            }
            // No floor over the Rift: most columns fall straight into it, and the low shelves
            // cover well under half the width.
            let open = stride(from: 0.0, to: t.width, by: 5).filter { x in !layout.ledges.contains { $0.spans(x) && $0.top < 200 } }
            #expect(Double(open.count) / (t.width / 5) > 0.4, "\(layout.name)")
            let low = layout.ledges.filter { $0.top < 200 }.reduce(0) { $0 + $1.length }
            #expect(low < t.width * 0.5, "\(layout.name)")
            // Never symmetrical: mirrored, the ledges do not line up.
            let mirrored = layout.ledges.map { RiftwingLedge(t.width - $0.maxX, t.width - $0.minX, top: $0.top) }
            let matches = mirrored.filter { m in layout.ledges.contains { abs($0.midX - m.midX) < 40 && abs($0.top - m.top) < 40 } }
            #expect(matches.count < layout.ledges.count / 2, "\(layout.name)")
            // Vents rise through open air, never into a ledge's underside.
            for vent in layout.vents {
                for ledge in layout.ledges where abs(ledge.midX - vent.x) < ledge.length / 2 + t.ventHalfWidth {
                    #expect(vent.top < ledge.top - t.ledgeThickness, "\(layout.name): vent at \(vent.x)")
                }
            }
            #expect(layout.ledges.indices.contains(layout.startLedge))
        }
        // The three are different from one another.
        #expect(Set(layouts.map(\.ledges.count)).count >= 2 || layouts[0].ledges != layouts[1].ledges)
    }

    @Test func theCavernShiftsEveryThreeWavesWithARumbleAndALongerBreak() throws {
        var r = RiftwingRun(seed: 1)
        r.rider.invulnerableTimer = .infinity
        var layoutsByWave: [Int: Int] = [:]
        var shifts: [(Int, Int)] = []
        var shifted: [Int] = []
        for _ in 0..<12 {
            // Run to the next wave's start, then clear it at once.
            var started = false
            while !started {
                for event in r.step(still) {
                    if case .waveStarted(let w, let layout) = event {
                        layoutsByWave[w] = layout
                        started = true
                    }
                    if case .cavernShifted(let l) = event { shifted.append(l) }
                }
            }
            r.sendIndex = r.toSend.count
            r.opponents.removeAll()
            r.arrivals.removeAll()
            r.rider.invulnerableTimer = .infinity
            for event in r.step(still) {
                if case .cavernShifting(let from, let to) = event { shifts.append((from, to)) }
            }
            if case .intermission(let remaining) = r.phase {
                let shifting = r.wave % 3 == 0
                #expect(abs(remaining - (r.tuning.intermission + (shifting ? r.tuning.shiftPause : 0))) < 0.02)
            }
        }
        #expect((1...12).map { layoutsByWave[$0]! } == [0, 0, 0, 1, 1, 1, 2, 2, 2, 0, 0, 0])
        #expect(shifts.map(\.0) == [0, 1, 2, 0])
        #expect(shifts.map(\.1) == [1, 2, 0, 1])
        #expect(shifted == [1, 2, 0])
    }

    // MARK: The Rift's breath

    @Test func aDraggingWaveMakesTheRiftBreatheAfterAWarning() throws {
        var tuning = RiftwingTuning()
        tuning.breathLevel = 200  // so the first layout's low shelf (top 135) is under the first breath
        var r = quietRun(tuning: tuning)
        let low = r.ledges[0]
        let after = r.tuning.breathAfter(forWave: 1)
        r.placeRider(at: Vec2(low.midX, low.top + 40))
        // A pod dropped onto the same low shelf shortly before the breath.
        run(&r, steps: seconds(after - 5))
        let pod = r.dropPod(at: Vec2(low.midX + 50, low.top + 10), vel: .zero, from: .glider)
        var warnedAt: Double?, breathedAt: Double?, lost: Double?, podLost = false, settled = false
        for step in seconds(after - 5)..<seconds(after + 10) {
            for event in r.step(still) {
                let t = Double(step + 1) / 120
                if case .riftWarning(let level) = event { warnedAt = t; #expect(level == r.tuning.breathLevel) }
                if case .riftBreathed = event { breathedAt = t }
                if case .riderLost(_, _, .breath) = event { lost = t }
                if case .podLost(pod, _, .breath) = event { podLost = true }
                if case .riftSettled = event { settled = true }
            }
            // While it only warns, nothing is lost.
            if case .warning = r.breath { #expect(r.rider.isAlive) }
        }
        let w = try #require(warnedAt), b = try #require(breathedAt), l = try #require(lost)
        #expect(abs(w - after) < 0.02)
        #expect(abs(b - w - r.tuning.breathWarning) < 0.02)
        #expect(l >= b)
        #expect(podLost)
        #expect(settled)
    }

    /// The first warning comes late while a new player is slow (about 90 s into waves 1 and 2),
    /// easing to about 50 s by wave 7, never earlier.
    @Test func theBreathComesLateInTheFirstWaves() throws {
        let t = RiftwingTuning()
        #expect(t.breathAfter(forWave: 1) == 90)
        #expect(t.breathAfter(forWave: 2) == 90)
        #expect(t.breathAfter(forWave: 7) == 50)
        #expect(t.breathAfter(forWave: 20) == 50)
        for wave in 1..<20 { #expect(t.breathAfter(forWave: wave + 1) <= t.breathAfter(forWave: wave)) }
    }

    /// The breath grows in steps, each a height with room above to fly in; only the last fills
    /// the gallery, after a warning of its own; then the cycle starts again from the lowest.
    @Test func theBreathRisesInStepsThenFillsTheGalleryAndStartsAgain() throws {
        var r = quietRun()
        r.removeRider()
        var warnings: [(fill: Bool, level: Double, at: Int)] = []
        var breathed: [Int] = []
        for _ in 0..<seconds(400) {
            for event in r.step(still) {
                if case .riftWarning(let level) = event { warnings.append((false, level, r.tick)) }
                if case .riftFillWarning(let level) = event { warnings.append((true, level, r.tick)) }
                if case .riftBreathed = event { breathed.append(r.tick) }
            }
        }
        let steps = r.tuning.breathSteps
        #expect(steps >= 3)
        try #require(warnings.count >= steps + 2)
        for i in 0..<steps {
            #expect(!warnings[i].fill)
            #expect(abs(warnings[i].level - (r.tuning.breathLevel + r.tuning.breathGrowth * Double(i))) < 1e-9)
            // Room above every step: the gallery's upper part stays clear.
            #expect(warnings[i].level < r.tuning.roof - 150)
            if i > 0 { #expect(warnings[i].level > warnings[i - 1].level) }
        }
        #expect(warnings[steps].fill)
        #expect(warnings[steps].level == r.tuning.roof)
        // Its own, longer warning.
        #expect(abs(Double(breathed[steps] - warnings[steps].at) / 120 - r.tuning.breathFillWarning) < 0.02)
        #expect(r.tuning.breathFillWarning > r.tuning.breathWarning)
        // Then it starts again from the lowest step.
        #expect(!warnings[steps + 1].fill)
        #expect(warnings[steps + 1].level == r.tuning.breathLevel)
    }

    /// Opponents are lost to a step of the breath but shelter from the gas that fills the
    /// gallery, so the fill ends a stalling rider's lives without clearing the wave for it.
    @Test func opponentsShelterFromTheFillButNotFromAStep() throws {
        var r = quietRun()
        r.removeRider()
        let low = r.place(.glider, at: Vec2(500, 80))
        r.freeze(low)
        r.breathsThisWave = 1
        r.breath = .holding(remaining: 1)
        let events = r.step(still)
        #expect(events.contains { if case .opponentFell(low, _, _, .breath) = $0 { true } else { false } })
        var f = quietRun()
        f.removeRider()
        let high = f.place(.glider, at: Vec2(500, 300))
        f.freeze(high)
        f.breathsThisWave = f.tuning.breathSteps + 1
        #expect(f.isBreathFilling)
        f.breath = .holding(remaining: 1)
        for _ in 0..<seconds(0.5) {
            f.opponents[f.index(of: high)].body.vel = .zero
            f.opponents[f.index(of: high)].body.pos = Vec2(500, 300)
            #expect(!has(f.step(still), "opponentFell"))
        }
        #expect(f.opponent(high) != nil)
    }

    @Test func aRiderHighUpIsNotTouchedByTheFirstBreath() throws {
        var r = quietRun()
        let high = r.ledges[4]  // top 455
        r.placeRider(at: Vec2(high.midX, high.top + 30))
        let events = run(&r, steps: seconds(r.tuning.breathAfter(forWave: 1) + 9))
        #expect(has(events, "riftBreathed"))
        #expect(!has(events, "riderLost"))
    }

    /// While the Rift breathes, a lost rider returns on a ledge above the gas when there is one.
    @Test func aRiderReturnsAboveTheGasWhenALedgeIsClear() throws {
        var tuning = RiftwingTuning()
        tuning.breathLevel = 300
        var r = quietRun(tuning: tuning)
        r.breathsThisWave = 1
        r.breath = .warning(remaining: 3)
        r.placeRider(at: Vec2(450, 560))
        r.loseRider(cause: .rift)
        var ledge: Int?
        for _ in 0..<seconds(r.tuning.respawnDelay + 0.1) {
            for event in r.step(still) {
                if case .riderRespawned(_, let l) = event { ledge = l }
            }
        }
        let l = try #require(ledge)
        #expect(r.ledges[l].top > r.breathLevel)
        #expect(!has(run(&r, steps: seconds(6)), "riderLost"))
    }

    // MARK: Lives

    @Test func aLostRiderReturnsOnTheLedgeFarthestFromTheFightProtected() throws {
        var r = quietRun()
        // Opponents near every ledge but the fourth (index 3).
        for (i, ledge) in r.ledges.enumerated() where i != 3 {
            let id = r.place(.glider, at: Vec2(ledge.midX, ledge.top + 60))
            r.freeze(id)
            r.opponents[r.index(of: id)].body.vel = .zero
        }
        r.placeRider(at: Vec2(700, 560))
        r.loseRider(cause: .rift)
        var respawned: Int?
        for _ in 0..<seconds(r.tuning.respawnDelay + 0.1) {
            for event in r.step(still) {
                if case .riderRespawned(_, let ledge) = event { respawned = ledge }
            }
            for i in r.opponents.indices { r.opponents[i].body.vel = .zero }
        }
        #expect(respawned == 3)
        #expect(r.rider.isAlive)
        #expect(r.rider.body.ledge == 3)
        #expect(r.rider.invulnerableTimer > r.tuning.respawnInvulnerability - 0.2)
    }

    @Test func anExtraLifeComesAtEachThresholdUpToTheMost() throws {
        var r = quietRun()
        let every = r.tuning.extraLifeEvery
        r.addScore(every - 1)
        #expect(r.rider.lives == 3)
        r.addScore(1)
        #expect(r.rider.lives == 4)
        r.addScore(every * 5)
        #expect(r.rider.lives == r.tuning.maxLives)
    }

    @Test func losingTheLastLifeEndsTheRun() throws {
        var r = quietRun()
        r.rider.lives = 1
        r.placeRider(at: Vec2(520, 60))
        let events = run(&r, steps: seconds(1))
        #expect(events.contains { if case .gameOver = $0 { true } else { false } })
        #expect(r.isGameOver)
        #expect(r.ending == .defeated)
        #expect(r.step(still).isEmpty)
    }

    // MARK: Lamps out

    @Test func losingEveryColonistOfAWavePutsTheLampsOutUntilOneIsFreed() throws {
        var r = RiftwingRun(seed: 3)
        run(&r, steps: seconds(r.tuning.firstWaveDelay + 0.1))
        r.sendIndex = r.toSend.count
        r.opponents.removeAll()
        r.arrivals.removeAll()
        r.waveDropped = 2
        r.waveLost = 2
        let cleared = r.step(still)
        #expect(cleared.contains { if case .allColonistsLost(1) = $0 { true } else { false } })
        #expect(r.lampsOutPending)
        #expect(!r.isLampsOut)
        let next = run(&r, steps: seconds(r.tuning.intermission + 0.1), until: { $0.kind == "waveStarted" })
        #expect(has(next, "lampsFailed"))
        #expect(r.isLampsOut)
        #expect(!r.lampsOutPending)
        // Freeing a colonist brings them back.
        let pod = r.dropPod(at: Vec2(570, 400), vel: .zero, from: .glider)
        r.pods[r.pods.count - 1].catchableIn = 0
        r.placeRider(at: Vec2(570, 395))
        r.rider.invulnerableTimer = .infinity
        let freed = r.step(still)
        #expect(freed.contains { if case .podCaught(pod, _, _, _) = $0 { true } else { false } })
        #expect(has(freed, "lampsRestored"))
        #expect(!r.isLampsOut)
    }

    @Test func aWaveThatDroppedNoPodsDoesNotPutTheLampsOut() throws {
        var r = RiftwingRun(seed: 3)
        run(&r, steps: seconds(r.tuning.firstWaveDelay + 0.1))
        r.sendIndex = r.toSend.count
        r.opponents.removeAll()
        r.arrivals.removeAll()
        let events = r.step(still)
        #expect(has(events, "waveCleared"))
        #expect(!has(events, "allColonistsLost"))
        #expect(!r.lampsOutPending)
    }

    #if DEBUG
    @Test func theLampsCanBeForcedOutAtAWaveForTesting() throws {
        var config = RiftwingRun.Config()
        config.lampsOutAtWave = 2
        var r = RiftwingRun(seed: 3, config: config)
        run(&r, steps: seconds(r.tuning.firstWaveDelay + 0.1))
        #expect(r.wave == 1)
        #expect(!r.isLampsOut)
        r.sendIndex = r.toSend.count
        r.opponents.removeAll()
        r.arrivals.removeAll()
        _ = r.step(still)
        #expect(r.lampsOutPending)
        let events = run(&r, steps: seconds(4), until: { $0.kind == "waveStarted" })
        #expect(has(events, "lampsFailed"))
        #expect(r.isLampsOut)

        config.lampsOutAtWave = 1
        var first = RiftwingRun(seed: 3, config: config)
        #expect(first.lampsOutPending)
        let start = run(&first, steps: seconds(2), until: { $0.kind == "waveStarted" })
        #expect(has(start, "lampsFailed"))
    }

    @Test func aRunCanStartAtALaterWaveForTesting() throws {
        var config = RiftwingRun.Config()
        config.startAtWave = 7
        var r = RiftwingRun(seed: 3, config: config)
        #expect(r.layoutIndex == 2)
        let events = run(&r, steps: seconds(2), until: { $0.kind == "waveStarted" })
        #expect(events.contains { if case .waveStarted(7, 2) = $0 { true } else { false } })
        #expect(r.toSend == waves.rigs(forWave: 7))
    }

    @Test func theRiftsFirstBreathCanBeBroughtForwardForTesting() throws {
        var config = RiftwingRun.Config()
        config.breathAfter = 3
        var r = RiftwingRun(seed: 3, config: config)
        let events = run(&r, steps: seconds(6), until: { $0.kind == "riftWarning" })
        #expect(has(events, "riftWarning"))
        #expect(r.wave == 1)
    }
    #endif
}
