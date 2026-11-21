import Testing
import GameCore
@testable import RedoubtCore

/// Lives, respawning, the extra life and the power cut.
@Suite struct LivesTests {
    @Test func theOrbComesBackAtTheCentreWithAMomentOfProtection() throws {
        var r = quietRun()
        r.orb.pos = Vec2(200, 200)
        let killer = r.addEnemy(.skitter, at: Vec2(205, 200))
        // Something waiting at the centre is shoved clear.
        let lurker = r.addEnemy(.skitter, at: r.centre + Vec2(30, 0))
        var events = run(&r, steps: 2)
        #expect(events.contains(.orbDestroyed(at: Vec2(200, 200), livesLeft: 2, cause: .enemy(id: killer, role: .skitter))))
        #expect(!r.orb.isAlive)
        // How long until it is back is readable.
        #expect(r.orb.respawnTimer > 1 && r.orb.respawnTimer <= r.tuning.respawnDelay)
        events = run(&r, steps: seconds(1.3)) { if case .orbRespawned = $0 { true } else { false } }
        #expect(events.contains(.orbRespawned(at: r.centre)))
        #expect(r.orb.pos == r.centre)
        #expect(r.orb.isInvulnerable)
        #expect(try r.req(enemy: lurker).push.length > 100)
        // Protected: touching an enemy does nothing for a while.
        r.addEnemy(.skitter, at: r.orb.pos)
        events = run(&r, steps: seconds(2))
        #expect(!events.contains { $0.isOrbDestroyed })
        events = run(&r, steps: seconds(1))
        #expect(events.contains { $0.isOrbDestroyed })
    }

    @Test func threeLivesThenGameOver() throws {
        var r = quietRun()
        var deaths = 0
        for _ in 0..<3 {
            run(&r, steps: seconds(4)) { if case .orbRespawned = $0 { true } else { false } }
            r.orb.invulnerableTimer = 0
            r.addEnemy(.husk, at: r.orb.pos)
            let events = run(&r, steps: 2)
            deaths += count(events, "orbDestroyed")
            if events.contains(where: \.isGameOver) { break }
        }
        #expect(deaths == 3)
        #expect(r.isGameOver)
        #expect(r.ending == .defeated)
        #expect(r.step(still).isEmpty)
    }

    @Test func anExtraLifeAtEachThresholdUpToTheLimit() throws {
        var r = quietRun()
        r.addScore(r.tuning.extraLifeEvery - 1)
        #expect(r.orb.lives == 3)
        r.addScore(1)
        #expect(r.orb.lives == 4)
        r.addScore(r.tuning.extraLifeEvery * 3)
        #expect(r.orb.lives == r.tuning.maxLives)
    }

    @Test func extraLivesComeFromDeliveriesToo() throws {
        var r = quietRun()
        r.addScore(r.tuning.extraLifeEvery - 400)
        r.formLine(1)
        r.orb.pos = Vec2(880, 300)
        let events = r.step(still)
        #expect(events.contains(.extraLife(lives: 4)))
    }
}

@Suite struct PowerCutTests {
    private func waveOne() -> RedoubtRun {
        var r = RedoubtRun(seed: 5)
        run(&r, steps: seconds(3)) { $0.isWaveStarted }
        return r
    }

    private func clearWave(_ r: inout RedoubtRun) -> [RedoubtEvent] {
        r.pendingIndex = r.pending.count
        r.quota = 0
        r.arrivals.removeAll()
        r.enemies.removeAll()
        return run(&r, steps: seconds(2.2)) { $0.isWaveStarted }
    }

    @Test func losingEveryColonistDarkensTheNextWaveUntilADelivery() throws {
        var r = waveOne()
        var events: [RedoubtEvent] = []
        for c in r.colonists.indices {
            r.loseColonist(at: c, takenBy: .gleaner, enemy: 0)
        }
        events = r.events
        #expect(events.contains(.allColonistsLost(wave: 1)))
        // Not yet: the rest of this wave is fought with the lights on.
        #expect(!r.isPowerCut)
        events = clearWave(&r)
        #expect(events.contains(.powerCutBegan))
        #expect(r.isPowerCut)
        #expect(r.wave == 2)
        // Delivering a colonist brings the power back.
        r.formLine(1)
        r.orb.pos = r.airlock.pos
        events = r.step(still)
        #expect(events.contains(.powerCutEnded))
        #expect(!r.isPowerCut)
    }

    @Test func aPendingPowerCutShowsThroughTheBreak() throws {
        var r = waveOne()
        #expect(!r.powerCutPending)
        for c in r.colonists.indices { r.loseColonist(at: c, takenBy: .gleaner, enemy: 0) }
        #expect(r.powerCutPending)
        #expect(!r.isPowerCut)
        // Clear the wave, then step into the break's last second, when the next wave's
        // colonists are already on the floor: still pending, still lit.
        r.pendingIndex = r.pending.count
        r.quota = 0
        r.arrivals.removeAll()
        r.enemies.removeAll()
        for _ in 0..<seconds(2.5) {
            _ = r.step(still)
            if case .intermission(let left) = r.phase, left < r.tuning.telegraphTime * 0.5 { break }
        }
        guard case .intermission = r.phase else {
            Issue.record("expected to be in the break")
            return
        }
        #expect(r.colonistsLeft > 0)
        #expect(r.powerCutPending)
        #expect(!r.isPowerCut)
        // The wave starts in the dark and the cut is no longer pending.
        let events = run(&r, steps: seconds(1)) { $0.isWaveStarted }
        #expect(events.contains(.powerCutBegan))
        #expect(r.isPowerCut)
        #expect(!r.powerCutPending)
    }

    @Test func theDarkLastsAcrossWavesWithoutADelivery() throws {
        var r = waveOne()
        for c in r.colonists.indices { r.crushColonist(at: c, by: 0) }
        _ = clearWave(&r)
        #expect(r.isPowerCut)
        let events = clearWave(&r)
        #expect(r.wave == 3)
        #expect(r.isPowerCut)
        #expect(!events.contains(.powerCutBegan))
    }

    @Test func savingEvenOneKeepsThePowerOn() throws {
        var r = waveOne()
        for c in r.colonists.indices.dropFirst() { r.loseColonist(at: c, takenBy: .skitter, enemy: 0) }
        _ = clearWave(&r)
        #expect(!r.isPowerCut)
    }
}
