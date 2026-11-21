import CoreHaptics
import Foundation
import GameCore
import UIKit

/// Plays `HapticCue`s on one Core Haptics engine: the phone's, or a game controller's.
///
/// The engine is started lazily and asynchronously, so nothing waits on it. If it can't be made or
/// started, cues are dropped quietly; if the system stops or resets it (backgrounding, an audio
/// interruption, the haptic server restarting) it is started again on the next cue.
final class CoreHapticPlayer {
    enum Device {
        case phone, controller
    }

    let device: Device
    private var engine: CHHapticEngine?
    private var isRunning = false
    private var isStarting = false
    /// Set when making or starting the engine failed for good; no more attempts.
    private var isBroken = false
    private var patterns: [HapticCue: CHHapticPattern] = [:]
    private var lastPlayed: [HapticCue: TimeInterval] = [:]
    private var observers: [NSObjectProtocol] = []

    /// The same cue no closer together than this, so a burst of hits stays a buzz, not a blur.
    private static let minimumGap: [HapticCue: TimeInterval] = [
        .tick: 0.05, .tap: 0.07, .doubleTap: 0.2, .warning: 0.15, .impact: 0.2, .sweep: 0.3, .rumble: 0.4,
    ]

    /// The phone's own engine, or nil when the hardware has no haptics (the simulator, an iPad).
    static func phone() -> CoreHapticPlayer? {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        return CoreHapticPlayer(device: .phone) { try CHHapticEngine() }
    }

    /// A controller's engine, made by `make` (from `GCDeviceHaptics.createEngine`). Nil if it
    /// makes none.
    static func controller(_ make: () -> CHHapticEngine?) -> CoreHapticPlayer? {
        guard let engine = make() else { return nil }
        return CoreHapticPlayer(device: .controller) { engine }
    }

    private init?(device: Device, make: () throws -> CHHapticEngine) {
        self.device = device
        guard let engine = try? make() else { return nil }
        self.engine = engine
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        // Both handlers are called on a Core Haptics queue.
        engine.stoppedHandler = { [weak self] _ in
            Task { @MainActor in self?.engineStopped() }
        }
        engine.resetHandler = { [weak self] in
            Task { @MainActor in self?.engineStopped() }
        }
        for cue in HapticCue.allCases {
            patterns[cue] = try? CHHapticPattern(events: Self.events(for: cue), parameterCurves: Self.curves(for: cue))
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        })
        startIfNeeded()
    }

    isolated deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        engine?.stop(completionHandler: nil)
    }

    /// Plays a cue. Returns false when it couldn't (engine broken or still starting).
    @discardableResult
    func play(_ cue: HapticCue) -> Bool {
        guard !isBroken, let engine, let pattern = patterns[cue] else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPlayed[cue], now - last < Self.minimumGap[cue, default: 0.05] { return true }
        guard isRunning else {
            // Played as soon as the engine is up, if that is soon.
            pending = (cue, now)
            startIfNeeded()
            return false
        }
        lastPlayed[cue] = now
        do {
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // The engine may have stopped under us; start it again for the next cue.
            isRunning = false
            startIfNeeded()
            return false
        }
        return true
    }

    /// Stops the engine (going to the background). The next cue starts it again.
    func stop() {
        guard let engine, isRunning || isStarting else { return }
        isRunning = false
        isStarting = false
        pending = nil
        // A start still in flight finishes after this; its completion must not mark it running.
        startGeneration &+= 1
        engine.stop(completionHandler: nil)
    }

    /// Bumped by `stop()`, so a start that completes afterwards is known to be stale.
    private var startGeneration = 0

    private func startIfNeeded() {
        guard let engine, !isRunning, !isStarting, !isBroken else { return }
        isStarting = true
        let generation = startGeneration
        engine.start { [weak self] error in
            Task { @MainActor in
                guard let self, generation == self.startGeneration else { return }
                self.isStarting = false
                if let error {
                    NSLog("[Rimwatch haptics] %@ engine failed to start: %@", "\(self.device)", "\(error)")
                    self.failures += 1
                    if self.failures >= 3 { self.isBroken = true }
                } else {
                    self.isRunning = true
                    self.failures = 0
                    if let (cue, asked) = self.pending, ProcessInfo.processInfo.systemUptime - asked < 0.15 {
                        self.play(cue)
                    }
                }
                self.pending = nil
            }
        }
    }

    private var failures = 0
    /// A cue asked for while the engine was starting.
    private var pending: (cue: HapticCue, at: TimeInterval)?

    private func engineStopped() {
        isRunning = false
        isStarting = false
    }

    // MARK: Patterns

    private static func transient(_ time: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time)
    }

    private static func continuous(_ time: TimeInterval, _ duration: TimeInterval, _ intensity: Float,
                                   _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time, duration: duration)
    }

    /// One short, distinct pattern per cue, from lightest to heaviest.
    static func events(for cue: HapticCue) -> [CHHapticEvent] {
        switch cue {
        case .tick:
            // A faint, crisp click.
            [transient(0, 0.32, 0.85)]
        case .tap:
            // A light knock: a kill, a catch.
            [transient(0, 0.55, 0.6)]
        case .doubleTap:
            // Two bright taps: a reward.
            [transient(0, 0.6, 0.75), transient(0.09, 0.75, 0.75)]
        case .warning:
            // A hard, sharp knock with a short buzz behind it.
            [transient(0, 0.85, 0.95), continuous(0.02, 0.09, 0.45, 0.9)]
        case .impact:
            // A heavy, dull thud that dies away.
            [transient(0, 1, 0.3), continuous(0, 0.22, 0.75, 0.2)]
        case .sweep:
            // A strong blast that swells, then sweeps out and fades: the Shockwave.
            [transient(0, 1, 0.7), continuous(0, 0.42, 1, 0.5)]
        case .rumble:
            // The heaviest: a deep, long rumble with a hit at the start (losing the ship).
            [transient(0, 1, 0.15), continuous(0, 0.75, 1, 0.08)]
        }
    }

    /// Envelopes for the continuous parts.
    static func curves(for cue: HapticCue) -> [CHHapticParameterCurve] {
        func curve(_ id: CHHapticDynamicParameter.ID, _ points: [(TimeInterval, Float)]) -> CHHapticParameterCurve {
            CHHapticParameterCurve(parameterID: id, controlPoints: points.map {
                CHHapticParameterCurve.ControlPoint(relativeTime: $0.0, value: $0.1)
            }, relativeTime: 0)
        }
        switch cue {
        case .tick, .tap, .doubleTap:
            return []
        case .warning:
            return [curve(.hapticIntensityControl, [(0, 1), (0.11, 0.2)])]
        case .impact:
            return [curve(.hapticIntensityControl, [(0, 1), (0.08, 0.6), (0.22, 0)])]
        case .sweep:
            return [
                // Starts at full strength so the opening blast isn't damped, dips, swells again
                // as the wave sweeps out, then fades.
                curve(.hapticIntensityControl, [(0, 1), (0.06, 0.75), (0.15, 1), (0.28, 0.6), (0.42, 0)]),
                curve(.hapticSharpnessControl, [(0, -0.3), (0.15, 0.3), (0.42, -0.4)]),
            ]
        case .rumble:
            return [curve(.hapticIntensityControl, [(0, 1), (0.3, 0.8), (0.75, 0)])]
        }
    }
}

/// Where a cue went, for the debug log.
struct HapticRoute: CustomStringConvertible {
    var device: String
    var note: String?

    var description: String { note.map { "\(device) (\($0))" } ?? device }
}

/// Sends cues to the controller's engine while a controller with haptics is connected, otherwise
/// to the phone. Either may be missing (the simulator has neither); cues then go nowhere.
final class HapticRouter: HapticOutput {
    private let phone: CoreHapticPlayer?
    /// The connected controller's player, if it has haptics.
    private var controllerPlayer: CoreHapticPlayer?
    /// A controller is connected, with or without haptics.
    private var hasController = false

    init(phone: CoreHapticPlayer? = CoreHapticPlayer.phone()) {
        self.phone = phone
    }

    /// The connected controller changed. `player` is its haptics, if it has any.
    func setController(connected: Bool, player: CoreHapticPlayer?) {
        controllerPlayer?.stop()
        hasController = connected
        controllerPlayer = connected ? player : nil
    }

    func play(_ cue: HapticCue) -> HapticRoute {
        if let controllerPlayer {
            controllerPlayer.play(cue)
            return HapticRoute(device: "controller")
        }
        if let phone {
            phone.play(cue)
            return HapticRoute(device: "phone", note: hasController ? "controller has no haptics" : nil)
        }
        let why = hasController ? "controller has no haptics, " : ""
        return HapticRoute(device: "none", note: why + "phone has no haptics hardware")
    }
}
