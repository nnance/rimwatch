import Foundation

/// A quiet generative ambient bed. `MusicComposer` decides the notes (pure logic, seeded);
/// `AmbientMusic` turns them into a stream of samples. The app only says which mood the game is
/// in and pulls samples; nothing is a recorded loop.

/// What the music should feel like.
public enum MusicMood: String, Sendable, CaseIterable {
    /// Title and menus without a run: calm and open.
    case title
    /// Between waves: calm, a little more movement.
    case calm
    /// A wave is under way: a soft pulse and busier figures.
    case tension
    /// Every colonist lost: a dark, sparse drone.
    case blackout
}

/// The parts the music is played on.
public enum MusicVoice: String, Sendable, CaseIterable {
    /// Slow chords.
    case pad
    /// A soft low pulse (tension only).
    case bass
    /// Sparse high bell notes.
    case bell
    /// A held low note (Blackout).
    case drone
}

public struct MusicNote: Sendable, Equatable {
    /// Seconds from the start of the music.
    public var time: Double
    public var duration: Double
    /// MIDI note number (60 is middle C).
    public var pitch: Int
    /// 0...1.
    public var velocity: Double
    public var voice: MusicVoice

    public var frequency: Double { 440 * pow(2, Double(pitch - 69) / 12) }
}

/// How one mood is played.
public struct MoodProfile: Sendable, Equatable {
    /// Chord roots as scale degrees (0 is the tonic), cycled.
    public var progression: [Int]
    public var chordSeconds: Double
    /// Chance of a bell note on each eighth-note slot.
    public var bellChance: Double
    /// Octaves above the root the bells sit in.
    public var bellOctave: Int
    /// Pulse pattern on eighths (1 plays, 0 rests), empty for none.
    public var pulse: [Int]
    /// Play a low drone instead of full chords.
    public var drone: Bool
    /// Pad brightness: low-pass cutoff in Hz.
    public var padCutoff: Double

    public init(progression: [Int], chordSeconds: Double, bellChance: Double, bellOctave: Int = 2,
                pulse: [Int] = [], drone: Bool = false, padCutoff: Double) {
        self.progression = progression
        self.chordSeconds = chordSeconds
        self.bellChance = bellChance
        self.bellOctave = bellOctave
        self.pulse = pulse
        self.drone = drone
        self.padCutoff = padCutoff
    }
}

/// A theme's music: key, scale, tempo and a profile for each mood.
public struct MusicStyle: Sendable, Equatable {
    /// MIDI note of the tonic in the pad's register.
    public var root: Int
    /// Semitones from the tonic, ascending, within one octave.
    public var scale: [Int]
    /// Beats per minute of the eighth-note grid's quarter.
    public var tempo: Double
    /// Overall level of the bed, 0...1. It sits well under the sound effects.
    public var gain: Double
    public var moods: [MusicMood: MoodProfile]

    public init(root: Int, scale: [Int], tempo: Double, gain: Double, moods: [MusicMood: MoodProfile]) {
        self.root = root
        self.scale = scale
        self.tempo = tempo
        self.gain = gain
        self.moods = moods
    }

    public func profile(_ mood: MusicMood) -> MoodProfile {
        moods[mood] ?? moods[.calm] ?? MoodProfile(progression: [0], chordSeconds: 8, bellChance: 0, padCutoff: 800)
    }

    /// The MIDI pitch of a scale degree (any integer; wraps into higher or lower octaves).
    public func pitch(degree: Int, octave: Int = 0) -> Int {
        let n = scale.count
        let wrapped = ((degree % n) + n) % n
        let octaves = (degree - wrapped) / n
        return root + scale[wrapped] + 12 * (octaves + octave)
    }

    /// True if the pitch belongs to the scale (any octave).
    public func inScale(_ pitch: Int) -> Bool {
        scale.contains(((pitch - root) % 12 + 12) % 12)
    }
}

/// Decides the notes, a slice of time at a time. Deterministic for a seed and a sequence of moods.
public struct MusicComposer: Sendable {
    public let style: MusicStyle
    private var rng: SeededRNG
    private var nextChord = 0.0
    private var chordIndex = 0
    private var nextSlot = 0.0
    private var slotIndex = 0
    /// The chord now sounding, as pitches, for the bells to draw on.
    private var chord: [Int] = []
    private var lastBell: Int?

    public init(style: MusicStyle, seed: UInt64) {
        self.style = style
        rng = SeededRNG(seed: seed)
    }

    /// Seconds per eighth-note slot.
    public var slotSeconds: Double { 30 / style.tempo }

    /// Notes that start in `start..<end` for `mood`. Call with consecutive, non-overlapping ranges.
    public mutating func notes(from start: Double, to end: Double, mood: MusicMood) -> [MusicNote] {
        let profile = style.profile(mood)
        var notes: [MusicNote] = []
        while nextChord < end {
            let time = max(nextChord, start)
            notes += chordNotes(at: time, profile: profile)
            nextChord = time + profile.chordSeconds
            chordIndex += 1
        }
        while nextSlot < end {
            let time = max(nextSlot, start)
            notes += slotNotes(at: time, profile: profile)
            nextSlot = time + slotSeconds
            slotIndex += 1
        }
        return notes.sorted { $0.time < $1.time }
    }

    /// The mood changed: start its first chord at once rather than waiting out the old one.
    public mutating func moodChanged(at time: Double) {
        nextChord = min(nextChord, time)
        chordIndex = 0
    }

    private mutating func chordNotes(at time: Double, profile: MoodProfile) -> [MusicNote] {
        let degree = profile.progression[chordIndex % max(profile.progression.count, 1)]
        // Pads overlap the next chord by a little, so changes cross-fade.
        let length = profile.chordSeconds + 2.5
        if profile.drone {
            // Root an octave down, and a fifth that drifts to a darker flat fifth now and then.
            let root = style.pitch(degree: degree, octave: -1)
            let fifth = rng.chance(0.35) ? root + 6 : root + 7
            chord = [root + 12, root + 15, root + 19]
            return [
                MusicNote(time: time, duration: length, pitch: root, velocity: 0.8, voice: .drone),
                MusicNote(time: time, duration: length, pitch: fifth, velocity: 0.45, voice: .drone),
                // A thin high echo of the root, so a phone speaker still carries the drone.
                MusicNote(time: time, duration: length, pitch: root + 24, velocity: 0.35, voice: .drone),
            ]
        }
        // A triad on the degree, in close voicing, plus the ninth on alternate chords for colour.
        var degrees = [degree, degree + 2, degree + 4]
        if chordIndex % 2 == 1 { degrees.append(degree + 8) }
        chord = degrees.map { style.pitch(degree: $0) }
        return chord.enumerated().map { index, pitch in
            MusicNote(time: time, duration: length, pitch: pitch, velocity: index == 0 ? 0.9 : 0.7, voice: .pad)
        }
    }

    private mutating func slotNotes(at time: Double, profile: MoodProfile) -> [MusicNote] {
        var notes: [MusicNote] = []
        if !profile.pulse.isEmpty, profile.pulse[slotIndex % profile.pulse.count] == 1, let root = chord.first {
            let accent = slotIndex % profile.pulse.count == 0
            notes.append(MusicNote(time: time, duration: slotSeconds * 0.9, pitch: root - 12,
                                   velocity: accent ? 0.9 : 0.55, voice: .bass))
        }
        if rng.chance(profile.bellChance), !chord.isEmpty {
            // Mostly chord tones, stepping near the last bell so the line sounds sung, not random.
            var pitch = chord[Int(rng.next() % UInt64(chord.count))] + 12 * profile.bellOctave
            if let last = lastBell, abs(pitch - last) > 7 {
                pitch += pitch > last ? -12 : 12
            }
            if !style.inScale(pitch) { pitch -= 1 }
            lastBell = pitch
            notes.append(MusicNote(time: time, duration: 2.4, pitch: pitch,
                                   velocity: rng.range(0.45...0.85), voice: .bell))
        }
        return notes
    }
}

/// Streams the music as samples. Mood changes glide over a couple of seconds; nothing cuts.
public struct AmbientMusic: Sendable {
    public let sampleRate: Double
    public let style: MusicStyle
    public private(set) var mood: MusicMood
    public private(set) var time = 0.0

    private var composer: MusicComposer
    private var queued: [MusicNote] = []
    private var voices: [Voice] = []
    /// Pad brightness, gliding toward the mood's.
    private var cutoff: Double
    private var plannedUntil = 0.0
    private var dcIn = 0.0
    private var dcOut = 0.0

    /// Most notes sounding at once; the oldest give way.
    static let maxVoices = 24
    /// Notes are planned this far ahead of the samples being made.
    static let planAhead = 0.25

    private struct Voice: Sendable {
        let note: MusicNote
        let start: Double
        var phase = 0.0
        var phase2 = 0.0
        var low1 = 0.0
        var low2 = 0.0
    }

    public init(style: MusicStyle, seed: UInt64, sampleRate: Double, mood: MusicMood = .title) {
        self.style = style
        self.sampleRate = sampleRate
        self.mood = mood
        composer = MusicComposer(style: style, seed: seed)
        cutoff = style.profile(mood).padCutoff
    }

    public mutating func setMood(_ mood: MusicMood) {
        guard mood != self.mood else { return }
        self.mood = mood
        // Notes already planned for the old mood but not started are dropped.
        queued.removeAll { $0.time > time }
        plannedUntil = time
        composer.moodChanged(at: time)
    }

    /// The next `count` samples.
    public mutating func render(_ count: Int) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        let dt = 1 / sampleRate
        let block = 64
        var n = 0
        while n < count {
            let blockEnd = min(n + block, count)
            let blockTime = time + Double(n) * dt
            plan(through: blockTime + Self.planAhead)
            startDue(by: blockTime + Double(blockEnd - n) * dt)
            let targetCutoff = style.profile(mood).padCutoff
            cutoff += (targetCutoff - cutoff) * min(Double(block) * dt / 2.0, 1)
            let smoothing = 1 - exp(-2 * .pi * cutoff * dt)
            for i in n..<blockEnd {
                let t = time + Double(i) * dt
                var sum = 0.0
                for v in voices.indices {
                    sum += Self.sample(&voices[v], at: t, smoothing: smoothing, sampleRate: sampleRate)
                }
                // A very low high-pass keeps the bed centred.
                let y = sum - dcIn + 0.9995 * dcOut
                dcIn = sum
                dcOut = y
                out[i] = Float(y * style.gain)
            }
            voices.removeAll { time + Double(blockEnd) * dt >= $0.start + $0.note.duration }
            n = blockEnd
        }
        time += Double(count) * dt
        return out
    }

    private mutating func plan(through end: Double) {
        guard end > plannedUntil else { return }
        queued += composer.notes(from: plannedUntil, to: end, mood: mood)
        plannedUntil = end
    }

    private mutating func startDue(by end: Double) {
        while let first = queued.first, first.time < end {
            queued.removeFirst()
            // With every voice busy the new note is skipped; cutting one short would click.
            guard voices.count < Self.maxVoices else { continue }
            voices.append(Voice(note: first, start: max(first.time, time)))
        }
    }

    private static func envelope(_ note: MusicNote, at local: Double) -> Double {
        switch note.voice {
        case .pad:
            return Envelope(attack: 2.2, decay: 0, sustain: 1, release: 2.5, curve: 1.5)
                .level(at: local, duration: note.duration)
        case .drone:
            return Envelope(attack: 3.5, decay: 0, sustain: 1, release: 3, curve: 1.5)
                .level(at: local, duration: note.duration)
        case .bass:
            return Envelope(attack: 0.012, decay: note.duration * 0.8, sustain: 0, release: 0.02, curve: 2)
                .level(at: local, duration: note.duration)
        case .bell:
            return Envelope(attack: 0.004, decay: note.duration, sustain: 0, release: 0.01, curve: 3)
                .level(at: local, duration: note.duration)
        }
    }

    /// One voice's sample at time `t`.
    private static func sample(_ voice: inout Voice, at t: Double, smoothing a: Double, sampleRate: Double) -> Double {
        let local = t - voice.start
        guard local >= 0 else { return 0 }
        let note = voice.note
        let env = envelope(note, at: local)
        let f = note.frequency
        let dt = 1 / sampleRate
        switch note.voice {
        case .pad:
            // Two slightly detuned triangles through a soft low-pass.
            voice.phase = (voice.phase + f * 1.003 * dt).truncatingRemainder(dividingBy: 1)
            voice.phase2 = (voice.phase2 + f * 0.997 * dt).truncatingRemainder(dividingBy: 1)
            let raw = (1 - 4 * abs(voice.phase - 0.5)) + (1 - 4 * abs(voice.phase2 - 0.5))
            voice.low1 += (raw - voice.low1) * a
            voice.low2 += (voice.low1 - voice.low2) * a
            return voice.low2 * 0.5 * env * note.velocity * 0.22
        case .drone:
            voice.phase = (voice.phase + f * dt).truncatingRemainder(dividingBy: 1)
            let swell = 0.75 + 0.25 * sin(2 * .pi * 0.11 * local)
            let raw = 1 - 4 * abs(voice.phase - 0.5)
            voice.low1 += (raw - voice.low1) * a
            return voice.low1 * env * swell * note.velocity * 0.32
        case .bass:
            voice.phase = (voice.phase + f * dt).truncatingRemainder(dividingBy: 1)
            return sin(2 * .pi * voice.phase) * env * note.velocity * 0.22
        case .bell:
            // A sine and a quieter inharmonic partial that fades sooner: a soft glassy bell.
            voice.phase = (voice.phase + f * dt).truncatingRemainder(dividingBy: 1)
            voice.phase2 = (voice.phase2 + f * 2.76 * dt).truncatingRemainder(dividingBy: 1)
            let partial = sin(2 * .pi * voice.phase2) * 0.3 * exp(-local * 3)
            return (sin(2 * .pi * voice.phase) + partial) * env * note.velocity * 0.1
        }
    }
}
