import GameCore

/// A rock shelf: a rig or pod can rest on its top and run along it. Ledges never cross the
/// gallery's join at the sides.
public struct RiftwingLedge: Sendable, Equatable {
    /// Left and right ends.
    public var minX: Double
    public var maxX: Double
    /// The standing surface.
    public var top: Double

    public init(_ minX: Double, _ maxX: Double, top: Double) {
        self.minX = minX
        self.maxX = maxX
        self.top = top
    }

    public var midX: Double { (minX + maxX) / 2 }
    public var length: Double { maxX - minX }

    /// True when `x` is over the ledge (a body stands on it while its centre is).
    public func spans(_ x: Double) -> Bool { x >= minX && x <= maxX }
}

/// A column of rising air from the Rift: fly into it and it carries you up without flapping.
public struct RiftwingVent: Sendable, Equatable {
    public var x: Double
    /// The column ends here; above it the air is still.
    public var top: Double

    public init(x: Double, top: Double) {
        self.x = x
        self.top = top
    }
}

/// One arrangement of the gallery: its ledges, its vents and where a run starts.
public struct RiftwingLayout: Sendable, Equatable {
    public var name: String
    public var ledges: [RiftwingLedge]
    public var vents: [RiftwingVent]
    /// The ledge the rider stands on when a run starts in this layout.
    public var startLedge: Int
}

/// The three layouts the cavern cycles through, every `RiftwingTuning.wavesPerLayout` waves.
/// Each has four to six ledges at uneven heights, never symmetrical, and no floor over the Rift.
/// They are drawn for this game, not taken from any other.
public enum RiftwingCavern {
    /// Waves 1 to 3 (and 10 to 12, ...): five shelves stepping up from a low one on the left,
    /// a lone low shelf on the right, two vents.
    public static let terraces = RiftwingLayout(
        name: "Terraces",
        ledges: [
            RiftwingLedge(70, 260, top: 135),
            RiftwingLedge(345, 505, top: 250),
            RiftwingLedge(640, 850, top: 175),
            RiftwingLedge(150, 330, top: 400),
            RiftwingLedge(530, 720, top: 455),
        ],
        vents: [RiftwingVent(x: 295, top: 360), RiftwingVent(x: 580, top: 400)],
        startLedge: 1)

    /// Waves 4 to 6: four shelves, a long one in the middle right, one high bridge, a single low
    /// step; three vents.
    public static let spur = RiftwingLayout(
        name: "Spur",
        ledges: [
            RiftwingLedge(30, 210, top: 300),
            RiftwingLedge(290, 430, top: 120),
            RiftwingLedge(520, 790, top: 235),
            RiftwingLedge(360, 560, top: 470),
        ],
        vents: [RiftwingVent(x: 250, top: 420), RiftwingVent(x: 475, top: 380), RiftwingVent(x: 850, top: 480)],
        startLedge: 2)

    /// Waves 7 to 9: six short shelves scattered high and low; two vents.
    public static let shelves = RiftwingLayout(
        name: "Shelves",
        ledges: [
            RiftwingLedge(90, 215, top: 105),
            RiftwingLedge(280, 440, top: 320),
            RiftwingLedge(505, 615, top: 165),
            RiftwingLedge(690, 870, top: 280),
            RiftwingLedge(110, 270, top: 505),
            RiftwingLedge(545, 700, top: 430),
        ],
        vents: [RiftwingVent(x: 472, top: 300), RiftwingVent(x: 655, top: 380)],
        startLedge: 1)

    public static let layouts: [RiftwingLayout] = [terraces, spur, shelves]

    /// The layout of a wave: the cavern shifts every `wavesPerLayout` waves (wave 0, before the
    /// first, uses the first).
    public static func layoutIndex(forWave wave: Int, wavesPerLayout: Int) -> Int {
        (max(wave - 1, 0) / max(wavesPerLayout, 1)) % layouts.count
    }
}
