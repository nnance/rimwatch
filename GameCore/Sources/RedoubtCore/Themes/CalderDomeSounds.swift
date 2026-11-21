import Foundation
import GameCore

/// The Calder Dome's sounds and music, all synthesised from the data below on the same
/// synthesiser as Ridgeline's, in a related palette but with a voice of its own.
///
/// Families, so a sound says where it came from before you see it:
/// - the orb: soft triangle and sine tones pitched around D, rounder than Ridgeline's square
///   ship; its fire is a short soft "pip" in three pitches so ten a second never machine-guns;
/// - enemies: chitin and grit. Skitters crack and chitter (short band-passed noise and crackle),
///   the bigger kills add a tone of their own and weight in proportion to their worth; all
///   enemy sounds use sawtooth, noise and crackle only;
/// - colonists: pure sine and triangle tones up high, where nothing in the crowd sits, so a
///   seized colonist cuts through ninety dying Skitters;
/// - alerts (waves, the power cut, extra life, the airlock): chords and figures in D with a
///   short, close echo: the dome's walls answering;
/// - menus: small sine and triangle blips a fourth apart.
/// Loudness follows importance: the stream of fire and the Skitter crowd are the quietest and
/// shortest; the Shockwave is the loudest sound in the game, then losing the orb and the power
/// failing.
extension CalderDome {
    static let soundPrefix = "dome."

    /// How many pitches the orb's fire and a Skitter's death come in.
    public static let fireVariants = 3
    public static let skitterVariants = 3
    /// Burrow hits come in this many stages, rising as it is shot closed.
    public static let burrowHitStages = 3
    /// Line positions with their own pickup note; longer lines repeat the top one.
    public static let joinNotes = 5
    /// Delivery fanfares for lines of 1 up to this many; longer lines play the last.
    public static let deliverySizes = 6

    /// Every patch, by name without the theme prefix.
    static let patches: [String: SoundPatch] = {
        var all: [String: SoundPatch] = [:]
        for patch in orbSounds + enemySounds + colonistSounds + alertSounds + interfaceSounds {
            all[String(patch.name.dropFirst(soundPrefix.count))] = patch
        }
        return all
    }()

    static func patch(_ short: String) -> SoundPatch {
        patches[short] ?? SoundPatch(name: soundPrefix + short)
    }

    // Pitches (Hz), around D.
    private static let d2 = 73.42, d3 = 146.83, a3 = 220.0
    private static let d4 = 293.66, a4 = 440.0
    private static let d5 = 587.33, a5 = 880.0
    private static let d6 = 1174.66

    /// The dome's own short echo, for the big sounds: close walls, not a canyon.
    private static func dome(_ time: Double = 0.07, feedback: Double = 0.4, mix: Double = 0.3) -> Echo {
        Echo(time: time, feedback: feedback, mix: mix)
    }

    private static func semitones(_ n: Double) -> Double { pow(2, n / 12) }

    private static func make(_ name: String, _ family: SoundFamily, gain: Double, priority: Int,
                             cooldown: Double = 0.03, maxVoices: Int = 2, echo: Echo? = nil,
                             _ layers: [SoundLayer]) -> SoundPatch {
        SoundPatch(name: soundPrefix + name, family: family, gain: gain, priority: priority, cooldown: cooldown,
                   maxVoices: maxVoices, echo: echo, layers: layers)
    }

    // MARK: The orb

    /// The sound of the game: ten a second for as long as the aim stick is held. A soft
    /// triangle "pip" that drops a fifth, with a breath of high noise at its front. Each copy
    /// ends (45 ms) long before the next starts (100 ms), so one voice carries the whole stream;
    /// the three pitches, a semitone apart and chosen at random, keep it from machine-gunning.
    static func fire(_ variant: Int) -> SoundPatch {
        let ratio = [1.0, semitones(1), semitones(-1)][variant % 3]
        return make("orb.fire.\(variant + 1)", .player, gain: 0.14, priority: 0, cooldown: 0.05, maxVoices: 1, [
            SoundLayer(.triangle, 1245 * ratio, to: 830 * ratio, envelope: .pluck(0.034, attack: 0.0012),
                       duration: 0.045),
            SoundLayer(.noise, 0, envelope: .pluck(0.008, attack: 0.0006),
                       filter: FilterSpec(.bandPass, cutoff: 5200 * ratio, resonance: 1.2), duration: 0.012, gain: 0.3),
        ])
    }

    static let orbSounds: [SoundPatch] = (0..<fireVariants).map(fire) + [
        // The biggest sound in the game: a hard crack, a wave front of noise that darkens as it
        // spreads across the floor, the orb's tone plunging, a ring of shimmering harmonics
        // racing outward and the dome ringing with it.
        make("shockwave", .player, gain: 0.95, priority: 10, cooldown: 0.3, maxVoices: 1, echo: dome(0.065, feedback: 0.45, mix: 0.35), [
            SoundLayer(.noise, 0, envelope: .pluck(0.025, attack: 0.0005),
                       filter: FilterSpec(.bandPass, cutoff: 2500, resonance: 0.6), duration: 0.03, gain: 0.7),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.004, decay: 0.7, sustain: 0, release: 0.05, curve: 1.3),
                       filter: FilterSpec(.lowPass, cutoff: 7000, to: 300, resonance: 1.0), duration: 0.8, gain: 0.8),
            SoundLayer(.triangle, d6, to: 98, envelope: Envelope(attack: 0.003, decay: 0.6, sustain: 0.35, release: 0.15),
                       duration: 0.75, gain: 0.8),
            SoundLayer(.square, d5, to: 2349, tremolo: (28, 0.45),
                       envelope: Envelope(attack: 0.01, decay: 0.5, sustain: 0.75, release: 0.2),
                       filter: FilterSpec(.lowPass, cutoff: 2000, to: 7000), delay: 0.02, duration: 0.8, gain: 1.2),
            SoundLayer(.sine, 82, to: 36, envelope: .pluck(0.35), duration: 0.38, gain: 0.35),
        ]),
        // Losing the orb: its ring cracks, its tone stutters and falls away, and the wreck
        // crackles on into the echo.
        make("orb.lost", .player, gain: 0.9, priority: 10, cooldown: 0.5, maxVoices: 1, echo: dome(0.15, feedback: 0.35, mix: 0.3), [
            SoundLayer(.noise, 0, envelope: .pluck(0.02, attack: 0.0005), filter: FilterSpec(.highPass, cutoff: 1500),
                       duration: 0.025, gain: 0.6),
            SoundLayer(.square, d6, to: d3, tremolo: (17, 0.9),
                       envelope: Envelope(attack: 0.003, decay: 1.0, sustain: 0, release: 0.05, curve: 1.6),
                       filter: FilterSpec(.lowPass, cutoff: 4000, to: 500), duration: 1.1, gain: 0.9),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.004, decay: 0.9, sustain: 0, release: 0.05),
                       filter: FilterSpec(.bandPass, cutoff: 1800, to: 500, resonance: 1.2), duration: 1.0, gain: 1.1),
            SoundLayer(.crackle, 260, to: 20, envelope: Envelope(attack: 0.02, decay: 1.1, sustain: 0, release: 0.05, curve: 1.4),
                       filter: FilterSpec(.lowPass, cutoff: 2600, to: 900), delay: 0.03, duration: 1.2, gain: 1.8),
            SoundLayer(.sine, 110, to: 35, envelope: Envelope(attack: 0.004, decay: 0.9, sustain: 0, release: 0.05),
                       duration: 1.0, gain: 0.4),
        ]),
        // Back at the centre: a hum swelling up two octaves, then a quick D major figure.
        make("orb.respawn", .player, gain: 0.46, priority: 5, cooldown: 0.5, maxVoices: 1, [
            SoundLayer(.sine, d3, to: d5, envelope: Envelope(attack: 0.35, decay: 0.1, sustain: 0.7, release: 0.2),
                       duration: 0.75),
            SoundLayer(.triangle, d5, steps: [0, 4, 7, 12], stepTime: 0.08,
                       envelope: Envelope(attack: 0.004, decay: 0.06, sustain: 0.5, release: 0.1),
                       delay: 0.45, duration: 0.42, gain: 0.5),
        ]),
        // A Shockwave charge earned: a quick charging whine that opens up, and a bright ping.
        make("charge.earned", .player, gain: 0.56, priority: 7, cooldown: 0.4, maxVoices: 1, echo: dome(0.06, feedback: 0.3), [
            SoundLayer(.square, d3, to: d6, envelope: Envelope(attack: 0.42, decay: 0.02, sustain: 0.8, release: 0.05),
                       filter: FilterSpec(.lowPass, cutoff: 1200, to: 5000), duration: 0.48, gain: 0.4),
            SoundLayer(.triangle, d6, steps: [0, 7, 12], stepTime: 0.06, envelope: .pluck(0.3), delay: 0.46,
                       duration: 0.32),
        ]),
    ]

    // MARK: Enemies

    /// A Skitter dies: the shell cracks, its legs chitter for a moment, a tiny squeak. Under a
    /// tenth of a second, quiet, its energy high and dry so a crowd of them reads as a rattle,
    /// not a roar. Three pitches, chosen at random.
    static func skitterPop(_ variant: Int) -> SoundPatch {
        let r = [1.0, 1.2, 0.85][variant % 3]
        return make("skitter.pop.\(variant + 1)", .enemy, gain: 0.28, priority: 1, cooldown: 0.03, maxVoices: 2, [
            SoundLayer(.noise, 0, envelope: .pluck(0.012, attack: 0.0005),
                       filter: FilterSpec(.bandPass, cutoff: 2600 * r, resonance: 1.4), duration: 0.018, gain: 1.3),
            SoundLayer(.crackle, 900, to: 200, envelope: Envelope(attack: 0.002, decay: 0.06, sustain: 0, release: 0.01),
                       filter: FilterSpec(.bandPass, cutoff: 3200 * r, to: 1600 * r, resonance: 1), delay: 0.006,
                       duration: 0.07, gain: 1.6),
            SoundLayer(.saw, 820 * r, to: 360 * r, detune: 18, envelope: .pluck(0.04),
                       filter: FilterSpec(.lowPass, cutoff: 3000), duration: 0.045, gain: 0.35),
        ])
    }

    /// A Burrow takes a hit: grit and a dull crunch, rising and brightening as it is shot closed.
    static func burrowHit(_ stage: Int) -> SoundPatch {
        let r = [1.0, 1.3, 1.7][min(max(stage, 0), 2)]
        return make("burrow.hit.\(stage + 1)", .enemy, gain: 0.24 + 0.03 * Double(stage), priority: 2, cooldown: 0.06,
                    maxVoices: 2, [
            SoundLayer(.noise, 0, envelope: .pluck(0.05, attack: 0.0006), filter: FilterSpec(.lowPass, cutoff: 800 * r),
                       duration: 0.06, gain: 1.2),
            SoundLayer(.crackle, 600, to: 200, envelope: .pluck(0.08),
                       filter: FilterSpec(.lowPass, cutoff: 1200 * r), duration: 0.1, gain: 1.4),
        ])
    }

    static let enemySounds: [SoundPatch] = (0..<skitterVariants).map(skitterPop) + (0..<burrowHitStages).map(burrowHit) + [
        // A group about to land: one soft rising rustle of legs for the whole group (or the whole
        // opening crowd), never one per marker, and at most one a second.
        make("arrival.swarm", .enemy, gain: 0.2, priority: 1, cooldown: 0.7, maxVoices: 1, [
            SoundLayer(.crackle, 60, to: 700, envelope: Envelope(attack: 0.45, decay: 0.05, sustain: 0.6, release: 0.12),
                       filter: FilterSpec(.bandPass, cutoff: 1400, to: 3200, resonance: 1.2), duration: 0.65, gain: 1.4),
            SoundLayer(.saw, 110, to: 165, noise: 0.4, detune: 35,
                       envelope: Envelope(attack: 0.4, decay: 0.05, sustain: 0.6, release: 0.12),
                       filter: FilterSpec(.lowPass, cutoff: 300, to: 900, resonance: 2), duration: 0.65, gain: 0.25),
        ]),
        // Something bigger than a Skitter on its way in: a low growl opening up.
        make("arrival.heavy", .enemy, gain: 0.3, priority: 2, cooldown: 1.0, maxVoices: 1, [
            SoundLayer(.saw, 110, to: 220, noise: 0.25, detune: 40,
                       envelope: Envelope(attack: 0.6, decay: 0.1, sustain: 0.7, release: 0.15),
                       filter: FilterSpec(.lowPass, cutoff: 400, to: 2400, resonance: 3.5), duration: 0.95),
        ]),
        // A Burrow pours out a Skitter: a small wet plop.
        make("burrow.spawn", .enemy, gain: 0.15, priority: 1, cooldown: 0.15, maxVoices: 1, [
            SoundLayer(.saw, 210, to: 90, noise: 0.3, detune: 20, envelope: .pluck(0.11),
                       filter: FilterSpec(.lowPass, cutoff: 900, to: 300, resonance: 4), duration: 0.13),
            SoundLayer(.crackle, 300, to: 80, envelope: .pluck(0.1), filter: FilterSpec(.bandPass, cutoff: 1200),
                       duration: 0.11, gain: 0.8),
        ]),
        // The Spitter's tell, exactly as long as its 0.4 s wind-up: a ratchet clicking up three
        // steps over a sizzling charge, cut off at the moment it fires.
        make("spitter.windup", .enemy, gain: 0.44, priority: 7, cooldown: 0.1, maxVoices: 3, [
            SoundLayer(.saw, 330, steps: [0, 4, 7], stepTime: 0.133, tremolo: (1 / 0.133, 0.7), detune: 20,
                       envelope: Envelope(attack: 0.02, decay: 0, sustain: 1, release: 0.02),
                       filter: FilterSpec(.lowPass, cutoff: 900, to: 4000, resonance: 3), duration: 0.4),
            SoundLayer(.crackle, 200, to: 1600, envelope: Envelope(attack: 0.3, decay: 0, sustain: 1, release: 0.02),
                       filter: FilterSpec(.bandPass, cutoff: 1500, to: 4500, resonance: 1), duration: 0.4, gain: 1.2),
        ]),
        // The spit itself.
        make("spitter.spit", .enemy, gain: 0.28, priority: 3, cooldown: 0.06, maxVoices: 2, [
            SoundLayer(.noise, 0, envelope: .pluck(0.1), filter: FilterSpec(.bandPass, cutoff: 2200, to: 700, resonance: 2),
                       duration: 0.12),
            SoundLayer(.saw, 520, to: 180, detune: 25, envelope: .pluck(0.12),
                       filter: FilterSpec(.lowPass, cutoff: 1800, resonance: 3), duration: 0.14, gain: 0.7),
        ]),
        // A Spitter loses its first point: a short buzzing knock.
        make("spitter.hit", .enemy, gain: 0.24, priority: 2, cooldown: 0.05, maxVoices: 2, [
            SoundLayer(.saw, 700, to: 520, detune: 30, envelope: .pluck(0.05),
                       filter: FilterSpec(.bandPass, cutoff: 1600, resonance: 2.5), duration: 0.06),
            SoundLayer(.noise, 0, envelope: .pluck(0.02), filter: FilterSpec(.highPass, cutoff: 2500), duration: 0.025,
                       gain: 0.5),
        ]),
        // A shot glancing off a Thresher's hull: a dull, ringing clank, not a kill.
        make("thresher.clank", .enemy, gain: 0.19, priority: 2, cooldown: 0.06, maxVoices: 2, [
            SoundLayer(.noise, 0, envelope: .pluck(0.05, attack: 0.0006),
                       filter: FilterSpec(.bandPass, cutoff: 1050, resonance: 5), duration: 0.07, gain: 1.6),
            SoundLayer(.saw, 150, to: 128, detune: 12, envelope: .pluck(0.06), filter: FilterSpec(.lowPass, cutoff: 900),
                       duration: 0.07, gain: 0.35),
        ]),
        // A Gleaner dies: its claw snaps twice and it rattles apart.
        make("gleaner.die", .enemy, gain: 0.55, priority: 4, cooldown: 0.05, maxVoices: 2, [
            SoundLayer(.noise, 0, envelope: .pluck(0.014, attack: 0.0005), filter: FilterSpec(.highPass, cutoff: 1800),
                       duration: 0.02, gain: 0.8),
            SoundLayer(.noise, 0, envelope: .pluck(0.012, attack: 0.0005), filter: FilterSpec(.highPass, cutoff: 1500),
                       delay: 0.05, duration: 0.02, gain: 0.7),
            SoundLayer(.saw, 620, to: 140, detune: 25, envelope: Envelope(attack: 0.003, decay: 0.22, sustain: 0, release: 0.02),
                       filter: FilterSpec(.bandPass, cutoff: 1400, to: 500, resonance: 3), duration: 0.25, gain: 0.9),
            SoundLayer(.crackle, 380, to: 40, envelope: Envelope(attack: 0.01, decay: 0.25, sustain: 0, release: 0.02),
                       filter: FilterSpec(.bandPass, cutoff: 2200, to: 900), delay: 0.02, duration: 0.3, gain: 1.6),
        ]),
        // A Spitter bursts: a pop, a warbling fall and its venom sizzling away.
        make("spitter.die", .enemy, gain: 0.5, priority: 4, cooldown: 0.05, maxVoices: 2, [
            SoundLayer(.noise, 0, envelope: .pluck(0.03, attack: 0.0005),
                       filter: FilterSpec(.bandPass, cutoff: 1600, resonance: 0.8), duration: 0.04, gain: 1.2),
            SoundLayer(.saw, 360, to: 70, vibrato: (16, 0.8), detune: 30,
                       envelope: Envelope(attack: 0.003, decay: 0.3, sustain: 0, release: 0.03),
                       filter: FilterSpec(.lowPass, cutoff: 2400, to: 500, resonance: 2), duration: 0.34),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.02, decay: 0.35, sustain: 0, release: 0.05),
                       filter: FilterSpec(.highPass, cutoff: 3500, to: 6000), delay: 0.04, duration: 0.42, gain: 0.45),
        ]),
        // A Husk is torn apart: a crack and a fast shredding flutter falling away.
        make("husk.die", .enemy, gain: 0.74, priority: 5, cooldown: 0.05, maxVoices: 2, [
            SoundLayer(.noise, 0, envelope: .pluck(0.02, attack: 0.0005),
                       filter: FilterSpec(.bandPass, cutoff: 2400, resonance: 0.7), duration: 0.03, gain: 0.5),
            SoundLayer(.saw, 520, to: 90, tremolo: (38, 0.6), noise: 0.3, detune: 45,
                       envelope: Envelope(attack: 0.003, decay: 0.38, sustain: 0, release: 0.03),
                       filter: FilterSpec(.lowPass, cutoff: 3200, to: 600, resonance: 1.8), duration: 0.42),
            SoundLayer(.crackle, 260, to: 30, envelope: Envelope(attack: 0.01, decay: 0.4, sustain: 0, release: 0.03),
                       filter: FilterSpec(.lowPass, cutoff: 2600, to: 1000), delay: 0.03, duration: 0.45, gain: 1.1),
        ]),
        // A Burrow caves in: a crack, a rumbling collapse, rubble pouring in and the floor
        // groaning, ringing in the dome.
        make("burrow.collapse", .enemy, gain: 0.8, priority: 7, cooldown: 0.15, maxVoices: 1, echo: dome(0.07, feedback: 0.4, mix: 0.3), [
            SoundLayer(.noise, 0, envelope: .pluck(0.03, attack: 0.0005), filter: FilterSpec(.lowPass, cutoff: 2600),
                       duration: 0.04, gain: 1.2),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.004, decay: 0.8, sustain: 0, release: 0.05),
                       filter: FilterSpec(.bandPass, cutoff: 700, to: 250, resonance: 1), duration: 0.9, gain: 1.6),
            SoundLayer(.crackle, 420, to: 25, envelope: Envelope(attack: 0.02, decay: 0.9, sustain: 0, release: 0.05, curve: 1.4),
                       filter: FilterSpec(.lowPass, cutoff: 2400, to: 800), delay: 0.04, duration: 1.0, gain: 2.2),
            SoundLayer(.saw, 300, to: 120, detune: 30, envelope: Envelope(attack: 0.05, decay: 0.6, sustain: 0, release: 0.05),
                       filter: FilterSpec(.bandPass, cutoff: 600, resonance: 3), duration: 0.7, gain: 0.5),
            SoundLayer(.saw, 90, to: 38, detune: 35, envelope: Envelope(attack: 0.004, decay: 0.7, sustain: 0, release: 0.05),
                       filter: FilterSpec(.lowPass, cutoff: 400), duration: 0.75, gain: 0.4),
        ]),
        // The heaviest kill, only ever made by a Shockwave: a crack, the hull clanging like a
        // struck plate, a roar and wreckage crackling on.
        make("thresher.wreck", .enemy, gain: 0.86, priority: 8, cooldown: 0.2, maxVoices: 1, echo: dome(0.11, feedback: 0.4, mix: 0.32), [
            SoundLayer(.noise, 0, envelope: .pluck(0.02, attack: 0.0005),
                       filter: FilterSpec(.bandPass, cutoff: 3000, resonance: 0.6), duration: 0.03, gain: 1.0),
            SoundLayer(.saw, 147, envelope: .pluck(0.6), filter: FilterSpec(.bandPass, cutoff: 800, resonance: 7),
                       duration: 0.65, gain: 0.9),
            SoundLayer(.saw, 208, envelope: .pluck(0.45), filter: FilterSpec(.bandPass, cutoff: 1250, resonance: 7),
                       duration: 0.5, gain: 0.6),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.003, decay: 0.9, sustain: 0, release: 0.05, curve: 2.2),
                       filter: FilterSpec(.lowPass, cutoff: 1500, to: 300, resonance: 0.8), duration: 1.0, gain: 1.3),
            SoundLayer(.crackle, 320, to: 30, envelope: Envelope(attack: 0.04, decay: 1.1, sustain: 0, release: 0.05, curve: 1.4),
                       filter: FilterSpec(.lowPass, cutoff: 1000, to: 500), delay: 0.05, duration: 1.2, gain: 2.0),
            SoundLayer(.saw, 70, to: 30, detune: 30, envelope: Envelope(attack: 0.004, decay: 0.85, sustain: 0, release: 0.05),
                       filter: FilterSpec(.lowPass, cutoff: 450), duration: 0.9, gain: 0.35),
        ]),
        // A Gleaner got its colonist away and turned: a rising, wobbling wail that collapses
        // into a growl.
        make("husk.form", .enemy, gain: 0.55, priority: 7, cooldown: 0.3, maxVoices: 1, [
            SoundLayer(.saw, d3, to: a4, vibrato: (9, 1.6), noise: 0.3, detune: 55,
                       envelope: Envelope(attack: 0.08, decay: 0.3, sustain: 0.6, release: 0.25),
                       filter: FilterSpec(.bandPass, cutoff: 500, to: 2000, resonance: 4), duration: 0.85),
            SoundLayer(.saw, d4, to: 98, detune: 40, envelope: Envelope(attack: 0.3, decay: 0.3, sustain: 0.4, release: 0.2),
                       filter: FilterSpec(.lowPass, cutoff: 1200, resonance: 2), delay: 0.25, duration: 0.6, gain: 0.6),
        ]),
    ]

    // MARK: Colonists

    /// Joining the line: a soft chirp whose note climbs a D major pentatonic with the line's
    /// length, so a growing line is heard growing.
    static func join(_ position: Int) -> SoundPatch {
        let degree = [0.0, 2, 4, 7, 9][min(max(position - 1, 0), joinNotes - 1)]
        let f = d6 * semitones(degree)
        return make("colonist.join.\(position)", .colonist, gain: 0.3, priority: 5, cooldown: 0.08, maxVoices: 1, [
            SoundLayer(.sine, f * 0.94, to: f, envelope: Envelope(attack: 0.003, decay: 0.05, sustain: 0.5, release: 0.04),
                       duration: 0.09),
            SoundLayer(.triangle, f / 2, envelope: .pluck(0.08), duration: 0.09, gain: 0.3),
        ])
    }

    /// The reward: a bright chime arpeggio climbing through D major, one note longer for each
    /// colonist delivered together (three notes for one, eight for six or more), ringing on in
    /// the dome. Louder too, a little, for a longer line.
    static func delivery(_ count: Int) -> SoundPatch {
        let n = min(max(count, 1), deliverySizes)
        let ladder: [Double] = [0, 4, 7, 12, 16, 19, 24, 28]
        let notes = Array(ladder.prefix(n + 2))
        let step = 0.065
        var layers: [SoundLayer] = []
        for (index, note) in notes.enumerated() {
            let last = index == notes.count - 1
            layers.append(SoundLayer(.sine, d5 * semitones(note), envelope: .pluck(last ? 0.5 : 0.2, attack: 0.003),
                                     delay: Double(index) * step, duration: last ? 0.52 : 0.22))
            layers.append(SoundLayer(.sine, 2 * d5 * semitones(note), envelope: .pluck(last ? 0.3 : 0.1, attack: 0.002),
                                     delay: Double(index) * step, duration: last ? 0.32 : 0.12, gain: 0.6))
        }
        return make("delivery.\(n)", .colonist, gain: 0.46 + 0.045 * Double(n), priority: 8, cooldown: 0.2, maxVoices: 1,
                    echo: dome(0.09, feedback: 0.35, mix: 0.35), layers)
    }

    static let colonistSounds: [SoundPatch] = (1...joinNotes).map(join) + (1...deliverySizes).map(delivery) + [
        // The most important warning: a shrill two-note alarm, fast, high above everything in
        // the crowd.
        make("colonist.seized", .colonist, gain: 0.74, priority: 9, cooldown: 0.3, maxVoices: 1, [
            SoundLayer(.sine, 1568, steps: [0, -4, 0, -4, 0, -4], stepTime: 0.055, vibrato: (14, 0.25),
                       tremolo: (1 / 0.055, 0.7),
                       envelope: Envelope(attack: 0.003, decay: 0.04, sustain: 0.85, release: 0.06), duration: 0.36),
            SoundLayer(.triangle, 784, steps: [0, -4, 0, -4, 0, -4], stepTime: 0.055, tremolo: (1 / 0.055, 0.7),
                       envelope: Envelope(attack: 0.003, decay: 0.04, sustain: 0.85, release: 0.06), duration: 0.36,
                       gain: 0.45),
        ]),
        // Freed: a relieved upward chirp and a little leap.
        make("colonist.freed", .colonist, gain: 0.42, priority: 6, cooldown: 0.15, maxVoices: 1, [
            SoundLayer(.sine, a5, to: 1320, envelope: Envelope(attack: 0.004, decay: 0.08, sustain: 0.6, release: 0.06),
                       duration: 0.12),
            SoundLayer(.sine, 1320, steps: [0, 5], stepTime: 0.06, envelope: .pluck(0.14), delay: 0.1, duration: 0.16,
                       gain: 0.8),
        ]),
        // Taken: three notes falling an octave, wavering, sinking low.
        make("colonist.taken", .colonist, gain: 0.52, priority: 8, cooldown: 0.2, maxVoices: 1, [
            SoundLayer(.triangle, d5, steps: [0, -5, -12], stepTime: 0.22, vibrato: (6, 0.35),
                       envelope: Envelope(attack: 0.02, decay: 0.3, sustain: 0.65, release: 0.25), duration: 0.75),
            SoundLayer(.sine, d4, to: 98, envelope: Envelope(attack: 0.02, decay: 0.3, sustain: 0.6, release: 0.25),
                       duration: 0.75, gain: 0.5),
        ]),
        // Crushed: a thud and a cry cut short.
        make("colonist.crushed", .colonist, gain: 0.54, priority: 8, cooldown: 0.2, maxVoices: 1, [
            SoundLayer(.sine, 180, to: 50, envelope: .pluck(0.18, attack: 0.001), duration: 0.2, gain: 0.6),
            SoundLayer(.triangle, d6, to: a5, tremolo: (26, 0.8),
                       envelope: Envelope(attack: 0.003, decay: 0.3, sustain: 0.2, release: 0.1), duration: 0.42),
        ]),
    ]

    // MARK: Alerts

    static let alertSounds: [SoundPatch] = [
        // A wave begins: the dome's alarm, four pulses stepping up a fourth over a rising swell.
        make("wave.start", .alert, gain: 0.54, priority: 8, cooldown: 1, maxVoices: 1, echo: dome(0.08), [
            SoundLayer(.square, d4, steps: [0, 0, 5, 5], stepTime: 0.16, tremolo: (1 / 0.16, 0.85),
                       envelope: Envelope(attack: 0.005, decay: 0.1, sustain: 0.8, release: 0.12),
                       filter: FilterSpec(.lowPass, cutoff: 1200), duration: 0.64),
            SoundLayer(.saw, d2, detune: 14, envelope: Envelope(attack: 0.3, decay: 0.2, sustain: 0.5, release: 0.25),
                       filter: FilterSpec(.lowPass, cutoff: 200, to: 1400, resonance: 1.5), duration: 0.8, gain: 0.5),
        ]),
        // The floor is clear: a warm chord swelling, a lead climbing to the ninth over it.
        make("wave.clear", .alert, gain: 0.6, priority: 8, cooldown: 1, maxVoices: 1, echo: dome(0.1, feedback: 0.4, mix: 0.35), [
            SoundLayer(.triangle, d4, envelope: Envelope(attack: 0.5, decay: 0.1, sustain: 0.8, release: 0.35),
                       duration: 1.0, gain: 0.5),
            SoundLayer(.triangle, a4 * semitones(-3), envelope: Envelope(attack: 0.5, decay: 0.1, sustain: 0.8, release: 0.35),
                       duration: 1.0, gain: 0.4),
            SoundLayer(.square, d5, steps: [0, 4, 7, 11, 14], stepTime: 0.11,
                       envelope: Envelope(attack: 0.3, decay: 0.1, sustain: 0.7, release: 0.3),
                       filter: FilterSpec(.lowPass, cutoff: 1200), duration: 0.9, gain: 0.45),
        ]),
        // The airlock opens at its new place: a latch, a hiss of air and a two-note chime,
        // panned to where it is.
        make("airlock.open", .alert, gain: 0.34, priority: 3, cooldown: 0.5, maxVoices: 1, [
            SoundLayer(.noise, 0, envelope: .pluck(0.03), filter: FilterSpec(.lowPass, cutoff: 700), duration: 0.04),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.01, decay: 0.35, sustain: 0, release: 0.05),
                       filter: FilterSpec(.highPass, cutoff: 2500, to: 5000), delay: 0.03, duration: 0.45, gain: 0.7),
            SoundLayer(.triangle, d5, steps: [0, 7], stepTime: 0.08, envelope: .pluck(0.15), delay: 0.08, duration: 0.2,
                       gain: 0.4),
        ]),
        // Every colonist of the wave is gone: a low two-note swell of dread over a cold draught.
        // The dark comes next wave.
        make("colonists.gone", .alert, gain: 0.62, priority: 9, cooldown: 1, maxVoices: 1, echo: dome(0.18, feedback: 0.4, mix: 0.35), [
            SoundLayer(.triangle, d3, steps: [0, -1], stepTime: 0.6,
                       envelope: Envelope(attack: 0.7, decay: 0.1, sustain: 0.8, release: 0.4), duration: 1.3),
            SoundLayer(.sine, d5, steps: [0, -1], stepTime: 0.6,
                       envelope: Envelope(attack: 0.7, decay: 0.1, sustain: 0.8, release: 0.4), duration: 1.3, gain: 0.5),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.3, decay: 0.5, sustain: 0.3, release: 0.4),
                       filter: FilterSpec(.bandPass, cutoff: 600, to: 250, resonance: 1.5), duration: 1.3, gain: 0.35),
        ]),
        // The power fails: the lights' hum falters and runs down, arcing crackles, a falling
        // whine and the breaker's thunk.
        make("power.fail", .alert, gain: 0.88, priority: 10, cooldown: 1, maxVoices: 1, echo: dome(0.12, feedback: 0.35, mix: 0.25), [
            SoundLayer(.saw, 120, to: 30, tremolo: (13, 0.9), detune: 20,
                       envelope: Envelope(attack: 0.005, decay: 1.4, sustain: 0.2, release: 0.4),
                       filter: FilterSpec(.lowPass, cutoff: 3000, to: 150), duration: 1.9),
            SoundLayer(.crackle, 500, to: 30, envelope: Envelope(attack: 0.003, decay: 0.9, sustain: 0, release: 0.05),
                       filter: FilterSpec(.highPass, cutoff: 1500), duration: 1.0, gain: 1.4),
            SoundLayer(.square, 1760, to: 110, envelope: Envelope(attack: 0.005, decay: 1.2, sustain: 0.1, release: 0.3),
                       filter: FilterSpec(.lowPass, cutoff: 5000, to: 400), duration: 1.6, gain: 0.45),
            SoundLayer(.noise, 0, envelope: .pluck(0.08), filter: FilterSpec(.lowPass, cutoff: 900), duration: 0.1, gain: 1.2),
        ]),
        // Power restored: generators spinning up and the lights coming on in a rising chord.
        make("power.restore", .alert, gain: 0.74, priority: 9, cooldown: 1, maxVoices: 1, echo: dome(0.1, feedback: 0.35), [
            SoundLayer(.saw, 40, to: 160, tremolo: (9, 0.5), detune: 15,
                       envelope: Envelope(attack: 0.8, decay: 0.2, sustain: 0.7, release: 0.3),
                       filter: FilterSpec(.lowPass, cutoff: 200, to: 2600, resonance: 1.5), duration: 1.5, gain: 0.7),
            SoundLayer(.triangle, d5, steps: [0, 4, 7, 12], stepTime: 0.12,
                       envelope: Envelope(attack: 0.004, decay: 0.1, sustain: 0.7, release: 0.2), delay: 0.7, duration: 0.8),
        ]),
        // An extra life: a fast bright climb two octaves up, each note struck.
        make("life.extra", .alert, gain: 0.74, priority: 9, cooldown: 1, maxVoices: 1, echo: dome(0.08, feedback: 0.3, mix: 0.25), [
            SoundLayer(.square, d5, steps: [0, 4, 7, 12, 7, 12, 16, 19, 24], stepTime: 0.055, tremolo: (1 / 0.055, 0.9),
                       envelope: Envelope(attack: 0.003, decay: 0.05, sustain: 0.85, release: 0.1),
                       filter: FilterSpec(.lowPass, cutoff: 4500), duration: 0.6),
            SoundLayer(.triangle, d4, steps: [0, 4, 7, 12, 7, 12, 16, 19, 24], stepTime: 0.055, tremolo: (1 / 0.055, 0.9),
                       envelope: Envelope(attack: 0.003, decay: 0.05, sustain: 0.85, release: 0.1), duration: 0.6, gain: 0.5),
        ]),
        // Game over: a slow falling minor line over a closing low chord.
        make("game.over", .alert, gain: 0.72, priority: 10, cooldown: 2, maxVoices: 1, echo: dome(0.2, feedback: 0.4, mix: 0.3), [
            SoundLayer(.triangle, d5, steps: [0, -2, -3, -7, -10, -12], stepTime: 0.3,
                       envelope: Envelope(attack: 0.01, decay: 0.3, sustain: 0.7, release: 0.5), duration: 2.0),
            SoundLayer(.square, d4, steps: [0, -2, -3, -7, -10, -12], stepTime: 0.3,
                       envelope: Envelope(attack: 0.01, decay: 0.3, sustain: 0.6, release: 0.5),
                       filter: FilterSpec(.lowPass, cutoff: 1800, to: 700), duration: 2.0, gain: 0.25),
            SoundLayer(.saw, d2, detune: 18, envelope: Envelope(attack: 0.4, decay: 0.5, sustain: 0.5, release: 0.6),
                       filter: FilterSpec(.lowPass, cutoff: 900, to: 250), duration: 2.1, gain: 0.35),
        ]),
    ]

    // MARK: Menus

    static let interfaceSounds: [SoundPatch] = [
        make("ui.move", .interface, gain: 0.18, priority: 1, cooldown: 0.03, maxVoices: 2, [
            SoundLayer(.triangle, 1568, envelope: .pluck(0.03), duration: 0.035),
            SoundLayer(.sine, 784, envelope: .pluck(0.03), duration: 0.035, gain: 0.4),
        ]),
        make("ui.change", .interface, gain: 0.22, priority: 1, cooldown: 0.03, maxVoices: 2, [
            SoundLayer(.triangle, d6, to: 1760, envelope: .pluck(0.08), duration: 0.09),
        ]),
        make("ui.activate", .interface, gain: 0.3, priority: 2, cooldown: 0.08, maxVoices: 1, [
            SoundLayer(.sine, d5, steps: [0, 5, 12], stepTime: 0.045,
                       envelope: Envelope(attack: 0.003, decay: 0.05, sustain: 0.6, release: 0.05), duration: 0.15),
        ]),
        make("ui.back", .interface, gain: 0.25, priority: 2, cooldown: 0.08, maxVoices: 1, [
            SoundLayer(.sine, a5, steps: [0, -5], stepTime: 0.06,
                       envelope: Envelope(attack: 0.003, decay: 0.08, sustain: 0.5, release: 0.05), duration: 0.14),
        ]),
    ]

    // MARK: Music

    /// G Phrygian, the flat second giving the dome its closeness, a little faster than
    /// Ridgeline's. Title and calm are open and slow; a wave drives a steady low chug under
    /// short chords that circle the tonic and its dark neighbour, with few bells, so it can loop
    /// for minutes without wearing; the power cut sinks to a drone.
    static let musicStyle = MusicStyle(
        root: 55, // G3
        scale: [0, 1, 3, 5, 7, 8, 10],
        tempo: 104,
        gain: 0.48,
        moods: [
            .title: MoodProfile(progression: [0, 5, 3, 5], chordSeconds: 10, bellChance: 0.08, padCutoff: 850),
            .calm: MoodProfile(progression: [0, 3, 5, 1], chordSeconds: 7, bellChance: 0.13, padCutoff: 950),
            .tension: MoodProfile(progression: [0, 1, 0, 6, 0, 1, 5, 6], chordSeconds: 4.6, bellChance: 0.1,
                                  pulse: [1, 1, 0, 1, 1, 0, 1, 1], padCutoff: 1250),
            .blackout: MoodProfile(progression: [0, 1], chordSeconds: 11, bellChance: 0.05, bellOctave: 1,
                                   drone: true, padCutoff: 750),
        ]
    )
}
