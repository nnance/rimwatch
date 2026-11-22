import Foundation
import GameCore

/// The Rift Caves' sounds and music, synthesised from the data below on the same synthesiser as
/// the other two modes, with a voice of their own: air and rock.
///
/// Families, so a sound says where it came from before you see it:
/// - the rider: air and canvas. A flap is a soft breath of filtered noise with a faint low
///   thump, short enough to sound six times a second for minutes without tiring; landing,
///   bumping, the dive and the wings opening are small noises of the rig; winning a clash is a
///   bright struck fifth; a stoop the same strike made heavier the farther the fall.
/// - opponents: rough sawtooth, noise and crackle only, the same rule as Redoubt's enemies: a
///   hum swelling in a tunnel mouth, a falling shriek for a dive, a clang for a Warden's armour,
///   a shell cracking and a growl for a pod hatching.
/// - colonists: pure sine and triangle tones up high, where the air and the rock never reach,
///   so the hatch warning and a pod being seized cut through everything.
/// - alerts (waves, the cavern shifting, the lamps, the Rift's breath, an extra life): figures
///   in E Lydian with a long cave echo, and the rock's own rumbles.
/// - menus: small glassy blips a fifth apart.
/// Loudness follows importance: flaps are the quietest sound in the game and the most frequent;
/// the biggest stoop, a clash lost, the lamps failing and the Rift's warning are the loudest.
extension RiftCaves {
    static let soundPrefix = "caves."

    /// How many pitches a flap comes in.
    public static let flapVariants = 3
    /// Rescue chimes for the 1st up to this many pods freed in a wave; later ones play the last.
    public static let freedNotes = 5
    /// Stoop strikes, from a short drop to the longest fall.
    public static let stoopStages = 4

    /// Every patch, by name without the theme prefix.
    static let patches: [String: SoundPatch] = {
        var all: [String: SoundPatch] = [:]
        for patch in riderSounds + opponentSounds + colonistSounds + alertSounds + interfaceSounds {
            all[String(patch.name.dropFirst(soundPrefix.count))] = patch
        }
        return all
    }()

    static func patch(_ short: String) -> SoundPatch {
        patches[short] ?? SoundPatch(name: soundPrefix + short)
    }

    /// The stoop stage (1 ... `stoopStages`) for a stoop's bonus points (2 a unit fallen, in
    /// 50s, up to 1,000): under 200 (a drop under 100 units), under 450, under 800, and the rest.
    public static func stoopStage(bonus: Int) -> Int {
        switch bonus {
        case ..<200: 1
        case ..<450: 2
        case ..<800: 3
        default: 4
        }
    }

    // Pitches (Hz), around E.
    private static let e2 = 82.41, b2 = 123.47, e3 = 164.81, b3 = 246.94
    private static let e4 = 329.63, b4 = 493.88
    private static let e5 = 659.26, b5 = 987.77
    private static let e6 = 1318.51

    /// The cave's echo: farther walls than the dome's, so a longer, softer answer.
    private static func cave(_ time: Double = 0.13, feedback: Double = 0.38, mix: Double = 0.28) -> Echo {
        Echo(time: time, feedback: feedback, mix: mix)
    }

    private static func semitones(_ n: Double) -> Double { pow(2, n / 12) }

    private static func make(_ name: String, _ family: SoundFamily, gain: Double, priority: Int,
                             cooldown: Double = 0.03, maxVoices: Int = 2, echo: Echo? = nil,
                             _ layers: [SoundLayer]) -> SoundPatch {
        SoundPatch(name: soundPrefix + name, family: family, gain: gain, priority: priority, cooldown: cooldown,
                   maxVoices: maxVoices, echo: echo, layers: layers)
    }

    // MARK: The rider

    /// The sound of the game: one breath of air pushed down by the wings. Band-passed noise
    /// that darkens as it goes, a faint low thump under it, 70 ms long. Three centre pitches,
    /// chosen by the director, never the same twice running. The quietest sound in the game,
    /// one voice for all of them, and the lowest priority, so it never takes a voice.
    static func flap(_ variant: Int) -> SoundPatch {
        let r = [1.0, 1.26, 0.8][variant % 3]
        return make("flap.\(variant + 1)", .player, gain: 0.13, priority: 0, cooldown: 0.06, maxVoices: 1, [
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.006, decay: 0.055, sustain: 0, release: 0.006, curve: 2.5),
                       filter: FilterSpec(.bandPass, cutoff: 1100 * r, to: 520 * r, resonance: 1.6), duration: 0.068),
            SoundLayer(.sine, 150 * r, to: 95 * r, envelope: .pluck(0.05, attack: 0.004), duration: 0.06, gain: 0.35),
        ])
    }

    static let riderSounds: [SoundPatch] = (0..<flapVariants).map(flap) + [
        // Taking off from a ledge: a scuff of boots, then a fuller beat than a flap in the air.
        make("flap.ledge", .player, gain: 0.2, priority: 1, cooldown: 0.12, maxVoices: 1, [
            SoundLayer(.noise, 0, envelope: .pluck(0.025, attack: 0.001), filter: FilterSpec(.highPass, cutoff: 2600),
                       duration: 0.03, gain: 0.5),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.01, decay: 0.09, sustain: 0, release: 0.01, curve: 2),
                       filter: FilterSpec(.bandPass, cutoff: 800, to: 380, resonance: 1.1), delay: 0.025, duration: 0.11),
            SoundLayer(.sine, 120, to: 70, envelope: .pluck(0.08, attack: 0.004), delay: 0.025, duration: 0.1, gain: 0.5),
        ]),
        // Feet on rock: a soft low thud and a grain of grit.
        make("land", .player, gain: 0.2, priority: 1, cooldown: 0.15, maxVoices: 1, [
            SoundLayer(.sine, 105, to: 55, envelope: .pluck(0.07, attack: 0.002), duration: 0.09),
            SoundLayer(.noise, 0, envelope: .pluck(0.03, attack: 0.001), filter: FilterSpec(.lowPass, cutoff: 1400),
                       duration: 0.05, gain: 0.45),
            SoundLayer(.triangle, 210, to: 160, envelope: .pluck(0.04), duration: 0.05, gain: 0.25),
        ]),
        // The frame's spar knocking on rock overhead: a dry hollow knock, higher than landing.
        make("bump", .player, gain: 0.24, priority: 2, cooldown: 0.15, maxVoices: 1, [
            SoundLayer(.triangle, 420, to: 250, envelope: .pluck(0.035, attack: 0.0008), duration: 0.045),
            SoundLayer(.noise, 0, envelope: .pluck(0.012, attack: 0.0005),
                       filter: FilterSpec(.bandPass, cutoff: 2400, resonance: 2), duration: 0.018, gain: 0.8),
        ]),
        // The dive: the wings snap shut and the wind rises past the rider.
        make("dive", .player, gain: 0.34, priority: 3, cooldown: 0.2, maxVoices: 1, [
            SoundLayer(.noise, 0, envelope: .pluck(0.02, attack: 0.0008), filter: FilterSpec(.highPass, cutoff: 1800),
                       duration: 0.025, gain: 0.7),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.22, decay: 0.05, sustain: 0.7, release: 0.1),
                       filter: FilterSpec(.bandPass, cutoff: 500, to: 2600, resonance: 1.6), delay: 0.02, duration: 0.4),
            SoundLayer(.square, 330, to: 660, envelope: Envelope(attack: 0.2, decay: 0.05, sustain: 0.5, release: 0.1),
                       filter: FilterSpec(.lowPass, cutoff: 900, to: 2200), delay: 0.02, duration: 0.38, gain: 0.18),
        ]),
        // The dive let go: the canvas cracks open and fills, a short lift over the 0.25 s the
        // wings take to open, ending as the rider can flap again.
        make("wings.open", .player, gain: 0.3, priority: 3, cooldown: 0.2, maxVoices: 1, [
            SoundLayer(.noise, 0, envelope: .pluck(0.03, attack: 0.001), filter: FilterSpec(.lowPass, cutoff: 1600),
                       duration: 0.04),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.05, decay: 0.15, sustain: 0.2, release: 0.04),
                       filter: FilterSpec(.bandPass, cutoff: 1800, to: 700, resonance: 1.2), delay: 0.02, duration: 0.23,
                       gain: 0.7),
            SoundLayer(.triangle, b4, to: e5, envelope: Envelope(attack: 0.06, decay: 0.12, sustain: 0.3, release: 0.05),
                       delay: 0.03, duration: 0.22, gain: 0.35),
        ]),
        // Into a vent's rising air: a soft lifting hiss with a shimmer in it.
        make("vent", .player, gain: 0.1, priority: 1, cooldown: 1, maxVoices: 1, [
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.3, decay: 0.1, sustain: 0.5, release: 0.25),
                       filter: FilterSpec(.bandPass, cutoff: 1300, to: 3400, resonance: 1.3), duration: 0.7),
            SoundLayer(.sine, e5, to: b5, vibrato: (5, 0.3),
                       envelope: Envelope(attack: 0.3, decay: 0.1, sustain: 0.5, release: 0.25), duration: 0.7, gain: 0.25),
        ]),
        // Met level: a springy twang as both are thrown apart. Nobody hurt.
        make("bounce", .player, gain: 0.32, priority: 4, cooldown: 0.1, maxVoices: 1, [
            SoundLayer(.noise, 0, envelope: .pluck(0.01, attack: 0.0005), filter: FilterSpec(.bandPass, cutoff: 1800),
                       duration: 0.015, gain: 0.5),
            SoundLayer(.triangle, 280, to: 420, vibrato: (22, 1.2),
                       envelope: Envelope(attack: 0.003, decay: 0.18, sustain: 0, release: 0.02, curve: 2),
                       duration: 0.2),
            SoundLayer(.sine, 560, to: 840, vibrato: (22, 1.2), envelope: .pluck(0.12), duration: 0.14, gain: 0.3),
        ]),
        // A clash won from above: a crack and a bright struck fifth, rising.
        make("clash.won", .player, gain: 0.38, priority: 7, cooldown: 0.08, maxVoices: 2, [
            SoundLayer(.noise, 0, envelope: .pluck(0.02, attack: 0.0005),
                       filter: FilterSpec(.bandPass, cutoff: 3200, resonance: 0.8), duration: 0.03, gain: 0.8),
            SoundLayer(.square, b4, steps: [0, 5], stepTime: 0.07, tremolo: (1 / 0.07, 0.9),
                       envelope: Envelope(attack: 0.002, decay: 0.16, sustain: 0.15, release: 0.05),
                       filter: FilterSpec(.lowPass, cutoff: 3500, to: 1800), duration: 0.24),
            SoundLayer(.triangle, e6, envelope: .pluck(0.1), delay: 0.06, duration: 0.12, gain: 0.4),
        ]),
        // Lost a clash: the rig is struck from above. A hard crunch and a dissonant stab.
        make("clash.lost", .player, gain: 0.9, priority: 10, cooldown: 0.3, maxVoices: 1, [
            SoundLayer(.noise, 0, envelope: .pluck(0.03, attack: 0.0005),
                       filter: FilterSpec(.highPass, cutoff: 3000), duration: 0.04, gain: 0.9),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.002, decay: 0.22, sustain: 0, release: 0.03, curve: 2),
                       filter: FilterSpec(.bandPass, cutoff: 1400, to: 300, resonance: 0.7), duration: 0.26, gain: 1.6),
            SoundLayer(.square, e4, to: 220, envelope: Envelope(attack: 0.002, decay: 0.25, sustain: 0.1, release: 0.05),
                       filter: FilterSpec(.lowPass, cutoff: 2600, to: 700), duration: 0.32),
            SoundLayer(.square, 349.23, to: 233, envelope: Envelope(attack: 0.002, decay: 0.25, sustain: 0.1, release: 0.05),
                       filter: FilterSpec(.lowPass, cutoff: 2600, to: 700), duration: 0.32, gain: 0.8),
            SoundLayer(.sine, 90, to: 40, envelope: .pluck(0.2), duration: 0.24, gain: 0.6),
        ]),
        // A life lost: the rig tumbles down into the dark, its tone fluttering and falling away.
        make("rider.lost", .player, gain: 0.82, priority: 10, cooldown: 0.5, maxVoices: 1, echo: cave(0.16, feedback: 0.35, mix: 0.3), [
            SoundLayer(.square, e5, to: e2, tremolo: (8, 1.0),
                       envelope: Envelope(attack: 0.004, decay: 1.0, sustain: 0, release: 0.05, curve: 1.5),
                       filter: FilterSpec(.lowPass, cutoff: 2000, to: 300), duration: 1.05),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.05, decay: 0.9, sustain: 0, release: 0.05),
                       filter: FilterSpec(.bandPass, cutoff: 1600, to: 300, resonance: 1.2), duration: 1.0, gain: 0.15),
            SoundLayer(.sine, b2, to: 40, envelope: Envelope(attack: 0.01, decay: 0.8, sustain: 0, release: 0.05),
                       duration: 0.85, gain: 0.35),
        ]),
        // Back on a ledge: air gathering and a rising E major arpeggio.
        make("rider.return", .player, gain: 0.44, priority: 5, cooldown: 0.5, maxVoices: 1, [
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.3, decay: 0.1, sustain: 0.3, release: 0.15),
                       filter: FilterSpec(.bandPass, cutoff: 900, to: 3000, resonance: 1.2), duration: 0.55, gain: 0.35),
            SoundLayer(.triangle, e5, steps: [0, 4, 7, 11, 12], stepTime: 0.07,
                       envelope: Envelope(attack: 0.004, decay: 0.06, sustain: 0.5, release: 0.12), delay: 0.25,
                       duration: 0.45),
        ]),
    ] + (1...stoopStages).map(stoop)

    /// A stoop: the strike of a clash won, made heavier by the fall. A crack, a low boom that
    /// grows longer and deeper, and a chord struck down from high, one note longer for each
    /// stage, the biggest ringing on in the cave.
    static func stoop(_ stage: Int) -> SoundPatch {
        let s = min(max(stage, 1), stoopStages)
        let ladder: [Double] = [24, 19, 16, 12, 7, 0]
        var layers: [SoundLayer] = [
            SoundLayer(.noise, 0, envelope: .pluck(0.03 + 0.01 * Double(s), attack: 0.0005),
                       filter: FilterSpec(.bandPass, cutoff: 2600, resonance: 0.6), duration: 0.05 + 0.01 * Double(s),
                       gain: 1.9 - 0.2 * Double(s)),
            SoundLayer(.sine, 140, to: 50 - 4 * Double(s), envelope: .pluck(0.12 + 0.08 * Double(s)),
                       duration: 0.16 + 0.09 * Double(s), gain: 0.5 + 0.12 * Double(s)),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.003, decay: 0.15 + 0.1 * Double(s), sustain: 0, release: 0.03),
                       filter: FilterSpec(.lowPass, cutoff: 3000, to: 400), duration: 0.2 + 0.1 * Double(s),
                       gain: 1.5 + 0.2 * Double(s)),
        ]
        for (index, note) in ladder.prefix(s + 2).enumerated() {
            layers.append(SoundLayer(.square, b4 * semitones(note), to: b4 * semitones(note - 2),
                                     envelope: .pluck(0.22 + 0.05 * Double(s)),
                                     filter: FilterSpec(.lowPass, cutoff: 3200), delay: 0.03 + 0.04 * Double(index),
                                     duration: 0.26 + 0.05 * Double(s), gain: 0.55))
        }
        return make("stoop.\(s)", .player, gain: 0.5 + 0.12 * Double(s), priority: 7 + min(s, 3), cooldown: 0.1,
                    maxVoices: 1, echo: s >= 3 ? cave(0.12, feedback: 0.3 + 0.04 * Double(s - 3), mix: 0.28) : nil, layers)
    }

    // MARK: Opponents

    static let opponentSounds: [SoundPatch] = [
        // A glow in a tunnel mouth: a hum swelling out of the rock, opening up as it comes.
        make("arrival", .enemy, gain: 0.24, priority: 3, cooldown: 0.4, maxVoices: 1, [
            SoundLayer(.saw, b2, to: e3, detune: 30, envelope: Envelope(attack: 0.6, decay: 0.1, sustain: 0.6, release: 0.18),
                       filter: FilterSpec(.bandPass, cutoff: 300, to: 1600, resonance: 3), duration: 0.95),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.6, decay: 0.1, sustain: 0.4, release: 0.18),
                       filter: FilterSpec(.bandPass, cutoff: 600, to: 2200, resonance: 1.5), duration: 0.95, gain: 0.25),
        ]),
        // An opponent dives: a falling shriek through the air.
        make("foe.dive", .enemy, gain: 0.4, priority: 6, cooldown: 0.3, maxVoices: 1, [
            SoundLayer(.saw, 1500, to: 400, detune: 25, envelope: Envelope(attack: 0.02, decay: 0.3, sustain: 0.2, release: 0.05),
                       filter: FilterSpec(.bandPass, cutoff: 1800, to: 500, resonance: 3), duration: 0.38),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.05, decay: 0.3, sustain: 0, release: 0.04),
                       filter: FilterSpec(.bandPass, cutoff: 2600, to: 700, resonance: 1.2), duration: 0.38, gain: 0.4),
        ]),
        // A Warden takes its first blow: the armour plate clangs and it rattles away.
        make("warden.hit", .enemy, gain: 0.46, priority: 6, cooldown: 0.1, maxVoices: 1, [
            SoundLayer(.noise, 0, envelope: .pluck(0.12, attack: 0.0005),
                       filter: FilterSpec(.bandPass, cutoff: 1250, resonance: 6), duration: 0.16, gain: 1.4),
            SoundLayer(.saw, 185, envelope: .pluck(0.22), filter: FilterSpec(.bandPass, cutoff: 900, resonance: 5),
                       duration: 0.26, gain: 0.7),
            SoundLayer(.crackle, 300, to: 60, envelope: Envelope(attack: 0.01, decay: 0.2, sustain: 0, release: 0.02),
                       filter: FilterSpec(.bandPass, cutoff: 2400), delay: 0.04, duration: 0.24, gain: 1.0),
        ]),
        // A Gleaner struck down: its claw snaps and it rattles apart.
        make("gleaner.down", .enemy, gain: 0.5, priority: 6, cooldown: 0.1, maxVoices: 1, [
            SoundLayer(.noise, 0, envelope: .pluck(0.012, attack: 0.0005), filter: FilterSpec(.highPass, cutoff: 2000),
                       duration: 0.02, gain: 0.8),
            SoundLayer(.noise, 0, envelope: .pluck(0.012, attack: 0.0005), filter: FilterSpec(.highPass, cutoff: 1700),
                       delay: 0.045, duration: 0.02, gain: 0.7),
            SoundLayer(.saw, 900, to: 200, detune: 30, envelope: Envelope(attack: 0.003, decay: 0.25, sustain: 0, release: 0.02),
                       filter: FilterSpec(.bandPass, cutoff: 1800, to: 600, resonance: 3), duration: 0.28, gain: 0.8),
            SoundLayer(.crackle, 420, to: 50, envelope: Envelope(attack: 0.01, decay: 0.3, sustain: 0, release: 0.02),
                       filter: FilterSpec(.bandPass, cutoff: 2600, to: 1000), delay: 0.02, duration: 0.34, gain: 1.4),
        ]),
        // An opponent lost to the Rift or the gas: a thin whine falling away, far off.
        make("foe.fell", .enemy, gain: 0.2, priority: 2, cooldown: 0.2, maxVoices: 1, [
            SoundLayer(.saw, 700, to: 110, detune: 20, envelope: Envelope(attack: 0.01, decay: 0.5, sustain: 0, release: 0.04),
                       filter: FilterSpec(.lowPass, cutoff: 1600, to: 300, resonance: 1.5), duration: 0.55),
        ]),
        // A pod hatches: the shell cracks and a growl rises out of it.
        make("hatch", .enemy, gain: 0.6, priority: 7, cooldown: 0.2, maxVoices: 1, [
            SoundLayer(.noise, 0, envelope: .pluck(0.025, attack: 0.0005), filter: FilterSpec(.bandPass, cutoff: 2800),
                       duration: 0.035, gain: 1.0),
            SoundLayer(.crackle, 180, to: 30, envelope: Envelope(attack: 0.005, decay: 0.25, sustain: 0, release: 0.02),
                       filter: FilterSpec(.highPass, cutoff: 1500), duration: 0.28, gain: 1.4),
            SoundLayer(.saw, 92, to: 185, vibrato: (7, 0.8), noise: 0.2, detune: 45,
                       envelope: Envelope(attack: 0.15, decay: 0.3, sustain: 0.5, release: 0.2),
                       filter: FilterSpec(.bandPass, cutoff: 400, to: 1700, resonance: 3.5), delay: 0.08, duration: 0.7),
        ]),
        // A Gleaner lifts a pod and makes for a tunnel mouth: a buzzing, wobbling climb.
        make("pod.carried", .enemy, gain: 0.44, priority: 7, cooldown: 0.4, maxVoices: 1, [
            SoundLayer(.saw, 220, to: 440, tremolo: (14, 0.7), detune: 35,
                       envelope: Envelope(attack: 0.05, decay: 0.2, sustain: 0.7, release: 0.15),
                       filter: FilterSpec(.bandPass, cutoff: 900, to: 2400, resonance: 2.5), duration: 0.6),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.05, decay: 0.2, sustain: 0.4, release: 0.15),
                       filter: FilterSpec(.highPass, cutoff: 3000), duration: 0.6, gain: 0.25),
        ]),
        // A Sower lets a mine go on its tether: a soft pluck and the line creaking taut.
        make("mine.laid", .enemy, gain: 0.2, priority: 2, cooldown: 0.25, maxVoices: 1, [
            SoundLayer(.saw, 1400, to: 1100, detune: 15, envelope: .pluck(0.05),
                       filter: FilterSpec(.bandPass, cutoff: 1800, resonance: 4), duration: 0.06),
            SoundLayer(.crackle, 120, to: 40, envelope: Envelope(attack: 0.02, decay: 0.12, sustain: 0, release: 0.02),
                       filter: FilterSpec(.bandPass, cutoff: 900), delay: 0.04, duration: 0.15, gain: 1.3),
        ]),
        // Mines going (their Sower struck down, or timed out): a fizzing pop.
        make("mine.clear", .enemy, gain: 0.3, priority: 4, cooldown: 0.15, maxVoices: 1, [
            SoundLayer(.noise, 0, envelope: .pluck(0.03, attack: 0.0005), filter: FilterSpec(.bandPass, cutoff: 1600),
                       duration: 0.04, gain: 0.8),
            SoundLayer(.crackle, 600, to: 80, envelope: Envelope(attack: 0.005, decay: 0.25, sustain: 0, release: 0.02),
                       filter: FilterSpec(.highPass, cutoff: 2500, to: 4500), duration: 0.28, gain: 1.4),
        ]),
    ]

    // MARK: Colonists

    /// A colonist freed: a chime that climbs an E major pentatonic with each one freed in the
    /// wave, so a run of rescues is heard rising (its score rises too). A little louder and
    /// longer each step.
    static func freed(_ order: Int) -> SoundPatch {
        let n = min(max(order, 1), freedNotes)
        let degree = [0.0, 2, 4, 7, 9][n - 1]
        let f = e5 * semitones(degree)
        return make("pod.freed.\(n)", .colonist, gain: 0.38 + 0.025 * Double(n), priority: 8, cooldown: 0.12, maxVoices: 1, [
            SoundLayer(.sine, f, steps: [0, 7, 12], stepTime: 0.06,
                       envelope: Envelope(attack: 0.003, decay: 0.08, sustain: 0.5, release: 0.08),
                       duration: 0.2 + 0.02 * Double(n)),
            SoundLayer(.triangle, f / 2, envelope: .pluck(0.18), duration: 0.2, gain: 0.35),
            SoundLayer(.sine, 2 * f * semitones(12), envelope: .pluck(0.16), delay: 0.12, duration: 0.18, gain: 0.3),
        ])
    }

    static let colonistSounds: [SoundPatch] = (1...freedNotes).map(freed) + [
        // A pod knocked loose: a little two-note fall, "oh-oh".
        make("pod.drop", .colonist, gain: 0.32, priority: 4, cooldown: 0.1, maxVoices: 1, [
            SoundLayer(.sine, e6, steps: [0, -5], stepTime: 0.08,
                       envelope: Envelope(attack: 0.004, decay: 0.06, sustain: 0.6, release: 0.05), duration: 0.18),
            SoundLayer(.triangle, e5, steps: [0, -5], stepTime: 0.08, envelope: .pluck(0.16), duration: 0.18, gain: 0.3),
        ]),
        // A pod comes to rest on a ledge: a soft bump and a small hopeful chirp.
        make("pod.land", .colonist, gain: 0.24, priority: 3, cooldown: 0.1, maxVoices: 1, [
            SoundLayer(.triangle, 260, to: 180, envelope: .pluck(0.05, attack: 0.001), duration: 0.06),
            SoundLayer(.sine, b5, to: e6, envelope: .pluck(0.07), delay: 0.05, duration: 0.09, gain: 0.5),
        ]),
        // Caught in the air: a quick sparkling climb an octave above the rescue chime.
        make("pod.caught", .colonist, gain: 0.8, priority: 8, cooldown: 0.15, maxVoices: 1, [
            SoundLayer(.sine, e6, steps: [0, 4, 7, 12, 16], stepTime: 0.05, tremolo: (1 / 0.05, 0.85),
                       envelope: Envelope(attack: 0.003, decay: 0.1, sustain: 0.55, release: 0.12), duration: 0.34),
            SoundLayer(.sine, e5, steps: [0, 4, 7, 12, 16], stepTime: 0.05,
                       envelope: Envelope(attack: 0.003, decay: 0.1, sustain: 0.55, release: 0.12), duration: 0.34, gain: 0.3),
            SoundLayer(.sine, 2 * e6, tremolo: (1 / 0.05, 0.85), envelope: .pluck(0.18), delay: 0.25, duration: 0.2,
                       gain: 0.4),
        ]),
        // A Gleaner has hold of a pod: a fast, shrill trill, the highest sound in the game.
        make("pod.seized", .colonist, gain: 0.74, priority: 9, cooldown: 0.3, maxVoices: 1, [
            SoundLayer(.sine, 2349, steps: [0, -3, 0, -3, 0, -3, 0], stepTime: 0.05, vibrato: (12, 0.2),
                       tremolo: (1 / 0.05, 0.6),
                       envelope: Envelope(attack: 0.003, decay: 0.04, sustain: 0.85, release: 0.05), duration: 0.36),
            SoundLayer(.triangle, 1175, steps: [0, -3, 0, -3, 0, -3, 0], stepTime: 0.05, tremolo: (1 / 0.05, 0.6),
                       envelope: Envelope(attack: 0.003, decay: 0.04, sustain: 0.85, release: 0.05), duration: 0.36,
                       gain: 0.4),
        ]),
        // A pod will hatch soon: three slow pings, each louder and lower, falling a fifth like a
        // clock running down.
        make("hatch.warning", .colonist, gain: 0.72, priority: 10, cooldown: 0.4, maxVoices: 1, [
            SoundLayer(.triangle, 988, steps: [0, -3, -7], stepTime: 0.2, tremolo: (1 / 0.2, 0.95),
                       envelope: Envelope(attack: 0.4, decay: 0.0, sustain: 1, release: 0.08, curve: 1), duration: 0.6),
            SoundLayer(.sine, 1976, steps: [0, -3, -7], stepTime: 0.2, tremolo: (1 / 0.2, 0.95),
                       envelope: Envelope(attack: 0.4, decay: 0.0, sustain: 1, release: 0.08, curve: 1), duration: 0.6, gain: 0.35),
        ]),
        // A colonist lost: three notes sinking a sixth, wavering, and a low sigh under them.
        make("pod.lost", .colonist, gain: 0.66, priority: 10, cooldown: 0.25, maxVoices: 1, echo: cave(0.14, feedback: 0.35, mix: 0.3), [
            SoundLayer(.triangle, b5, steps: [0, -4, -9], stepTime: 0.2, vibrato: (6, 0.4),
                       envelope: Envelope(attack: 0.01, decay: 0.25, sustain: 0.7, release: 0.2), duration: 0.72),
            SoundLayer(.sine, b4, steps: [0, -4, -9], stepTime: 0.2,
                       envelope: Envelope(attack: 0.01, decay: 0.25, sustain: 0.6, release: 0.2), duration: 0.72, gain: 0.5),
            SoundLayer(.sine, e3, to: 90, envelope: Envelope(attack: 0.05, decay: 0.5, sustain: 0.3, release: 0.15),
                       duration: 0.7, gain: 0.35),
        ]),
    ]

    // MARK: Alerts

    static let alertSounds: [SoundPatch] = [
        // A wave begins: a call of open fifths climbing in E, answered by the cave.
        make("wave.start", .alert, gain: 0.54, priority: 8, cooldown: 1, maxVoices: 1, echo: cave(0.12, feedback: 0.25), [
            SoundLayer(.square, e4, steps: [0, 7, 12, 14], stepTime: 0.13, tremolo: (1 / 0.13, 0.8),
                       envelope: Envelope(attack: 0.01, decay: 0.1, sustain: 0.75, release: 0.15),
                       filter: FilterSpec(.lowPass, cutoff: 1500), duration: 0.6),
            SoundLayer(.triangle, b3, steps: [0, 5, 7, 7], stepTime: 0.13,
                       envelope: Envelope(attack: 0.01, decay: 0.1, sustain: 0.75, release: 0.15), duration: 0.6, gain: 0.5),
            SoundLayer(.saw, e2, detune: 12, envelope: Envelope(attack: 0.25, decay: 0.2, sustain: 0.5, release: 0.2),
                       filter: FilterSpec(.lowPass, cutoff: 250, to: 1100, resonance: 1.2), duration: 0.7, gain: 0.4),
        ]),
        // The wave is won: a warm E major chord with the Lydian sharp fourth floating over it.
        make("wave.clear", .alert, gain: 0.6, priority: 8, cooldown: 1, maxVoices: 1, echo: cave(0.15, feedback: 0.4, mix: 0.32), [
            SoundLayer(.triangle, e4, envelope: Envelope(attack: 0.35, decay: 0.1, sustain: 0.8, release: 0.5),
                       duration: 1.3, gain: 0.5),
            SoundLayer(.triangle, e4 * semitones(4), envelope: Envelope(attack: 0.35, decay: 0.1, sustain: 0.8, release: 0.5),
                       duration: 1.3, gain: 0.4),
            SoundLayer(.square, b4, steps: [0, 5, 7, 11, 12], stepTime: 0.1,
                       envelope: Envelope(attack: 0.2, decay: 0.1, sustain: 0.7, release: 0.3),
                       filter: FilterSpec(.lowPass, cutoff: 1500), duration: 0.85, gain: 0.45),
        ]),
        // The cavern shifts: after the wave's sting, the rock groans, grinds and pours down.
        // Starts half a second late, so it follows the wave-clear sting instead of masking it.
        make("cavern.shift", .alert, gain: 0.78, priority: 8, cooldown: 1, maxVoices: 1, echo: cave(0.18, feedback: 0.3, mix: 0.25), [
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.4, decay: 0.6, sustain: 0.5, release: 0.4),
                       filter: FilterSpec(.lowPass, cutoff: 220, to: 600, resonance: 1.3), delay: 0.5, duration: 1.8, gain: 1.6),
            SoundLayer(.saw, 46, to: 38, detune: 30, envelope: Envelope(attack: 0.4, decay: 0.5, sustain: 0.6, release: 0.4),
                       filter: FilterSpec(.lowPass, cutoff: 300), delay: 0.5, duration: 1.8, gain: 0.5),
            SoundLayer(.crackle, 30, to: 90, envelope: Envelope(attack: 0.5, decay: 0.3, sustain: 0.7, release: 0.3),
                       filter: FilterSpec(.bandPass, cutoff: 1400, to: 800), delay: 0.7, duration: 1.5, gain: 2.0),
            SoundLayer(.square, 110, to: 104, tremolo: (6, 0.6), envelope: Envelope(attack: 0.6, decay: 0.3, sustain: 0.5, release: 0.4),
                       filter: FilterSpec(.lowPass, cutoff: 600), delay: 0.5, duration: 1.6, gain: 0.3),
        ]),
        // The new ledges are in place: one heavy thud and the last grit settling.
        make("cavern.settle", .alert, gain: 0.55, priority: 6, cooldown: 1, maxVoices: 1, echo: cave(0.16, feedback: 0.3, mix: 0.25), [
            SoundLayer(.sine, 95, to: 38, envelope: .pluck(0.3, attack: 0.002), duration: 0.34),
            SoundLayer(.noise, 0, envelope: .pluck(0.08, attack: 0.001), filter: FilterSpec(.lowPass, cutoff: 1800),
                       duration: 0.1, gain: 0.9),
            SoundLayer(.crackle, 70, to: 15, envelope: Envelope(attack: 0.02, decay: 0.4, sustain: 0, release: 0.03),
                       filter: FilterSpec(.bandPass, cutoff: 2200), delay: 0.06, duration: 0.45, gain: 1.6),
        ]),
        // Every colonist of the wave lost: a low two-note swell of dread, a draught through the
        // galleries. The dark comes next wave.
        make("colonists.gone", .alert, gain: 0.62, priority: 9, cooldown: 1, maxVoices: 1, echo: cave(0.2, feedback: 0.4, mix: 0.32), [
            SoundLayer(.triangle, e3, steps: [0, 1], stepTime: 0.55,
                       envelope: Envelope(attack: 0.9, decay: 0.1, sustain: 0.8, release: 0.4), duration: 1.2),
            SoundLayer(.sine, e5, steps: [0, 1], stepTime: 0.55,
                       envelope: Envelope(attack: 0.9, decay: 0.1, sustain: 0.8, release: 0.4), duration: 1.2, gain: 0.45),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.4, decay: 0.4, sustain: 0.3, release: 0.4),
                       filter: FilterSpec(.bandPass, cutoff: 500, to: 900, resonance: 1.5), duration: 1.2, gain: 2.0),
        ]),
        // The lamps fail: their hum gutters and sputters out, a glass tink, and the dark.
        make("lamps.fail", .alert, gain: 0.9, priority: 10, cooldown: 1, maxVoices: 1, echo: cave(0.2, feedback: 0.35, mix: 0.25), [
            SoundLayer(.square, 440, to: 110, tremolo: (17, 0.95),
                       envelope: Envelope(attack: 0.005, decay: 1.2, sustain: 0.1, release: 0.3),
                       filter: FilterSpec(.lowPass, cutoff: 2400, to: 200), duration: 1.5),
            SoundLayer(.crackle, 400, to: 20, envelope: Envelope(attack: 0.003, decay: 0.8, sustain: 0, release: 0.05),
                       filter: FilterSpec(.highPass, cutoff: 1800), duration: 0.9, gain: 1.3),
            SoundLayer(.sine, 3520, envelope: .pluck(0.15), delay: 0.35, duration: 0.18, gain: 0.3),
            SoundLayer(.sine, e2, envelope: Envelope(attack: 0.3, decay: 0.6, sustain: 0.3, release: 0.4),
                       delay: 0.3, duration: 1.3, gain: 0.45),
        ]),
        // A colonist freed in the dark brings the lamps back: a hum flickering up into a
        // bright rising chord.
        make("lamps.restore", .alert, gain: 0.72, priority: 9, cooldown: 1, maxVoices: 1, echo: cave(0.13, feedback: 0.35), [
            SoundLayer(.square, 55, to: 220, tremolo: (9, 0.6),
                       envelope: Envelope(attack: 0.6, decay: 0.2, sustain: 0.6, release: 0.3),
                       filter: FilterSpec(.lowPass, cutoff: 300, to: 2400, resonance: 1.3), duration: 1.2, gain: 0.6),
            SoundLayer(.triangle, e5, steps: [0, 4, 6, 11, 12], stepTime: 0.1,
                       envelope: Envelope(attack: 0.004, decay: 0.1, sustain: 0.7, release: 0.2), delay: 0.55, duration: 0.75),
        ]),
        // The Rift is about to breathe: a deep breath drawn in under a rising, pulsing alarm.
        // The loudest warning in the game; it comes 3 s before the gas, so it says "climb".
        make("rift.warning", .alert, gain: 0.9, priority: 10, cooldown: 1, maxVoices: 1, echo: cave(0.15, feedback: 0.3, mix: 0.22), [
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.7, decay: 0.2, sustain: 0.6, release: 0.3),
                       filter: FilterSpec(.bandPass, cutoff: 200, to: 900, resonance: 2), duration: 1.3, gain: 3.5),
            SoundLayer(.saw, e2, to: e3, detune: 25, envelope: Envelope(attack: 0.6, decay: 0.2, sustain: 0.6, release: 0.3),
                       filter: FilterSpec(.lowPass, cutoff: 300, to: 1500, resonance: 2), duration: 1.3, gain: 0.5),
            SoundLayer(.square, e5, steps: [0, 0, 1, 1, 2, 2], stepTime: 0.18, tremolo: (1 / 0.18, 0.9),
                       envelope: Envelope(attack: 0.005, decay: 0.05, sustain: 0.85, release: 0.15),
                       filter: FilterSpec(.lowPass, cutoff: 2500), delay: 0.3, duration: 1.08, gain: 0.55),
        ]),
        // The gas rises: a long hiss swelling up out of the Rift, lasting its 1 s climb.
        make("rift.rise", .alert, gain: 0.5, priority: 8, cooldown: 1, maxVoices: 1, [
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.5, decay: 0.2, sustain: 0.7, release: 0.3),
                       filter: FilterSpec(.bandPass, cutoff: 350, to: 2400, resonance: 1.2), duration: 1.1),
            SoundLayer(.saw, 70, to: 110, noise: 0.3, detune: 40,
                       envelope: Envelope(attack: 0.5, decay: 0.2, sustain: 0.6, release: 0.3),
                       filter: FilterSpec(.lowPass, cutoff: 500), duration: 1.1, gain: 0.3),
        ]),
        // The gas sinks back: the hiss falling away, quietly.
        make("rift.settle", .alert, gain: 0.24, priority: 3, cooldown: 1, maxVoices: 1, [
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.05, decay: 0.7, sustain: 0, release: 0.05, curve: 1.5),
                       filter: FilterSpec(.bandPass, cutoff: 2000, to: 300, resonance: 1), duration: 0.8),
        ]),
        // An extra life: a quick climb up the Lydian scale and a high ring.
        make("life.extra", .alert, gain: 0.74, priority: 9, cooldown: 1, maxVoices: 1, echo: cave(0.1, feedback: 0.3, mix: 0.25), [
            SoundLayer(.square, e5, steps: [0, 2, 4, 6, 7, 11, 12, 16, 19], stepTime: 0.05, tremolo: (1 / 0.05, 0.85),
                       envelope: Envelope(attack: 0.003, decay: 0.05, sustain: 0.85, release: 0.1),
                       filter: FilterSpec(.lowPass, cutoff: 4500), duration: 0.55),
            SoundLayer(.triangle, e4, steps: [0, 2, 4, 6, 7, 11, 12, 16, 19], stepTime: 0.05,
                       envelope: Envelope(attack: 0.003, decay: 0.05, sustain: 0.85, release: 0.1), duration: 0.55, gain: 0.5),
            SoundLayer(.sine, 2 * e6, envelope: .pluck(0.4), delay: 0.45, duration: 0.42, gain: 0.35),
        ]),
        // Game over: a slow line falling through the scale to the low E, over a darkening drone.
        make("game.over", .alert, gain: 0.72, priority: 10, cooldown: 2, maxVoices: 1, echo: cave(0.22, feedback: 0.4, mix: 0.3), [
            SoundLayer(.triangle, b4, steps: [0, -1, -3, -5, -7, -12], stepTime: 0.28,
                       envelope: Envelope(attack: 0.01, decay: 0.3, sustain: 0.7, release: 0.5), duration: 1.9),
            SoundLayer(.square, b3, steps: [0, -1, -3, -5, -7, -12], stepTime: 0.28,
                       envelope: Envelope(attack: 0.01, decay: 0.3, sustain: 0.6, release: 0.5),
                       filter: FilterSpec(.lowPass, cutoff: 1600, to: 600), duration: 1.9, gain: 0.25),
            SoundLayer(.saw, e2, detune: 15, envelope: Envelope(attack: 0.4, decay: 0.5, sustain: 0.5, release: 0.6),
                       filter: FilterSpec(.lowPass, cutoff: 800, to: 220), duration: 2.0, gain: 0.35),
        ]),
    ]

    // MARK: Menus

    static let interfaceSounds: [SoundPatch] = [
        make("ui.move", .interface, gain: 0.18, priority: 1, cooldown: 0.03, maxVoices: 2, [
            SoundLayer(.sine, b5, envelope: .pluck(0.03), duration: 0.035),
            SoundLayer(.triangle, e5, envelope: .pluck(0.03), duration: 0.035, gain: 0.4),
        ]),
        make("ui.change", .interface, gain: 0.22, priority: 1, cooldown: 0.03, maxVoices: 2, [
            SoundLayer(.sine, e6, to: b5 * semitones(2), envelope: .pluck(0.08), duration: 0.09),
        ]),
        make("ui.activate", .interface, gain: 0.3, priority: 2, cooldown: 0.08, maxVoices: 1, [
            SoundLayer(.triangle, e5, steps: [0, 7, 14], stepTime: 0.045,
                       envelope: Envelope(attack: 0.003, decay: 0.05, sustain: 0.6, release: 0.05), duration: 0.15),
        ]),
        make("ui.back", .interface, gain: 0.25, priority: 2, cooldown: 0.08, maxVoices: 1, [
            SoundLayer(.triangle, b5, steps: [0, -7], stepTime: 0.06,
                       envelope: Envelope(attack: 0.003, decay: 0.08, sustain: 0.5, release: 0.05), duration: 0.14),
        ]),
    ]

    // MARK: Music

    /// E Lydian, the raised fourth giving the open air of the galleries, at 96 bpm (Ridgeline
    /// is A minor at 84, Redoubt G Phrygian at 104). A wave rides a lilting pulse in threes, a
    /// wingbeat (stroke, lift, glide), under chords that lean on the bright second and fall
    /// back; between waves the pulse drops away; with the lamps out it sinks to a low drone
    /// that never rests on the tonic, on the note a tritone above it and then the third.
    static let musicStyle = MusicStyle(
        root: 52, // E3
        scale: [0, 2, 4, 6, 7, 9, 11],
        tempo: 96,
        gain: 0.46,
        moods: [
            .title: MoodProfile(progression: [0, 1, 4, 1], chordSeconds: 9, bellChance: 0.09, padCutoff: 900),
            .calm: MoodProfile(progression: [0, 4, 1, 5], chordSeconds: 6.5, bellChance: 0.14, padCutoff: 1000),
            .tension: MoodProfile(progression: [0, 1, 0, 5, 0, 1, 6, 4], chordSeconds: 4, bellChance: 0.09,
                                  pulse: [1, 0, 1, 1, 0, 1], padCutoff: 1300),
            .blackout: MoodProfile(progression: [3, 2], chordSeconds: 10, bellChance: 0.05, bellOctave: 1,
                                   drone: true, padCutoff: 720),
        ]
    )

    // MARK: Which sound for which event

    /// The patch's short name for an event, or nil for silence. `variant` is the flap's pitch
    /// (chosen by `RiftwingSoundDirector`); other events carry what they need (a rescue's
    /// order, a stoop's bonus). Silent on purpose:
    /// - a clash won (its outcome speaks: the knock-off, the Warden's clang or the stoop);
    /// - the wings fully open (the opening sound ends at that moment);
    /// - an opponent arriving (its glow in the mouth was the warning) or withdrawing at a
    ///   wave's end (the wave-clear sting covers it);
    /// - mines cleared by the wave's end (the sting) or struck (the life lost covers it);
    /// - any event this theme does not know, such as one added later.
    static func soundName(for event: RiftwingEvent, variant: Int) -> String? {
        switch event {
        case .waveStarted: "wave.start"
        case .waveCleared: "wave.clear"
        case .cavernShifting: "cavern.shift"
        case .cavernShifted: "cavern.settle"
        case .allColonistsLost: "colonists.gone"
        case .lampsFailed: "lamps.fail"
        case .lampsRestored: "lamps.restore"
        case .riftWarning: "rift.warning"
        case .riftBreathed: "rift.rise"
        case .riftSettled: "rift.settle"
        case .flapped(_, let fromLedge): fromLedge ? "flap.ledge" : "flap.\(wrap(variant, flapVariants) + 1)"
        case .landed: "land"
        case .bumpedLedge: "bump"
        case .diveBegan: "dive"
        case .wingsOpening: "wings.open"
        case .ventEntered: "vent"
        case .clashBounced, .gleanerBumped: "bounce"
        case .clashLost: "clash.lost"
        case .riderLost: "rider.lost"
        case .riderRespawned: "rider.return"
        case .extraLife: "life.extra"
        case .arrivalTelegraphed: "arrival"
        case .opponentDived: "foe.dive"
        case .opponentHit: "warden.hit"
        case .opponentDestroyed(_, let role, _, _, let stoopBonus):
            if stoopBonus > 0 { "stoop.\(stoopStage(bonus: stoopBonus))" } else if role == .gleaner { "gleaner.down" } else { "clash.won" }
        case .opponentFell: "foe.fell"
        case .mineLaid: "mine.laid"
        case .mineCleared(_, _, let reason):
            switch reason {
            case .sowerDown, .expired: "mine.clear"
            case .waveEnded, .struck: nil
            }
        case .podDropped: "pod.drop"
        case .podLanded: "pod.land"
        case .podFreed(_, _, let order, _): "pod.freed.\(min(max(order, 1), freedNotes))"
        case .podCaught: "pod.caught"
        case .podSeized: "pod.seized"
        case .podCarried: "pod.carried"
        case .podLost: "pod.lost"
        case .hatchWarning: "hatch.warning"
        case .podHatched: "hatch"
        case .gameOver: "game.over"
        default: nil
        }
    }

    private static func wrap(_ value: Int, _ count: Int) -> Int {
        ((value % count) + count) % count
    }
}

// MARK: The theme's sound interface

extension RiftCaves {
    /// Names are stable identifiers, prefixed "caves." so they never collide with Ridgeline's
    /// "frontier." or Redoubt's "dome." patches in the one synthesiser.
    public func sound(for event: RiftwingEvent) -> SoundPatch? {
        sound(for: event, variant: 0)
    }

    public func sound(for event: RiftwingEvent, variant: Int) -> SoundPatch? {
        Self.soundName(for: event, variant: variant).map { Self.patch($0) }
    }

    public func menuSound(_ sound: MenuSound) -> SoundPatch? {
        Self.patch("ui.\(sound.rawValue)")
    }

    public var allSounds: [SoundPatch] {
        Self.patches.values.sorted { $0.name < $1.name }
    }

    public var music: MusicStyle? { Self.musicStyle }
}
