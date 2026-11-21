import Foundation

/// The screens of the shared flow.
public enum FlowScreen: Sendable, Equatable {
    /// Running on a phone without a hinge.
    case madeForDuo
    case title
    case playing
    case countdown(remaining: Double)
    /// The pause menu.
    case paused
    case gameOver(score: Int)
    case options
    case highScores
}

/// Things the app must act on after a front-end call.
public enum FlowEffect: Sendable, Equatable {
    /// A new run replaced the old one (new world, clear old nodes).
    case newRun
    case optionsChanged
    case highScoresChanged
    /// The player chose another mode on the title: load it, then start a run of it there.
    case switchMode(ModeID)
}

/// What a menu command did.
public struct FlowCommandResult: Sendable, Equatable {
    /// False when the command was ignored (nothing to move to, held back by the activation
    /// grace, nothing to go back to). Only accepted commands should be confirmed with a sound
    /// or a haptic.
    public var accepted: Bool
    public var effects: [FlowEffect]

    public init(accepted: Bool, effects: [FlowEffect] = []) {
        self.accepted = accepted
        self.effects = effects
    }

    public static let ignored = FlowCommandResult(accepted: false)
}

/// Everything around a run: which screen shows, the menus, options and high scores. It drives a
/// `ModeSession` (never the run itself) and is told about the fold pose and app focus. The app
/// draws whatever `screen` and `menu` say and forwards touches and gamepad presses here.
public struct ModeFrontEnd<Run: ModeRun>: Sendable {
    public typealias Screen = FlowScreen
    public typealias Effect = FlowEffect
    public typealias CommandResult = FlowCommandResult

    @usableFromInline
    enum Overlay: Sendable, Equatable {
        case options, highScores
    }

    public package(set) var session: ModeSession<Run> {
        @inlinable get { _session }
        set { _session = newValue }
    }
    /// Storage behind `session` and `screenTime`, so `update` can be `@inlinable` and specialised
    /// for each mode's run (see `ModeSession`).
    @usableFromInline var _session: ModeSession<Run>
    @usableFromInline var _screenTime = 0.0
    public private(set) var pose: FoldPose
    public private(set) var options: GameOptions
    /// The loaded mode's high scores.
    public private(set) var highScores: HighScoreTable
    /// The modes on the title screen and the other modes' tables.
    public private(set) var catalog: ModeCatalog
    /// The mode whose table the high-score screen shows.
    public private(set) var scoresShown: ModeID
    /// The menu on screen, or nil while playing, counting down or on the Made for iPhone Duo screen.
    public private(set) var menu: Menu?
    /// Where the last recorded run placed in the table (0 is the top), or nil if it didn't place.
    public private(set) var lastRank: Int?

    @usableFromInline var overlay: Overlay?

    /// How long a screen must have been showing before a gamepad press activates or backs out
    /// of it, so a player still pressing fire when a menu appears doesn't choose something.
    public static var activationGrace: Double { 0.35 }
    /// The game-over screen's longer hold-off: the summary stays up through a burst of fire
    /// presses at the moment of death, and Continue is dimmed until it is live.
    public static var gameOverGrace: Double { 1.2 }

    /// The activation grace of a screen.
    @inlinable
    public static func activationGrace(for screen: Screen) -> Double {
        if case .gameOver = screen { return gameOverGrace }
        return activationGrace
    }

    /// The current screen has shown long enough for an activation (by pad, or on game over by
    /// touch too).
    @inlinable
    public var isActivationLive: Bool {
        screenTime >= Self.activationGrace(for: screen)
    }
    /// Changes each time the screen changes (the countdown's ticking aside). Input sources use it
    /// to drop presses made on the previous screen.
    public private(set) var screenID = 0
    /// Seconds the current screen has been showing.
    @inlinable public var screenTime: Double { _screenTime }
    /// The pause menu on show appeared without the player asking (the phone closed, the app lost
    /// focus, the controller went away).
    public private(set) var isUnrequestedPause = false
    private var screenKey = ""

    public init(session: ModeSession<Run>, pose: FoldPose, options: GameOptions = GameOptions(),
                highScores: HighScoreTable = HighScoreTable(), catalog: ModeCatalog = ModeCatalog()) {
        _session = session
        self.pose = pose
        self.options = options
        self.highScores = highScores
        self.catalog = catalog
        scoresShown = catalog.loaded
        _session.setPlayfieldAvailable(pose.isPlayfieldAvailable)
        refreshMenu()
        screenKey = Self.key(of: screen)
    }

    @inlinable
    public var screen: Screen {
        if pose == .noHinge { return .madeForDuo }
        switch overlay {
        case .options: return .options
        case .highScores: return .highScores
        case nil: break
        }
        switch _session.phase {
        case .title: return .title
        case .playing: return .playing
        case .countdown(let remaining): return .countdown(remaining: remaining)
        case .paused: return .paused
        case .gameOver(let score): return .gameOver(score: score)
        }
    }

    // MARK: Things that happen to the app

    /// The phone was opened, closed or turned out to have no hinge. Closing pauses at once.
    public mutating func setPose(_ newPose: FoldPose) {
        let wasInPlay = isInPlay
        pose = newPose
        _session.setPlayfieldAvailable(newPose.isPlayfieldAvailable)
        refreshMenu()
        noteScreen(unrequestedPause: wasInPlay && screen == .paused)
    }

    /// The app is losing focus or going to the background: pause like a fold. Coming back shows
    /// the pause menu; nothing resumes by itself.
    public mutating func appWillResignActive() {
        let wasInPlay = isInPlay
        _session.pause()
        refreshMenu()
        noteScreen(unrequestedPause: wasInPlay)
    }

    /// The pause button (or a gamepad's menu button) during play or the countdown.
    public mutating func requestPause() {
        _session.pause()
        refreshMenu()
        noteScreen()
    }

    /// Advances the game by real time. Records the score when a run ends in game over.
    @inlinable
    public mutating func update(elapsed: Double, input: Run.Input) -> (events: [Run.Event], effects: [Effect]) {
        let wasInGame = _session.isInGame
        let wasCountingDown = isCountingDown
        let events = _session.update(elapsed: elapsed, input: input)
        var effects: [Effect] = []
        if wasInGame, case .gameOver(let score) = _session.phase {
            effects += record(score: score)
            refreshMenu()
        } else if wasCountingDown != isCountingDown {
            refreshMenu()
        }
        if !noteScreen() {
            let wasLive = isActivationLive
            _screenTime += elapsed
            // Continue lights up when the game-over hold-off ends.
            if !wasLive, isActivationLive, case .gameOver = screen { refreshMenu() }
        }
        return (events, effects)
    }

    // MARK: Menu input

    /// A device-neutral menu command (gamepad, debug notifications). Up and down move the
    /// selection, left and right step an option, activate and back act once the screen's
    /// activation grace has passed. Pause pauses during play or the countdown, and resumes from
    /// the pause menu when Resume is allowed; elsewhere it does nothing.
    @discardableResult
    public mutating func handle(_ command: MenuCommand) -> CommandResult {
        switch command {
        case .up, .down:
            let before = menu?.selection
            moveSelection(by: command == .up ? -1 : 1)
            return CommandResult(accepted: menu?.selection != before)
        case .left, .right:
            let step = command == .left ? -1 : 1
            // With several modes, left and right page through their tables wherever the selection is.
            if screen == .highScores, catalog.offersChoice {
                return CommandResult(accepted: true, effects: perform(.scoresMode, step: step, wrap: true))
            }
            let before = options
            let effects = adjust(by: step)
            return CommandResult(accepted: options != before, effects: effects)
        case .activate:
            guard isActivationLive, menu?.selectedItem != nil else { return .ignored }
            return CommandResult(accepted: true, effects: activate())
        case .back:
            guard isActivationLive, back() else { return .ignored }
            return CommandResult(accepted: true)
        case .pause:
            switch screen {
            case .playing, .countdown:
                requestPause()
                return CommandResult(accepted: true)
            case .paused where _session.canResume:
                return CommandResult(accepted: true, effects: perform(.resume))
            default:
                return .ignored
            }
        }
    }

    /// The game controller went away. During play or the countdown the player has lost their
    /// controls, so the game pauses.
    public mutating func controllerDisconnected() {
        guard isInPlay else { return }
        _session.pause()
        refreshMenu()
        noteScreen(unrequestedPause: true)
    }

    /// Whether a touch may activate an item now. On game over, and on a pause menu the player
    /// didn't ask for, a touch inside the screen's activation grace is ignored: the thumb was
    /// probably still on a fire button.
    public var acceptsTouchActivation: Bool {
        switch screen {
        case .gameOver: return isActivationLive
        case .paused: return !isUnrequestedPause || isActivationLive
        default: return true
        }
    }

    public mutating func moveSelection(by step: Int) {
        menu?.moveSelection(by: step)
    }

    /// Selects item `index` without acting on it (a touch on an option row's label). Returns
    /// false for a disabled item or a bad index.
    @discardableResult
    public mutating func select(_ index: Int) -> Bool {
        menu?.select(index) ?? false
    }

    /// Activates the selected item (gamepad A, Return). An option steps forward and wraps.
    @discardableResult
    public mutating func activate() -> [Effect] {
        guard let item = menu?.selectedItem else { return [] }
        return perform(item.command, step: 1, wrap: true)
    }

    /// Steps the selected option down or up (gamepad left and right). Does nothing on other items.
    @discardableResult
    public mutating func adjust(by step: Int) -> [Effect] {
        guard let item = menu?.selectedItem, item.isAdjustable else { return [] }
        return perform(item.command, step: step, wrap: false)
    }

    /// A touch on item `index`: selects it and acts. `step` is -1 for a touch on an option's
    /// down arrow. A disabled item ignores the touch, and so does any item while
    /// `acceptsTouchActivation` is false.
    @discardableResult
    public mutating func choose(_ index: Int, step: Int = 1) -> [Effect] {
        guard acceptsTouchActivation, menu?.select(index) == true, let item = menu?.selectedItem else { return [] }
        return perform(item.command, step: step, wrap: step > 0)
    }

    /// Back out of Options or High scores (gamepad B). Returns true if something closed.
    @discardableResult
    public mutating func back() -> Bool {
        guard overlay != nil else { return false }
        overlay = nil
        refreshMenu()
        noteScreen()
        return true
    }

    @discardableResult
    public mutating func perform(_ command: MenuItem.Command, step: Int = 1, wrap: Bool = true) -> [Effect] {
        var effects: [Effect] = []
        switch command {
        case .play:
            if _session.startGame() {
                lastRank = nil
                effects.append(.newRun)
            }
        case .chooseMode(let id):
            if id == catalog.loaded {
                return perform(.play)
            }
            // Another mode starts the same way Play would: only from the title or game over, and
            // only with the playfield there. The app loads it and starts the run.
            if catalog.descriptor(id) != nil, _session.isPlayfieldAvailable, !_session.isInGame {
                effects.append(.switchMode(id))
            }
        case .scoresMode:
            // Like the other choices, it always wraps.
            let ids = catalog.modes.map(\.id)
            if let index = ids.firstIndex(of: scoresShown) {
                let next = index + step
                scoresShown = ids[((next % ids.count) + ids.count) % ids.count]
            } else {
                scoresShown = catalog.loaded
            }
        case .resume:
            _session.resume()
        case .startOver:
            guard _session.isInGame else { break }
            _session.startOver()
            effects.append(.newRun)
        case .endGame:
            if _session.isInGame, let score = _session.endGame() {
                effects += record(score: score)
            }
        case .proceed:
            if case .gameOver = _session.phase { _session.endGame() }
        case .options:
            overlay = .options
        case .highScores:
            overlay = .highScores
            scoresShown = catalog.loaded
        case .back:
            overlay = nil
        case .option(let key):
            options.adjust(key, by: step, wrap: wrap)
            effects.append(.optionsChanged)
        }
        refreshMenu()
        noteScreen()
        return effects
    }

    // MARK: Private

    private var isInPlay: Bool {
        switch screen {
        case .playing, .countdown: true
        default: false
        }
    }

    private static func key(of screen: Screen) -> String {
        if case .countdown = screen { return "countdown" }
        return "\(screen)"
    }

    /// Restarts the screen clock when the screen changed, or when a pause was forced on the
    /// player. Returns true if it restarted.
    @discardableResult
    @usableFromInline
    mutating func noteScreen(unrequestedPause: Bool = false) -> Bool {
        let key = Self.key(of: screen)
        guard key != screenKey || unrequestedPause else { return false }
        screenKey = key
        screenID &+= 1
        _screenTime = 0
        isUnrequestedPause = unrequestedPause && screen == .paused
        return true
    }

    @usableFromInline
    var isCountingDown: Bool {
        if case .countdown = _session.phase { true } else { false }
    }

    @usableFromInline
    mutating func record(score: Int) -> [Effect] {
        let result = _session.run.result
        lastRank = highScores.insert(HighScoreEntry(score: score, wave: max(result.wave, 1), date: Date(),
                                                    saved: result.saved))
        return lastRank == nil ? [] : [.highScoresChanged]
    }

    /// Rebuilds the menu for the current screen. Keeps the selection when the screen is the same.
    @usableFromInline
    mutating func refreshMenu() {
        // A screen that is only now appearing has not served its grace yet.
        let live = Self.key(of: screen) == screenKey && isActivationLive
        guard let fresh = Self.menu(for: screen, session: _session, pose: pose, options: options,
                                    highScores: highScores, lastRank: lastRank, gameOverLive: live,
                                    catalog: catalog, scoresShown: scoresShown) else {
            menu = nil
            return
        }
        if var current = menu, current.kind == fresh.kind {
            current.heading = fresh.heading
            current.subtitle = fresh.subtitle
            current.lines = fresh.lines
            current.table = fresh.table
            current.replaceItems(fresh.items)
            menu = current
        } else {
            menu = fresh
        }
    }

    /// The high scores as a table: rank, score, wave, colonists saved and date. The most recent
    /// entry is highlighted. Narrow screens drop the lower-priority columns first.
    public static func highScoreTable(_ table: HighScoreTable, timeZone: TimeZone = .current) -> MenuTable {
        MenuTable(
            columns: [
                MenuTable.Column("#", priority: 3),
                MenuTable.Column("Score", priority: 3),
                MenuTable.Column("Wave", priority: 2),
                MenuTable.Column("Saved", priority: 1),
                MenuTable.Column("Date", alignment: .trailing, priority: 0),
            ],
            rows: table.entries.enumerated().map { index, entry in
                ["\(index + 1)", groupedDigits(entry.score), "\(entry.wave)", "\(entry.saved)",
                 shortDate(entry.date, timeZone: timeZone)]
            },
            highlightedRow: table.latestIndex
        )
    }

    /// The menu each screen shows. Pure, so it can be checked on its own.
    /// `gameOverLive` is false during the game-over hold-off, when Continue shows dimmed.
    /// `highScores` is the loaded mode's table; `scoresShown` (the loaded mode when nil) picks the
    /// table the high-score screen shows.
    public static func menu(for screen: Screen, session: ModeSession<Run>, pose: FoldPose, options: GameOptions,
                            highScores: HighScoreTable, lastRank: Int? = nil, gameOverLive: Bool = true,
                            catalog: ModeCatalog = ModeCatalog(), scoresShown: ModeID? = nil) -> Menu? {
        func table(_ id: ModeID) -> HighScoreTable {
            id == catalog.loaded ? highScores : catalog.tables[id] ?? HighScoreTable()
        }
        let open = pose.isPlayfieldAvailable
        switch screen {
        case .madeForDuo, .playing, .countdown:
            return nil

        case .title:
            // One item per mode, by name; the loaded one plays, the others switch first. Each
            // carries its summary and best score for the title to show while it is selected.
            // While closed they wait for the phone to open: one mode says so on its item, several
            // say it once under the heading.
            let several = catalog.offersChoice
            let modes = catalog.modes.map { mode in
                var details = mode.summary.isEmpty ? [] : [mode.summary]
                if let best = table(mode.id).best { details.append("Best \(groupedDigits(best.score))") }
                return MenuItem(mode.id == catalog.loaded ? .play : .chooseMode(mode.id), mode.displayName,
                                disabledTitle: several ? nil : "Open to play", isEnabled: open, details: details)
            }
            return Menu(kind: .title, heading: "Rimwatch", subtitle: "Outpost Calder",
                        lines: several && !open ? ["Open to play"] : [],
                        items: modes + [MenuItem(.options, "Options"), MenuItem(.highScores, "High scores")],
                        preferredDefaults: [.play])

        case .paused:
            let result = session.run.result
            return Menu(kind: .pause, heading: "Paused", lines: [
                "Score \(groupedDigits(result.score))",
                "Wave \(max(result.wave, 1))",
            ], items: [
                MenuItem(.resume, "Resume", disabledTitle: "Open to resume", isEnabled: session.canResume),
                MenuItem(.startOver, "Start over"),
                MenuItem(.endGame, "End game"),
                MenuItem(.options, "Options"),
                MenuItem(.highScores, "High scores"),
            ],
            // Never default to a destructive item: with Resume unavailable, Options is selected,
            // so a player still pressing fire as the phone closes doesn't throw the run away.
            preferredDefaults: [.resume, .options])

        case .gameOver(let score):
            let result = session.run.result
            var lines = [
                "Score \(groupedDigits(score))",
                "Wave \(max(result.wave, 1))",
                "Colonists saved \(result.saved)",
            ]
            if let lastRank { lines.append("New high score: #\(lastRank + 1)") }
            return Menu(kind: .gameOver, heading: "Game over", lines: lines, items: [
                MenuItem(.proceed, "Continue", isEnabled: gameOverLive),
            ])

        case .options:
            let rows = OptionKey.allCases.map { key in
                MenuItem(.option(key), options.title(of: key), value: options.valueText(of: key),
                         isAdjustable: true)
            }
            return Menu(kind: .options, heading: "Options", items: rows + [MenuItem(.back, "Back")])

        case .highScores:
            // Names the mode whose table this is; with several modes a row steps between them.
            let shown = scoresShown ?? catalog.loaded
            let name = catalog.descriptor(shown)?.displayName
            var items = [MenuItem(.back, "Back")]
            if catalog.offersChoice {
                items.insert(MenuItem(.scoresMode, "Mode", value: name, isAdjustable: true), at: 0)
            }
            let scores = table(shown)
            guard !scores.entries.isEmpty else {
                return Menu(kind: .highScores, heading: "High scores", subtitle: name, lines: ["No scores yet"],
                            items: items)
            }
            return Menu(kind: .highScores, heading: "High scores", subtitle: name, table: highScoreTable(scores),
                        items: items)
        }
    }
}
