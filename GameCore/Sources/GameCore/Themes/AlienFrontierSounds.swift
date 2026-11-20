/// The Alien Frontier's sounds and music, all synthesised from the data below.
///
/// Families, so a sound says where it came from before you see it:
/// - the ship: clean square and triangle tones pitched around E, bright and short;
/// - enemies: detuned, buzzy sawtooth with noise, low and filtered; their deaths are explosions
///   with a sharp crack and their energy in the mid band, where a phone speaker can play it;
/// - colonists: soft sine chirps up high;
/// - alerts (waves, Blackout, outposts, extra life): chords and arpeggios in A minor with echo.
/// Loudness follows importance: firing is the quietest and shortest; losing the ship, Blackout,
/// a Shockwave and an extra life are the loudest.
extension AlienFrontier {
    static let soundPrefix = "frontier."

    /// Every patch, by name without the theme prefix.
    static let patches: [String: SoundPatch] = {
        var all: [String: SoundPatch] = [:]
        for patch in shipSounds + enemySounds + colonistSounds + alertSounds + interfaceSounds {
            all[String(patch.name.dropFirst(soundPrefix.count))] = patch
        }
        return all
    }()

    static func patch(_ short: String) -> SoundPatch {
        patches[short] ?? SoundPatch(name: soundPrefix + short)
    }

    // Pitches (Hz).
    private static let e5 = 659.26, b5 = 987.77, e6 = 1318.5
    private static let a2 = 110.0, a3 = 220.0, a4 = 440.0, a5 = 880.0
    private static let c6 = 1046.5

    private static func make(_ name: String, _ family: SoundFamily, gain: Double, priority: Int,
                             cooldown: Double = 0.03, maxVoices: Int = 2, echo: Echo? = nil,
                             _ layers: [SoundLayer]) -> SoundPatch {
        SoundPatch(name: soundPrefix + name, family: family, gain: gain, priority: priority, cooldown: cooldown,
                   maxVoices: maxVoices, echo: echo, layers: layers)
    }

    // MARK: The ship

    static let shipSounds: [SoundPatch] = [
        // A tight, bright tick that drops an octave: ten a second, so it must stay out of the way.
        make("lance.fire", .player, gain: 0.15, priority: 0, cooldown: 0.05, maxVoices: 3, [
            SoundLayer(.square, 1480, to: 740, envelope: .pluck(0.045), filter: FilterSpec(.lowPass, cutoff: 6000, to: 2200),
                       duration: 0.055),
        ]),
        // The lance chokes: a falling, stuttering tone and a hiss of venting heat.
        make("lance.overheat", .player, gain: 0.5, priority: 4, cooldown: 0.4, maxVoices: 1, [
            SoundLayer(.square, b5, to: 247, tremolo: (24, 0.8), envelope: Envelope(attack: 0.005, decay: 0.3, sustain: 0.3, release: 0.12),
                       filter: FilterSpec(.lowPass, cutoff: 3500, to: 900), duration: 0.45),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.02, decay: 0.4, sustain: 0.2, release: 0.15),
                       filter: FilterSpec(.highPass, cutoff: 3500, to: 6000), delay: 0.05, duration: 0.55, gain: 0.15),
        ]),
        // A quick upward zip with a glassy echo.
        make("blink", .player, gain: 0.42, priority: 4, cooldown: 0.1, maxVoices: 1,
             echo: Echo(time: 0.055, feedback: 0.35, mix: 0.4), [
                SoundLayer(.triangle, 440, to: 2640, envelope: Envelope(attack: 0.004, decay: 0.08, sustain: 0.4, release: 0.04),
                           duration: 0.13),
                SoundLayer(.square, e6, to: 2637, envelope: .pluck(0.09), filter: FilterSpec(.lowPass, cutoff: 5000),
                           delay: 0.03, duration: 0.1, gain: 0.25),
             ]),
        // The big one: a deep thump, a roaring sweep and the ship's tone diving under it.
        make("shockwave", .player, gain: 0.9, priority: 9, cooldown: 0.3, maxVoices: 1,
             echo: Echo(time: 0.09, feedback: 0.3, mix: 0.3), [
                SoundLayer(.sine, 70, to: 45, envelope: .pluck(0.3), duration: 0.32, gain: 0.35),
                SoundLayer(.square, 330, to: 1760, tremolo: (12, 0.95),
                           envelope: Envelope(attack: 0.01, decay: 0.45, sustain: 0.65, release: 0.25),
                           filter: FilterSpec(.lowPass, cutoff: 1400, to: 6500), duration: 0.85),
                SoundLayer(.noise, 0, envelope: Envelope(attack: 0.05, decay: 0.5, sustain: 0.2, release: 0.2),
                           filter: FilterSpec(.bandPass, cutoff: 700, to: 5000, resonance: 1.2), duration: 0.8, gain: 0.3),
             ]),
        // A rising major arpeggio: protection is ready.
        make("shield.charged", .player, gain: 0.5, priority: 6, cooldown: 0.5, maxVoices: 1, [
            // Charging up: a rising whine that swells to full and rings off.
            SoundLayer(.triangle, 330, to: 1320, envelope: Envelope(attack: 0.42, decay: 0.05, sustain: 0.9, release: 0.18),
                       duration: 0.65),
            SoundLayer(.square, 660, to: 2640, envelope: Envelope(attack: 0.42, decay: 0.05, sustain: 0.7, release: 0.18),
                       filter: FilterSpec(.lowPass, cutoff: 3000, to: 6000), duration: 0.65, gain: 0.25),
        ]),
        // Glass shattering downward.
        make("shield.break", .player, gain: 0.6, priority: 7, cooldown: 0.3, maxVoices: 1, [
            SoundLayer(.square, 2637, to: 330, noise: 0.25, envelope: Envelope(attack: 0.002, decay: 0.3, sustain: 0, release: 0.04),
                       filter: FilterSpec(.lowPass, cutoff: 6000, to: 700), duration: 0.34),
            SoundLayer(.noise, 0, envelope: .pluck(0.18), filter: FilterSpec(.highPass, cutoff: 2500), duration: 0.2, gain: 0.5),
        ]),
        // Losing the ship: a long roar, a sub drop and the ship's tone falling away.
        make("player.explode", .player, gain: 0.92, priority: 10, cooldown: 0.5, maxVoices: 1,
             echo: Echo(time: 0.17, feedback: 0.3, mix: 0.3), [
                SoundLayer(.noise, 0, envelope: Envelope(attack: 0.004, decay: 1.3, sustain: 0, release: 0.05, curve: 1.6),
                           filter: FilterSpec(.lowPass, cutoff: 5000, to: 120, resonance: 0.9), duration: 1.4),
                // Debris crackling apart, in the range a phone speaker carries.
                SoundLayer(.noise, 0, envelope: Envelope(attack: 0.004, decay: 0.9, sustain: 0, release: 0.05),
                           filter: FilterSpec(.bandPass, cutoff: 2200, to: 700, resonance: 1.3), duration: 1.0, gain: 1.0),
                SoundLayer(.sine, 130, to: 32, envelope: Envelope(attack: 0.004, decay: 1.0, sustain: 0, release: 0.05),
                           duration: 1.1, gain: 0.45),
                SoundLayer(.square, e5, to: 110, envelope: Envelope(attack: 0.004, decay: 0.85, sustain: 0, release: 0.05),
                           filter: FilterSpec(.lowPass, cutoff: 4000, to: 600), duration: 0.9, gain: 0.7),
             ]),
        // The ship fades back in: a fifth-and-octave sweep upward.
        make("player.respawn", .player, gain: 0.45, priority: 5, cooldown: 0.5, maxVoices: 1, [
            SoundLayer(.triangle, 330, to: 1320, envelope: Envelope(attack: 0.3, decay: 0.2, sustain: 0.5, release: 0.2),
                       duration: 0.9),
            SoundLayer(.square, e5, steps: [0, 7, 12, 19], stepTime: 0.1, envelope: Envelope(attack: 0.004, decay: 0.05, sustain: 0.5, release: 0.1),
                       filter: FilterSpec(.lowPass, cutoff: 3500), delay: 0.4, duration: 0.45, gain: 0.3),
        ]),
    ]

    // MARK: Enemies

    static let enemySounds: [SoundPatch] = [
        // Something tears in from elsewhere: a rising, filtered buzz.
        make("enemy.warp", .enemy, gain: 0.26, priority: 1, cooldown: 0.2, maxVoices: 2, [
            SoundLayer(.saw, 70, to: 330, noise: 0.35, detune: 25,
                       envelope: Envelope(attack: 0.12, decay: 0.15, sustain: 0.4, release: 0.1),
                       filter: FilterSpec(.lowPass, cutoff: 400, to: 2600, resonance: 2.5), duration: 0.38),
        ]),
        // A small wet chirp: a Mote hatching from the burst.
        make("mote.hatch", .enemy, gain: 0.2, priority: 1, cooldown: 0.06, maxVoices: 2, [
            SoundLayer(.saw, 400, to: 1400, noise: 0.3, detune: 30, envelope: .pluck(0.15),
                       filter: FilterSpec(.bandPass, cutoff: 1200, to: 3000, resonance: 2), duration: 0.16),
        ]),
        // A low "blorp" as a spore leaves the pod.
        make("spore.fire", .enemy, gain: 0.24, priority: 2, cooldown: 0.08, maxVoices: 2, [
            SoundLayer(.saw, 290, to: 150, noise: 0.25, detune: 20, envelope: Envelope(attack: 0.004, decay: 0.1, sustain: 0, release: 0.02),
                       filter: FilterSpec(.lowPass, cutoff: 1800, to: 500, resonance: 3), duration: 0.13),
        ]),
        // A dull knock on armour.
        make("enemy.hit", .enemy, gain: 0.3, priority: 2, cooldown: 0.04, maxVoices: 2, [
            SoundLayer(.noise, 0, envelope: .pluck(0.07), filter: FilterSpec(.bandPass, cutoff: 800, resonance: 1.5),
                       duration: 0.08),
            SoundLayer(.saw, 170, to: 120, noise: 0.4, detune: 20, envelope: .pluck(0.07), filter: FilterSpec(.lowPass, cutoff: 1000),
                       duration: 0.08, gain: 0.6),
        ]),
        // A craft blows apart: a bright crack, a burst of noise that darkens as it spreads, and
        // debris crackling away. The body lives in the mid band a phone speaker carries; the low
        // thump under it is only for headphones.
        make("enemy.explode", .enemy, gain: 0.75, priority: 4, cooldown: 0.05, maxVoices: 3, [
            // The crack.
            SoundLayer(.noise, 0, envelope: .pluck(0.016, attack: 0.0005),
                       filter: FilterSpec(.bandPass, cutoff: 3000, resonance: 0.6), duration: 0.024, gain: 2.6),
            // The blast: bright at first, falling away.
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.006, decay: 0.28, sustain: 0, release: 0.02, curve: 2.4),
                       filter: FilterSpec(.lowPass, cutoff: 3500, to: 700, resonance: 0.8), duration: 0.32, gain: 1.2),
            // Its rumbling core, as low as a phone speaker still plays.
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.003, decay: 0.36, sustain: 0, release: 0.02, curve: 2),
                       filter: FilterSpec(.bandPass, cutoff: 950, to: 420, resonance: 0.9), duration: 0.4, gain: 1.6),
            // Debris crackling away.
            SoundLayer(.crackle, 240, to: 30, envelope: Envelope(attack: 0.03, decay: 0.55, sustain: 0, release: 0.03, curve: 1.3),
                       filter: FilterSpec(.lowPass, cutoff: 2600, to: 1000, resonance: 0.9), delay: 0.03, duration: 0.62,
                       gain: 2.2),
            // A low thump for headphones.
            SoundLayer(.saw, 120, to: 45, detune: 30, envelope: .pluck(0.16), filter: FilterSpec(.lowPass, cutoff: 500),
                       duration: 0.18, gain: 0.35),
        ]),
        // A small, high crackle.
        make("mote.pop", .enemy, gain: 0.3, priority: 2, cooldown: 0.04, maxVoices: 3, [
            SoundLayer(.noise, 0, envelope: .pluck(0.09), filter: FilterSpec(.bandPass, cutoff: 3200, to: 1500, resonance: 1.5),
                       duration: 0.11),
            SoundLayer(.saw, 1000, to: 420, detune: 25, envelope: .pluck(0.08), filter: FilterSpec(.lowPass, cutoff: 3500),
                       duration: 0.09, gain: 0.5),
        ]),
        // A mine goes off: a resonant ping that snaps shut.
        make("mine.pop", .enemy, gain: 0.36, priority: 2, cooldown: 0.05, maxVoices: 2, [
            SoundLayer(.saw, 760, to: 190, detune: 15, envelope: .pluck(0.16),
                       filter: FilterSpec(.lowPass, cutoff: 2400, to: 500, resonance: 5), duration: 0.18),
            SoundLayer(.noise, 0, envelope: .pluck(0.05), filter: FilterSpec(.highPass, cutoff: 2000), duration: 0.06, gain: 0.5),
        ]),
        // The sac bursts: a wet splat, then a gurgling spill that drains away. Kept in the mid
        // band, with only a little weight underneath.
        make("brood.burst", .enemy, gain: 0.7, priority: 5, cooldown: 0.1, maxVoices: 2, [
            SoundLayer(.noise, 0, envelope: .pluck(0.04, attack: 0.0008), filter: FilterSpec(.bandPass, cutoff: 1400, resonance: 0.7),
                       duration: 0.05, gain: 0.7),
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.004, decay: 0.6, sustain: 0, release: 0.05),
                       filter: FilterSpec(.lowPass, cutoff: 2200, to: 400, resonance: 1.5), duration: 0.7, gain: 1.3),
            SoundLayer(.saw, 240, to: 110, tremolo: (17, 0.7), detune: 40, envelope: Envelope(attack: 0.004, decay: 0.55, sustain: 0, release: 0.05),
                       filter: FilterSpec(.lowPass, cutoff: 1200, to: 600, resonance: 1.5), duration: 0.65, gain: 0.6),
        ]),
        // The biggest enemy blows up: a heavy crack, a long roar with metal clanging inside it,
        // and wreckage crackling on into the echo. The roar sits where a phone speaker plays; the
        // sub-bass under it is for headphones.
        make("anchor.explode", .enemy, gain: 0.8, priority: 6, cooldown: 0.2, maxVoices: 1,
             echo: Echo(time: 0.14, feedback: 0.3, mix: 0.3), [
                SoundLayer(.noise, 0, envelope: .pluck(0.03, attack: 0.0005),
                           filter: FilterSpec(.lowPass, cutoff: 3200, resonance: 0.8), duration: 0.04, gain: 2.4),
                SoundLayer(.noise, 0, envelope: Envelope(attack: 0.003, decay: 0.7, sustain: 0, release: 0.05, curve: 2.2),
                           filter: FilterSpec(.lowPass, cutoff: 2400, to: 400, resonance: 0.7), duration: 0.8, gain: 1.1),
                SoundLayer(.noise, 0, envelope: Envelope(attack: 0.004, decay: 0.95, sustain: 0, release: 0.05),
                           filter: FilterSpec(.lowPass, cutoff: 900, to: 380, resonance: 1.2), duration: 1.0, gain: 1.3),
                SoundLayer(.saw, 233, to: 175, envelope: .pluck(0.5), filter: FilterSpec(.bandPass, cutoff: 700, resonance: 4),
                           duration: 0.55, gain: 0.7),
                SoundLayer(.crackle, 300, to: 35, envelope: Envelope(attack: 0.04, decay: 1.0, sustain: 0, release: 0.05, curve: 1.4),
                           filter: FilterSpec(.lowPass, cutoff: 2000, to: 700, resonance: 0.9), delay: 0.05, duration: 1.1,
                           gain: 2.0),
                SoundLayer(.saw, 72, to: 30, detune: 30, envelope: Envelope(attack: 0.004, decay: 0.8, sustain: 0, release: 0.05),
                           filter: FilterSpec(.lowPass, cutoff: 500), duration: 0.85, gain: 0.3),
             ]),
        // A Harvester turns: a sick, wobbling growl.
        make("husk.form", .enemy, gain: 0.52, priority: 6, cooldown: 0.3, maxVoices: 1, [
            SoundLayer(.saw, a3, to: 98, vibrato: (7, 1.2), noise: 0.4, detune: 50,
                       envelope: Envelope(attack: 0.05, decay: 0.4, sustain: 0.5, release: 0.2),
                       filter: FilterSpec(.lowPass, cutoff: 800, to: 2400, resonance: 3), duration: 0.95),
        ]),
        // A soft thunk as a mine drops.
        make("mine.lay", .enemy, gain: 0.2, priority: 1, cooldown: 0.12, maxVoices: 1, [
            SoundLayer(.saw, 140, to: 90, noise: 0.35, envelope: .pluck(0.12), filter: FilterSpec(.lowPass, cutoff: 700, resonance: 4),
                       duration: 0.14),
        ]),
        // The wind-up: a pulsing tone that climbs for the length of the telegraph.
        make("lancer.windup", .enemy, gain: 0.46, priority: 6, cooldown: 0.2, maxVoices: 2, [
            SoundLayer(.saw, 180, to: 860, tremolo: (14, 0.75), noise: 0.3, detune: 15,
                       envelope: Envelope(attack: 0.03, decay: 0, sustain: 1, release: 0.08),
                       filter: FilterSpec(.lowPass, cutoff: 700, to: 4200, resonance: 2), duration: 0.8),
        ]),
        // The charge: a hard whoosh past.
        make("lancer.charge", .enemy, gain: 0.5, priority: 6, cooldown: 0.15, maxVoices: 2, [
            SoundLayer(.noise, 0, envelope: Envelope(attack: 0.02, decay: 0.4, sustain: 0, release: 0.05),
                       filter: FilterSpec(.bandPass, cutoff: 700, to: 3400, resonance: 1.5), duration: 0.5),
            SoundLayer(.saw, 860, to: 260, detune: 20, envelope: .pluck(0.35), filter: FilterSpec(.lowPass, cutoff: 3000),
                       duration: 0.38, gain: 0.5),
        ]),
        // An Anchor bites into an outpost: a thud and a grinding drill.
        make("anchor.land", .enemy, gain: 0.55, priority: 6, cooldown: 0.3, maxVoices: 1, [
            SoundLayer(.saw, 82, tremolo: (26, 0.8), noise: 0.35, detune: 30, envelope: Envelope(attack: 0.01, decay: 0.2, sustain: 0.6, release: 0.15),
                       filter: FilterSpec(.lowPass, cutoff: 1100, resonance: 2), duration: 0.6),
            SoundLayer(.noise, 0, envelope: .pluck(0.2), filter: FilterSpec(.lowPass, cutoff: 500), duration: 0.22, gain: 0.8),
        ]),
    ]

    // MARK: Colonists

    static let colonistSounds: [SoundPatch] = [
        // A wavering two-note cry for help.
        make("colonist.grabbed", .colonist, gain: 0.4, priority: 7, cooldown: 0.25, maxVoices: 1, [
            SoundLayer(.sine, c6, steps: [0, 3, 0, 3], stepTime: 0.075, vibrato: (11, 0.3),
                       envelope: Envelope(attack: 0.005, decay: 0.05, sustain: 0.8, release: 0.06), duration: 0.32),
        ]),
        // A falling whistle: someone is dropping.
        make("colonist.dropped", .colonist, gain: 0.4, priority: 7, cooldown: 0.2, maxVoices: 1, [
            // Quick bright chirps tumbling down: someone is falling, catch them.
            SoundLayer(.sine, 2000, to: 800, tremolo: (9, 0.95),
                       envelope: Envelope(attack: 0.005, decay: 0.1, sustain: 0.85, release: 0.08), duration: 0.45),
        ]),
        // A bright up-fifth: caught.
        make("colonist.caught", .colonist, gain: 0.4, priority: 6, cooldown: 0.1, maxVoices: 2, [
            SoundLayer(.sine, c6, steps: [0, 7], stepTime: 0.07, envelope: Envelope(attack: 0.003, decay: 0.08, sustain: 0.6, release: 0.06),
                       duration: 0.2),
            SoundLayer(.triangle, c6 / 2, steps: [0, 7], stepTime: 0.07, envelope: .pluck(0.18), duration: 0.2, gain: 0.35),
        ]),
        // Home: a little four-note fanfare with a shimmer.
        make("colonist.delivered", .colonist, gain: 0.46, priority: 7, cooldown: 0.12, maxVoices: 1,
             echo: Echo(time: 0.1, feedback: 0.35, mix: 0.35), [
                SoundLayer(.sine, c6, steps: [0, 4, 7, 12], stepTime: 0.08,
                           envelope: Envelope(attack: 0.004, decay: 0.1, sustain: 0.6, release: 0.12), duration: 0.42),
                SoundLayer(.sine, c6 * 2, steps: [0, 4, 7, 12], stepTime: 0.08, envelope: .pluck(0.4), duration: 0.42, gain: 0.35),
             ]),
        // A soft landing: a quiet little blip.
        make("colonist.landed", .colonist, gain: 0.24, priority: 3, cooldown: 0.1, maxVoices: 1, [
            SoundLayer(.sine, 520, to: 360, envelope: .pluck(0.065), duration: 0.07),
        ]),
        make("colonist.lost", .colonist, gain: 0.44, priority: 7, cooldown: 0.2, maxVoices: 2, [
            // One long, low, sinking sigh: gone.
            SoundLayer(.triangle, 520, to: 165, vibrato: (4, 0.3),
                       envelope: Envelope(attack: 0.06, decay: 0.3, sustain: 0.7, release: 0.35), duration: 0.95),
            SoundLayer(.sine, 260, to: 82, envelope: Envelope(attack: 0.06, decay: 0.3, sustain: 0.6, release: 0.35),
                       duration: 0.95, gain: 0.5),
        ]),
    ]

    // MARK: Alerts

    static let alertSounds: [SoundPatch] = [
        // A rising fifth over a swelling chord: here they come.
        make("wave.start", .alert, gain: 0.56, priority: 8, cooldown: 1, maxVoices: 1,
             echo: Echo(time: 0.15, feedback: 0.35, mix: 0.35), [
                SoundLayer(.triangle, a3, steps: [0, 7, 12], stepTime: 0.13,
                           envelope: Envelope(attack: 0.005, decay: 0.15, sustain: 0.6, release: 0.2), duration: 0.6),
                SoundLayer(.saw, a2, detune: 12, envelope: Envelope(attack: 0.25, decay: 0.2, sustain: 0.6, release: 0.3),
                           filter: FilterSpec(.lowPass, cutoff: 300, to: 1600), duration: 0.85, gain: 0.5),
             ]),
        // Wave cleared: a quick major run to the top.
        make("wave.clear", .alert, gain: 0.6, priority: 8, cooldown: 1, maxVoices: 1,
             echo: Echo(time: 0.12, feedback: 0.35, mix: 0.35), [
                // Legato: a run that swells into a held major chord.
                SoundLayer(.triangle, a4, steps: [0, 4, 7, 12, 16], stepTime: 0.09,
                           envelope: Envelope(attack: 0.25, decay: 0.1, sustain: 0.9, release: 0.3), duration: 0.9),
                SoundLayer(.sine, a5, envelope: Envelope(attack: 0.4, decay: 0.1, sustain: 0.8, release: 0.3),
                           delay: 0.3, duration: 0.65, gain: 0.5),
                SoundLayer(.sine, a5 * 1.26, envelope: Envelope(attack: 0.4, decay: 0.1, sustain: 0.8, release: 0.3),
                           delay: 0.3, duration: 0.65, gain: 0.35),
             ]),
        // Extra life: a bright leaping figure, loud and unmistakable.
        make("life.extra", .alert, gain: 0.72, priority: 9, cooldown: 1, maxVoices: 1,
             echo: Echo(time: 0.1, feedback: 0.3, mix: 0.25), [
                // Staccato: each note of the leap is struck separately.
                SoundLayer(.square, e5, steps: [0, 12, 7, 19, 12, 24], stepTime: 0.07, tremolo: (1 / 0.07, 0.95),
                           envelope: Envelope(attack: 0.003, decay: 0.05, sustain: 0.8, release: 0.1),
                           filter: FilterSpec(.lowPass, cutoff: 5000), duration: 0.56),
                SoundLayer(.triangle, e5 / 2, steps: [0, 12, 7, 19, 12, 24], stepTime: 0.07, tremolo: (1 / 0.07, 0.95),
                           envelope: Envelope(attack: 0.003, decay: 0.05, sustain: 0.8, release: 0.1), duration: 0.56, gain: 0.5),
             ]),
        // An outpost falls: a collapse and a descending minor line.
        make("outpost.destroyed", .alert, gain: 0.72, priority: 9, cooldown: 0.5, maxVoices: 1,
             echo: Echo(time: 0.16, feedback: 0.3, mix: 0.3), [
                SoundLayer(.noise, 0, envelope: Envelope(attack: 0.004, decay: 0.55, sustain: 0, release: 0.05),
                           filter: FilterSpec(.lowPass, cutoff: 1800, to: 70), duration: 0.6, gain: 0.45),
                SoundLayer(.triangle, a4, steps: [0, -4, -9, -12], stepTime: 0.3,
                           envelope: Envelope(attack: 0.005, decay: 0.2, sustain: 0.7, release: 0.25), duration: 1.35),
             ]),
        // A supply drop: a falling-in whoosh and a bright chime when it lands.
        make("outpost.supply", .alert, gain: 0.56, priority: 8, cooldown: 0.5, maxVoices: 1,
             echo: Echo(time: 0.12, feedback: 0.35, mix: 0.35), [
                SoundLayer(.noise, 0, envelope: Envelope(attack: 0.6, decay: 0.2, sustain: 0, release: 0.05),
                           filter: FilterSpec(.bandPass, cutoff: 3000, to: 500, resonance: 1.5), duration: 0.85, gain: 0.9),
                SoundLayer(.triangle, a4, steps: [0, 4, 7, 12], stepTime: 0.08,
                           envelope: Envelope(attack: 0.004, decay: 0.15, sustain: 0.5, release: 0.15), delay: 0.75,
                           duration: 0.45),
             ]),
        // Blackout: everything sinks into a low, rough drone with a falling tritone.
        make("blackout.begin", .alert, gain: 0.86, priority: 10, cooldown: 1, maxVoices: 1,
             echo: Echo(time: 0.2, feedback: 0.3, mix: 0.25), [
                SoundLayer(.square, 880, to: 45, tremolo: (19, 0.65), envelope: Envelope(attack: 0.01, decay: 1.3, sustain: 0.35, release: 0.45),
                           filter: FilterSpec(.lowPass, cutoff: 4500, to: 260), duration: 1.9),
                SoundLayer(.noise, 0, envelope: Envelope(attack: 0.005, decay: 0.6, sustain: 0, release: 0.05),
                           filter: FilterSpec(.highPass, cutoff: 1800, to: 900), duration: 0.65, gain: 0.35),
                SoundLayer(.saw, 55, to: 30, detune: 30, envelope: Envelope(attack: 0.05, decay: 1.4, sustain: 0.2, release: 0.4),
                           filter: FilterSpec(.lowPass, cutoff: 600, to: 90), duration: 2.0, gain: 0.45),
             ]),
        // Power restored: a slow rising line as the filter opens.
        make("blackout.end", .alert, gain: 0.7, priority: 9, cooldown: 1, maxVoices: 1,
             echo: Echo(time: 0.14, feedback: 0.35, mix: 0.3), [
                SoundLayer(.triangle, a3, steps: [0, 5, 7, 12], stepTime: 0.34,
                           envelope: Envelope(attack: 0.4, decay: 0.2, sustain: 0.8, release: 0.3), duration: 1.7),
                SoundLayer(.saw, a2, detune: 15, envelope: Envelope(attack: 1.0, decay: 0.3, sustain: 0.6, release: 0.4),
                           filter: FilterSpec(.lowPass, cutoff: 250, to: 3200), duration: 1.9, gain: 0.6),
             ]),
        // Game over: a slow falling line over a closing chord.
        make("game.over", .alert, gain: 0.76, priority: 10, cooldown: 2, maxVoices: 1,
             echo: Echo(time: 0.22, feedback: 0.35, mix: 0.3), [
                SoundLayer(.triangle, a4, steps: [0, -2, -5, -9, -12], stepTime: 0.34,
                           envelope: Envelope(attack: 0.01, decay: 0.3, sustain: 0.7, release: 0.45), duration: 1.95),
                SoundLayer(.square, a4, steps: [0, -2, -5, -9, -12], stepTime: 0.34,
                           envelope: Envelope(attack: 0.01, decay: 0.3, sustain: 0.6, release: 0.45),
                           filter: FilterSpec(.lowPass, cutoff: 2600, to: 1200), duration: 1.95, gain: 0.3),
                SoundLayer(.saw, a3, detune: 15, envelope: Envelope(attack: 0.3, decay: 0.5, sustain: 0.5, release: 0.6),
                           filter: FilterSpec(.lowPass, cutoff: 1600, to: 500), duration: 2.0, gain: 0.35),
             ]),
    ]

    // MARK: Menus

    static let interfaceSounds: [SoundPatch] = [
        make("ui.move", .interface, gain: 0.18, priority: 1, cooldown: 0.03, maxVoices: 2, [
            SoundLayer(.sine, 1760, envelope: .pluck(0.035), duration: 0.04),
        ]),
        make("ui.change", .interface, gain: 0.22, priority: 1, cooldown: 0.03, maxVoices: 2, [
            SoundLayer(.sine, 1480, to: 2350, envelope: .pluck(0.09), duration: 0.1),
        ]),
        make("ui.activate", .interface, gain: 0.3, priority: 2, cooldown: 0.08, maxVoices: 1, [
            SoundLayer(.triangle, a5, steps: [0, 7], stepTime: 0.05, envelope: Envelope(attack: 0.003, decay: 0.05, sustain: 0.6, release: 0.05),
                       duration: 0.14),
        ]),
        make("ui.back", .interface, gain: 0.25, priority: 2, cooldown: 0.08, maxVoices: 1, [
            SoundLayer(.sine, 990, to: 520, envelope: Envelope(attack: 0.003, decay: 0.08, sustain: 0.5, release: 0.05),
                       duration: 0.15),
        ]),
    ]

    // MARK: Music

    /// A minor, unhurried. Title and calm share a progression; a wave tightens it and adds a pulse;
    /// Blackout drops to a drone.
    static let musicStyle = MusicStyle(
        root: 57, // A3
        scale: [0, 2, 3, 5, 7, 8, 10],
        tempo: 84,
        gain: 0.5,
        moods: [
            .title: MoodProfile(progression: [0, 5, 2, 6], chordSeconds: 9, bellChance: 0.1, padCutoff: 900),
            .calm: MoodProfile(progression: [0, 5, 3, 4], chordSeconds: 8, bellChance: 0.14, padCutoff: 1000),
            .tension: MoodProfile(progression: [0, 5, 3, 4], chordSeconds: 5.7, bellChance: 0.22,
                                  pulse: [1, 0, 1, 1, 0, 1, 1, 0], padCutoff: 1300),
            .blackout: MoodProfile(progression: [0, 1], chordSeconds: 12, bellChance: 0.07, bellOctave: 1,
                                   drone: true, padCutoff: 800),
        ]
    )
}
