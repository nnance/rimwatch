import Foundation
import GameCore

/// Every mode the app can run. The only shell-level file that names a mode.
@MainActor
enum ModeRegistry {
    struct Entry {
        let descriptor: ModeDescriptor
        /// The shell's look while this mode runs.
        let style: ShellStyle
        /// Makes the mode's driver. The descriptors are every registered mode, for the title.
        let make: (ShellServices, ShellDevices, [ModeDescriptor]) -> any ModeDriver

        init<M: GameMode>(_: M.Type) {
            self.init(M.self, as: M.descriptor)
        }

        /// The mode listed under another id and name (DEBUG `-debugSecondMode`).
        private init<M: GameMode>(_: M.Type, as descriptor: ModeDescriptor) {
            self.descriptor = descriptor
            style = M.shellStyle
            make = { ModeHost<M>(descriptor: descriptor, modes: $2, services: $0, devices: $1) }
        }

        #if DEBUG
        /// Ridgeline again, under its own id, name and high-score table, so switching between
        /// modes can be tried before a second mode exists.
        static let debugSecondMode = Entry(RidgelineMode.self, as: ModeDescriptor(
            id: "ridgelineB", displayName: "Ridgeline B", summary: "A second copy, for testing mode switching",
            optionRows: RidgelineMode.descriptor.optionRows))
        #endif
    }

    static let all: [Entry] = {
        var entries = [Entry(RidgelineMode.self)]
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-debugSecondMode") { entries.append(.debugSecondMode) }
        #endif
        return entries
    }()

    /// The mode the app starts in: the one played last, or with the DEBUG `-mode <id>` launch
    /// argument that one.
    static var launch: Entry {
        var requested: ModeID?
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-mode"), arguments.indices.contains(flag + 1) {
            requested = ModeID(rawValue: arguments[flag + 1])
        }
        #endif
        let id = ModeCatalog.launchMode(registered: all.map(\.descriptor.id), remembered: Settings.shared.lastMode,
                                        requested: requested)
        return all.first { $0.descriptor.id == id } ?? all[0]
    }

    /// The mode that owns the high-score table saved before there were modes.
    static let legacyHighScoreOwner: ModeID = RidgelineMode.descriptor.id
}

extension Settings {
    /// The app's settings, with a high-score table for every mode.
    static let shared = Settings(modes: ModeRegistry.all.map(\.descriptor.id),
                                 legacyHighScoreOwner: ModeRegistry.legacyHighScoreOwner)
}
