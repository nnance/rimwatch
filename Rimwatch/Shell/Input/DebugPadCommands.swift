#if DEBUG
import Foundation
import GameCore

/// DEBUG only: a simulated game controller driven by Darwin notifications, for checking gamepad
/// play and menus on a simulator with no controller attached. It feeds `GamepadInput` exactly
/// as a real controller's handlers do (same `PadSnapshot` path, same connect and disconnect).
///
///     xcrun simctl spawn <udid> notifyutil -p com.rimwatch.debug.pad.connect
///
/// Names, after `com.rimwatch.debug.pad.`:
/// - `connect`, `disconnect`
/// - `stick.left|right|up|down|center` (full deflection), `stick.upleft|upright|downleft|downright`,
///   `stick.nudge` (a small push to the right, inside the dead zone)
/// - `dpad.left|right|up|down|center`
/// - `stick.tap.left|right|up|down`, `dpad.tap.left|right|up|down`: pushed and let go at once (a
///   single menu step; notifications arrive too slowly to time a hold shorter than the repeat)
/// - `a.down|up|press`, `b.down|up|press`, `x.down|up|press`, `y.down|up|press` (press = down and
///   up at once, a tap shorter than a frame)
/// - `menu` (a press), `menu.down|up`
/// - `rstick.left|right|up|down|center|upleft|upright|downleft|downright`: the right stick (full
///   deflection), for a mode that aims with it
/// - `lshoulder.down|up|press`, `rshoulder.down|up|press`, `ltrigger.down|up|press`,
///   `rtrigger.down|up|press`: shoulder buttons and triggers
/// - `release` (everything back to neutral)
@MainActor
enum DebugPadCommands {
    static let prefix = "com.rimwatch.debug.pad."
    private static weak var target: GamepadInput?
    private static var isListening = false

    static var names: [String] {
        var names = ["connect", "disconnect", "release", "menu", "menu.down", "menu.up", "stick.nudge"]
        for direction in ["left", "right", "up", "down", "center"] {
            names += ["stick.\(direction)", "dpad.\(direction)"]
        }
        names += ["stick.upleft", "stick.upright", "stick.downleft", "stick.downright"]
        for direction in ["left", "right", "up", "down", "center", "upleft", "upright", "downleft", "downright"] {
            names.append("rstick.\(direction)")
        }
        for direction in ["left", "right", "up", "down"] {
            names += ["stick.tap.\(direction)", "dpad.tap.\(direction)"]
        }
        for button in ["a", "b", "x", "y", "lshoulder", "rshoulder", "ltrigger", "rtrigger"] {
            names += ["\(button).down", "\(button).up", "\(button).press"]
        }
        return names
    }

    static func listen(_ gamepad: GamepadInput) {
        target = gamepad
        guard !isListening else { return }
        isListening = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for name in names {
            CFNotificationCenterAddObserver(center, nil, debugPadNotificationCallback,
                                            (prefix + name) as CFString, nil, .deliverImmediately)
        }
    }

    fileprivate static func receive(_ fullName: String) {
        guard fullName.hasPrefix(prefix), let pad = target else { return }
        let name = String(fullName.dropFirst(prefix.count))
        NSLog("[Rimwatch debug] pad %@", name)
        let parts = name.split(separator: ".").map(String.init)
        switch parts.first {
        case "connect":
            pad.simulatedConnect()
        case "disconnect":
            pad.simulatedDisconnect()
        case "release":
            pad.simulated { $0 = .neutral }
        case "stick" where parts.count == 3 && parts[1] == "tap":
            guard let v = direction(parts[2]) else { return }
            pad.simulated { $0.stick = v }
            pad.simulated { $0.stick = .zero }
        case "dpad" where parts.count == 3 && parts[1] == "tap":
            guard let v = direction(parts[2]) else { return }
            pad.simulated { $0.dpad = v }
            pad.simulated { $0.dpad = .zero }
        case "stick":
            guard parts.count == 2 else { return }
            if parts[1] == "nudge" {
                pad.simulated { $0.stick = Vec2(0.12, 0) }
            } else if let v = direction(parts[1]) {
                pad.simulated { $0.stick = v.clampedToUnit }
            }
        case "dpad":
            guard parts.count == 2, let v = direction(parts[1]) else { return }
            pad.simulated { $0.dpad = v }
        case "rstick":
            guard parts.count == 2, let v = direction(parts[1]) else { return }
            pad.simulated { $0.rightStick = v.clampedToUnit }
        case "menu":
            press(pad, .menu, parts.count == 2 ? parts[1] : "press")
        default:
            guard parts.count == 2, let first = parts.first, let button = PadButton(rawValue: first) else { return }
            press(pad, button, parts[1])
        }
    }

    private static func press(_ pad: GamepadInput, _ button: PadButton, _ action: String) {
        switch action {
        case "down":
            pad.simulated { $0.buttons.insert(button) }
        case "up":
            pad.simulated { $0.buttons.remove(button) }
        case "press":
            pad.simulated { $0.buttons.insert(button) }
            pad.simulated { $0.buttons.remove(button) }
        default:
            break
        }
    }

    private static func direction(_ text: String) -> Vec2? {
        switch text {
        case "left": Vec2(-1, 0)
        case "right": Vec2(1, 0)
        case "up": Vec2(0, 1)
        case "down": Vec2(0, -1)
        case "center": .zero
        case "upleft": Vec2(-1, 1)
        case "upright": Vec2(1, 1)
        case "downleft": Vec2(-1, -1)
        case "downright": Vec2(1, -1)
        default: nil
        }
    }
}

nonisolated private func debugPadNotificationCallback(
    _ center: CFNotificationCenter?, _ observer: UnsafeMutableRawPointer?, _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?, _ userInfo: CFDictionary?
) {
    guard let name = name?.rawValue as String? else { return }
    DispatchQueue.main.async {
        MainActor.assumeIsolated { DebugPadCommands.receive(name) }
    }
}
#endif
