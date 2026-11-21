import GameCore

/// How Redoubt looks and sounds, kept apart from how it plays. The run knows roles; a
/// `RedoubtTheme` says what each looks like. Everything here is device-neutral data (colours are
/// plain RGB numbers and shapes are polylines, from GameCore's `Shapes.swift`), so the app decides
/// how to draw it.
///
/// Shapes are seen from above. In unit coordinates +x is the way the thing faces (its heading,
/// or the orb's aim) and +y is to its left; the origin is its position. A shape's `scale` is
/// arena units per unit coordinate.

/// Everything the renderer draws with a shape of its own.
public enum RedoubtShape: Sendable, Hashable, CaseIterable {
    /// The player's hover orb. Faces its aim (or the way it moves).
    case orb
    case colonist
    case enemy(RedoubtRole)
    case orbShot
    case enemyShot
    /// The airlock drawn along its wall: x runs along the wall (the opening is `airlockWidth`
    /// wide, so the shape spans -0.5...0.5 at scale `airlockWidth`), +y points into the arena.
    case airlockOpen
    case airlockShut
    /// The marker for an enemy on its way in. White, so the renderer can tint it by role.
    case arrival
    /// A life in the HUD (the orb, pointing up when drawn with +x up).
    case life
    /// A Shockwave charge in the HUD and on the touch button.
    case charge

    public static var allCases: [RedoubtShape] {
        [.orb, .colonist, .orbShot, .enemyShot, .airlockOpen, .airlockShut, .arrival, .life, .charge]
            + RedoubtRole.allCases.map { .enemy($0) }
    }
}

/// Colours that are not part of a single shape.
public struct RedoubtPalette: Sendable, Equatable {
    public var background: RGB
    /// The wall round the floor.
    public var wall: RGB
    /// Floor markings: faint, so motion reads without competing with the crowd.
    public var floor: RGB
    /// A colonist in a Gleaner's grip, the Spitter's wind-up, a life lost.
    public var warning: RGB
    /// Points popups and other good news.
    public var reward: RGB
    /// Shockwave charges and the Shockwave ring.
    public var shockwave: RGB
    /// Invulnerability after a respawn.
    public var shield: RGB
    /// On-screen touch controls.
    public var controls: RGB
    public var hud: RGB
    /// Wave banners and menu headings.
    public var heading: RGB

    public init(background: RGB, wall: RGB, floor: RGB, warning: RGB, reward: RGB, shockwave: RGB, shield: RGB,
                controls: RGB, hud: RGB, heading: RGB) {
        self.background = background
        self.wall = wall
        self.floor = floor
        self.warning = warning
        self.reward = reward
        self.shockwave = shockwave
        self.shield = shield
        self.controls = controls
        self.hud = hud
        self.heading = heading
    }
}

public protocol RedoubtTheme: Sendable {
    var name: String { get }
    var palette: RedoubtPalette { get }
    func shape(for thing: RedoubtShape) -> ShapeDescription
    func displayName(for role: RedoubtRole) -> String
    /// The sound to play for an event, if any (see `SoundPatch` in GameCore's `Audio/`).
    func sound(for event: RedoubtEvent) -> SoundPatch?
    /// The sound for an event in one of its versions. `variant` means, by event: for a shot
    /// fired or a Skitter destroyed, which of the theme's pitches (any integer; the theme wraps
    /// it); for a Burrow hit, its damage stage from 0 (fresh) up; for a colonist delivered, how
    /// many colonists were delivered together. Other events ignore it. `RedoubtSoundDirector`
    /// chooses it.
    func sound(for event: RedoubtEvent, variant: Int) -> SoundPatch?
    /// The sound for a menu action, if any.
    func menuSound(_ sound: MenuSound) -> SoundPatch?
    /// Every patch the theme can play, so an app can prepare them all up front.
    var allSounds: [SoundPatch] { get }
    /// The ambient music, or nil for none.
    var music: MusicStyle? { get }
}

extension RedoubtTheme {
    public func sound(for event: RedoubtEvent) -> SoundPatch? { nil }
    public func sound(for event: RedoubtEvent, variant: Int) -> SoundPatch? { sound(for: event) }
    public func menuSound(_ sound: MenuSound) -> SoundPatch? { nil }
    public var allSounds: [SoundPatch] { [] }
    public var music: MusicStyle? { nil }

    /// The main colour of a shape: its first stroke's.
    public func color(of thing: RedoubtShape) -> RGB {
        shape(for: thing).strokes.first?.color ?? palette.hud
    }

    /// The look the shared screens take from this theme.
    public var shellStyle: ShellStyle {
        var sounds: [MenuSound: SoundPatch] = [:]
        for sound in MenuSound.allCases {
            if let patch = menuSound(sound) { sounds[sound] = patch }
        }
        return ShellStyle(background: palette.background, text: palette.hud, highlight: palette.reward,
                          heading: palette.heading, controls: palette.controls, menuSounds: sounds)
    }
}
