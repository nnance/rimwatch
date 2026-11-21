import Foundation
import Testing
import GameCore
@testable import RidgelineCore

/// Measurements of a rendered sound, so sounds can be checked without listening.
struct SoundMeasure {
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
    func smallSpeaker(cutoff: Double = 400) -> SoundMeasure {
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
        return SoundMeasure(samples: out, sampleRate: sampleRate)
    }

    /// Rhythm: how much the loudness jumps from one 20 ms window to the next, relative to the
    /// average loudness (a steady swell is near 0, a stutter or a run of notes is high).
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

    /// Click check: the first and last samples are silent, and the sound ramps in and out
    /// rather than jumping. Returns the worst of: an end sample, and the loudness reached within
    /// 0.3 ms of the start or 1 ms of the end as a fraction of the peak.
    func clickiness() -> Double {
        let head = max(Int(0.0003 * sampleRate), 1)
        let tail = max(Int(0.001 * sampleRate), 1)
        let first = samples.prefix(head).map { abs(Double($0)) }.max() ?? 0
        let last = samples.suffix(tail).map { abs(Double($0)) }.max() ?? 0
        let ends = max(abs(Double(samples.first ?? 0)), abs(Double(samples.last ?? 0)))
        return max(ends * 50, max(first, last) / max(peak, 1e-9))
    }

    /// Largest second difference: a step or a kink shows up here; a smooth tone barely does.
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

    /// Magnitude spectrum of a Hann-windowed frame of 2048 samples starting at `start`.
    func spectrum(at start: Int) -> [Double] {
        let size = Self.frameSize
        var re = [Double](repeating: 0, count: size)
        var im = [Double](repeating: 0, count: size)
        for i in 0..<size where start + i < samples.count {
            re[i] = Double(samples[start + i]) * Self.window[i]
        }
        fft(&re, &im)
        return (0..<(size / 2)).map { hypot(re[$0], im[$0]) }
    }

    /// Spectral centroid (Hz) and flatness (0 tonal ... 1 noise) of the frames in a time range,
    /// weighted by each frame's energy.
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

    /// How the brightness moves: log2 of the late centroid over the early one.
    var centroidSlope: Double {
        let early = spectralShape(from: 0, to: 0.4).centroid
        let late = spectralShape(from: 0.4, to: 1).centroid
        guard early > 0, late > 0 else { return 0 }
        return log2(late / early)
    }

    /// Where the loudest 50 ms sits, as a fraction of the length.
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

    /// In-place radix-2 FFT.
    private func fft(_ re: inout [Double], _ im: inout [Double]) {
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
                    let (wr, wi) = Self.twiddles[k * step]
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

@Suite struct SoundPatchTests {
    static let rate = 44_100.0
    static let theme = AlienFrontier()

    /// Every distinct patch any event or menu action can play.
    static let usedPatches: [SoundPatch] = {
        var events = FeedbackCueTests.everyEvent
        for kind in EnemyKind.allCases {
            events.append(.enemySpawned(id: 1, kind: kind))
            events.append(.enemyDestroyed(id: 1, kind: kind, at: .zero, points: 1))
        }
        var byName: [String: SoundPatch] = [:]
        for event in events { if let p = theme.sound(for: event) { byName[p.name] = p } }
        for sound in MenuSound.allCases { if let p = theme.menuSound(sound) { byName[p.name] = p } }
        return byName.values.sorted { $0.name < $1.name }
    }()

    static let measures: [String: SoundMeasure] = {
        var all: [String: SoundMeasure] = [:]
        for patch in usedPatches {
            all[patch.name] = SoundMeasure(samples: SoundRenderer.render(patch, sampleRate: rate), sampleRate: rate)
        }
        return all
    }()

    static func measure(_ short: String) -> SoundMeasure { measures["frontier." + short]! }

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

    @Test func everyPatchIsRealAndListed() {
        #expect(Self.usedPatches.count >= 40)
        let listed = Set(Self.theme.allSounds.map(\.name))
        for patch in Self.usedPatches {
            #expect(!patch.layers.isEmpty, "\(patch.name) has no layers")
            #expect(listed.contains(patch.name), "\(patch.name) is not in allSounds")
            #expect(patch.duration > 0.03 && patch.duration < 3.5, "\(patch.name) lasts \(patch.duration)")
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
        }
    }

    @Test func printFeatureTable() {
        for patch in Self.usedPatches {
            let f = Self.features[patch.name]!, m = Self.measures[patch.name]!
            print(String(format: "FEAT %-28@ %-9@ dur %.3f peak %.2f loud %.3f cent %6.0f flat %.3f slope %+.2f pk %.2f",
                         patch.name as NSString, patch.family.rawValue as NSString, f.duration, m.peak, m.loudness,
                         f.centroid, f.flatness, f.slope, f.peakPosition))
        }
    }

    @Test func renderingIsDeterministic() {
        let patch = Self.theme.sound(for: .shockwave(at: .zero))!
        #expect(SoundRenderer.render(patch, sampleRate: Self.rate) == SoundRenderer.render(patch, sampleRate: Self.rate))
        #expect(SoundRenderer.stableHash("frontier.blink") == SoundRenderer.stableHash("frontier.blink"))
    }

    /// Two sounds are told apart if their length, brightness, noisiness, the way their
    /// brightness moves, or where their loudest moment falls differs clearly.
    static func difference(_ a: Features, _ b: Features) -> (Double, String) {
        featureScores(a, b).max { $0.score < $1.score }!
    }

    /// Pairs a player must never mix up: each must differ clearly in at least two ways that are
    /// not just length.
    static let importantPairs: [(String, String)] = [
        ("shockwave", "player.explode"), ("blackout.begin", "game.over"), ("shield.break", "player.explode"),
        ("life.extra", "wave.clear"), ("wave.start", "blackout.begin"), ("shockwave", "anchor.explode"),
        ("player.explode", "outpost.destroyed"), ("colonist.lost", "colonist.dropped"),
        ("blackout.end", "outpost.supply"), ("shield.charged", "colonist.delivered"),
    ]

    @Test func importantPairsDifferInCharacterNotJustLength() {
        for (a, b) in Self.importantPairs {
            let scores = Self.featureScores(Self.features["frontier." + a]!, Self.features["frontier." + b]!)
                .dropFirst()
            let clear = scores.filter { $0.score >= 1 }.map(\.name)
            print("PAIR \(a) / \(b): " + scores.map { "\($0.name) \(String(format: "%.2f", $0.score))" }.joined(separator: ", "))
            #expect(clear.count >= 2, "\(a) and \(b) differ clearly only in \(clear)")
        }
    }

    @Test func importantSoundsSurviveASmallSpeaker() {
        // A phone speaker gives little below a few hundred hertz. Through one, the sounds that
        // matter must still stand well above the lance, and keep their order among themselves.
        func loud(_ name: String) -> Double { Self.measure(name).smallSpeaker().loudness }
        let fire = loud("lance.fire")
        for big in ["player.explode", "blackout.begin", "life.extra", "shockwave", "game.over", "outpost.destroyed"] {
            let full = Self.measure(big).loudness
            let small = loud(big)
            print(String(format: "SPEAKER %-18@ full %.3f small %.3f (%.1f dB) vs fire %.3f", big as NSString, full, small,
                         20 * log10(small / full), fire))
            #expect(small >= 2.5 * fire, "\(big) through a small speaker: \(small) vs fire \(fire)")
            // Never more than about 10 dB lost.
            #expect(small >= full * 0.32, "\(big) loses \(20 * log10(small / full)) dB")
        }
        #expect(loud("enemy.hit") < loud("enemy.explode"))
        #expect(loud("enemy.explode") < loud("player.explode"))
        // Using a Shockwave and losing the ship are the biggest moments in play: through a phone
        // speaker they stay louder than every routine sound.
        let routine = ["colonist.grabbed", "colonist.dropped", "colonist.caught", "colonist.delivered",
                       "colonist.landed", "colonist.lost", "enemy.explode", "enemy.hit", "mote.pop", "mine.pop",
                       "spore.fire", "enemy.warp", "lance.fire", "blink", "brood.burst", "husk.form"]
        for big in ["shockwave", "player.explode"] {
            for small in routine {
                #expect(loud(big) >= 1.1 * loud(small), "\(big) \(loud(big)) vs \(small) \(loud(small)) on a small speaker")
            }
        }
    }

    @Test func killSoundsAreSharpAndCarryOnAPhoneSpeaker() {
        // Destroying something should crack, not thud: the sound hits its peak at once, and its
        // weight sits where a phone speaker plays rather than in the bass it drops.
        let kills = ["enemy.explode", "brood.burst", "anchor.explode", "mote.pop", "mine.pop"]
        for name in kills {
            let m = Self.measure(name)
            let small = m.smallSpeaker().loudness
            #expect(small >= 0.75 * m.loudness, "\(name) loses \(20 * log10(small / m.loudness)) dB on a small speaker")
            let level = 0.9 * m.peak
            let rise = m.samples.firstIndex { Double(abs($0)) >= level } ?? m.samples.count
            #expect(Double(rise) / Self.rate <= 0.005, "\(name) takes \(Double(rise) / Self.rate) s to reach its peak")
        }
        // Scaled to what was destroyed, and all under losing the ship.
        func loud(_ name: String) -> Double { Self.measure(name).smallSpeaker().loudness }
        #expect(loud("mote.pop") < loud("enemy.explode"))
        #expect(loud("enemy.explode") < loud("anchor.explode"))
        #expect(loud("anchor.explode") < loud("player.explode"))
    }

    @Test func distinctEventsSoundMeasurablyDifferent() {
        let patches = Self.usedPatches
        var closest = (score: Double.infinity, pair: "")
        for i in patches.indices {
            for j in patches.indices where j > i {
                let (score, _) = Self.difference(Self.features[patches[i].name]!, Self.features[patches[j].name]!)
                #expect(score >= 1, "\(patches[i].name) and \(patches[j].name) are too alike (\(score))")
                if score < 1 { print("ALIKE \(patches[i].name) \(patches[j].name) \(score)") }
                if score < closest.score { closest = (score, "\(patches[i].name) / \(patches[j].name)") }
            }
        }
        print("closest pair: \(closest.pair) at \(closest.score)")
    }

    @Test func loudnessFollowsImportance() {
        let fire = Self.measure("lance.fire")
        #expect(fire.duration <= 0.08)
        #expect(fire.peak <= 0.2)
        // The most frequent sound is among the quietest.
        let quieter = Self.usedPatches.filter { Self.measures[$0.name]!.loudness < fire.loudness }
        #expect(quieter.count <= 4, "\(quieter.map(\.name))")
        for big in ["player.explode", "blackout.begin", "life.extra", "shockwave", "game.over"] {
            let m = Self.measure(big)
            #expect(m.peak >= 0.7, "\(big) peak \(m.peak)")
            #expect(m.loudness >= 2.5 * fire.loudness, "\(big) loudness \(m.loudness) vs fire \(fire.loudness)")
        }
        // Small enemy noises sit under the big ones.
        #expect(Self.measure("enemy.hit").loudness < Self.measure("enemy.explode").loudness)
        #expect(Self.measure("enemy.explode").loudness < Self.measure("player.explode").loudness)
        #expect(Self.measure("mote.pop").loudness < Self.measure("brood.burst").loudness)
    }

    @Test func familiesShareATimbre() {
        /// The family's median, so one odd member (a ship explosion is noise) doesn't decide it.
        func average(_ family: SoundFamily, _ value: (Features) -> Double) -> Double {
            let values = Self.usedPatches.filter { $0.family == family }.map { value(Self.features[$0.name]!) }.sorted()
            return values[values.count / 2]
        }
        // Colonists are the purest tones of all; enemies sit lower than the ship.
        let colonistNoise = average(.colonist) { $0.flatness }
        #expect(colonistNoise < average(.player) { $0.flatness } && colonistNoise < average(.enemy) { $0.flatness })
        let enemyBright = average(.enemy) { $0.centroid }, playerBright = average(.player) { $0.centroid }
        #expect(enemyBright < playerBright, "enemy \(enemyBright) player \(playerBright)")
        // And by construction: enemies buzz (sawtooth, noise and crackle), colonists sing (sine and
        // triangle), the ship never buzzes.
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

    @Test func envelopesStartAndEndAtZero() {
        let envelopes = [Envelope.pluck(0.1), Envelope(attack: 0.1, decay: 0.2, sustain: 0.5, release: 0.3)]
        for e in envelopes {
            #expect(e.level(at: 0, duration: 1) == 0)
            #expect(e.level(at: 1, duration: 1) == 0)
            #expect(e.level(at: 0.999_999, duration: 1) < 0.001)
        }
        #expect(Envelope(attack: 0.1, release: 0.1).level(at: 0.5, duration: 1) == 1)
    }

    @Test func crackleIsSparseGrainsThatThinOut() {
        func render(_ layer: SoundLayer) -> SoundMeasure {
            let patch = SoundPatch(name: "test.crackle", family: .enemy, gain: 0.8, layers: [layer])
            return SoundMeasure(samples: SoundRenderer.render(patch, sampleRate: Self.rate), sampleRate: Self.rate)
        }
        let steady = render(SoundLayer(.crackle, 200, envelope: Envelope(attack: 0.001, release: 0.001), duration: 1))
        let noise = render(SoundLayer(.noise, 0, envelope: Envelope(attack: 0.001, release: 0.001), duration: 1))
        #expect(steady.isFinite && steady.peak > 0.5)
        // Grains with gaps between them: far more of the sound is near silence than in noise.
        func quietShare(_ m: SoundMeasure) -> Double {
            let floor = 0.05 * m.peak
            return Double(m.samples.filter { Double(abs($0)) < floor }.count) / Double(m.samples.count)
        }
        #expect(quietShare(steady) > 0.5)
        #expect(quietShare(noise) < 0.1)
        // Grain density glides like a pitch does: thinning out leaves the end quieter.
        let thinning = render(SoundLayer(.crackle, 400, to: 20, envelope: Envelope(attack: 0.001, release: 0.001), duration: 1))
        let quarter = thinning.samples.count / 4
        #expect(SoundMeasure.rms(thinning.samples[(3 * quarter)...]) < 0.6 * SoundMeasure.rms(thinning.samples[..<quarter]))
    }

    @Test func echoTailFallsAway() {
        let echo = Echo(time: 0.1, feedback: 0.4, mix: 0.4)
        // 0.4 * 0.4^n < 0.01 after five repeats.
        #expect(echo.tail >= 0.4 && echo.tail <= 0.6)
    }
}

@Suite struct MusicTests {
    static let style = AlienFrontier().music!
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

    @Test func theComposerIsDeterministic() {
        #expect(notes(.tension) == notes(.tension))
        #expect(notes(.tension, seed: 3) != notes(.tension, seed: 4))
    }

    @Test func notesStayInKeyAndInOrder() {
        for mood in MusicMood.allCases {
            let all = notes(mood)
            #expect(!all.isEmpty)
            #expect(zip(all, all.dropFirst()).allSatisfy { $0.time <= $1.time })
            for note in all where note.voice != .drone {
                #expect(Self.style.inScale(note.pitch), "\(mood): \(note.pitch) out of key")
            }
            #expect(all.allSatisfy { $0.velocity > 0 && $0.velocity <= 1 && $0.duration > 0 })
        }
    }

    @Test func moodsDifferInDensityAndRegister() {
        func perMinute(_ mood: MusicMood, _ voice: MusicVoice? = nil) -> Int {
            notes(mood).filter { voice == nil || $0.voice == voice }.count
        }
        // A wave is busier than the calm; Blackout is the sparsest.
        #expect(perMinute(.tension) > perMinute(.calm))
        #expect(perMinute(.calm) >= perMinute(.title))
        #expect(perMinute(.blackout, .bell) < perMinute(.calm, .bell))
        #expect(perMinute(.tension, .bass) > 0 && perMinute(.calm, .bass) == 0)
        // Blackout sits lowest.
        func meanPitch(_ mood: MusicMood) -> Double {
            let all = notes(mood).filter { $0.voice != .bell }
            return Double(all.map(\.pitch).reduce(0, +)) / Double(all.count)
        }
        #expect(meanPitch(.blackout) < meanPitch(.calm) - 6)
        #expect(notes(.blackout).contains { $0.voice == .drone })
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

    @Test func theBedIsQuietCleanAndAlive() {
        for mood in MusicMood.allCases {
            let m = SoundMeasure(samples: render(mood, seconds: 20), sampleRate: Self.rate)
            #expect(m.isFinite, "\(mood)")
            #expect(m.peak < 0.5, "\(mood) peaks at \(m.peak)")
            #expect(m.rms > 0.004 && m.rms < 0.12, "\(mood) rms \(m.rms)")
            #expect(abs(m.mean) < 0.01, "\(mood) DC \(m.mean)")
            // Never a step or kink big enough to click.
            // (At this test's 22 kHz rate the highest bell partials alone reach about 0.02.)
            #expect(m.largestKink < 0.03, "\(mood) kinks by \(m.largestKink)")
        }
    }

    @Test func changingMoodGlidesWithoutClicks() {
        var music = AmbientMusic(style: Self.style, seed: 9, sampleRate: Self.rate, mood: .calm)
        var out = music.render(Int(Self.rate * 6))
        for mood in [MusicMood.tension, .blackout, .title, .tension] {
            music.setMood(mood)
            out += music.render(Int(Self.rate * 4))
        }
        #expect(out.allSatisfy { $0.isFinite && abs($0) < 0.5 })
        let kink = SoundMeasure(samples: out, sampleRate: Self.rate).largestKink
        #expect(kink < 0.03, "kink \(kink)")
        #expect(music.mood == .tension)
    }

    @Test func everyMoodStaysAudibleThroughASmallSpeaker() {
        for mood in MusicMood.allCases {
            let full = SoundMeasure(samples: render(mood, seconds: 12), sampleRate: Self.rate)
            let small = full.smallSpeaker()
            let loss = 20 * log10(small.rms / full.rms)
            print(String(format: "SPEAKER music.%@ rms %.4f -> %.4f (%.1f dB)", mood.rawValue as NSString, full.rms, small.rms, loss))
            #expect(loss > -12, "\(mood) loses \(loss) dB")
            #expect(small.rms > 0.006, "\(mood) small-speaker rms \(small.rms)")
        }
    }

    @Test func blackoutIsDarkerThanTension() {
        let dark = SoundMeasure(samples: render(.blackout, seconds: 12), sampleRate: Self.rate).spectralShape()
        let tense = SoundMeasure(samples: render(.tension, seconds: 12), sampleRate: Self.rate).spectralShape()
        #expect(dark.centroid < tense.centroid * 0.8, "blackout \(dark.centroid) tension \(tense.centroid)")
    }
}
