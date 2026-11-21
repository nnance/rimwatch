import Foundation
import GameCore

/// A uniform grid over the floor holding enemy indices, rebuilt each step with a counting sort
/// so it allocates nothing once warm. Queries visit every index in the cells a box touches; the
/// caller does the exact distance test.
struct SpatialGrid: Sendable {
    let cellSize: Double
    let columns: Int
    let rows: Int
    /// `cellStart[c] ..< cellStart[c + 1]` is cell c's run in `items`.
    private(set) var cellStart: [Int]
    private(set) var items: [Int] = []
    private var cellOf: [Int] = []

    init(width: Double, height: Double, cellSize: Double) {
        self.cellSize = cellSize
        columns = max(1, Int((width / cellSize).rounded(.up)))
        rows = max(1, Int((height / cellSize).rounded(.up)))
        cellStart = Array(repeating: 0, count: columns * rows + 1)
    }

    @inline(__always)
    private func column(_ x: Double) -> Int { min(max(Int(x / cellSize), 0), columns - 1) }
    @inline(__always)
    private func row(_ y: Double) -> Int { min(max(Int(y / cellSize), 0), rows - 1) }

    // The loops below are plain `while` loops over integers on purpose: in an unoptimised
    // (Debug) build, `for` over a range goes through generic iterator code that made a full floor
    // step about fifty times slower than the same loops written this way.

    /// Files every live enemy by its position.
    mutating func rebuild(_ enemies: [RedoubtEnemy]) {
        let cellCount = columns * rows
        var c = 0
        while c <= cellCount {
            cellStart[c] = 0
            c += 1
        }
        cellOf.removeAll(keepingCapacity: true)
        var i = 0
        while i < enemies.count {
            let enemy = enemies[i]
            let cell = enemy.isDead ? -1 : row(enemy.pos.y) * columns + column(enemy.pos.x)
            cellOf.append(cell)
            if cell >= 0 { cellStart[cell + 1] += 1 }
            i += 1
        }
        c = 0
        while c < cellCount {
            cellStart[c + 1] += cellStart[c]
            c += 1
        }
        let total = cellStart[cellCount]
        if items.count != total {
            items.removeAll(keepingCapacity: true)
            items.append(contentsOf: repeatElement(0, count: total))
        }
        var fill = cellStart
        i = 0
        while i < cellOf.count {
            let cell = cellOf[i]
            if cell >= 0 {
                items[fill[cell]] = i
                fill[cell] += 1
            }
            i += 1
        }
    }

    /// Calls `body` with every enemy index filed in a cell the box touches.
    @inline(__always)
    func forEach(minX: Double, minY: Double, maxX: Double, maxY: Double, _ body: (Int) -> Void) {
        let c0 = column(minX), c1 = column(maxX)
        var r = row(minY)
        let r1 = row(maxY)
        while r <= r1 {
            var cell = r * columns + c0
            let last = r * columns + c1
            while cell <= last {
                var slot = cellStart[cell]
                let end = cellStart[cell + 1]
                while slot < end {
                    body(items[slot])
                    slot += 1
                }
                cell += 1
            }
            r += 1
        }
    }

    /// Every enemy index filed near a point (cells within `reach`).
    @inline(__always)
    func forEach(near p: Vec2, reach: Double, _ body: (Int) -> Void) {
        forEach(minX: p.x - reach, minY: p.y - reach, maxX: p.x + reach, maxY: p.y + reach, body)
    }
}
