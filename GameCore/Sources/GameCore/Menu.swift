/// A device-neutral menu: a heading, some lines of text and a list of items, one of which is
/// selected. Touch selects and activates an item directly; a gamepad moves the selection and then
/// activates it. Neither knows how the menu is drawn.
public struct Menu: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case title, pause, options, highScores, gameOver
    }

    public let kind: Kind
    public var heading: String
    /// A quieter line under the heading (the setting on the title, the mode on High scores).
    public var subtitle: String?
    /// Text shown under the heading: the score on the pause menu, the table on High scores.
    public var lines: [String]
    /// A table of rows and columns (the high scores), drawn beside or below the lines.
    public var table: MenuTable?
    public private(set) var items: [MenuItem]
    /// Index of the selected item. Always an enabled item, or nil when none is enabled.
    public private(set) var selection: Int?
    /// Commands to select first when the menu opens or its enabled items change, best first.
    /// When none of them is enabled the first enabled item is selected.
    public let preferredDefaults: [MenuItem.Command]

    public init(kind: Kind, heading: String, subtitle: String? = nil, lines: [String] = [], table: MenuTable? = nil,
                items: [MenuItem], preferredDefaults: [MenuItem.Command] = []) {
        self.kind = kind
        self.heading = heading
        self.subtitle = subtitle
        self.lines = lines
        self.table = table
        self.items = items
        self.preferredDefaults = preferredDefaults
        selection = Self.defaultSelection(items, preferredDefaults)
    }

    private static func defaultSelection(_ items: [MenuItem], _ preferred: [MenuItem.Command]) -> Int? {
        for command in preferred {
            if let index = items.firstIndex(where: { $0.command == command && $0.isEnabled }) { return index }
        }
        return items.firstIndex { $0.isEnabled }
    }

    public var selectedItem: MenuItem? {
        selection.map { items[$0] }
    }

    /// The detail lines to show for the selection: the selected item's, or when it has none (the
    /// selection is on Options, or nothing can be selected) those of the item that plays.
    public var detailLines: [String] {
        if let details = selectedItem?.details, !details.isEmpty { return details }
        return items.first { $0.command == .play }?.details ?? []
    }

    /// Moves the selection by `step` items, skipping disabled ones and wrapping at the ends.
    public mutating func moveSelection(by step: Int) {
        guard step != 0, items.contains(where: { $0.isEnabled }) else { return }
        var index = selection ?? (step > 0 ? -1 : items.count)
        let direction = step > 0 ? 1 : -1
        for _ in 0..<abs(step) {
            repeat {
                index = (index + direction + items.count) % items.count
            } while !items[index].isEnabled
        }
        selection = index
    }

    /// Selects an item. Refused (returns false) for a disabled item or a bad index.
    @discardableResult
    public mutating func select(_ index: Int) -> Bool {
        guard items.indices.contains(index), items[index].isEnabled else { return false }
        selection = index
        return true
    }

    /// Selects the item with `command`, if it is present and enabled.
    @discardableResult
    public mutating func select(_ command: MenuItem.Command) -> Bool {
        guard let index = items.firstIndex(where: { $0.command == command }) else { return false }
        return select(index)
    }

    /// Swaps in new items (labels, values or enabled states changed). The selection stays on the
    /// same command while the set of enabled commands is unchanged; when it changes (the phone
    /// opened and Resume became available) the selection goes back to the first enabled item.
    public mutating func replaceItems(_ newItems: [MenuItem]) {
        let enabledBefore = items.filter(\.isEnabled).map(\.command)
        let enabledAfter = newItems.filter(\.isEnabled).map(\.command)
        let previous = selectedItem?.command
        items = newItems
        if enabledBefore == enabledAfter, let previous,
           let index = items.firstIndex(where: { $0.command == previous && $0.isEnabled }) {
            selection = index
        } else {
            selection = Self.defaultSelection(items, preferredDefaults)
        }
    }
}

public struct MenuItem: Sendable, Equatable, Identifiable {
    public enum Command: Sendable, Hashable {
        case play, resume, startOver, endGame, options, highScores, back
        /// Leaves the game-over screen.
        case proceed
        case option(OptionKey)
        /// Switches to another mode and starts a run of it. (`play` starts the loaded mode.)
        case chooseMode(ModeID)
        /// Steps which mode's table the high-score screen shows.
        case scoresMode
    }

    public var id: Command { command }
    public let command: Command
    public var title: String
    /// Shown instead of the title while the item is disabled, e.g. "Open to resume".
    public var disabledTitle: String?
    /// The current setting, for an option row ("70%", "On").
    public var value: String?
    public var isEnabled: Bool
    /// True for an option that steps up and down (gamepad left and right, touch arrows).
    public var isAdjustable: Bool
    /// Lines describing the item, shown while it is selected (a mode's summary and best score).
    public var details: [String]

    public init(_ command: Command, _ title: String, disabledTitle: String? = nil, value: String? = nil,
                isEnabled: Bool = true, isAdjustable: Bool = false, details: [String] = []) {
        self.command = command
        self.title = title
        self.disabledTitle = disabledTitle
        self.value = value
        self.isEnabled = isEnabled
        self.isAdjustable = isAdjustable
        self.details = details
    }

    /// What to show on the item right now.
    public var label: String {
        isEnabled ? title : (disabledTitle ?? title)
    }
}

/// Rows of text in columns, with one row that can be picked out (the latest high score).
public struct MenuTable: Sendable, Equatable {
    public enum Alignment: Sendable, Equatable {
        case leading, trailing
    }

    public struct Column: Sendable, Equatable {
        public var title: String
        public var alignment: Alignment
        /// Columns with a higher priority are kept when the table is too narrow for them all.
        public var priority: Int

        public init(_ title: String, alignment: Alignment = .trailing, priority: Int = 1) {
            self.title = title
            self.alignment = alignment
            self.priority = priority
        }
    }

    public var columns: [Column]
    /// Each row has one string per column.
    public var rows: [[String]]
    public var highlightedRow: Int?

    public init(columns: [Column], rows: [[String]], highlightedRow: Int? = nil) {
        self.columns = columns
        self.rows = rows
        self.highlightedRow = highlightedRow
    }
}
