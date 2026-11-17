import Foundation


/// Sound design as data. A `SoundPatch` describes a short synthesised sound completely, in terms
/// that don't depend on any audio framework: oscillators, pitch sweeps, noise, envelopes and
/// filters. `SoundRenderer` turns one into samples; the app plays those. A theme owns its patches,
/// so a new theme can replace every sound without touching the game.

/// The basic tone of an oscillator.
public enum Waveform: String, Sendable, Equatable, CaseIterable {
    case sine
    case triangle
    /// Band-limited square.
    case square
    /// Band-limited sawtooth.
    case saw
    /// White noise (seeded, so a patch always renders the same).
    case noise
}

/// Which group a sound belongs to. Sounds in a family share a timbre, so the player can tell at
/// once whether something came from the ship, an enemy, a colonist or the game itself.
public enum SoundFamily: String, Sendable, Equatable, CaseIterable {
    /// The ship: clean, bright, tonal.
    case player
    /// Enemies: buzzy, detuned, noisy, lower.
    case enemy
    /// Colonists: soft sine chirps.
    case colonist
    /// Waves, Blackout, extra lives, outposts: chords and swells.
    case alert
    /// Menus.
    case interface
}

/// A menu action that makes a sound.
public enum MenuSound: String, Sendable, CaseIterable {
    /// The selection moved.
    case move
    /// An item was chosen.
    case activate
    /// Back out of a screen.
    case back
    /// An option's value changed.
    case change
}

/// Attack, decay, sustain and release, in seconds (sustain is a level, 0...1). The sustain lasts
/// for whatever is left of the layer's duration. Every envelope starts and ends at zero.
public struct Envelope: Sendable, Equatable {
    public var attack: Double
    public var decay: Double
    public var sustain: Double
    public var release: Double
    /// Bends the decay and release: 1 is linear, higher falls away faster at first.
    public var curve: Double

    public init(attack: Double, decay: Double = 0, sustain: Double = 1, release: Double, curve: Double = 2) {
        self.attack = attack
        self.decay = decay
        self.sustain = sustain
        self.release = release
        self.curve = curve
    }

    /// A sharp hit that dies away over `decay`.
    public static func pluck(_ decay: Double, attack: Double = 0.002) -> Envelope {
        Envelope(attack: attack, decay: decay, sustain: 0, release: 0.004, curve: 3)
    }
}

/// A resonant filter whose cutoff glides exponentially from `cutoff` to `endCutoff`.
public struct FilterSpec: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case lowPass, highPass, bandPass
    }

    public var kind: Kind
    public var cutoff: Double
    public var endCutoff: Double
    /// 0.5 is gentle; 5 rings.
    public var resonance: Double

    public init(_ kind: Kind, cutoff: Double, to endCutoff: Double? = nil, resonance: Double = 0.7) {
        self.kind = kind
        self.cutoff = cutoff
        self.endCutoff = endCutoff ?? cutoff
        self.resonance = resonance
    }
}

/// One oscillator (or noise source) with its own pitch movement, envelope and filter. A patch
/// sums its layers.
public struct SoundLayer: Sendable, Equatable {
    public var wave: Waveform
    /// Starting frequency in Hz (ignored for pure noise, which has none).
    public var frequency: Double
    /// Frequency at the end of the layer; the glide between is exponential.
    public var endFrequency: Double
    /// Semitone offsets played in turn, each for `stepTime` seconds (an arpeggio). Empty for a
    /// single note. The last step holds once the list runs out.
    public var steps: [Double]
    public var stepTime: Double
    /// Vibrato: rate in Hz and depth in semitones.
    public var vibratoRate: Double
    public var vibratoDepth: Double
    /// Tremolo: rate in Hz and depth 0...1.
    public var tremoloRate: Double
    public var tremoloDepth: Double
    /// White noise mixed into the oscillator, 0...1.
    public var noise: Double
    /// A second oscillator this many cents above the first, for thickness. 0 for none.
    public var detune: Double
    public var envelope: Envelope
    public var filter: FilterSpec?
    /// Seconds after the patch starts.
    public var delay: Double
    public var duration: Double
    public var gain: Double

    public init(_ wave: Waveform, _ frequency: Double, to endFrequency: Double? = nil,
                steps: [Double] = [], stepTime: Double = 0.08,
                vibrato: (rate: Double, depth: Double) = (0, 0), tremolo: (rate: Double, depth: Double) = (0, 0),
                noise: Double = 0, detune: Double = 0,
                envelope: Envelope, filter: FilterSpec? = nil,
                delay: Double = 0, duration: Double, gain: Double = 1) {
        self.wave = wave
        self.frequency = frequency
        self.endFrequency = endFrequency ?? frequency
        self.steps = steps
        self.stepTime = stepTime
        vibratoRate = vibrato.rate
        vibratoDepth = vibrato.depth
        tremoloRate = tremolo.rate
        tremoloDepth = tremolo.depth
        self.noise = noise
        self.detune = detune
        self.envelope = envelope
        self.filter = filter
        self.delay = delay
        self.duration = duration
        self.gain = gain
    }

    /// When the layer falls silent, in seconds from the start of the patch.
    public var end: Double { delay + duration }
}

/// A feedback echo after the layers are summed.
public struct Echo: Sendable, Equatable {
    public var time: Double
    /// 0...0.9: how much of each repeat comes back.
    public var feedback: Double
    /// 0...1: how loud the repeats are against the dry sound.
    public var mix: Double

    public init(time: Double, feedback: Double, mix: Double) {
        self.time = time
        self.feedback = feedback
        self.mix = mix
    }

    /// How long the repeats take to fall below about -40 dB of the dry sound.
    public var tail: Double {
        guard feedback > 0.001, mix > 0 else { return time }
        let repeats = ceil(log(0.01 / max(mix, 0.01)) / log(feedback))
        return time * max(repeats, 1)
    }
}

/// A complete synthesised sound and how the player should treat it.
public struct SoundPatch: Sendable, Equatable {
    /// A stable identifier, prefixed by the theme (e.g. "frontier.lance.fire").
    public var name: String
    public var family: SoundFamily
    public var layers: [SoundLayer]
    public var echo: Echo?
    /// Overall level, 0...1. The renderer never lets the peak pass `SoundRenderer.ceiling`.
    public var gain: Double
    /// Higher wins when voices run out: a big sound may cut off a small one, never the reverse.
    public var priority: Int
    /// The same patch is not started again sooner than this, in seconds.
    public var cooldown: Double
    /// At most this many copies of the patch sound at once; another one replaces the oldest.
    public var maxVoices: Int

    public init(name: String, family: SoundFamily, gain: Double, priority: Int = 1, cooldown: Double = 0.03,
                maxVoices: Int = 2, echo: Echo? = nil, layers: [SoundLayer]) {
        self.name = name
        self.family = family
        self.layers = layers
        self.echo = echo
        self.gain = gain
        self.priority = priority
        self.cooldown = cooldown
        self.maxVoices = maxVoices
    }

    /// A placeholder with no sound, for a theme that only names its patches.
    public init(name: String) {
        self.init(name: name, family: .alert, gain: 0, layers: [])
    }

    /// Length of the rendered sound in seconds, echo tail included.
    public var duration: Double {
        let dry = layers.map(\.end).max() ?? 0
        return dry + (echo.map { $0.tail } ?? 0)
    }
}
