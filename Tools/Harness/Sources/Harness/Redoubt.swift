import Foundation
import GameCore
import RedoubtCore

// `Harness redoubt [seeds] [maxMinutes] [skill...]`: runs Redoubt's scripted pilots over many
// seeds and prints difficulty statistics. Skills: idle, novice, competent, shooter, wallCircler, innerCircler,
// reversingCircler (default idle, novice, competent and wallCircler).
// Environment overrides for sweeps, e.g. SKSPEED=55 SKGROW=0.05 CROWD... (see `redoubtTuning`).

private func redoubtTuning() -> RedoubtTuning {
    var t = RedoubtTuning()
    let env = ProcessInfo.processInfo.environment
    if let v = env["SKSPEED"].flatMap(Double.init) { t.skitterSpeed = v }
    if let v = env["SKGROW"].flatMap(Double.init) { t.skitterSpeedGrowth = v }
    if let v = env["SKMAX"].flatMap(Double.init) { t.skitterMaxScale = v }
    if let v = env["HUSKSPEED"].flatMap(Double.init) { t.huskMaxSpeed = v }
    if let v = env["ORBSPEED"].flatMap(Double.init) { t.orbMaxSpeed = v }
    if let v = env["SAFE"].flatMap(Double.init) { t.safeDistance = v }
    if let v = env["SPITSHOT"].flatMap(Double.init) { t.spitterShotSpeed = v }
    if let v = env["GLSPEED"].flatMap(Double.init) { t.gleanerSpeed = v }
    if let v = env["INVULN"].flatMap(Double.init) { t.respawnInvulnerability = v }
    if let v = env["EXTRA"].flatMap(Int.init) { t.extraLifeEvery = v }
    if let v = env["HIT"].flatMap(Double.init) { t.orbHitRadius = v }
    if let v = env["CLEAR"].flatMap(Double.init) { t.respawnClearRadius = v }
    if let v = env["SPITMIN"].flatMap(Double.init) { t.spitterMinScale = v }
    if let v = env["SPITGROW"].flatMap(Double.init) { t.spitterFireGrowth = v }
    if let v = env["HUSKACC"].flatMap(Double.init) { t.huskAcceleration = v }
    if let v = env["WALLRUN"].flatMap(Double.init) { t.wallRunGap = v }
    return t
}

private struct RedoubtStats {
    var survival = 0.0
    var firstDeath: Double?
    var wave = 0
    var score = 0
    var saved = 0
    var delivered = 0
    var lost = 0
    var crushed = 0
    var taken: [String: Int] = [:]
    var deathsByWave: [Int: Int] = [:]
    var waveStarts: [Int: Double] = [:]
    var colonistsByWave: [Int: Int] = [:]
    var savedByWave: [Int: Int] = [:]
    var powerCuts = 0
    var powerCutWaves: [Int] = []
    var causes: [String: Int] = [:]
    var shockwaves = 0
    var peakEnemies = 0
    var enemySteps = 0
    var steps = 0
    var shotsFired = 0
    var kills = 0
    var extraLives = 0
    var stepSeconds = 0.0
    /// Per wave: fighting steps, steps with fewer than 5 shootable enemies alive on the floor,
    /// steps with none, and the sum of the shootable count.
    var fightSteps: [Int: Int] = [:]
    var sparseSteps: [Int: Int] = [:]
    var emptySteps: [Int: Int] = [:]
    var shootableSum: [Int: Int] = [:]
    var waveSeconds: [Int: Double] = [:]
    /// Distance from the orb (alive) of every enemy as it lands from its telegraph.
    var landings: [Double] = []
}

/// What most likely touched the orb: the closest enemy shot or enemy before the step.
private func redoubtCause(_ run: RedoubtRun) -> String {
    var best = ("?", 1e9)
    for shot in run.shots where shot.owner == .enemy {
        let d = (shot.pos - run.orb.pos).length
        if d < best.1 { best = ("shot", d) }
    }
    for enemy in run.enemies {
        let d = (enemy.pos - run.orb.pos).length - enemy.radius
        if d < best.1 { best = (enemy.role.rawValue, d) }
    }
    return best.0
}

private func playRedoubt(skill: RedoubtPilot.Skill, seed: UInt64, maxMinutes: Double, tuning: RedoubtTuning) -> RedoubtStats {
    var run = RedoubtRun(seed: seed, tuning: tuning)
    var pilot = RedoubtPilot(skill: skill, seed: seed)
    var stats = RedoubtStats()
    let maxSteps = Int(maxMinutes * 60 * 120)
    var stepTime: UInt64 = 0
    for _ in 0..<maxSteps {
        let input = pilot.input(for: run)
        let before = run
        let t0 = DispatchTime.now().uptimeNanoseconds
        let events = run.step(input)
        stepTime += DispatchTime.now().uptimeNanoseconds - t0
        let t = Double(run.tick) * RedoubtRun.timeStep
        stats.steps += 1
        stats.enemySteps += run.enemies.count
        stats.peakEnemies = max(stats.peakEnemies, run.enemies.count)
        if run.phase == .fighting {
            let w = run.wave
            let shootable = run.enemies.count { $0.role.holdsWave }
            stats.fightSteps[w, default: 0] += 1
            stats.shootableSum[w, default: 0] += shootable
            if shootable < 5 { stats.sparseSteps[w, default: 0] += 1 }
            if shootable == 0 { stats.emptySteps[w, default: 0] += 1 }
        }
        for event in events {
            switch event {
            case .enemyArrived(_, _, let at):
                if run.orb.isAlive { stats.landings.append((at - run.orb.pos).length) }
            case .waveStarted(let w, let colonists):
                stats.waveStarts[w] = t
                stats.colonistsByWave[w] = colonists
            case .waveCleared(let w, let safe, _):
                stats.savedByWave[w, default: 0] += safe
                stats.waveSeconds[w] = t - (stats.waveStarts[w] ?? t)
            case .colonistDelivered:
                stats.savedByWave[run.wave, default: 0] += 1
            case .orbDestroyed:
                stats.deathsByWave[run.wave, default: 0] += 1
                stats.causes[redoubtCause(before), default: 0] += 1
                if stats.firstDeath == nil { stats.firstDeath = t }
            case .colonistTaken(_, let by, _, _):
                stats.taken[by.rawValue, default: 0] += 1
                stats.lost += 1
            case .colonistCrushed:
                stats.crushed += 1
                stats.lost += 1
            case .powerCutBegan:
                stats.powerCuts += 1
                stats.powerCutWaves.append(run.wave)
            case .shockwave: stats.shockwaves += 1
            case .orbFired: stats.shotsFired += 1
            case .enemyDestroyed: stats.kills += 1
            case .extraLife: stats.extraLives += 1
            default: break
            }
        }
        if run.isGameOver { break }
    }
    stats.survival = Double(run.tick) * RedoubtRun.timeStep
    stats.wave = run.wave
    stats.score = run.score
    stats.saved = run.colonistsSaved
    stats.delivered = run.colonistsDelivered
    stats.stepSeconds = Double(stepTime) / 1e9
    return stats
}

private func q3(_ values: [Double]) -> String {
    guard !values.isEmpty else { return "-" }
    let s = values.sorted()
    func q(_ p: Double) -> Double { s[min(Int(Double(s.count - 1) * p + 0.5), s.count - 1)] }
    return String(format: "%7.1f [%6.1f %6.1f]", q(0.5), q(0.25), q(0.75))
}

func runRedoubt(_ args: [String]) {
    let seeds = args.count > 0 ? Int(args[0]) ?? 40 : 40
    let maxMinutes = args.count > 1 ? Double(args[1]) ?? 20 : 20
    let names = args.count > 2 ? Array(args[2...]) : ["idle", "novice", "competent", "wallCircler"]
    let tuning = redoubtTuning()
    let debut = Dictionary(uniqueKeysWithValues: RedoubtWaves.debut.map { ($0.wave, $0.role.rawValue) })
    for name in names {
        let skill = RedoubtPilot.Skill(rawValue: name) ?? .competent
        var all: [RedoubtStats] = []
        for i in 0..<seeds {
            all.append(playRedoubt(skill: skill, seed: UInt64(1000 + i * 7919), maxMinutes: maxMinutes, tuning: tuning))
        }
        func col(_ f: (RedoubtStats) -> Double) -> String { q3(all.map(f)) }
        print("== redoubt \(name): \(seeds) seeds, cap \(Int(maxMinutes)) min   median [q1 q3]")
        print("survival s        ", col { $0.survival })
        print("first death s     ", col { $0.firstDeath ?? $0.survival })
        print("wave reached      ", col { Double($0.wave) })
        print("score             ", col { Double($0.score) }, " / min", col { Double($0.score) / max($0.survival / 60, 0.01) })
        print("survival min..max  ", String(format: "%.0f..%.0f s", all.map(\.survival).min() ?? 0, all.map(\.survival).max() ?? 0),
              " wave min..max \(all.map(\.wave).min() ?? 0)..\(all.map(\.wave).max() ?? 0)",
              " reached the cap: \(all.filter { $0.survival >= maxMinutes * 60 - 0.01 }.count)")
        print("colonists saved   ", col { Double($0.saved) }, " delivered", col { Double($0.delivered) })
        print("colonists lost    ", col { Double($0.lost) }, " crushed", col { Double($0.crushed) })
        var taken: [String: Int] = [:]
        for g in all { for (k, v) in g.taken { taken[k, default: 0] += v } }
        print("taken by (all)    ", taken.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: " "))
        print("kills / min       ", col { Double($0.kills) / max($0.survival / 60, 0.01) },
              " shots / s", col { Double($0.shotsFired) / max($0.survival, 1) })
        print("shockwaves / game ", col { Double($0.shockwaves) }, " extra lives", col { Double($0.extraLives) })
        print("power cuts / game ", col { Double($0.powerCuts) }, " games with one: \(all.filter { $0.powerCuts > 0 }.count)",
              " first in w", q3(all.compactMap { $0.powerCutWaves.first.map(Double.init) }))
        let landings = all.flatMap(\.landings).sorted()
        if !landings.isEmpty {
            func at(_ p: Double) -> Double { landings[min(Int(Double(landings.count) * p), landings.count - 1)] }
            print(String(format: "landing dist       min %.0f  0.1%% %.0f  1%% %.0f  5%% %.0f  median %.0f   under 150: %.2f%%", landings[0],
                         at(0.001), at(0.01), at(0.05), at(0.5), 100 * Double(landings.count { $0 < 150 }) / Double(landings.count)))
        }
        print("enemies on floor  ", col { Double($0.enemySteps) / Double(max($0.steps, 1)) }, " peak", col { Double($0.peakEnemies) })
        var causes: [String: Int] = [:]
        for g in all { for (k, v) in g.causes { causes[k, default: 0] += v } }
        print("death causes      ", causes.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }.joined(separator: " "))
        var hist: [Int: Int] = [:]
        for g in all { hist[g.wave, default: 0] += 1 }
        print("final wave hist   ", hist.sorted { $0.key < $1.key }.map { "w\($0.key):\($0.value)" }.joined(separator: " "))
        let maxWave = all.map(\.wave).max() ?? 0
        var deaths = "deaths/game by wave"
        var saved = "saved frac by wave "
        var starts = "wave start t (med) "
        for w in 1...max(min(maxWave, 16), 1) {
            let reached = all.filter { $0.wave >= w }
            let n = reached.reduce(0) { $0 + ($1.deathsByWave[w] ?? 0) }
            let mark = debut[w].map { "(\($0.prefix(3)))" } ?? ""
            deaths += String(format: " w%d%@:%.2f", w, mark, reached.isEmpty ? 0 : Double(n) / Double(reached.count))
            // Saved over colonists, for waves that were finished (the next one started).
            let finished = all.filter { $0.wave > w }
            let total = finished.reduce(0) { $0 + ($1.colonistsByWave[w] ?? 0) }
            let kept = finished.reduce(0) { $0 + ($1.savedByWave[w] ?? 0) }
            if total > 0 { saved += String(format: " w%d:%.2f", w, Double(kept) / Double(total)) }
            let s = all.compactMap { $0.waveStarts[w] }.sorted()
            if !s.isEmpty { starts += String(format: " w%d:%.0f", w, s[s.count / 2]) }
        }
        print(deaths)
        print(saved)
        print(starts)
        // The feel: share of fighting time with fewer than 5 / no shootable enemies alive, the
        // mean shootable count, and the median length of finished waves.
        var sparse = "floor <5 frac      "
        var empty = "floor empty frac   "
        var mean = "mean shootable     "
        var length = "wave length s (med)"
        for w in 1...max(min(maxWave, 16), 1) {
            let steps = all.reduce(0) { $0 + ($1.fightSteps[w] ?? 0) }
            guard steps > 0 else { continue }
            let few = all.reduce(0) { $0 + ($1.sparseSteps[w] ?? 0) }
            let none = all.reduce(0) { $0 + ($1.emptySteps[w] ?? 0) }
            let sum = all.reduce(0) { $0 + ($1.shootableSum[w] ?? 0) }
            sparse += String(format: " w%d:%.3f", w, Double(few) / Double(steps))
            empty += String(format: " w%d:%.3f", w, Double(none) / Double(steps))
            mean += String(format: " w%d:%.1f", w, Double(sum) / Double(steps))
            let lengths = all.compactMap { $0.waveSeconds[w] }.sorted()
            if !lengths.isEmpty { length += String(format: " w%d:%.0f", w, lengths[lengths.count / 2]) }
        }
        print(sparse)
        print(empty)
        print(mean)
        print(length)
        let totalSteps = all.reduce(0) { $0 + $1.steps }
        let totalTime = all.reduce(0.0) { $0 + $1.stepSeconds }
        print(String(format: "step time          %.2f us mean over %d steps", totalTime / Double(max(totalSteps, 1)) * 1e6, totalSteps))
        print()
    }
}
