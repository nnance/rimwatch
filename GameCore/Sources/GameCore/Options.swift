/// Player options. The app stores them (UserDefaults) and reads them; this type only knows the
/// values and how each one steps.
public struct GameOptions: Sendable, Equatable, Codable {
    /// Which side of the screen the flight stick lives on. The buttons take the other side.
    public enum Handedness: String, Sendable, Codable, CaseIterable {
        case stickLeft, stickRight
    }

    /// Which face buttons do what on a gamepad. Fire is always the bottom button.
    public enum GamepadLayout: String, Sendable, Codable, CaseIterable {
        /// A fire, B Blink, X Shockwave.
        case standard
        /// A fire, X Blink, B Shockwave.
        case swapped
    }

    /// Volume steps, 0...volumeSteps.
    public static let volumeSteps = 10

    public var soundVolume = 8
    public var musicVolume = 6
    public var hapticsEnabled = true
    public var handedness = Handedness.stickLeft
    public var gamepadLayout = GamepadLayout.standard

    public init() {}

    /// Sound volume as 0...1.
    public var soundLevel: Double { Double(soundVolume) / Double(Self.volumeSteps) }
    /// Music volume as 0...1.
    public var musicLevel: Double { Double(musicVolume) / Double(Self.volumeSteps) }

    /// Steps an option. Volumes clamp at the ends unless `wrap` is set (a single tap cycles);
    /// on/off and choices always cycle.
    public mutating func adjust(_ key: OptionKey, by step: Int, wrap: Bool = false) {
        switch key {
        case .soundVolume: soundVolume = Self.stepVolume(soundVolume, by: step, wrap: wrap)
        case .musicVolume: musicVolume = Self.stepVolume(musicVolume, by: step, wrap: wrap)
        case .haptics: if step % 2 != 0 { hapticsEnabled.toggle() }
        case .handedness: handedness = Self.cycle(handedness, by: step)
        case .gamepadLayout: gamepadLayout = Self.cycle(gamepadLayout, by: step)
        }
    }

    public func title(of key: OptionKey) -> String {
        switch key {
        case .soundVolume: "Sound"
        case .musicVolume: "Music"
        case .haptics: "Haptics"
        case .handedness: "Stick side"
        case .gamepadLayout: "Gamepad"
        }
    }

    public func valueText(of key: OptionKey) -> String {
        switch key {
        case .soundVolume: "\(soundVolume * 100 / Self.volumeSteps)%"
        case .musicVolume: "\(musicVolume * 100 / Self.volumeSteps)%"
        case .haptics: hapticsEnabled ? "On" : "Off"
        case .handedness: handedness == .stickLeft ? "Left" : "Right"
        case .gamepadLayout: gamepadLayout == .standard ? "Standard" : "Swapped"
        }
    }

    private static func stepVolume(_ value: Int, by step: Int, wrap: Bool) -> Int {
        let next = value + step
        if wrap {
            let count = volumeSteps + 1
            return ((next % count) + count) % count
        }
        return min(max(next, 0), volumeSteps)
    }

    private static func cycle<T: CaseIterable & Equatable>(_ value: T, by step: Int) -> T {
        let all = Array(T.allCases)
        let index = all.firstIndex(of: value) ?? 0
        return all[((index + step) % all.count + all.count) % all.count]
    }

    // Missing keys (an older save) fall back to the defaults.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GameOptions()
        soundVolume = min(max(try c.decodeIfPresent(Int.self, forKey: .soundVolume) ?? defaults.soundVolume, 0),
                          Self.volumeSteps)
        musicVolume = min(max(try c.decodeIfPresent(Int.self, forKey: .musicVolume) ?? defaults.musicVolume, 0),
                          Self.volumeSteps)
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? defaults.hapticsEnabled
        handedness = (try? c.decodeIfPresent(Handedness.self, forKey: .handedness)) ?? defaults.handedness
        gamepadLayout = (try? c.decodeIfPresent(GamepadLayout.self, forKey: .gamepadLayout)) ?? defaults.gamepadLayout
    }
}

public enum OptionKey: Sendable, Hashable, CaseIterable {
    case soundVolume, musicVolume, haptics, handedness, gamepadLayout
}
