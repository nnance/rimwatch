import Foundation
import Testing
import GameCore
@testable import RiftwingCore

/// A model of the app's synthesiser voices (`Rimwatch/Shell/Audio/Synth.swift`), so a test can
/// check what a real game's sounds would do to them: 12 voices, each patch's cooldown and copy
/// limit, and a new sound taking a free voice, else the oldest of the lowest priority no higher
/// than its own, else dropped.
struct CavesVoiceModel {
    struct Voice {
        var name: String?
        var priority = 0
        var startedAt = 0.0
        var endsAt = 0.0
    }

    var voices = [Voice](repeating: Voice(), count: 12)
    var lastStart: [String: Double] = [:]
    /// Patch names dropped because every voice was busy with something that mattered more.
    var crowdedOut: [String: Int] = [:]
    var rateLimited: [String: Int] = [:]
    var cutShort: [String: Int] = [:]
    var started: [String: Int] = [:]

    mutating func play(_ patch: SoundPatch, at now: Double) {
        let name = patch.name
        if let last = lastStart[name], now - last < patch.cooldown {
            rateLimited[name, default: 0] += 1
            return
        }
        let copies = voices.indices.filter { voices[$0].name == name && voices[$0].endsAt > now }
        let index: Int
        if copies.count >= patch.maxVoices, let oldest = copies.min(by: { voices[$0].startedAt < voices[$1].startedAt }) {
            index = oldest
        } else if let free = voices.indices.first(where: { voices[$0].endsAt <= now }) {
            index = free
        } else if let victim = voices.indices
            .filter({ voices[$0].priority <= patch.priority })
            .min(by: { (voices[$0].priority, voices[$0].startedAt) < (voices[$1].priority, voices[$1].startedAt) }) {
            index = victim
        } else {
            crowdedOut[name, default: 0] += 1
            return
        }
        if let old = voices[index].name, voices[index].endsAt > now, old != name { cutShort[old, default: 0] += 1 }
        voices[index] = Voice(name: name, priority: patch.priority, startedAt: now, endsAt: now + patch.duration)
        lastStart[name] = now
        started[name, default: 0] += 1
    }
}

@Suite struct RiftwingSoundDirectorTests {
    static let p = Vec2(450, 300)
    static let theme = RiftCaves()
    static let flap = RiftwingEvent.flapped(at: p, fromLedge: false)

    /// Asks the director about `events` as one frame at `tick`.
    static func frame(_ director: inout RiftwingSoundDirector, _ events: [RiftwingEvent], tick: Int) -> [Int?] {
        events.map { director.variant(for: $0, tick: tick) }
    }

    @Test func flapsAreLimitedAndNeverTheSamePitchTwiceRunning() {
        var director = RiftwingSoundDirector()
        // A flap every step for two seconds: voiced only every `flapGapTicks` steps.
        var voiced: [Int] = []
        for tick in 1...240 {
            if let v = Self.frame(&director, [Self.flap], tick: tick)[0] { voiced.append(v) }
        }
        #expect(voiced.count == 240 / RiftwingSoundDirector.flapGapTicks)
        #expect(zip(voiced, voiced.dropFirst()).allSatisfy { $0 != $1 })
        #expect(Set(voiced) == Set(0..<RiftwingSoundDirector.pitchVariants))
        // Not a fixed cycle.
        #expect(Set(zip(voiced, voiced.dropFirst()).map { "\($0)\($1)" }).count == 6)
        // A person's fastest tapping (about eight a second, 15 steps apart) is heard in full.
        var person = RiftwingSoundDirector()
        let heard = (1...40).compactMap { Self.frame(&person, [Self.flap], tick: 15 * $0)[0] }
        #expect(heard.count == 40)
        // Same calls, same answers.
        var again = RiftwingSoundDirector()
        var replay: [Int] = []
        for tick in 1...240 {
            if let v = Self.frame(&again, [Self.flap], tick: tick)[0] { replay.append(v) }
        }
        #expect(replay == voiced)
        // A take-off from a ledge is its own kind and plays its one version.
        #expect(Self.frame(&director, [.flapped(at: Self.p, fromLedge: true)], tick: 1000) == [0])
    }

    @Test func oneSoundPerKindPerFrame() {
        var director = RiftwingSoundDirector()
        let pods = (1...3).map { RiftwingEvent.podDropped(id: $0, at: Self.p, from: .glider) }
        let voiced = Self.frame(&director, pods + [.waveCleared(wave: 1, freed: 0, bonus: 0)], tick: 10)
        #expect(voiced.map { $0 != nil } == [true, false, false, true])
        // Next frame, a pod drop sounds again.
        #expect(Self.frame(&director, [pods[0]], tick: 11) == [0])
    }

    @Test func urgentCuesAreNeverRefusedAndClearTheAir() {
        var director = RiftwingSoundDirector()
        // A busy frame: the small sounds and the normal ones use up the budget...
        let busy: [RiftwingEvent] = [
            Self.flap, .landed(at: Self.p, ledge: 1), .bumpedLedge(at: Self.p), .ventEntered(vent: 0, at: Self.p),
            .podDropped(id: 1, at: Self.p, from: .glider),
            .opponentDestroyed(id: 1, role: .glider, at: Self.p, points: 250, stoopBonus: 0),
            .diveBegan(at: Self.p), .opponentDived(id: 2, role: .warden, at: Self.p),
            .podLanded(id: 3, at: Self.p, ledge: 0),
        ]
        // ...and every urgent cue in the same frame still sounds.
        let urgent: [RiftwingEvent] = [
            .clashLost(opponent: 2, role: .striker, at: Self.p),
            .riderLost(at: Self.p, livesLeft: 1, cause: .clash(opponent: 2, role: .striker)),
            .hatchWarning(id: 4, at: Self.p, becomes: .warden), .riftWarning(level: 200),
            .podLost(id: 5, at: Self.p, cause: .rift), .podSeized(id: 6, by: 7, at: Self.p),
        ]
        let voiced = Self.frame(&director, busy + urgent, tick: 50)
        let small = voiced.prefix(4).compactMap { $0 }.count
        let normal = voiced[4..<busy.count].compactMap { $0 }.count
        #expect(small == RiftwingSoundDirector.smallBudget)
        #expect(small + normal <= RiftwingSoundDirector.frameBudget)
        #expect(voiced.suffix(urgent.count).allSatisfy { $0 != nil }, "\(voiced)")
        for event in urgent { #expect(RiftwingSoundDirector.tier(of: event) == .urgent, "\(event)") }
        // For a quarter of a second after, small sounds are silent; normal ones still play.
        let hush = RiftwingSoundDirector.hushTicks
        #expect(Self.frame(&director, [Self.flap], tick: 50 + hush - 1) == [nil])
        #expect(Self.frame(&director, [.waveCleared(wave: 2, freed: 1, bonus: 250)], tick: 50 + hush - 1) == [0])
        #expect(Self.frame(&director, [Self.flap], tick: 50 + hush) != [nil])
    }

    @Test func repeatsAreSpaced() {
        var director = RiftwingSoundDirector()
        let land = RiftwingEvent.landed(at: Self.p, ledge: 0)
        #expect(Self.frame(&director, [land], tick: 100) == [0])
        #expect(Self.frame(&director, [land], tick: 110) == [nil])
        #expect(Self.frame(&director, [land], tick: 130) == [0])
        let glow = RiftwingEvent.arrivalTelegraphed(id: 1, role: .striker, side: .left, at: Self.p)
        #expect(Self.frame(&director, [glow], tick: 200) == [0])
        #expect(Self.frame(&director, [glow], tick: 220) == [nil])
        #expect(Self.frame(&director, [glow], tick: 248) == [0])
        // A level bounce and a bump off a Gleaner play the same sound, and count as one kind.
        let bounce = RiftwingEvent.clashBounced(opponent: 1, role: .glider, at: Self.p)
        let bump = RiftwingEvent.gleanerBumped(opponent: 2, at: Self.p)
        #expect(Self.frame(&director, [bounce, bump], tick: 300) == [0, nil])
    }

    @Test func silentEventsHaveNoKind() {
        var director = RiftwingSoundDirector()
        for event in RiftwingEventCatalog.every where RiftwingEventCatalog.isSilent(event) {
            #expect(RiftwingSoundDirector.kind(of: event) == nil, "\(event)")
            #expect(director.variant(for: event, tick: 1) == nil, "\(event)")
        }
        // Every event that sounds has a kind, and the director lets it through on a quiet frame.
        for (index, event) in RiftwingEventCatalog.every.enumerated() where !RiftwingEventCatalog.isSilent(event) {
            var fresh = RiftwingSoundDirector()
            #expect(RiftwingSoundDirector.kind(of: event) != nil, "\(event)")
            #expect(fresh.variant(for: event, tick: 10 + index) != nil, "\(event)")
        }
    }

    #if DEBUG
    /// Real games, voiced as the app voices them (frames of two steps) and played into a model
    /// of the synth's voices: flaps stay a light stream, the busiest frame stays within the
    /// budget, and no urgent cue is ever crowded out or rate-limited away.
    @Test(arguments: [RiftwingPilot.Skill.novice, .competent])
    func aRealGameNeverDrownsTheUrgentCues(skill: RiftwingPilot.Skill) {
        var urgentAsked = 0, urgentVoiced = 0
        var flapsVoiced = 0, flapEvents = 0
        var busiestFrame = 0
        var perSecond: [Int] = []
        var model = CavesVoiceModel()
        var byName: [String: Int] = [:]
        var seconds = 0.0
        var waves = 0
        for seed in [UInt64(3), 7, 11] {
            var game = RiftwingRun(seed: seed)
            var pilot = RiftwingPilot(skill: skill, seed: seed)
            var director = RiftwingSoundDirector()
            var thisSecond = 0
            var frameEvents: [RiftwingEvent] = []
            for step in 1...(120 * 400) where !game.isGameOver {
                frameEvents += game.step(pilot.input(for: game))
                guard step % 2 == 0 else { continue }
                let now = seconds + Double(step) / 120
                var voiced = 0
                for event in frameEvents {
                    if case .flapped(_, false) = event { flapEvents += 1 }
                    let urgent = RiftwingSoundDirector.tier(of: event) == .urgent
                    if urgent { urgentAsked += 1 }
                    guard let variant = director.variant(for: event, in: game),
                          let patch = Self.theme.sound(for: event, variant: variant) else { continue }
                    if urgent { urgentVoiced += 1 }
                    if case .flapped(_, false) = event { flapsVoiced += 1 }
                    voiced += 1
                    byName[patch.name, default: 0] += 1
                    model.play(patch, at: now)
                }
                frameEvents.removeAll(keepingCapacity: true)
                busiestFrame = max(busiestFrame, voiced)
                thisSecond += voiced
                if step % 120 == 0 {
                    perSecond.append(thisSecond)
                    thisSecond = 0
                }
            }
            seconds += Double(game.tick) / 120 + 10
            waves += game.wave
        }
        let played = Double(perSecond.reduce(0, +)) / Double(max(perSecond.count, 1))
        let urgentNames = Set(Self.theme.allSounds.filter { $0.priority >= 9 }.map(\.name))
        print("VOICED riftwing \(skill): 3 games, waves \(waves), \(Int(seconds)) s, flaps \(flapEvents) -> \(flapsVoiced) voiced, "
              + "busiest frame \(busiestFrame), average \(String(format: "%.1f", played))/s, busiest second \(perSecond.max() ?? 0), "
              + "urgent \(urgentAsked) asked \(urgentVoiced) voiced")
        print("VOICED by patch: " + byName.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        print("VOICES crowded out: \(model.crowdedOut), rate-limited: \(model.rateLimited), cut short: \(model.cutShort)")
        // Every urgent cue the game produced was voiced, except a second one of the same kind in
        // the same frame (two pods lost at once are one sound).
        #expect(urgentVoiced >= urgentAsked * 9 / 10, "urgent \(urgentVoiced) of \(urgentAsked)")
        // ...and none of them lost a voice or was rate-limited by the synth.
        for name in urgentNames {
            #expect(model.crowdedOut[name] == nil, "\(name) crowded out")
            #expect(model.cutShort[name] == nil, "\(name) cut short")
        }
        #expect(model.crowdedOut.isEmpty, "\(model.crowdedOut)")
        #expect(busiestFrame <= RiftwingSoundDirector.frameBudget + 4)
        #expect((perSecond.max() ?? 0) <= 30)
        // Flaps are most of what is heard and never more than ten a second.
        #expect(flapsVoiced > 0 && flapsVoiced <= flapEvents)
        let flapRate = Double(flapsVoiced) / max(seconds - 30, 1)
        #expect(flapRate <= 10)
        #expect(byName["caves.wave.start", default: 0] >= 3)
    }
    #endif
}

@Suite struct RiftwingMoodTests {
    @Test func theMoodFollowsTheRun() {
        #expect(RiftwingMoodDirector.mood(fighting: true, lampsOut: false) == .tension)
        #expect(RiftwingMoodDirector.mood(fighting: false, lampsOut: false) == .calm)
        #expect(RiftwingMoodDirector.mood(fighting: true, lampsOut: true) == .blackout)
        #expect(RiftwingMoodDirector.mood(fighting: false, lampsOut: true) == .blackout)
        var director = RiftwingMoodDirector()
        #expect(director.mood == .calm)
        #expect(director.update(fighting: true, lampsOut: false) == .tension)
        #expect(director.update(fighting: true, lampsOut: true) == .blackout)
        // A colonist freed in the dark: straight back to the wave's tension.
        #expect(director.update(fighting: true, lampsOut: false) == .tension)
        director.reset()
        #expect(director.mood == .calm)
    }

    @Test func aNewRunBeginsCalmUntilTheFirstWave() {
        var director = RiftwingMoodDirector()
        var game = RiftwingRun(seed: 1)
        #expect(director.update(run: game) == .calm)
        while game.phase != .fighting { _ = game.step(RiftwingInput()) }
        #expect(director.update(run: game) == .tension)
    }

    /// The lamps out are dark from the moment they fail, as a wave starts, until a colonist is
    /// freed.
    @Test func lampsOutIsDarkUntilAColonistIsFreed() {
        var game = RiftwingRun(seed: 3)
        var director = RiftwingMoodDirector()
        game.lampsOutPending = true
        var failed = false
        while !failed {
            failed = game.step(RiftwingInput()).contains(.lampsFailed)
            #expect(director.update(run: game) == (failed ? .blackout : .calm))
        }
        #expect(game.phase == .fighting)
        for _ in 0..<240 { #expect(director.update(run: game) == .blackout); _ = game.step(RiftwingInput()) }
        game.isLampsOut = false
        #expect(director.update(run: game) == .tension)
    }

    #if DEBUG
    /// A competent game: the music goes calm, tense, calm, ... and changes only when a wave
    /// starts or clears or the lamps change.
    @Test func aRealGameMovesBetweenCalmAndTensionAndNeverFlaps() {
        var game = RiftwingRun(seed: 7)
        var pilot = RiftwingPilot(skill: .competent, seed: 7)
        var director = RiftwingMoodDirector()
        var last = director.update(run: game)
        var changes: [(time: Double, mood: MusicMood)] = []
        var structural = 0
        for _ in 0..<(120 * 300) where !game.isGameOver {
            for event in game.step(pilot.input(for: game)) {
                switch event {
                case .waveStarted, .waveCleared, .lampsFailed, .lampsRestored: structural += 1
                default: break
                }
            }
            let mood = director.update(run: game)
            if mood != last {
                changes.append((Double(game.tick) / 120, mood))
                last = mood
            }
        }
        let summary = changes.map { "\(String(format: "%.0f", $0.time))s \($0.mood.rawValue)" }.joined(separator: ", ")
        print("MOOD riftwing seed 7 competent: wave \(game.wave), \(changes.count) changes: \(summary)")
        #expect(changes.count { $0.mood == .calm } >= 2 && changes.count { $0.mood == .tension } >= 3)
        #expect(changes.count <= structural)
        let gaps = zip(changes, changes.dropFirst()).map { $1.time - $0.time }
        #expect(gaps.allSatisfy { $0 >= 1.5 }, "\(gaps)")
    }
    #endif
}

@Suite struct RiftwingHapticTests {
    static let p = Vec2(450, 300)

    @Test func flightIsNotFelt() {
        var silent: [RiftwingEvent] = [
            .flapped(at: Self.p, fromLedge: false), .flapped(at: Self.p, fromLedge: true), .landed(at: Self.p, ledge: 0),
            .bumpedLedge(at: Self.p), .diveBegan(at: Self.p), .wingsOpening(at: Self.p), .wingsOpened(at: Self.p),
            .ventEntered(vent: 0, at: Self.p), .gleanerBumped(opponent: 1, at: Self.p), .riderRespawned(at: Self.p, ledge: 1),
            .mineLaid(id: 1, by: 2, at: Self.p), .mineCleared(id: 1, at: Self.p, reason: .sowerDown),
            .podDropped(id: 1, at: Self.p, from: .glider), .podLanded(id: 1, at: Self.p, ledge: 0),
            .podCarried(id: 1, by: 2, at: Self.p), .cavernShifted(layout: 1), .allColonistsLost(wave: 2),
            .riftBreathed(level: 200), .riftSettled,
            // A clash lost is felt once: the life it costs is not felt again.
            .riderLost(at: Self.p, livesLeft: 1, cause: .clash(opponent: 1, role: .striker)),
        ]
        for role in RiftwingRole.allCases {
            silent.append(.clashBounced(opponent: 1, role: role, at: Self.p))
            silent.append(.arrivalTelegraphed(id: 1, role: role, side: .right, at: Self.p))
            silent.append(.opponentArrived(id: 1, role: role, at: Self.p))
            silent.append(.opponentDived(id: 1, role: role, at: Self.p))
            silent.append(.opponentHit(id: 1, role: role, at: Self.p, blowsLeft: 1))
            silent.append(.opponentDestroyed(id: 1, role: role, at: Self.p, points: 250, stoopBonus: 0))
            silent.append(.opponentFell(id: 1, role: role, at: Self.p, cause: .rift))
            silent.append(.opponentWithdrew(id: 1, role: role, at: Self.p))
            silent.append(.podHatched(id: 1, opponent: 2, role: role, at: Self.p))
        }
        for event in silent {
            #expect(HapticCue.cue(for: event) == nil, "\(event)")
        }
    }

    @Test func whatMattersIsFeltByWeight() {
        var expected: [(RiftwingEvent, HapticCue)] = [
            (.clashLost(opponent: 1, role: .striker, at: Self.p), .rumble),
            (.riderLost(at: Self.p, livesLeft: 1, cause: .rift), .rumble),
            (.riderLost(at: Self.p, livesLeft: 1, cause: .mine(id: 3)), .rumble),
            (.riderLost(at: Self.p, livesLeft: 0, cause: .breath), .rumble),
            (.cavernShifting(from: 0, to: 1), .rumble), (.lampsFailed, .rumble), (.gameOver(score: 10), .rumble),
            (.podFreed(id: 1, at: Self.p, order: 1, points: 500), .doubleTap),
            (.podCaught(id: 1, at: Self.p, order: 2, points: 2000), .doubleTap),
            (.waveCleared(wave: 1, freed: 2, bonus: 500), .doubleTap), (.extraLife(lives: 4), .doubleTap),
            (.lampsRestored, .doubleTap),
            (.podSeized(id: 1, by: 2, at: Self.p), .warning), (.hatchWarning(id: 1, at: Self.p, becomes: .warden), .warning),
            (.riftWarning(level: 200), .warning),
            (.waveStarted(wave: 2, layout: 0), .tap),
        ]
        for cause in [RiftwingPodLoss.rift, .hatched, .carried, .breath] {
            expected.append((.podLost(id: 1, at: Self.p, cause: cause), .impact))
        }
        for role in RiftwingRole.allCases {
            expected.append((.clashWon(opponent: 1, role: role, at: Self.p, stoop: false), .tap))
            expected.append((.clashWon(opponent: 1, role: role, at: Self.p, stoop: true), .impact))
        }
        for (event, cue) in expected {
            #expect(HapticCue.cue(for: event) == cue, "\(event)")
        }
    }

    #if DEBUG
    /// Real games are felt now and then, never as a constant buzz, and only where intended.
    @Test(arguments: [RiftwingPilot.Skill.novice, .competent])
    func aRealGameIsNotABuzz(skill: RiftwingPilot.Skill) {
        var game = RiftwingRun(seed: 7)
        var pilot = RiftwingPilot(skill: skill, seed: 7)
        var cues: [HapticCue: Int] = [:]
        var steps = 0
        var busiestSecond = 0, thisSecond = 0
        var flaps = 0
        for step in 1...(120 * 300) where !game.isGameOver {
            for event in game.step(pilot.input(for: game)) {
                if case .flapped = event { flaps += 1 }
                guard let cue = HapticCue.cue(for: event) else { continue }
                cues[cue, default: 0] += 1
                thisSecond += 1
            }
            steps = step
            if step % 120 == 0 {
                busiestSecond = max(busiestSecond, thisSecond)
                thisSecond = 0
            }
        }
        let total = cues.values.reduce(0, +)
        let perSecond = Double(total) / (Double(steps) / 120)
        print("HAPTICS riftwing seed 7 \(skill): \(total) cues in \(steps / 120) s (\(String(format: "%.2f", perSecond))/s), "
              + "busiest second \(busiestSecond), \(flaps) flaps; \(cues.sorted { $0.key.rawValue < $1.key.rawValue })")
        #expect(flaps > 100)
        #expect(perSecond < 1)
        #expect(busiestSecond <= 6)
        #expect(cues[.sweep] == nil && cues[.tick] == nil)
    }
    #endif
}
