import Foundation
import Testing
import GameCore
@testable import RedoubtCore

@Suite struct RedoubtSoundDirectorTests {
    static let p = Vec2(450, 300)
    static let theme = CalderDome()

    /// Asks the director about `events` as one frame at `tick`.
    static func frame(_ director: inout RedoubtSoundDirector, _ events: [RedoubtEvent], tick: Int,
                      delivered: Int = 0, hp: Int? = nil) -> [Int?] {
        events.map { director.variant(for: $0, tick: tick, delivered: delivered, hp: { _ in hp }) }
    }

    @Test func aCrowdArrivingIsOneSoundPerFrame() {
        var director = RedoubtSoundDirector()
        let markers = (0..<90).map { RedoubtEvent.arrivalTelegraphed(id: $0, role: .skitter, at: Self.p) }
            + [.arrivalTelegraphed(id: 99, role: .spitter, at: Self.p)]
        let voiced = Self.frame(&director, markers, tick: 10).compactMap { $0 }
        // One for the Skitters, one for the newcomer.
        #expect(voiced.count == 2)
        // Another group within the second is quiet; after it, it sounds again.
        #expect(Self.frame(&director, [markers[0]], tick: 11).compactMap { $0 }.isEmpty)
        #expect(Self.frame(&director, [markers[0]], tick: 10 + RedoubtSoundDirector.arrivalGapTicks).compactMap { $0 }.count == 1)
    }

    @Test func eightSkittersDyingTogetherAreOneLightSoundAndTheyAreSpacedOut() {
        var director = RedoubtSoundDirector()
        let deaths = (0..<8).map { RedoubtEvent.enemyDestroyed(id: $0, role: .skitter, at: Self.p, points: 50, byShockwave: false) }
        #expect(Self.frame(&director, deaths, tick: 100).compactMap { $0 }.count == 1)
        // Every step for 50 ms: voiced every `skitterGapTicks` steps only.
        var voiced = 0
        for tick in 101...106 {
            voiced += Self.frame(&director, [deaths[0]], tick: tick).compactMap { $0 }.count
        }
        #expect(voiced == 6 / RedoubtSoundDirector.skitterGapTicks)
        // A Gleaner dying in a Skitter frame still sounds.
        let mixed = Self.frame(&director, deaths + [.enemyDestroyed(id: 50, role: .gleaner, at: Self.p, points: 150,
                                                                    byShockwave: false)], tick: 200)
        #expect(mixed.compactMap { $0 }.count == 2)
    }

    @Test func theShockwaveSpeaksForTheSmallFryButNotForTheHeavies() {
        var director = RedoubtSoundDirector()
        var events: [RedoubtEvent] = [.shockwave(at: Self.p, destroyed: 40)]
        for role in [RedoubtRole.skitter, .gleaner, .spitter, .husk] {
            events.append(.enemyDestroyed(id: 1, role: role, at: Self.p, points: 1, byShockwave: true))
        }
        events.append(.enemyDestroyed(id: 2, role: .burrow, at: Self.p, points: 1000, byShockwave: true))
        events.append(.enemyDestroyed(id: 3, role: .thresher, at: Self.p, points: 1500, byShockwave: true))
        let voiced = Self.frame(&director, events, tick: 5)
        #expect(voiced.map { $0 != nil } == [true, false, false, false, false, true, true])
    }

    @Test func shotsTakeAPitchAtRandomNeverTheSameTwiceRunning() {
        var director = RedoubtSoundDirector()
        var pitches: [Int] = []
        for i in 0..<300 {
            // A shot every 12 steps (ten a second), each in its own frame, every one voiced.
            let v = Self.frame(&director, [.orbFired(at: Self.p, heading: 0)], tick: 12 * (i + 1))
            #expect(v[0] != nil)
            pitches.append(v[0] ?? -1)
        }
        #expect(zip(pitches, pitches.dropFirst()).allSatisfy { $0 != $1 })
        #expect(Set(pitches) == Set(0..<RedoubtSoundDirector.pitchVariants))
        // Not a fixed cycle: some pitch follows another in more than one way.
        let pairs = Set(zip(pitches, pitches.dropFirst()).map { "\($0)\($1)" })
        #expect(pairs.count == 6)
        // The same calls give the same answers.
        var again = RedoubtSoundDirector()
        let replay = (0..<300).map { Self.frame(&again, [.orbFired(at: Self.p, heading: 0)], tick: 12 * ($0 + 1))[0] ?? -1 }
        #expect(replay == pitches)
    }

    @Test func aDeliveryIsVoicedOnceWithTheNumberDelivered() {
        var director = RedoubtSoundDirector()
        _ = Self.frame(&director, [.orbFired(at: Self.p, heading: 0)], tick: 1, delivered: 2)
        let line = (1...5).map { RedoubtEvent.colonistDelivered(id: $0, at: Self.p, position: $0, points: 500 * $0) }
        let voiced = Self.frame(&director, line + [.chargeEarned(charges: 1)], tick: 2, delivered: 7)
        #expect(voiced == [5, nil, nil, nil, nil, 0])
        #expect(Self.theme.sound(for: line[0], variant: voiced[0]!)?.name == "dome.delivery.5")
        // A later single delivery counts only itself.
        #expect(Self.frame(&director, [line[0]], tick: 50, delivered: 8) == [1])
        // A new run (counts back to zero) after a reset.
        director.reset()
        #expect(Self.frame(&director, [line[0]], tick: 3, delivered: 1) == [1])
    }

    @Test func aBurrowHitSaysHowDamagedItIs() {
        #expect(RedoubtSoundDirector.burrowStage(hp: 20) == 0)
        #expect(RedoubtSoundDirector.burrowStage(hp: 14) == 0)
        #expect(RedoubtSoundDirector.burrowStage(hp: 13) == 1)
        #expect(RedoubtSoundDirector.burrowStage(hp: 7) == 1)
        #expect(RedoubtSoundDirector.burrowStage(hp: 6) == 2)
        #expect(RedoubtSoundDirector.burrowStage(hp: 1) == 2)
        var director = RedoubtSoundDirector()
        let hit = RedoubtEvent.enemyHit(id: 4, role: .burrow, at: Self.p)
        #expect(Self.frame(&director, [hit], tick: 1, hp: 3) == [2])
        #expect(Self.theme.sound(for: hit, variant: 2)?.name == "dome.burrow.hit.3")
    }

    #if DEBUG
    /// A real game, voiced as the app voices it: the busiest frame stays within the synth's
    /// voices, and over a whole wave the sounds asked for stay a stream, not a flood.
    @Test func aCompetentGameStaysWithinTheVoices() {
        var run = RedoubtRun(seed: 7)
        var pilot = RedoubtPilot(skill: .competent, seed: 7)
        var director = RedoubtSoundDirector()
        var busiestFrame = 0
        var perSecond: [Int] = []
        var thisSecond = 0
        var byName: [String: Int] = [:]
        var events = 0
        for step in 1...(120 * 240) where !run.isGameOver {
            let frame = run.step(pilot.input(for: run))
            events += frame.count
            var voiced = 0
            for event in frame {
                guard let variant = director.variant(for: event, in: run),
                      let patch = Self.theme.sound(for: event, variant: variant) else { continue }
                voiced += 1
                byName[patch.name, default: 0] += 1
            }
            busiestFrame = max(busiestFrame, voiced)
            thisSecond += voiced
            if step % 120 == 0 {
                perSecond.append(thisSecond)
                thisSecond = 0
            }
        }
        let average = Double(perSecond.reduce(0, +)) / Double(max(perSecond.count, 1))
        print("VOICED seed 7 competent: \(events) events, busiest frame \(busiestFrame) sounds, average \(String(format: "%.1f", average))/s, busiest second \(perSecond.max() ?? 0), wave \(run.wave)")
        print("VOICED by patch: " + byName.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        #expect(busiestFrame <= 8)
        #expect((perSecond.max() ?? 0) <= 60)
        // The shots are most of what is heard; Skitter deaths next.
        let shots = byName.filter { $0.key.hasPrefix("dome.orb.fire") }.values.reduce(0, +)
        #expect(shots > byName.values.reduce(0, +) / 3)
        #expect(byName.keys.contains { $0.hasPrefix("dome.delivery") })
        #expect(byName["dome.wave.start", default: 0] >= 3)
    }
    #endif
}

@Suite struct RedoubtMoodTests {
    @Test func theMoodFollowsTheRun() {
        #expect(RedoubtMoodDirector.mood(fighting: true, powerCut: false) == .tension)
        #expect(RedoubtMoodDirector.mood(fighting: false, powerCut: false) == .calm)
        #expect(RedoubtMoodDirector.mood(fighting: true, powerCut: true) == .blackout)
        #expect(RedoubtMoodDirector.mood(fighting: false, powerCut: true) == .blackout)
        var director = RedoubtMoodDirector()
        #expect(director.mood == .calm)
        #expect(director.update(fighting: true, powerCut: false) == .tension)
        #expect(director.update(fighting: true, powerCut: true) == .blackout)
        // Power back mid-wave: straight back to the wave's tension.
        #expect(director.update(fighting: true, powerCut: false) == .tension)
        director.reset()
        #expect(director.mood == .calm)
    }

    @Test func aNewRunBeginsCalmUntilTheFirstWave() {
        var director = RedoubtMoodDirector()
        var run = RedoubtRun(seed: 1)
        #expect(director.update(run: run) == .calm)
        while run.phase != .fighting { _ = run.step(RedoubtInput()) }
        #expect(director.update(run: run) == .tension)
    }

    #if DEBUG
    /// A competent game: the music goes calm, tense, calm, ... and changes only when a wave
    /// starts or clears; each wave holds its tension for its whole length.
    @Test func aRealGameMovesBetweenCalmAndTensionAndNeverFlaps() {
        var run = RedoubtRun(seed: 7)
        var pilot = RedoubtPilot(skill: .competent, seed: 7)
        var director = RedoubtMoodDirector()
        var last = director.update(run: run)
        var changes: [(time: Double, mood: MusicMood)] = []
        var structural = 0
        for _ in 0..<(120 * 300) where !run.isGameOver {
            for event in run.step(pilot.input(for: run)) {
                switch event {
                case .waveStarted, .waveCleared, .powerCutBegan, .powerCutEnded: structural += 1
                default: break
                }
            }
            let mood = director.update(run: run)
            if mood != last {
                changes.append((Double(run.tick) / 120, mood))
                last = mood
            }
        }
        let summary = changes.map { "\(String(format: "%.0f", $0.time))s \($0.mood.rawValue)" }.joined(separator: ", ")
        print("MOOD seed 7 competent: wave \(run.wave), \(changes.count) changes: \(summary)")
        #expect(changes.count { $0.mood == .calm } >= 3 && changes.count { $0.mood == .tension } >= 4)
        #expect(changes.count <= structural)
        let gaps = zip(changes, changes.dropFirst()).map { $1.time - $0.time }
        #expect(gaps.allSatisfy { $0 >= 1.5 }, "\(gaps)")
    }
    #endif

    /// The power cut is dark from the moment the lights fail until they come back, mid-wave.
    @Test func thePowerCutIsDarkUntilTheLightsReturn() {
        var run = RedoubtRun(seed: 3)
        var director = RedoubtMoodDirector()
        // Every colonist of a wave lost: the lights fail when the next wave starts.
        run.powerCutPending = true
        var began = false
        while !began {
            began = run.step(RedoubtInput()).contains(.powerCutBegan)
            #expect(director.update(run: run) == (began ? .blackout : .calm))
        }
        #expect(run.phase == .fighting)
        for _ in 0..<240 { #expect(director.update(run: run) == .blackout); _ = run.step(RedoubtInput()) }
        run.isPowerCut = false
        #expect(director.update(run: run) == .tension)
    }
}

@Suite struct RedoubtHapticTests {
    static let p = Vec2(450, 300)

    @Test func theRoutineIsNotFelt() {
        var silent: [RedoubtEvent] = [
            .orbFired(at: Self.p, heading: 0), .shotEnded(id: 1, at: Self.p, reason: .hit),
            .burrowSpawned(burrow: 1, id: 2, at: Self.p), .spitterWindUp(id: 1, at: Self.p),
            .enemyFired(id: 1, at: Self.p, heading: 0), .orbRespawned(at: Self.p),
            .airlockOpened(wall: .east, at: Self.p), .airlockClosed(at: Self.p), .lineScattered(count: 2),
            .enemyDestroyed(id: 1, role: .skitter, at: Self.p, points: 50, byShockwave: false),
            .enemyDestroyed(id: 1, role: .skitter, at: Self.p, points: 50, byShockwave: true),
            .colonistDelivered(id: 2, at: Self.p, position: 2, points: 1000),
        ]
        for role in RedoubtRole.allCases {
            silent.append(.enemyHit(id: 1, role: role, at: Self.p))
            silent.append(.arrivalTelegraphed(id: 1, role: role, at: Self.p))
            silent.append(.enemyArrived(id: 1, role: role, at: Self.p))
            silent.append(.enemyWithdrew(id: 1, role: role, at: Self.p))
        }
        for event in silent {
            #expect(HapticCue.cue(for: event) == nil, "\(event)")
        }
    }

    @Test func whatMattersIsFeltByWeight() {
        let expected: [(RedoubtEvent, HapticCue)] = [
            (.orbDestroyed(at: Self.p, livesLeft: 1, cause: .shot(id: 1)), .rumble),
            (.powerCutBegan, .rumble), (.gameOver(score: 10), .rumble),
            (.shockwave(at: Self.p, destroyed: 3), .sweep),
            (.colonistSeized(id: 1, by: 2, at: Self.p), .warning), (.huskFormed(id: 1, at: Self.p), .warning),
            (.colonistTaken(id: 1, by: .gleaner, enemy: 2, at: Self.p), .impact),
            (.colonistCrushed(id: 1, by: 2, at: Self.p), .impact),
            (.enemyDestroyed(id: 1, role: .burrow, at: Self.p, points: 1000, byShockwave: false), .impact),
            (.enemyDestroyed(id: 1, role: .thresher, at: Self.p, points: 1500, byShockwave: true), .impact),
            (.enemyDestroyed(id: 1, role: .gleaner, at: Self.p, points: 150, byShockwave: false), .tap),
            (.enemyDestroyed(id: 1, role: .husk, at: Self.p, points: 250, byShockwave: false), .tap),
            (.colonistDelivered(id: 1, at: Self.p, position: 1, points: 500), .doubleTap),
            (.waveCleared(wave: 1, safe: 2, bonus: 500), .doubleTap), (.extraLife(lives: 4), .doubleTap),
            (.powerCutEnded, .doubleTap),
            (.waveStarted(wave: 2, colonists: 6), .tap), (.colonistFreed(id: 1, at: Self.p), .tap),
            (.chargeEarned(charges: 2), .tap),
            (.colonistPickedUp(id: 1, at: Self.p, position: 1), .tick),
        ]
        for (event, cue) in expected {
            #expect(HapticCue.cue(for: event) == cue, "\(event)")
        }
        // The Shockwave's sweep covers the small fry it clears.
        for role in [RedoubtRole.gleaner, .spitter, .husk] {
            #expect(HapticCue.cue(for: .enemyDestroyed(id: 1, role: role, at: Self.p, points: 1, byShockwave: true)) == nil)
        }
    }

    #if DEBUG
    /// A competent game is felt now and then, never as a constant buzz.
    @Test func aCompetentGameIsNotABuzz() {
        var run = RedoubtRun(seed: 7)
        var pilot = RedoubtPilot(skill: .competent, seed: 7)
        var cues = 0
        var steps = 0
        var busiestSecond = 0, thisSecond = 0
        for step in 1...(120 * 180) where !run.isGameOver {
            for event in run.step(pilot.input(for: run)) where HapticCue.cue(for: event) != nil {
                cues += 1
                thisSecond += 1
            }
            steps = step
            if step % 120 == 0 {
                busiestSecond = max(busiestSecond, thisSecond)
                thisSecond = 0
            }
        }
        let perSecond = Double(cues) / (Double(steps) / 120)
        print("HAPTICS seed 7 competent: \(cues) cues in \(steps / 120) s (\(String(format: "%.2f", perSecond))/s), busiest second \(busiestSecond)")
        #expect(perSecond < 1.5)
        #expect(busiestSecond <= 8)
    }
    #endif
}
