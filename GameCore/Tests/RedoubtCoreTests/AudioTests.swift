import Foundation
import Testing
import GameCore
@testable import RedoubtCore

/// Measurements of a rendered sound, so sounds can be checked without listening. (The same
/// measures as Ridgeline's audio tests, which live in another test target.)
struct DomeSoundMeasure {
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
    func smallSpeaker(cutoff: Double = 400) -> DomeSoundMeasure {
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
        return DomeSoundMeasure(samples: out, sampleRate: sampleRate)
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

/// Every kind of Redoubt event, each role where an event carries one.
enum RedoubtEventCatalog {
    static let p = Vec2(450, 300)

    static let every: [RedoubtEvent] = {
        var events: [RedoubtEvent] = [
            .waveStarted(wave: 1, colonists: 6), .waveCleared(wave: 1, safe: 3, bonus: 750),
            .airlockClosed(at: p), .airlockOpened(wall: .north, at: p), .allColonistsLost(wave: 2),
            .powerCutBegan, .powerCutEnded,
            .orbFired(at: p, heading: 0), .shotEnded(id: 1, at: p, reason: .wall), .shockwave(at: p, destroyed: 12),
            .chargeEarned(charges: 2), .orbDestroyed(at: p, livesLeft: 2, cause: .shot(id: 3)),
            .lineScattered(count: 3), .orbRespawned(at: p), .extraLife(lives: 4),
            .burrowSpawned(burrow: 1, id: 2, at: p), .spitterWindUp(id: 1, at: p),
            .enemyFired(id: 1, at: p, heading: 0), .huskFormed(id: 1, at: p),
            .colonistSeized(id: 1, by: 2, at: p), .colonistFreed(id: 1, at: p),
            .colonistTaken(id: 1, by: .gleaner, enemy: 2, at: p), .colonistCrushed(id: 1, by: 2, at: p),
            .gameOver(score: 1000),
        ]
        for position in 1...7 {
            events.append(.colonistPickedUp(id: position, at: p, position: position))
            events.append(.colonistDelivered(id: position, at: p, position: position, points: 500 * position))
        }
        for role in RedoubtRole.allCases {
            events.append(.arrivalTelegraphed(id: 1, role: role, at: p))
            events.append(.enemyArrived(id: 1, role: role, at: p))
            events.append(.enemyHit(id: 1, role: role, at: p))
            events.append(.enemyDestroyed(id: 1, role: role, at: p, points: 50, byShockwave: false))
            events.append(.enemyDestroyed(id: 1, role: role, at: p, points: 50, byShockwave: true))
            events.append(.enemyWithdrew(id: 1, role: role, at: p))
        }
        return events
    }()

    /// Events that make no sound of their own, on purpose (see `CalderDome.sound(for:variant:)`).
    static func isSilent(_ event: RedoubtEvent) -> Bool {
        switch event {
        case .airlockClosed, .lineScattered, .enemyWithdrew, .enemyArrived, .shotEnded: true
        default: false
        }
    }
}

@Suite struct RedoubtSoundPatchTests {
    static let rate = 44_100.0
    static let theme = CalderDome()

    /// Every distinct patch any event (in every version) or menu action can play.
    static let usedPatches: [SoundPatch] = {
        var byName: [String: SoundPatch] = [:]
        for event in RedoubtEventCatalog.every {
            for variant in 0..<8 {
                if let patch = theme.sound(for: event, variant: variant) { byName[patch.name] = patch }
            }
        }
        for sound in MenuSound.allCases { if let p = theme.menuSound(sound) { byName[p.name] = p } }
        return byName.values.sorted { $0.name < $1.name }
    }()

    static let measures: [String: DomeSoundMeasure] = {
        var all: [String: DomeSoundMeasure] = [:]
        for patch in usedPatches {
            all[patch.name] = DomeSoundMeasure(samples: SoundRenderer.render(patch, sampleRate: rate), sampleRate: rate)
        }
        return all
    }()

    static func measure(_ short: String) -> DomeSoundMeasure { measures["dome." + short]! }
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

    /// A sound family's versions (pitches, stages, line lengths) share a stem: "orb.fire.2" is
    /// "orb.fire".
    static func stem(_ name: String) -> String {
        guard let last = name.split(separator: ".").last, Int(last) != nil else { return name }
        return String(name.dropLast(last.count + 1))
    }

    @Test func everyEventThatShouldSoundHasAPatchInTheTheme() {
        let listed = Set(Self.theme.allSounds.map(\.name))
        for event in RedoubtEventCatalog.every {
            let patch = Self.theme.sound(for: event)
            if RedoubtEventCatalog.isSilent(event) {
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

    @Test func patchNamesAreUniqueAndTheDomesOwn() {
        let names = Self.theme.allSounds.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.count >= 45)
        for name in names {
            // Ridgeline's patches are all "frontier."; the one synthesiser keys buffers by name.
            #expect(name.hasPrefix("dome."), "\(name)")
            #expect(!name.hasPrefix("frontier."), "\(name)")
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
            #expect(patch.maxVoices >= 1 && patch.cooldown > 0, "\(name)")
        }
    }

    @Test func printFeatureTable() {
        for patch in Self.usedPatches {
            let f = Self.features[patch.name]!, m = Self.measures[patch.name]!
            print(String(format: "FEAT %-24@ %-9@ dur %.3f peak %.2f loud %.3f small %.3f cent %6.0f flat %.3f slope %+.2f pk %.2f",
                         patch.name as NSString, patch.family.rawValue as NSString, f.duration, m.peak, m.loudness,
                         m.smallSpeaker().loudness, f.centroid, f.flatness, f.slope, f.peakPosition))
        }
    }

    @Test func renderingIsDeterministic() {
        let patch = Self.theme.sound(for: .shockwave(at: .zero, destroyed: 1))!
        #expect(SoundRenderer.render(patch, sampleRate: Self.rate) == SoundRenderer.render(patch, sampleRate: Self.rate))
    }

    @Test func theStreamOfFireIsShortQuietAndVaried() {
        let shots = (0..<CalderDome.fireVariants).map { Self.theme.sound(for: .orbFired(at: .zero, heading: 0), variant: $0)! }
        #expect(Set(shots.map(\.name)).count == 3)
        for shot in shots {
            let m = Self.measures[shot.name]!
            // Ten a second: each copy ends well before the next, so one voice carries the stream
            // and the synth never cuts a copy short (which would click).
            #expect(shot.duration <= 0.06, "\(shot.name) lasts \(shot.duration)")
            #expect(shot.cooldown < 0.1 && shot.cooldown >= 0.04, "\(shot.name) cooldown \(shot.cooldown)")
            #expect(shot.maxVoices == 1)
            // The lowest priority: it never takes a voice from anything else.
            #expect(shot.priority == 0)
            #expect(m.peak <= 0.15)
            #expect(m.loudness <= 0.035, "\(shot.name) loudness \(m.loudness)")
        }
        // The most frequent sound is among the very quietest.
        let fire = Self.loud("orb.fire.1")
        let quieter = Self.usedPatches.filter { Self.measures[$0.name]!.loudness < fire && !$0.name.contains("orb.fire") }
        #expect(quieter.isEmpty, "\(quieter.map(\.name))")
        // The pitches differ, by about a semitone either way.
        let centroids = shots.map { Self.features[$0.name]!.centroid }
        #expect(centroids.max()! / centroids.min()! > 1.05)
    }

    @Test func aCrowdDyingIsLight() {
        for v in 0..<CalderDome.skitterVariants {
            let patch = Self.theme.sound(for: .enemyDestroyed(id: 1, role: .skitter, at: .zero, points: 50,
                                                               byShockwave: false), variant: v)!
            let m = Self.measures[patch.name]!
            #expect(patch.duration < 0.1, "\(patch.name) lasts \(patch.duration)")
            #expect(m.peak <= 0.3)
            #expect(patch.priority <= 1 && patch.maxVoices <= 2)
            // Eight landing in 50 ms (as the director allows, every third step) never pass the
            // ceiling even summed raw.
            var sum = [Double](repeating: 0, count: Int(0.2 * Self.rate))
            let samples = SoundRenderer.render(patch, sampleRate: Self.rate)
            for k in 0..<8 {
                let start = Int(Double(k * RedoubtSoundDirector.skitterGapTicks) / 120 * Self.rate)
                for i in samples.indices where start + i < sum.count { sum[start + i] += Double(samples[i]) }
            }
            #expect(sum.map(abs).max()! < 0.6, "eight \(patch.name) sum to \(sum.map(abs).max()!)")
        }
    }

    @Test func killsWeighInProportionToTheirWorth() {
        // Points: Skitter 50, Gleaner 150, Spitter 200, Husk 250, Burrow 1,000, Thresher 1,500.
        let order = ["skitter.pop.1", "gleaner.die", "spitter.die", "husk.die", "burrow.collapse", "thresher.wreck"]
        for (a, b) in zip(order, order.dropFirst()) {
            #expect(Self.loud(a) < Self.loud(b), "\(a) \(Self.loud(a)) vs \(b) \(Self.loud(b))")
            #expect(Self.measure(a).duration <= Self.measure(b).duration, "\(a) vs \(b) length")
        }
        // Each still carries on a phone speaker, and the big two stand well above a Skitter.
        for name in order {
            let m = Self.measure(name)
            #expect(m.smallSpeaker().loudness >= 0.7 * m.loudness, "\(name) loses too much on a small speaker")
        }
        #expect(Self.small("burrow.collapse") >= 2.5 * Self.small("skitter.pop.1"))
        #expect(Self.small("thresher.wreck") >= 3 * Self.small("skitter.pop.1"))
    }

    @Test func theShockwaveIsTheBiggestSoundInTheGame() {
        let shock = Self.measure("shockwave")
        for patch in Self.usedPatches where patch.name != "dome.shockwave" {
            let m = Self.measures[patch.name]!
            #expect(shock.loudness > m.loudness, "\(patch.name) \(m.loudness) vs shockwave \(shock.loudness)")
            #expect(shock.smallSpeaker().loudness > m.smallSpeaker().loudness,
                    "\(patch.name) on a small speaker \(m.smallSpeaker().loudness) vs \(shock.smallSpeaker().loudness)")
        }
        #expect(shock.peak >= 0.9)
    }

    @Test func warningsStandWellAboveTheCrowd() {
        // Heard over the stream of fire and a crowd of Skitters dying: on a phone speaker each
        // warning is at least several times as loud as a shot or a Skitter.
        let crowd = max(Self.small("orb.fire.1"), Self.small("skitter.pop.1"), Self.small("skitter.pop.2"),
                        Self.small("skitter.pop.3"))
        let warnings = ["colonist.seized": 5.0, "colonist.taken": 3.5, "colonist.crushed": 2.5, "husk.form": 2.5,
                        "spitter.windup": 2.5, "orb.lost": 5, "power.fail": 4, "colonists.gone": 2.5]
        for (name, factor) in warnings {
            #expect(Self.small(name) >= factor * crowd, "\(name) \(Self.small(name)) vs crowd \(crowd)")
        }
        // A seized colonist is the loudest colonist sound but the reward, and pitched above
        // the crowd's noise.
        for patch in Self.usedPatches where patch.family == .colonist && !patch.name.contains("delivery") {
            if patch.name != "dome.colonist.seized" {
                #expect(Self.loud("colonist.seized") > Self.measures[patch.name]!.loudness, "\(patch.name)")
            }
        }
        #expect(Self.features["dome.colonist.seized"]!.flatness < Self.features["dome.skitter.pop.1"]!.flatness)
        // The Spitter's tell lasts exactly its wind-up.
        let windUp = Self.theme.sound(for: .spitterWindUp(id: 1, at: .zero))!
        #expect(abs(windUp.duration - RedoubtTuning().spitterWindUp) < 0.001)
        // A Thresher being hit is a dull clank, much smaller than a kill.
        #expect(Self.loud("thresher.clank") < 0.5 * Self.loud("gleaner.die"))
        #expect(Self.measure("thresher.clank").duration < 0.1)
    }

    @Test func aDeliveryGrowsWithTheLine() {
        var last: (duration: Double, loudness: Double, layers: Int) = (0, 0, 0)
        for count in 1...CalderDome.deliverySizes {
            let patch = Self.theme.sound(for: .colonistDelivered(id: 1, at: .zero, position: 1, points: 500),
                                         variant: count)!
            #expect(patch.name == "dome.delivery.\(count)")
            let m = Self.measures[patch.name]!
            #expect(patch.duration > last.duration)
            #expect(m.loudness >= last.loudness * 0.95, "delivery \(count) \(m.loudness) vs \(last.loudness)")
            #expect(patch.layers.count > last.layers)
            last = (patch.duration, m.loudness, patch.layers.count)
        }
        #expect(Self.loud("delivery.\(CalderDome.deliverySizes)") >= 1.15 * Self.loud("delivery.1"))
        // Longer lines play the biggest; a missing count plays the smallest.
        let ten = Self.theme.sound(for: .colonistDelivered(id: 1, at: .zero, position: 1, points: 500), variant: 10)
        #expect(ten?.name == "dome.delivery.\(CalderDome.deliverySizes)")
        #expect(Self.theme.sound(for: .colonistDelivered(id: 1, at: .zero, position: 1, points: 500))?.name == "dome.delivery.1")
        // The reward is louder than joining the line, and than a charge's chime.
        #expect(Self.loud("delivery.1") > Self.loud("colonist.join.1"))
        // Joining climbs with the line.
        let joins = (1...CalderDome.joinNotes).map { Self.features["dome.colonist.join.\($0)"]!.centroid }
        #expect(zip(joins, joins.dropFirst()).allSatisfy { $0 < $1 }, "\(joins)")
    }

    @Test func aBurrowSoundsMoreDamagedAsItIsShot() {
        let stages = (0..<CalderDome.burrowHitStages).map {
            Self.theme.sound(for: .enemyHit(id: 1, role: .burrow, at: .zero), variant: $0)!.name
        }
        #expect(Set(stages).count == CalderDome.burrowHitStages)
        let centroids = stages.map { Self.features[$0]!.centroid }
        #expect(centroids.last! > centroids.first!, "\(centroids)")
    }

    @Test func loudnessFollowsImportance() {
        for big in ["shockwave", "orb.lost", "power.fail", "life.extra", "game.over"] {
            let m = Self.measure(big)
            #expect(m.peak >= 0.7, "\(big) peak \(m.peak)")
            #expect(m.loudness >= 8 * Self.loud("orb.fire.1"), "\(big) \(m.loudness)")
        }
        // The orb's loss is louder than every kill.
        for kill in ["gleaner.die", "spitter.die", "husk.die", "burrow.collapse", "thresher.wreck"] {
            #expect(Self.small("orb.lost") > Self.small(kill), "\(kill)")
        }
        // Subtle things stay subtle.
        for subtle in ["arrival.swarm", "arrival.heavy", "burrow.spawn", "burrow.hit.1", "spitter.hit", "thresher.clank"] {
            #expect(Self.loud(subtle) < Self.loud("gleaner.die"), "\(subtle)")
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
            case .player: #expect(!waves.contains(.saw), "\(patch.name)")
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
        ("shockwave", "orb.lost"), ("power.fail", "game.over"), ("colonist.seized", "colonist.taken"),
        ("colonist.taken", "colonist.crushed"), ("wave.start", "power.fail"), ("delivery.1", "charge.earned"),
        ("life.extra", "wave.clear"), ("shockwave", "thresher.wreck"), ("spitter.windup", "husk.form"),
        ("colonist.seized", "spitter.windup"), ("power.fail", "power.restore"), ("colonists.gone", "colonist.taken"),
    ]

    @Test func importantPairsDifferInCharacterNotJustLength() {
        for (a, b) in Self.importantPairs {
            let scores = Self.featureScores(Self.features["dome." + a]!, Self.features["dome." + b]!).dropFirst()
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

@Suite struct RedoubtMusicTests {
    static let style = CalderDome().music!
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

    @Test func aWaveDrivesAndTheDarkIsSparse() {
        func count(_ mood: MusicMood, _ voice: MusicVoice? = nil) -> Int {
            notes(mood).filter { voice == nil || $0.voice == voice }.count
        }
        #expect(count(.tension) > count(.calm))
        #expect(count(.calm) >= count(.title))
        // The relentless part: a low pulse on most eighths of a wave, none outside it.
        let pulse = Self.style.profile(.tension).pulse
        #expect(Double(pulse.reduce(0, +)) / Double(pulse.count) >= 0.7)
        #expect(count(.tension, .bass) > 150)
        #expect(count(.calm, .bass) == 0 && count(.title, .bass) == 0)
        #expect(count(.blackout, .bell) < count(.calm, .bell))
        #expect(notes(.blackout).contains { $0.voice == .drone })
        func meanPitch(_ mood: MusicMood) -> Double {
            let all = notes(mood).filter { $0.voice != .bell }
            return Double(all.map(\.pitch).reduce(0, +)) / Double(all.count)
        }
        #expect(meanPitch(.blackout) < meanPitch(.calm) - 6)
        // The flat second: Phrygian, the dome's closeness.
        #expect(Self.style.scale.contains(1))
    }

    @Test func theBedIsQuietCleanAndLoopsWithoutWearing() {
        for mood in MusicMood.allCases {
            let m = DomeSoundMeasure(samples: render(mood, seconds: 20), sampleRate: Self.rate)
            #expect(m.isFinite, "\(mood)")
            #expect(m.peak < 0.5, "\(mood) peaks at \(m.peak)")
            #expect(m.rms > 0.004 && m.rms < 0.12, "\(mood) rms \(m.rms)")
            #expect(abs(m.mean) < 0.01, "\(mood) DC \(m.mean)")
            #expect(m.largestKink < 0.03, "\(mood) kinks by \(m.largestKink)")
        }
        // Five minutes of a wave: the level holds steady from minute to minute (no build-up, no
        // dying away), so it can loop for as long as a wave lasts.
        let long = render(.tension, seconds: 300)
        let minute = Int(60 * Self.rate)
        let levels = (0..<5).map { DomeSoundMeasure.rms(long[($0 * minute)..<min(($0 + 1) * minute, long.count)]) }
        #expect(levels.max()! / levels.min()! < 1.5, "\(levels)")
        #expect(long.allSatisfy { $0.isFinite && abs($0) < 0.5 })
    }

    @Test func changingMoodGlidesWithoutClicks() {
        var music = AmbientMusic(style: Self.style, seed: 9, sampleRate: Self.rate, mood: .calm)
        var out = music.render(Int(Self.rate * 3))
        // A wave, its break, the next wave, the power failing and coming back.
        for (mood, seconds) in [(MusicMood.tension, 6.0), (.calm, 2), (.tension, 6), (.blackout, 6), (.tension, 4)] {
            music.setMood(mood)
            out += music.render(Int(Self.rate * seconds))
        }
        #expect(out.allSatisfy { $0.isFinite && abs($0) < 0.5 })
        let kink = DomeSoundMeasure(samples: out, sampleRate: Self.rate).largestKink
        #expect(kink < 0.03, "kink \(kink)")
    }

    @Test func everyMoodStaysAudibleThroughASmallSpeaker() {
        for mood in MusicMood.allCases {
            let full = DomeSoundMeasure(samples: render(mood, seconds: 12), sampleRate: Self.rate)
            let small = full.smallSpeaker()
            let loss = 20 * log10(small.rms / full.rms)
            print(String(format: "SPEAKER dome music.%@ rms %.4f -> %.4f (%.1f dB)", mood.rawValue as NSString, full.rms, small.rms, loss))
            #expect(loss > -12, "\(mood) loses \(loss) dB")
            #expect(small.rms > 0.006, "\(mood) small-speaker rms \(small.rms)")
        }
    }

    @Test func blackoutIsDarkerThanTension() {
        let dark = DomeSoundMeasure(samples: render(.blackout, seconds: 12), sampleRate: Self.rate).spectralShape()
        let calm = DomeSoundMeasure(samples: render(.calm, seconds: 12), sampleRate: Self.rate).spectralShape()
        #expect(dark.centroid < calm.centroid, "blackout \(dark.centroid) calm \(calm.centroid)")
    }
}
