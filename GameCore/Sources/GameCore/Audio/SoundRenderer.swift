import Foundation

/// Turns a `SoundPatch` into mono samples. Pure Swift and deterministic: the same patch at the same
/// sample rate always gives the same samples (noise is seeded from the patch name), which is what
/// lets the sounds be tested without anyone listening.
public enum SoundRenderer {
    /// No rendered sample is louder than this.
    public static let ceiling = 0.98
    /// Fade applied at the very start and end, so a sound can never click on or off.
    static let fadeIn = 0.0008
    static let fadeOut = 0.004

    /// Renders a patch. The result is `patch.duration` long, peaks at `patch.gain` (capped at
    /// `ceiling`), and starts and ends at silence.
    public static func render(_ patch: SoundPatch, sampleRate: Double) -> [Float] {
        let count = max(Int((patch.duration * sampleRate).rounded()), 1)
        var mix = [Double](repeating: 0, count: count)
        var rng = SeededRNG(seed: stableHash(patch.name))
        for layer in patch.layers {
            renderLayer(layer, into: &mix, sampleRate: sampleRate, rng: &rng)
        }
        if let echo = patch.echo {
            applyEcho(echo, to: &mix, sampleRate: sampleRate)
        }
        removeDC(&mix)

        // Peak-normalise to the patch gain.
        let peak = mix.reduce(0) { max($0, abs($1)) }
        let target = min(max(patch.gain, 0), ceiling)
        let scale = peak > 1e-9 ? target / peak : 0
        let fadeInCount = max(Int(fadeIn * sampleRate), 1)
        let fadeOutCount = max(Int(fadeOut * sampleRate), 1)
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            var v = mix[i] * scale
            if i < fadeInCount { v *= Double(i) / Double(fadeInCount) }
            let fromEnd = count - 1 - i
            if fromEnd < fadeOutCount { v *= Double(fromEnd) / Double(fadeOutCount) }
            out[i] = Float(v)
        }
        return out
    }

    /// FNV-1a: a hash that is the same on every run (Swift's own `hashValue` is not).
    public static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    // MARK: Layers

    static func renderLayer(_ layer: SoundLayer, into mix: inout [Double], sampleRate: Double,
                            rng: inout SeededRNG) {
        let start = Int((layer.delay * sampleRate).rounded())
        let length = Int((layer.duration * sampleRate).rounded())
        guard length > 0, start < mix.count else { return }
        let dt = 1 / sampleRate
        var osc = Oscillator()
        var osc2 = Oscillator()
        var filter = StateVariableFilter()
        let detuneRatio = pow(2, layer.detune / 1200)
        let glide = layer.endFrequency / max(layer.frequency, 1)
        let cutoffGlide = layer.filter.map { $0.endCutoff / max($0.cutoff, 1) } ?? 1

        for n in 0..<length {
            let index = start + n
            guard index < mix.count else { break }
            let t = Double(n) * dt
            let progress = t / layer.duration
            var semitones = 0.0
            if !layer.steps.isEmpty {
                let step = min(Int(t / max(layer.stepTime, 0.001)), layer.steps.count - 1)
                semitones = layer.steps[step]
            }
            if layer.vibratoDepth > 0 {
                semitones += layer.vibratoDepth * sin(2 * .pi * layer.vibratoRate * t)
            }
            let frequency = layer.frequency * pow(glide, progress) * pow(2, semitones / 12)

            var sample: Double
            let white = rng.range(-1...1)
            if layer.wave == .noise {
                sample = white
            } else {
                sample = osc.next(layer.wave, increment: frequency * dt)
                if layer.detune != 0 {
                    sample = 0.5 * (sample + osc2.next(layer.wave, increment: frequency * detuneRatio * dt))
                }
                if layer.noise > 0 {
                    sample = sample * (1 - layer.noise) + white * layer.noise
                }
            }
            if let spec = layer.filter {
                let cutoff = spec.cutoff * pow(cutoffGlide, progress)
                sample = filter.process(sample, kind: spec.kind, cutoff: cutoff, resonance: spec.resonance,
                                        sampleRate: sampleRate)
            }
            var level = layer.envelope.level(at: t, duration: layer.duration) * layer.gain
            if layer.tremoloDepth > 0 {
                level *= 1 - layer.tremoloDepth * 0.5 * (1 - cos(2 * .pi * layer.tremoloRate * t))
            }
            mix[index] += sample * level
        }
    }

    static func applyEcho(_ echo: Echo, to mix: inout [Double], sampleRate: Double) {
        let delay = max(Int(echo.time * sampleRate), 1)
        var line = [Double](repeating: 0, count: delay)
        var position = 0
        for i in mix.indices {
            let delayed = line[position]
            let dry = mix[i]
            line[position] = dry + delayed * echo.feedback
            position = (position + 1) % delay
            mix[i] = dry + delayed * echo.mix
        }
    }

    /// A gentle high-pass (a few Hz) that keeps the output centred on zero.
    static func removeDC(_ mix: inout [Double]) {
        var lastIn = 0.0
        var lastOut = 0.0
        for i in mix.indices {
            let x = mix[i]
            let y = x - lastIn + 0.9992 * lastOut
            lastIn = x
            lastOut = y
            mix[i] = y
        }
    }
}

extension Envelope {
    /// Level at `t` seconds into a note lasting `duration`. Zero before the start and at the end.
    public func level(at t: Double, duration: Double) -> Double {
        guard t >= 0, t < duration else { return 0 }
        let attack = max(self.attack, 0.0005)
        var v: Double
        if t < attack {
            v = t / attack
        } else if t < attack + decay {
            let x = (t - attack) / decay
            v = sustain + (1 - sustain) * pow(1 - x, curve)
        } else {
            v = sustain
        }
        let release = min(max(self.release, 0.0005), duration)
        let releaseStart = duration - release
        if t > releaseStart {
            let x = (t - releaseStart) / release
            v *= pow(1 - x, curve)
        }
        return v
    }
}

/// A phase-accumulating oscillator. Square and saw use PolyBLEP to keep aliasing down.
struct Oscillator {
    var phase = 0.0

    mutating func next(_ wave: Waveform, increment: Double) -> Double {
        let dt = min(max(increment, 0), 0.5)
        let p = phase
        phase += dt
        if phase >= 1 { phase -= 1 }
        switch wave {
        case .sine:
            return sin(2 * .pi * p)
        case .triangle:
            return 1 - 4 * abs(p - 0.5)
        case .saw:
            return (2 * p - 1) - Self.blep(p, dt)
        case .square:
            var v = p < 0.5 ? 1.0 : -1.0
            v += Self.blep(p, dt)
            var q = p + 0.5
            if q >= 1 { q -= 1 }
            v -= Self.blep(q, dt)
            return v
        case .noise:
            return 0
        }
    }

    private static func blep(_ t: Double, _ dt: Double) -> Double {
        guard dt > 0 else { return 0 }
        if t < dt {
            let x = t / dt
            return x + x - x * x - 1
        }
        if t > 1 - dt {
            let x = (t - 1) / dt
            return x * x + x + x + 1
        }
        return 0
    }
}

/// A trapezoidal state-variable filter (stable when its cutoff moves every sample).
struct StateVariableFilter {
    private var ic1 = 0.0
    private var ic2 = 0.0

    mutating func process(_ input: Double, kind: FilterSpec.Kind, cutoff: Double, resonance: Double,
                          sampleRate: Double) -> Double {
        let fc = min(max(cutoff, 10), sampleRate * 0.45)
        let g = tan(.pi * fc / sampleRate)
        let k = 1 / max(resonance, 0.3)
        let a1 = 1 / (1 + g * (g + k))
        let a2 = g * a1
        let a3 = g * a2
        let v3 = input - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        switch kind {
        case .lowPass: return v2
        case .bandPass: return v1 * k
        case .highPass: return input - k * v1 - v2
        }
    }
}
