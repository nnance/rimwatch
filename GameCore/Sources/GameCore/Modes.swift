/// Names a game mode, for its saved high scores and (later) for choosing it.
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

    public init(id: ModeID, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}
