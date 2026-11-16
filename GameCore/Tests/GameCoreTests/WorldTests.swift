import Testing
@testable import GameCore

@Suite struct WorldTests {
    let world = World(tuning: Tuning(), seed: 1)

    @Test func wrapKeepsXInsideTheWorld() {
        #expect(world.wrap(-10) == world.width - 10)
        #expect(world.wrap(world.width + 25) == 25)
        #expect(world.wrap(world.width) == 0)
        #expect(world.wrap(-1e-13) < world.width)
        #expect(world.wrap(123.5) == 123.5)
    }

    @Test func deltaTakesTheShortWayRoundTheSeam() {
        #expect(world.delta(from: world.width - 20, to: 30) == 50)
        #expect(world.delta(from: 30, to: world.width - 20) == -50)
        #expect(world.delta(from: 100, to: 400) == 300)
        #expect(abs(world.delta(from: 0, to: world.width / 2)) == world.width / 2)
    }

    @Test func distanceIsMeasuredAcrossTheSeam() {
        let a = Vec2(world.width - 3, 100)
        let b = Vec2(1, 103)
        #expect(world.distance(a, b) == 5)
    }

    @Test func terrainMeetsItselfAtTheSeamAndStaysLow() {
        #expect(abs(world.groundHeight(at: world.width - 0.5) - world.groundHeight(at: 0.5)) < 2)
        for x in stride(from: 0.0, to: world.width, by: 37) {
            let h = world.groundHeight(at: x)
            #expect(h >= 20)
            #expect(h < world.ceiling / 2)
            #expect(abs(h - world.groundHeight(at: x + world.width)) < 1e-6)
        }
    }

    @Test func groundIsLevelUnderEachOutpost() {
        #expect(world.outposts.count == 5)
        for outpost in world.outposts {
            #expect(world.groundHeight(at: outpost.x - 40) == outpost.groundY)
            #expect(world.groundHeight(at: outpost.x + 40) == outpost.groundY)
        }
    }

    @Test func sweepCatchesAFastShotThatWouldSkipItsTarget() {
        // The shot starts 10 short of the target and ends 10 past it; neither end point touches.
        #expect(Collision.sweepTime(center: Vec2(10, 0), travel: Vec2(20, 0), radius: 2) != nil)
        #expect(Collision.sweepTime(center: Vec2(10, 5), travel: Vec2(20, 0), radius: 2) == nil)
        #expect(Collision.sweepTime(center: Vec2(-10, 0), travel: Vec2(20, 0), radius: 2) == nil)
        #expect(Collision.sweepTime(center: Vec2(1, 0), travel: .zero, radius: 2) == 0)
    }
}
