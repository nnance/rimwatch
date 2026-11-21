/// Names a game mode, for its saved high scores and for choosing it on the title screen.
public struct ModeID: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }
}

/// A mode as the shared screens list it.
public struct ModeDescriptor: Sendable, Equatable {
    public let id: ModeID
    public let displayName: String
    /// One short line the title screen shows while the mode is highlighted.
    public let summary: String

    public init(id: ModeID, displayName: String, summary: String = "") {
        self.id = id
        self.displayName = displayName
        self.summary = summary
    }
}

/// The modes the title screen offers in Free Play, which one is loaded, and the other modes'
/// high-score tables (the loaded mode's table is the front end's own).
public struct ModeCatalog: Sendable, Equatable {
    public var modes: [ModeDescriptor]
    public var loaded: ModeID
    /// High-score tables of the modes that are not loaded, for browsing on the high-score screen.
    public var tables: [ModeID: HighScoreTable]

    public init(modes: [ModeDescriptor], loaded: ModeID, tables: [ModeID: HighScoreTable] = [:]) {
        self.modes = modes
        self.loaded = loaded
        self.tables = tables
    }

    /// One unnamed mode whose title item reads "Play": a front end that is not choosing between
    /// modes (the package's own tests and tools).
    public init() {
        self.init(modes: [ModeDescriptor(id: "play", displayName: "Play")], loaded: "play")
    }

    /// True when the player can choose between modes.
    public var offersChoice: Bool { modes.count > 1 }

    public func descriptor(_ id: ModeID) -> ModeDescriptor? {
        modes.first { $0.id == id }
    }

    /// The mode to load at launch: the one asked for (a debug launch argument), else the one last
    /// played, else the first registered. A mode that is no longer registered is passed over.
    public static func launchMode(registered: [ModeID], remembered: ModeID?, requested: ModeID? = nil) -> ModeID? {
        if let requested, registered.contains(requested) { return requested }
        if let remembered, registered.contains(remembered) { return remembered }
        return registered.first
    }
}
