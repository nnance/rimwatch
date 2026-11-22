import Foundation
import Testing
import GameCore
@testable import RiftwingCore

/// Measurements of a rendered sound, so sounds can be checked without listening. (The same
/// measures as the other modes' audio tests, which live in other test targets.)
struct CavesSoundMeasure {
    let samples: [Float]
    let sampleRate: Double

    var duration: Double { Double(samples.count) / sampleRate }
    var peak: Double { Double(samples.map { abs($0) }.max() ?? 0) }
    var rms: Double { Self.rms(samples[...]) }
    var mean: Double { samples.reduce(0.0) { $0 + Double($1) } / Double(max(samples.count, 1)) }
    var isFinite: Bool { samples.allSatisfy { $0.isFinite } }

    static func rms(_ slice: ArraySlice<Float>) -> Double {
        guard !slice.isEmpty else { return 0 }
        return sqrt(slice.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(slice.count))
    }

    /// The RMS of the loudest 50 ms: how loud the sound feels at its strongest.
    var loudness: Double {
        let window = Int(0.05 * sampleRate)
        guard samples.count > window else { return rms }
        var best = 0.0
        var start = 0
        while start + window <= samples.count {
            best = max(best, Self.rms(samples[start..<(start + window)]))
            start += window / 2
        }
        return best
    }

    /// The sound as a small phone speaker would play it: a 12 dB/octave high-pass at `cutoff`.
    func smallSpeaker(cutoff: Double = 400) -> CavesSoundMeasure {
        let w0 = 2 * Double.pi * cutoff / sampleRate
        let alpha = sin(w0) / (2 * 0.707)
        let a0 = 1 + alpha
        let b0 = (1 + cos(w0)) / 2 / a0, b1 = -(1 + cos(w0)) / a0, b2 = b0
        let a1 = -2 * cos(w0) / a0, a2 = (1 - alpha) / a0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        let out = samples.map { sample -> Float in
            let x = Double(sample)
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return Float(y)
        }
        return CavesSoundMeasure(samples: out, sampleRate: sampleRate)
    }

    /// How much the loudness jumps from one 20 ms window to the next, relative to the average.
    var fluctuation: Double {
        let window = max(Int(0.02 * sampleRate), 1)
        var levels: [Double] = []
        var start = 0
        while start + window <= samples.count {
            levels.append(Self.rms(samples[start..<(start + window)]))
            start += window
        }
        guard levels.count > 2 else { return 0 }
        let mean = levels.reduce(0, +) / Double(levels.count)
        guard mean > 1e-9 else { return 0 }
        let jumps = zip(levels, levels.dropFirst()).map { abs($1 - $0) }.reduce(0, +) / Double(levels.count - 1)
        return jumps / mean
    }

    /// The worst of: an end sample, and the loudness within 0.3 ms of the start or 1 ms of the
    /// end, as a fraction of the peak.
    func clickiness() -> Double {
        let head = max(Int(0.0003 * sampleRate), 1)
        let tail = max(Int(0.001 * sampleRate), 1)
        let first = samples.prefix(head).map { abs(Double($0)) }.max() ?? 0
        let last = samples.suffix(tail).map { abs(Double($0)) }.max() ?? 0
        let ends = max(abs(Double(samples.first ?? 0)), abs(Double(samples.last ?? 0)))
        return max(ends * 50, max(first, last) / max(peak, 1e-9))
    }

    var largestKink: Double {
        guard samples.count > 2 else { return 0 }
        var worst = 0.0
        for i in 1..<(samples.count - 1) {
            worst = max(worst, abs(Double(samples[i + 1]) - 2 * Double(samples[i]) + Double(samples[i - 1])))
        }
        return worst
    }

    static let frameSize = 2048
    static let window: [Double] = (0..<frameSize).map { 0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(frameSize - 1)) }
    static let twiddles: [(Double, Double)] = (0..<(frameSize / 2)).map {
        (cos(-2 * .pi * Double($0) / Double(frameSize)), sin(-2 * .pi * Double($0) / Double(frameSize)))
    }

    func spectrum(at start: Int) -> [Double] {
        let size = Self.frameSize
        var re = [Double](repeating: 0, count: size)
        var im = [Double](repeating: 0, count: size)
        for i in 0..<size where start + i < samples.count {
            re[i] = Double(samples[start + i]) * Self.window[i]
        }
        Self.fft(&re, &im)
        return (0..<(size / 2)).map { hypot(re[$0], im[$0]) }
    }

    /// Spectral centroid (Hz) and flatness (0 tonal ... 1 noise), weighted by frame energy.
    func spectralShape(from: Double = 0, to: Double = 1) -> (centroid: Double, flatness: Double) {
        let hop = 1024
        let first = Int(from * Double(samples.count))
        let last = max(Int(to * Double(samples.count)) - 1024, first + 1)
        var weighted = 0.0, flat = 0.0, total = 0.0
        var start = first
        while start < last {
            let mags = spectrum(at: start)
            let energy = mags.reduce(0) { $0 + $1 * $1 }
            if energy > 1e-9 {
                let binHz = sampleRate / 2048
                let sum = mags.reduce(0, +)
                let centroid = mags.enumerated().reduce(0.0) { $0 + Double($1.offset) * binHz * $1.element } / sum
                let bins = mags[1...]
                let geo = exp(bins.reduce(0.0) { $0 + log($1 + 1e-12) } / Double(bins.count))
                let arith = bins.reduce(0, +) / Double(bins.count)
                weighted += centroid * energy
                flat += geo / arith * energy
                total += energy
            }
            start += hop
        }
        guard total > 0 else { return (0, 0) }
        return (weighted / total, flat / total)
    }

    var centroidSlope: Double {
        let early = spectralShape(from: 0, to: 0.4).centroid
        let late = spectralShape(from: 0.4, to: 1).centroid
        guard early > 0, late > 0 else { return 0 }
        return log2(late / early)
    }

    var peakPosition: Double {
        let window = Int(0.05 * sampleRate)
        guard samples.count > window else { return 0 }
        var best = (value: 0.0, at: 0)
        var start = 0
        while start + window <= samples.count {
            let value = Self.rms(samples[start..<(start + window)])
            if value > best.value { best = (value, start) }
            start += window / 4
        }
        return Double(best.at) / Double(samples.count)
    }

    private static func fft(_ re: inout [Double], _ im: inout [Double]) {
        let n = re.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j |= bit
            if i < j { re.swapAt(i, j); im.swapAt(i, j) }
        }
        var length = 2
        while length <= n {
            let step = n / length
            for start in stride(from: 0, to: n, by: length) {
                for k in 0..<(length / 2) {
                    let (wr, wi) = twiddles[k * step]
                    let a = start + k, b = start + k + length / 2
                    let tr = re[b] * wr - im[b] * wi
                    let ti = re[b] * wi + im[b] * wr
                    re[b] = re[a] - tr; im[b] = im[a] - ti
                    re[a] += tr; im[a] += ti
                }
            }
            length <<= 1
        }
    }
}

/// Every kind of Riftwing event, each role and cause where an event carries one.
enum RiftwingEventCatalog {
    static let p = Vec2(450, 300)

    static let every: [RiftwingEvent] = {
        var events: [RiftwingEvent] = [
            .waveStarted(wave: 1, layout: 0), .waveCleared(wave: 1, freed: 2, bonus: 500),
            .cavernShifting(from: 0, to: 1), .cavernShifted(layout: 1), .allColonistsLost(wave: 2),
            .lampsFailed, .lampsRestored, .riftWarning(level: 180), .riftFillWarning(level: 600),
            .riftBreathed(level: 180), .riftSettled, .bumpedRoof(at: p),
            .flapped(at: p, fromLedge: false), .flapped(at: p, fromLedge: true), .landed(at: p, ledge: 1),
            .bumpedLedge(at: p), .diveBegan(at: p), .wingsOpening(at: p), .wingsOpened(at: p),
            .ventEntered(vent: 0, at: p), .gleanerBumped(opponent: 3, at: p),
            .riderRespawned(at: p, ledge: 2), .extraLife(lives: 4),
            .mineLaid(id: 1, by: 2, at: p),
            .mineCleared(id: 1, at: p, reason: .sowerDown), .mineCleared(id: 1, at: p, reason: .expired),
            .mineCleared(id: 1, at: p, reason: .waveEnded), .mineCleared(id: 1, at: p, reason: .struck),
            .podDropped(id: 1, at: p, from: .glider), .podLanded(id: 1, at: p, ledge: 0),
            .podCaught(id: 1, at: p, order: 1, points: 1000), .podSeized(id: 1, by: 2, at: p),
            .podCarried(id: 1, by: 2, at: p), .hatchWarning(id: 1, at: p, becomes: .striker),
            .gameOver(score: 1000),
        ]
        for cause in [RiftwingLossCause.clash(opponent: 1, role: .glider), .mine(id: 2), .rift, .breath] {
            events.append(.riderLost(at: p, livesLeft: 1, cause: cause))
        }
        for cause in [RiftwingPodLoss.rift, .hatched, .carried, .breath] {
            events.append(.podLost(id: 1, at: p, cause: cause))
        }
        for order in 1...7 {
            events.append(.podFreed(id: order, at: p, order: order, points: 500 * order))
        }
        for role in RiftwingRole.allCases {
            events.append(.clashWon(opponent: 1, role: role, at: p, stoop: false))
            events.append(.clashWon(opponent: 1, role: role, at: p, stoop: true))
            events.append(.clashBounced(opponent: 1, role: role, at: p))
            events.append(.clashLost(opponent: 1, role: role, at: p))
            events.append(.arrivalTelegraphed(id: 1, role: role, side: .left, at: p))
            events.append(.opponentArrived(id: 1, role: role, at: p))
            events.append(.opponentDived(id: 1, role: role, at: p))
            events.append(.opponentHit(id: 1, role: role, at: p, blowsLeft: 1))
            events.append(.opponentDestroyed(id: 1, role: role, at: p, points: 250, stoopBonus: 0))
            for bonus in [50, 300, 600, 1000] {
                events.append(.opponentDestroyed(id: 1, role: role, at: p, points: 250 + bonus, stoopBonus: bonus))
            }
            events.append(.opponentFell(id: 1, role: role, at: p, cause: .rift))
            events.append(.opponentFell(id: 1, role: role, at: p, cause: .breath))
            events.append(.opponentWithdrew(id: 1, role: role, at: p))
            events.append(.podHatched(id: 1, opponent: 2, role: role, at: p))
        }
        return events
    }()

    /// Events that make no sound of their own, on purpose (see `RiftCaves.soundName`). No
    /// `default`: an event added to the game does not compile here until it is decided.
    static func isSilent(_ event: RiftwingEvent) -> Bool {
        switch event {
        case .clashWon, .wingsOpened, .opponentArrived, .opponentWithdrew: true
        case .mineCleared(_, _, let reason): reason == .waveEnded || reason == .struck
        case .waveStarted, .waveCleared, .cavernShifting, .cavernShifted, .allColonistsLost, .lampsFailed,
             .lampsRestored, .riftWarning, .riftFillWarning, .riftBreathed, .riftSettled, .flapped, .landed,
             .bumpedLedge, .bumpedRoof, .diveBegan,
             .wingsOpening, .ventEntered, .clashBounced, .clashLost, .gleanerBumped, .riderLost, .riderRespawned,
             .extraLife, .arrivalTelegraphed, .opponentDived, .opponentHit, .opponentDestroyed, .opponentFell,
             .mineLaid, .podDropped, .podLanded, .podFreed, .podCaught, .podSeized, .podCarried, .podLost,
             .hatchWarning, .podHatched, .gameOver:
            false
        }
    }

    /// A number for each case of `RiftwingEvent`, 0 ..< `caseCount`. The switch has no
    /// `default`, so a new event fails to compile here; give it the next number, raise
    /// `caseCount` and add an example to `every`, or `theCatalogHoldsEveryKindOfEvent` fails.
    static func caseIndex(_ event: RiftwingEvent) -> Int {
        switch event {
        case .waveStarted: 0
        case .waveCleared: 1
        case .cavernShifting: 2
        case .cavernShifted: 3
        case .allColonistsLost: 4
        case .lampsFailed: 5
        case .lampsRestored: 6
        case .riftWarning: 7
        case .riftBreathed: 8
        case .riftSettled: 9
        case .flapped: 10
        case .landed: 11
        case .bumpedLedge: 12
        case .diveBegan: 13
        case .wingsOpening: 14
        case .wingsOpened: 15
        case .ventEntered: 16
        case .clashWon: 17
        case .clashBounced: 18
        case .clashLost: 19
        case .gleanerBumped: 20
        case .riderLost: 21
        case .riderRespawned: 22
        case .extraLife: 23
        case .arrivalTelegraphed: 24
        case .opponentArrived: 25
        case .opponentDived: 26
        case .opponentHit: 27
        case .opponentDestroyed: 28
        case .opponentFell: 29
        case .opponentWithdrew: 30
        case .mineLaid: 31
        case .mineCleared: 32
        case .podDropped: 33
        case .podLanded: 34
        case .podFreed: 35
        case .podCaught: 36
        case .podSeized: 37
        case .podCarried: 38
        case .podLost: 39
        case .hatchWarning: 40
        case .podHatched: 41
        case .gameOver: 42
        case .riftFillWarning: 43
        case .bumpedRoof: 44
        }
    }

    static let caseCount = 45
}

@Suite struct RiftwingEventCatalogTests {
    /// The lists the sound, kind and haptic tests walk cannot miss an event.
    @Test func theCatalogHoldsEveryKindOfEvent() {
        let indices = RiftwingEventCatalog.every.map(RiftwingEventCatalog.caseIndex)
        #expect(indices.allSatisfy { (0..<RiftwingEventCatalog.caseCount).contains($0) })
        #expect(Set(indices) == Set(0..<RiftwingEventCatalog.caseCount),
                "missing: \(Set(0..<RiftwingEventCatalog.caseCount).subtracting(indices).sorted())")
    }
}

@Suite struct RiftwingSoundPatchTests {
    static let rate = 44_100.0
    static let theme = RiftCaves()

    /// Every distinct patch any event (in every version) or menu action can play.
    static let usedPatches: [SoundPatch] = {
        var byName: [String: SoundPatch] = [:]
        for event in RiftwingEventCatalog.every {
            for variant in 0..<6 {
                if let patch = theme.sound(for: event, variant: variant) { byName[patch.name] = patch }
            }
        }
        for sound in MenuSound.allCases { if let p = theme.menuSound(sound) { byName[p.name] = p } }
        return byName.values.sorted { $0.name < $1.name }
    }()

    static let measures: [String: CavesSoundMeasure] = {
        var all: [String: CavesSoundMeasure] = [:]
        for patch in usedPatches {
            all[patch.name] = CavesSoundMeasure(samples: SoundRenderer.render(patch, sampleRate: rate), sampleRate: rate)
        }
        return all
    }()

    static func measure(_ short: String) -> CavesSoundMeasure { measures["caves." + short]! }
    static func loud(_ short: String) -> Double { measure(short).loudness }
    static func small(_ short: String) -> Double { measure(short).smallSpeaker().loudness }

    struct Features {
        var duration, centroid, flatness, slope, peakPosition, fluctuation: Double
    }

    static let features: [String: Features] = measures.mapValues { m in
        let shape = m.spectralShape()
        return Features(duration: m.duration, centroid: shape.centroid, flatness: shape.flatness,
                        slope: m.centroidSlope, peakPosition: m.peakPosition, fluctuation: m.fluctuation)
    }

    /// Per-feature differences scaled so 1 is "clearly different". Duration first.
    static func featureScores(_ a: Features, _ b: Features) -> [(score: Double, name: String)] {
        [
            (abs(log2(a.duration / b.duration)) / 0.35, "duration"),
            (abs(log2(max(a.centroid, 1) / max(b.centroid, 1))) / 0.4, "centroid"),
            (abs(a.flatness - b.flatness) / 0.15, "noisiness"),
            (abs(a.slope - b.slope) / 0.6, "contour"),
            (abs(a.peakPosition - b.peakPosition) / 0.3, "envelope"),
            (abs(a.fluctuation - b.fluctuation) / 0.25, "rhythm"),
        ]
    }

    /// A sound's versions (pitches, stages, rescue orders) share a stem: "flap.2" is "flap".
    static func stem(_ name: String) -> String {
        guard let last = name.split(separator: ".").last, Int(last) != nil else { return name }
        return String(name.dropLast(last.count + 1))
    }

    @Test func everyEventThatShouldSoundHasAPatchInTheTheme() {
        let listed = Set(Self.theme.allSounds.map(\.name))
        for event in RiftwingEventCatalog.every {
            let patch = Self.theme.sound(for: event)
            if RiftwingEventCatalog.isSilent(event) {
                #expect(patch == nil, "\(event) should be silent")
            } else {
                #expect(patch != nil, "\(event) has no sound")
                if let patch {
                    #expect(!patch.layers.isEmpty, "\(event) plays a placeholder \(patch.name)")
                    #expect(listed.contains(patch.name), "\(patch.name) is not in allSounds")
                }
            }
        }
        for sound in MenuSound.allCases {
            #expect(Self.theme.menuSound(sound).map { !$0.layers.isEmpty } == true, "menu \(sound) has no sound")
            #expect(Self.theme.shellStyle.menuSounds[sound] != nil, "the shell gets no \(sound) sound")
        }
        #expect(Self.theme.music != nil)
        // Nothing in allSounds goes unused.
        #expect(Set(Self.usedPatches.map(\.name)) == listed)
    }

    @Test func patchNamesAreUniqueAndTheCavesOwn() {
        let names = Self.theme.allSounds.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.count >= 45)
        for name in names {
            // The one synthesiser keys its buffers by name, across all three modes.
            #expect(name.hasPrefix("caves."), "\(name)")
        }
    }

    @Test func everyPatchRendersCleanly() {
        for patch in Self.usedPatches {
            let m = Self.measures[patch.name]!
            let name = patch.name
            #expect(m.isFinite, "\(name) has NaN or infinity")
            #expect(m.peak <= 1, "\(name) peaks at \(m.peak)")
            #expect(m.peak > 0.1, "\(name) is nearly silent: peak \(m.peak)")
            #expect(m.rms > 0.01, "\(name) is nearly silent: rms \(m.rms)")
            #expect(abs(m.duration - patch.duration) < 1.5 / Self.rate, "\(name) lasts \(m.duration), states \(patch.duration)")
            #expect(m.clickiness() < 0.35, "\(name) clicks at an end: \(m.clickiness())")
            #expect(abs(m.mean) < 0.01, "\(name) has a DC offset of \(m.mean)")
            #expect(patch.duration > 0.03 && patch.duration < 3.5, "\(name) lasts \(patch.duration)")
            // Urgent cues have no cooldown at all (see `urgentPatchesCannotBeRefusedByTheSynth`).
            #expect(patch.maxVoices >= 1 && (patch.cooldown > 0 || patch.priority == 10), "\(name)")
        }
    }

    @Test func printFeatureTable() {
        for patch in Self.usedPatches {
            let f = Self.features[patch.name]!, m = Self.measures[patch.name]!
            print(String(format: "FEAT %-24@ %-9@ p%2d dur %.3f peak %.2f loud %.3f small %.3f cent %6.0f flat %.3f slope %+.2f pk %.2f",
                         patch.name as NSString, patch.family.rawValue as NSString, patch.priority, f.duration, m.peak,
                         m.loudness, m.smallSpeaker().loudness, f.centroid, f.flatness, f.slope, f.peakPosition))
        }
    }

    @Test func renderingIsDeterministic() {
        let patch = Self.theme.sound(for: .riftWarning(level: 200))!
        #expect(SoundRenderer.render(patch, sampleRate: Self.rate) == SoundRenderer.render(patch, sampleRate: Self.rate))
    }

    @Test func theFlapIsShortSoftVariedAndNeverTiring() {
        let flaps = (0..<RiftCaves.flapVariants).map {
            Self.theme.sound(for: .flapped(at: .zero, fromLedge: false), variant: $0)!
        }
        #expect(Set(flaps.map(\.name)).count == RiftCaves.flapVariants)
        for flap in flaps {
            let m = Self.measures[flap.name]!
            // Each copy ends before the next can start (at most ten a second), so one voice
            // carries every flap and none is cut short.
            #expect(flap.duration < Double(RiftwingSoundDirector.flapGapTicks) / 120, "\(flap.name) lasts \(flap.duration)")
            #expect(flap.maxVoices == 1 && flap.priority == 0)
            #expect(m.peak <= 0.14)
            #expect(m.loudness <= 0.04, "\(flap.name) loudness \(m.loudness)")
            // Soft: no hard front. The loudest 5 ms are not in the first millisecond.
            let firstMs = CavesSoundMeasure.rms(m.samples.prefix(Int(0.001 * Self.rate))[...])
            #expect(firstMs < 0.5 * m.loudness, "\(flap.name) starts hard")
        }
        // The most frequent sound is the quietest in the game.
        let flap = Self.loud("flap.1")
        let quieter = Self.usedPatches.filter { !$0.name.contains(".flap.") && Self.measures[$0.name]!.loudness < flap }
        #expect(quieter.isEmpty, "\(quieter.map(\.name))")
        // The pitches differ.
        let centroids = flaps.map { Self.features[$0.name]!.centroid }
        #expect(centroids.max()! / centroids.min()! > 1.12, "\(centroids)")
        // A take-off from a ledge is a fuller beat.
        #expect(Self.loud("flap.ledge") > Self.loud("flap.1"))
        #expect(Self.measure("flap.ledge").duration > Self.measure("flap.1").duration)
    }

    @Test func aStoopGrowsWithTheFall() {
        #expect(RiftCaves.stoopStage(bonus: 50) == 1)
        #expect(RiftCaves.stoopStage(bonus: 150) == 1)
        #expect(RiftCaves.stoopStage(bonus: 200) == 2)
        #expect(RiftCaves.stoopStage(bonus: 450) == 3)
        #expect(RiftCaves.stoopStage(bonus: 800) == 4)
        #expect(RiftCaves.stoopStage(bonus: 1000) == 4)
        var last = (duration: 0.0, loudness: 0.0, small: 0.0)
        for stage in 1...RiftCaves.stoopStages {
            let m = Self.measure("stoop.\(stage)")
            #expect(m.duration > last.duration, "stoop \(stage) length")
            #expect(m.loudness > last.loudness, "stoop \(stage) \(m.loudness) vs \(last.loudness)")
            last = (m.duration, m.loudness, m.smallSpeaker().loudness)
        }
        // Even the smallest stoop is bigger than a plain clash won; the biggest is among the
        // biggest sounds in the game.
        #expect(Self.loud("stoop.1") > Self.loud("clash.won"))
        #expect(Self.small("stoop.4") >= 1.4 * Self.small("clash.won"))
        // A stoop with no bonus (a drop too short to score) is a plain clash won.
        #expect(Self.theme.sound(for: .opponentDestroyed(id: 1, role: .striker, at: .zero, points: 500, stoopBonus: 0))?.name
            == "caves.clash.won")
        #expect(Self.theme.sound(for: .opponentDestroyed(id: 1, role: .warden, at: .zero, points: 1750, stoopBonus: 1000))?.name
            == "caves.stoop.4")
    }

    @Test func aRunOfRescuesClimbs() {
        let orders = (1...RiftCaves.freedNotes).map { "caves.pod.freed.\($0)" }
        let centroids = orders.map { Self.features[$0]!.centroid }
        #expect(zip(centroids, centroids.dropFirst()).allSatisfy { $0 < $1 }, "\(centroids)")
        // Later rescues play the top chime.
        #expect(Self.theme.sound(for: .podFreed(id: 1, at: .zero, order: 9, points: 4500))?.name
            == "caves.pod.freed.\(RiftCaves.freedNotes)")
        // A mid-air catch scores double and sounds bigger than any rescue from a ledge.
        for name in orders {
            #expect(Self.measure("pod.caught").loudness > Self.measures[name]!.loudness, "\(name)")
        }
    }

    @Test func urgentCuesStandWellAboveTheFlightSounds() {
        // On a phone speaker each urgent cue is several times as loud as the steady sounds of
        // flight, so it is never lost under them.
        let flight = ["flap.1", "flap.2", "flap.3", "flap.ledge", "land", "bump", "vent"].map(Self.small).max()!
        let urgent = ["clash.lost": 5.0, "rider.lost": 4.0, "hatch.warning": 5.0, "rift.warning": 4.0,
                      "pod.lost": 4.0, "pod.seized": 5.0, "lamps.fail": 4.0, "colonists.gone": 2.5, "game.over": 4.0,
                      "rift.erupt": 4.0]
        for (name, factor) in urgent {
            #expect(Self.small(name) >= factor * flight, "\(name) \(Self.small(name)) vs flight \(flight)")
        }
        // Urgent cues win when the synth runs out of voices: they outrank everything else.
        let urgentNames = Set(urgent.keys.map { "caves." + $0 })
        let topOther = Self.usedPatches.filter { !urgentNames.contains($0.name) }.map(\.priority).max()!
        for name in urgentNames {
            let priority = Self.usedPatches.first { $0.name == name }!.priority
            #expect(priority >= 9 && priority >= topOther - 1, "\(name) priority \(priority)")
        }
        // The colonists' alarms are pitched above everything noisy and are tonal.
        #expect(Self.features["caves.pod.seized"]!.centroid > 1500)
        #expect(Self.features["caves.hatch.warning"]!.centroid > 900)
        #expect(Self.features["caves.pod.seized"]!.flatness < Self.features["caves.flap.1"]!.flatness)
        // The wings' opening lasts exactly as long as they take to open.
        let opening = Self.theme.sound(for: .wingsOpening(at: .zero))!
        #expect(abs(opening.duration - RiftwingTuning().wingReopen) < 0.001)
    }

    /// The Rift about to fill the gallery sounds worse than an ordinary breath: at least as loud,
    /// longer, lower, and unlike it.
    @Test func theEruptionIsWorseThanABreath() {
        let erupt = Self.measure("rift.erupt"), breath = Self.measure("rift.warning")
        #expect(erupt.duration >= breath.duration * 1.5)
        #expect(erupt.loudness >= breath.loudness * 0.95, "\(erupt.loudness) vs \(breath.loudness)")
        #expect(Self.small("rift.erupt") >= Self.small("rift.warning") * 0.8)
        #expect(erupt.peak >= 0.7)
        let a = Self.features["caves.rift.erupt"]!, b = Self.features["caves.rift.warning"]!
        #expect(Self.featureScores(a, b).map(\.score).max()! >= 1)
        #expect(RiftwingSoundDirector.kind(of: .riftFillWarning(level: 600)) != RiftwingSoundDirector.kind(of: .riftWarning(level: 200)))
    }

    @Test func loudnessFollowsImportance() {
        for big in ["clash.lost", "rider.lost", "lamps.fail", "rift.warning", "life.extra", "game.over", "stoop.4"] {
            let m = Self.measure(big)
            #expect(m.peak >= 0.7, "\(big) peak \(m.peak)")
            #expect(m.loudness >= 6 * Self.loud("flap.1"), "\(big) \(m.loudness)")
        }
        // Losing a clash is louder than winning one.
        #expect(Self.small("clash.lost") > Self.small("clash.won"))
        // Subtle things stay subtle.
        for subtle in ["land", "bump", "vent", "mine.laid", "pod.land", "foe.fell", "rift.settle", "arrival"] {
            #expect(Self.loud(subtle) < Self.loud("clash.won"), "\(subtle)")
        }
    }

    @Test func familiesShareATimbre() {
        func median(_ family: SoundFamily, _ value: (Features) -> Double) -> Double {
            let values = Self.usedPatches.filter { $0.family == family }.map { value(Self.features[$0.name]!) }.sorted()
            return values[values.count / 2]
        }
        let colonistNoise = median(.colonist) { $0.flatness }
        #expect(colonistNoise < median(.player) { $0.flatness } && colonistNoise < median(.enemy) { $0.flatness })
        for patch in Self.usedPatches {
            let waves = Set(patch.layers.map(\.wave))
            switch patch.family {
            case .enemy: #expect(waves.isSubset(of: [.saw, .noise, .crackle]), "\(patch.name)")
            case .colonist: #expect(waves.isSubset(of: [.sine, .triangle]), "\(patch.name)")
            case .player: #expect(!waves.contains(.saw) && !waves.contains(.crackle), "\(patch.name)")
            case .alert, .interface: break
            }
        }
        for family in SoundFamily.allCases {
            #expect(Self.usedPatches.contains { $0.family == family }, "\(family) has no sounds")
        }
    }

    /// Pairs a player must never mix up: each must differ clearly in at least two ways that are
    /// not just length.
    static let importantPairs: [(String, String)] = [
        ("clash.won", "clash.lost"), ("clash.lost", "rider.lost"), ("pod.seized", "hatch.warning"),
        ("pod.lost", "pod.freed.1"), ("hatch.warning", "rift.warning"), ("rift.warning", "lamps.fail"),
        ("lamps.fail", "lamps.restore"), ("cavern.shift", "rift.rise"), ("wave.start", "rift.warning"),
        ("life.extra", "wave.clear"), ("pod.lost", "colonists.gone"), ("bounce", "clash.won"),
        ("dive", "foe.dive"), ("flap.1", "land"), ("pod.caught", "pod.freed.1"), ("hatch", "pod.lost"),
    ]

    @Test func importantPairsDifferInCharacterNotJustLength() {
        for (a, b) in Self.importantPairs {
            let scores = Self.featureScores(Self.features["caves." + a]!, Self.features["caves." + b]!).dropFirst()
            let clear = scores.filter { $0.score >= 1 }.map(\.name)
            print("PAIR \(a) / \(b): " + scores.map { "\($0.name) \(String(format: "%.2f", $0.score))" }.joined(separator: ", "))
            #expect(clear.count >= 2, "\(a) and \(b) differ clearly only in \(clear)")
        }
    }

    @Test func distinctEventsSoundMeasurablyDifferent() {
        let patches = Self.usedPatches
        var closest = (score: Double.infinity, pair: "")
        for i in patches.indices {
            for j in patches.indices where j > i {
                // Versions of one sound are meant to be alike.
                guard Self.stem(patches[i].name) != Self.stem(patches[j].name) else { continue }
                let scores = Self.featureScores(Self.features[patches[i].name]!, Self.features[patches[j].name]!)
                let score = scores.map(\.score).max()!
                #expect(score >= 1, "\(patches[i].name) and \(patches[j].name) are too alike (\(score))")
                if score < closest.score { closest = (score, "\(patches[i].name) / \(patches[j].name)") }
            }
        }
        print("closest pair: \(closest.pair) at \(closest.score)")
    }
}

@Suite struct RiftwingMusicTests {
    static let style = RiftCaves().music!
    static let rate = 22_050.0

    func notes(_ mood: MusicMood, seconds: Double = 60, seed: UInt64 = 3) -> [MusicNote] {
        var composer = MusicComposer(style: Self.style, seed: seed)
        var all: [MusicNote] = []
        var t = 0.0
        while t < seconds {
            all += composer.notes(from: t, to: t + 0.25, mood: mood)
            t += 0.25
        }
        return all
    }

    func render(_ mood: MusicMood, seconds: Double) -> [Float] {
        var music = AmbientMusic(style: Self.style, seed: 9, sampleRate: Self.rate, mood: mood)
        var out: [Float] = []
        var made = 0.0
        while made < seconds {
            out += music.render(2048)
            made += 2048 / Self.rate
        }
        return out
    }

    @Test func itsOwnKeyAndTempo() {
        // Ridgeline is A minor at 84 bpm, Redoubt G Phrygian at 104 (other targets, so their
        // values are written here). Riftwing is E Lydian at 96: another tonic, another mode.
        #expect(Self.style.root % 12 == 4)
        #expect(Self.style.root % 12 != 9 && Self.style.root % 12 != 7)
        #expect(Self.style.scale == [0, 2, 4, 6, 7, 9, 11])
        #expect(Self.style.tempo != 84 && Self.style.tempo != 104)
        #expect(abs(Self.style.tempo - 84) >= 8 && abs(Self.style.tempo - 104) >= 8)
        for mood in MusicMood.allCases { #expect(Self.style.moods[mood] != nil, "\(mood)") }
    }

    @Test func notesStayInKeyAndInOrder() {
        for mood in MusicMood.allCases {
            let all = notes(mood)
            #expect(!all.isEmpty)
            #expect(zip(all, all.dropFirst()).allSatisfy { $0.time <= $1.time })
            for note in all where note.voice != .drone {
                #expect(Self.style.inScale(note.pitch), "\(mood): \(note.pitch) out of key")
            }
        }
    }

    @Test func aWaveRidesAWingbeatAndTheDarkIsSparse() {
        func count(_ mood: MusicMood, _ voice: MusicVoice? = nil) -> Int {
            notes(mood).filter { voice == nil || $0.voice == voice }.count
        }
        #expect(count(.tension) > count(.calm))
        #expect(count(.calm) >= count(.title))
        // A pulse in threes (six eighths: stroke, lift, glide twice), on most of them.
        let pulse = Self.style.profile(.tension).pulse
        #expect(pulse.count == 6)
        #expect(Double(pulse.reduce(0, +)) / Double(pulse.count) >= 0.6)
        #expect(count(.tension, .bass) > 120)
        #expect(count(.calm, .bass) == 0 && count(.title, .bass) == 0 && count(.blackout, .bass) == 0)
        #expect(count(.blackout, .bell) < count(.calm, .bell))
        #expect(notes(.blackout).contains { $0.voice == .drone })
        func meanPitch(_ mood: MusicMood) -> Double {
            let all = notes(mood).filter { $0.voice != .bell }
            return Double(all.map(\.pitch).reduce(0, +)) / Double(all.count)
        }
        #expect(meanPitch(.blackout) < meanPitch(.calm) - 6)
    }

    @Test func theBedIsQuietCleanAndLoopsWithoutWearing() {
        for mood in MusicMood.allCases {
            let m = CavesSoundMeasure(samples: render(mood, seconds: 20), sampleRate: Self.rate)
            #expect(m.isFinite, "\(mood)")
            #expect(m.peak < 0.5, "\(mood) peaks at \(m.peak)")
            #expect(m.rms > 0.004 && m.rms < 0.12, "\(mood) rms \(m.rms)")
            #expect(abs(m.mean) < 0.01, "\(mood) DC \(m.mean)")
            #expect(m.largestKink < 0.03, "\(mood) kinks by \(m.largestKink)")
        }
        // Five minutes of a wave: the level holds steady from minute to minute.
        let long = render(.tension, seconds: 300)
        let minute = Int(60 * Self.rate)
        let levels = (0..<5).map { CavesSoundMeasure.rms(long[($0 * minute)..<min(($0 + 1) * minute, long.count)]) }
        #expect(levels.max()! / levels.min()! < 1.5, "\(levels)")
        #expect(long.allSatisfy { $0.isFinite && abs($0) < 0.5 })
    }

    @Test func changingMoodGlidesWithoutClicks() {
        var music = AmbientMusic(style: Self.style, seed: 9, sampleRate: Self.rate, mood: .calm)
        var out = music.render(Int(Self.rate * 3))
        // A wave, its break, the lamps failing as the next starts, coming back, the next break.
        for (mood, seconds) in [(MusicMood.tension, 6.0), (.calm, 4), (.blackout, 6), (.tension, 4), (.calm, 3)] {
            music.setMood(mood)
            out += music.render(Int(Self.rate * seconds))
        }
        #expect(out.allSatisfy { $0.isFinite && abs($0) < 0.5 })
        let kink = CavesSoundMeasure(samples: out, sampleRate: Self.rate).largestKink
        #expect(kink < 0.03, "kink \(kink)")
    }

    @Test func everyMoodStaysAudibleThroughASmallSpeaker() {
        for mood in MusicMood.allCases {
            let full = CavesSoundMeasure(samples: render(mood, seconds: 12), sampleRate: Self.rate)
            let small = full.smallSpeaker()
            let loss = 20 * log10(small.rms / full.rms)
            print(String(format: "SPEAKER caves music.%@ rms %.4f -> %.4f (%.1f dB)", mood.rawValue as NSString, full.rms, small.rms, loss))
            #expect(loss > -12, "\(mood) loses \(loss) dB")
            #expect(small.rms > 0.006, "\(mood) small-speaker rms \(small.rms)")
        }
    }

    @Test func lampsOutIsDarkerThanCalm() {
        let dark = CavesSoundMeasure(samples: render(.blackout, seconds: 12), sampleRate: Self.rate).spectralShape()
        let calm = CavesSoundMeasure(samples: render(.calm, seconds: 12), sampleRate: Self.rate).spectralShape()
        #expect(dark.centroid < calm.centroid, "lamps out \(dark.centroid) calm \(calm.centroid)")
    }
}
