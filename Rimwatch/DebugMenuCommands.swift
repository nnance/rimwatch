#if DEBUG
import Foundation

/// DEBUG only: drives menus from the command line through the same device-neutral calls a gamepad
/// will use, so menu flows can be checked on a simulator without synthesised touches:
///
///     xcrun simctl spawn <udid> notifyutil -p com.rimwatch.debug.menu.down
///
/// Commands: up, down, left, right, activate, back, pause.
@MainActor
enum DebugMenuCommands {
    enum Command: String, CaseIterable {
        case up, down, left, right, activate, back, pause
    }

    static let prefix = "com.rimwatch.debug.menu."
    private static var handler: ((Command) -> Void)?

    static func listen(_ onCommand: @escaping (Command) -> Void) {
        let first = handler == nil
        handler = onCommand
        guard first else { return }
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for command in Command.allCases {
            CFNotificationCenterAddObserver(center, nil, debugMenuNotificationCallback,
                                            (prefix + command.rawValue) as CFString, nil, .deliverImmediately)
        }
    }

    fileprivate static func receive(_ name: String) {
        guard name.hasPrefix(prefix), let command = Command(rawValue: String(name.dropFirst(prefix.count))) else {
            return
        }
        NSLog("[Rimwatch debug] menu command %@", command.rawValue)
        handler?(command)
    }
}

nonisolated private func debugMenuNotificationCallback(
    _ center: CFNotificationCenter?, _ observer: UnsafeMutableRawPointer?, _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?, _ userInfo: CFDictionary?
) {
    guard let name = name?.rawValue as String? else { return }
    DispatchQueue.main.async {
        MainActor.assumeIsolated { DebugMenuCommands.receive(name) }
    }
}
#endif
