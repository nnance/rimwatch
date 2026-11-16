import Foundation
import GameCore
import UIKit

/// Turns the hinge into a `FoldPose` (open / closed / no hinge) and reports changes.
///
/// The pose normally comes from UIKit's hinge API (`UIHingeInteraction`, iOS 27.1). DEBUG builds
/// can override it, because no simulator here can be folded from the command line:
///
/// - launch argument `-hinge open|closed|none` sets the starting pose;
/// - Darwin notifications `com.rimwatch.debug.hinge.open`, `.closed` and `.none` switch it at run
///   time, e.g. `xcrun simctl spawn <udid> notifyutil -p com.rimwatch.debug.hinge.closed`.
///
/// Once overridden, readings from the real hinge are ignored for the rest of the run.
@MainActor
final class FoldGate {
    /// What one hinge source last said.
    enum Reading: Equatable {
        case status(UIHinge.Status)
        /// The view's hierarchy provides no hinge (a phone without one).
        case unavailable
    }

    /// The current pose, or nil until the first reading arrives.
    private(set) var pose: FoldPose?
    /// True while the DEBUG override, not the real hinge, decides the pose.
    private(set) var isOverridden = false
    /// Called on the main actor whenever `pose` changes.
    var onChange: ((FoldPose) -> Void)?

    /// How long to wait for the real hinge API before deciding there is no hinge.
    private static let noReadingTimeout: TimeInterval = 1.0
    private var interaction: UIHingeInteraction?
    private var fallbackTimer: Timer?
    /// True once the real hinge API has reported any status.
    private var hasSeenHinge = false

    init() {
        #if DEBUG
        if let initial = DebugHingeOverride.launchPose() {
            isOverridden = true
            pose = initial
            log("override from launch argument: \(initial)")
        }
        DebugHingeOverride.listen { [weak self] pose in
            self?.applyOverride(pose)
        }
        #endif
    }

    /// Starts following the real hinge through an interaction on `view`, which should be the
    /// window's root view.
    func start(observing view: UIView) {
        guard interaction == nil else { return }
        let interaction = UIHingeInteraction { [weak self] _, update in
            let reading: Reading = update.hinge.map { .status($0.status) } ?? .unavailable
            let detail = update.hinge.map {
                "status \(Self.name(of: $0.status)) (raw \($0.status.rawValue)), angle \(String(format: "%.3f", $0.angle)) rad"
            } ?? "hinge nil"
            self?.log("UIHingeInteraction update: \(detail)")
            self?.receive(reading)
        }
        view.addInteraction(interaction)
        self.interaction = interaction

        // A phone without a hinge may never call the handler at all.
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: Self.noReadingTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.pose == nil else { return }
                self.log("no hinge reading after \(Self.noReadingTimeout) s: treating as no hinge")
                self.set(.noHinge)
            }
        }
    }

    /// Maps a hinge reading to a pose. Returns nil when the reading says nothing new.
    static func pose(for reading: Reading, previous: FoldPose?) -> FoldPose? {
        switch reading {
        case .unavailable:
            return .noHinge
        case .status(let status):
            switch status {
            case .fullyOpen, .partiallyOpen: return .open
            case .closed: return .closed
            // There is a hinge but its state is not known yet. Keep an open or closed pose we
            // already had; otherwise (nothing yet, or the no-hinge timeout fired first) assume
            // closed, so gameplay never starts on the wrong display and a phone that has a hinge
            // is never treated as one without.
            case .unknown: return Self.keepingHingedPose(previous)
            @unknown default: return Self.keepingHingedPose(previous)
            }
        }
    }

    private static func keepingHingedPose(_ previous: FoldPose?) -> FoldPose {
        switch previous {
        case .open: .open
        case .closed: .closed
        case .noHinge, nil: .closed
        }
    }

    static func name(of status: UIHinge.Status) -> String {
        switch status {
        case .unknown: "unknown"
        case .closed: "closed"
        case .partiallyOpen: "partiallyOpen"
        case .fullyOpen: "fullyOpen"
        @unknown default: "future case"
        }
    }

    private func receive(_ reading: Reading) {
        guard !isOverridden else { return }
        if case .status = reading {
            hasSeenHinge = true
        } else if hasSeenHinge {
            // A phone that has reported a hinge keeps it; a missing hinge in a later update is
            // a transient, not a reason to show the made-for-Duo screen.
            return
        }
        guard let next = Self.pose(for: reading, previous: pose) else { return }
        set(next)
    }

    private func applyOverride(_ next: FoldPose) {
        isOverridden = true
        log("override from notification: \(next)")
        set(next, force: true)
    }

    private func set(_ next: FoldPose, force: Bool = false) {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        guard next != pose || force else { return }
        pose = next
        onChange?(next)
    }

    private func log(_ message: String) {
        NSLog("[Rimwatch fold] %@", message)
    }
}

#if DEBUG
/// The DEBUG-only stand-in for a hinge. Compiled out of release builds.
@MainActor
enum DebugHingeOverride {
    static let notificationPrefix = "com.rimwatch.debug.hinge."
    private static let names = ["open", "closed", "none"]
    private static var handler: ((FoldPose) -> Void)?

    /// The pose from `-hinge open|closed|none`, if given.
    static func launchPose() -> FoldPose? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-hinge"), index + 1 < args.count else { return nil }
        return pose(named: args[index + 1])
    }

    static func pose(named name: String) -> FoldPose? {
        switch name.lowercased() {
        case "open": .open
        case "closed": .closed
        case "none": .noHinge
        default: nil
        }
    }

    /// Registers for the three Darwin notifications. `onPose` runs on the main actor.
    static func listen(_ onPose: @escaping (FoldPose) -> Void) {
        let first = handler == nil
        handler = onPose
        guard first else { return }
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for name in names {
            CFNotificationCenterAddObserver(center, nil, debugHingeNotificationCallback,
                                            (notificationPrefix + name) as CFString, nil, .deliverImmediately)
        }
    }

    fileprivate static func receive(_ fullName: String) {
        guard fullName.hasPrefix(notificationPrefix),
              let pose = pose(named: String(fullName.dropFirst(notificationPrefix.count))) else { return }
        handler?(pose)
    }
}

/// Darwin notifications arrive on an arbitrary thread through a C callback.
nonisolated private func debugHingeNotificationCallback(
    _ center: CFNotificationCenter?, _ observer: UnsafeMutableRawPointer?, _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?, _ userInfo: CFDictionary?
) {
    guard let name = name?.rawValue as String? else { return }
    DispatchQueue.main.async {
        MainActor.assumeIsolated { DebugHingeOverride.receive(name) }
    }
}
#endif
