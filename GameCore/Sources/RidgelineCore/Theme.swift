import Foundation
import GameCore

/// How the game looks and sounds, kept apart from how it plays. The simulation knows entity roles;
/// a `Theme` says what each role looks like. Everything here is device-neutral data: colours are
/// plain RGB numbers and shapes are polylines (`RGB` and the shape types are in GameCore's
/// `Shapes.swift`), so the app decides how to draw them.

/// Everything the renderer draws that has a shape of its own.
public enum EntityRole: Sendable, Hashable {
    case player
    case enemy(EnemyKind)
    case colonist
    /// A standing outpost. Its origin is the ground under its centre.
    case outpost
    /// What is left of a destroyed outpost.
    case ruin
    case projectile(Projectile.Owner)

    public static var allCases: [EntityRole] {
        [.player, .colonist, .outpost, .ruin, .projectile(.player), .projectile(.enemy)]
            + EnemyKind.allCases.map { .enemy($0) }
    }
}

/// Colours that are not part of a single shape.
public struct Palette: Sendable, Equatable {
    public var background: RGB
    public var stars: RGB
    /// Lancer wind-up, a colonist in a Harvester's grip, outpost damage.
    public var warning: RGB
    /// A colonist falling free.
    public var falling: RGB
    /// The ship's shield and invulnerability.
    public var shield: RGB
    /// Explosion sparks for enemies; the player's own burst uses the player shape's colour.
    public var spark: RGB
    /// On-screen touch controls.
    public var controls: RGB
    public var hud: RGB

    public init(background: RGB, stars: RGB, warning: RGB, falling: RGB, shield: RGB, spark: RGB,
                controls: RGB, hud: RGB) {
        self.background = background
        self.stars = stars
        self.warning = warning
        self.falling = falling
        self.shield = shield
        self.spark = spark
        self.controls = controls
        self.hud = hud
    }
}

public struct TerrainStyle: Sendable, Equatable {
    /// The bright ridge line along the ground.
    public var ridge: RGB
    /// Fainter lines drawn below the ridge, each this many world units lower.
    public var strata: RGB
    public var strataOffsets: [Double]
    /// Ridge colour during a Blackout.
    public var blackoutRidge: RGB

    public init(ridge: RGB, strata: RGB, strataOffsets: [Double], blackoutRidge: RGB) {
        self.ridge = ridge
        self.strata = strata
        self.strataOffsets = strataOffsets
        self.blackoutRidge = blackoutRidge
    }
}

public protocol Theme: Sendable {
    var name: String { get }
    var palette: Palette { get }
    var terrain: TerrainStyle { get }
    func shape(for role: EntityRole) -> ShapeDescription
    func displayName(for role: EntityRole) -> String
    /// The sound to play for an event, if any. See `SoundPatch` (in GameCore's `Audio/`).
    func sound(for event: GameEvent) -> SoundPatch?
    /// The sound for a menu action, if any.
    func menuSound(_ sound: MenuSound) -> SoundPatch?
    /// Every patch the theme can play, so an app can prepare them all up front.
    var allSounds: [SoundPatch] { get }
    /// The ambient music, or nil for none.
    var music: MusicStyle? { get }
}

extension Theme {
    public func sound(for event: GameEvent) -> SoundPatch? { nil }
    public func menuSound(_ sound: MenuSound) -> SoundPatch? { nil }
    public var allSounds: [SoundPatch] { [] }
    public var music: MusicStyle? { nil }
}
