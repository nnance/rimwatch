import Foundation
import GameCore
import RedoubtCore

// `Harness redoubt [seeds] [maxMinutes] [skill...]`: runs Redoubt's scripted pilots over many
// seeds and prints difficulty statistics. Skills: idle, novice, competent, shooter, wallCircler, innerCircler,
// reversingCircler (default idle, novice, competent and wallCircler).
// Environment overrides for sweeps, e.g. SKSPEED=55 SKGROW=0.05 (see `redoubtTuning`), and for
// the early-game ease: SIDES=4 EASE0=1 EASESTEP=0 SPITEASE=1 together restore the waves as they
// were before it (see `redoubtWaves`). PUSH=0 turns off the main push and the scatter (the first
// 13d entry exactly); SCATTER=0.2,0.25,... PUSHDEPTH FALLOFF ALONG SCATCLEAR WALLW GDRAWS tune it.
// FIGURE=1 CROWD=1 QUOTA0=90 QUOTASTEP=25 EASE0=0.9 EASESTEP=0.015 SPITEASE=2 together restore
// the game before the figures grew. GLDELAY GLDRAG GLSTEPS tune the Gleaners' ease; GLDELAY=0
// GLDRAG=1 restore the game before it. GLSTEPS=1,0.6,... sets the ease left in each Gleaner
// wave; GLRAMP=0 restores the game before the Gleaners' ramp (the ease counted in waves over
// GLEASE, not Gleaner waves). LATESCATTER=1 lets late Gleaners scatter. LIVES0=99 starts with that many lives, so
// a weak bot plays on into later waves (for their colonist numbers). BURSLOW BUREASE tune the Burrows' ease and BURKIDS their
// Skitter limit; BEFORE6=1 GLRAMP=0 SPITEASE=3.8 BURSLOW=1 BURN=2 restore the game before the Burrows' ease. SEEDBASE moves the seed set (default 1000) to check a result is not luck of the seeds.
// Refinement 6: BEFORE6=1 starts from `RedoubtWaves.beforeGleanersThroughWave` (exactly the game
// before it; the other overrides apply on top, and every note above that restores an older game
// assumes it). GLTHRU=0 lands all of a wave's Gleaners together;
// GLFIRST (how many land first), GLARRIVE=10,9,... (seconds after the crowd they land, by Gleaner
// appearance), GLSTART GLSPREAD (the quota shares over which the rest are due) and GLGAP (the
// clock fallback between them) tune the schedule. SEIZE=8,7,... (least seizure time by appearance)
// and SEIZEMIN (its floor) tune the least time from seizure to loss. APPEASE=0 counts the
// Spitters' and Burrows' eases in wave numbers again; SPITSTEPS BURSTEPS set the share of ease
// left in each appearance; SPITN=2,6,7,8 sets the Spitters after their debut by appearance (empty
// for the old one more a wave); SPITSHOTE SPITLEAD set a debut Spitter's shot speed and lead
// (as multiples); SPITRANGE=lo,hi and SPITWIND set the Spitters' holding range and wind-up.
// GLMINGAP (least gap between Gleaners) and DRAGMIN (least drag speed) tune the 2026-11-21 fixes.
// The "gleaner" lines print, per wave, Gleaner markers sharing a step with another, the largest
// gap between consecutive ones, and seconds a wave was held open only by Gleaners still to come;
// "drag speed" each drag's speed on its first step.
// Each wave's colonist line also prints the share of its seizures in its first 10 s.

private func redoubtTuning() -> RedoubtTuning {
    var t = RedoubtTuning()
    let env = ProcessInfo.processInfo.environment
    // First, so the size overrides below (HIT) are read at the chosen figure scale.
    if let v = env["FIGURE"].flatMap(Double.init) { t.figureScale = v }
    if let v = env["MAXEN"].flatMap(Int.init) { t.maxEnemies = v }
    if let v = env["SEP"].flatMap(Double.init) { t.separationStrength = v }
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
    if let v = env["BAND"].flatMap(Double.init) { t.entryBandDepth = v }
    if let v = env["JITTER"].flatMap(Double.init) { t.entrySideJitter = v }
    if let v = env["LIVES"].flatMap(Int.init) { t.extraLifeEvery = v }
    if let v = env["PUSHDEPTH"].flatMap(Double.init) { t.pushDepth = v }
    if let v = env["FALLOFF"].flatMap(Double.init) { t.pushFalloff = v }
    if let v = env["SCATCLEAR"].flatMap(Double.init) { t.scatterClearance = v }
    if let v = env["WALLW"].flatMap(Double.init) { t.mainWallWeighting = v }
    if let v = env["ALONG"].flatMap(Int.init) { t.pushAlongDraws = v }
    if let v = env["GDRAWS"].flatMap(Int.init) { t.groupSpotDraws = v }
    if let v = env["BURKIDS"].flatMap(Int.init) { t.burrowMaxChildren = v }
    if let v = env["SPITRANGE"] { let p = v.split(separator: ",").compactMap { Double($0) }; t.spitterRange = p[0]...p[1] }
    if let v = env["SPITWIND"].flatMap(Double.init) { t.spitterWindUp = v }
    // Lives to start with (and the most the orb can hold): a large number lets a weak bot play
    // on into waves it would not reach, to measure them.
    if let v = env["LIVES0"].flatMap(Int.init) { t.startingLives = v; t.maxLives = max(t.maxLives, v) }
    return t
}

private func redoubtWaves() -> RedoubtWaves {
    let env = ProcessInfo.processInfo.environment
    var w = env["BEFORE6"] == "1" ? RedoubtWaves.beforeGleanersThroughWave : RedoubtWaves()
    if let v = env["CROWD"].flatMap(Double.init) { w.crowdScale = v }
    if let v = env["QUOTA0"].flatMap(Double.init) { w.quotaFirst = v }
    if let v = env["QUOTASTEP"].flatMap(Double.init) { w.quotaGrowth = v }
    if let v = env["SIDES"] { w.entrySides = v.split(separator: ",").compactMap { Int($0) } }
    if let v = env["EASE0"].flatMap(Double.init) { w.crowdEaseStart = v }
    if let v = env["EASESTEP"].flatMap(Double.init) { w.crowdEaseGrowth = v }
    if let v = env["SPITEASE"].flatMap(Double.init) { w.spitterDebutSlowdown = v }
    if let v = env["SPITWAVES"].flatMap(Double.init) { w.spitterEaseWaves = v }
    if let v = env["PUSH"].flatMap(Int.init) { w.pushAndScatter = v != 0 }
    if let v = env["SCATTER"] { w.scatterShare = v.split(separator: ",").compactMap { Double($0) } }
    if let v = env["GLDELAY"].flatMap(Double.init) { w.gleanerDebutDelay = v }
    if let v = env["GLDRAG"].flatMap(Double.init) { w.gleanerDebutDragSlowdown = v }
    if let v = env["GLEASE"].flatMap(Double.init) { w.gleanerEaseWaves = v }
    if let v = env["GLRAMP"].flatMap(Int.init) { w.gleanerRamp = v != 0 }
    if let v = env["LATESCATTER"].flatMap(Int.init) { w.lateArrivalsScatter = v != 0 }
    if let v = env["GLSTEPS"] { w.gleanerRampEase = v.split(separator: ",").compactMap { Double($0) } }
    if let v = env["BURSLOW"].flatMap(Double.init) { w.burrowDebutSlowdown = v }
    if let v = env["BUREASE"].flatMap(Double.init) { w.burrowEaseWaves = v }
    if let v = env["BURN"].flatMap(Int.init) { w.burrowsAtDebut = v }
    if let v = env["GLTHRU"].flatMap(Int.init) { w.gleanersThroughWave = v != 0 }
    if let v = env["GLFIRST"].flatMap(Int.init) { w.gleanerFirstGroup = v }
    if let v = env["GLSPREAD"].flatMap(Double.init) { w.gleanerSpreadEnd = v }
    if let v = env["GLGAP"].flatMap(Double.init) { w.gleanerFallbackGap = v }
    if let v = env["SEIZE"] { w.seizeTimes = v.split(separator: ",").compactMap { Double($0) } }
    if let v = env["GLSTART"].flatMap(Double.init) { w.gleanerSpreadStart = v }
    if let v = env["SPITN"] { w.spitterCounts = v.split(separator: ",").compactMap { Int($0) } }
    if let v = env["GLARRIVE"] { w.gleanerFirstArrival = v.split(separator: ",").compactMap { Double($0) } }
    if let v = env["SEIZEMIN"].flatMap(Double.init) { w.seizeTimeFloor = v }
    if let v = env["GLMINGAP"].flatMap(Double.init) { w.gleanerLeastGap = v }
    if let v = env["DRAGMIN"].flatMap(Double.init) { w.leastDragSpeed = v }
    if let v = env["APPEASE"].flatMap(Int.init) { w.easeByAppearance = v != 0 }
    if let v = env["SPITSTEPS"] { w.spitterRampEase = v.split(separator: ",").compactMap { Double($0) } }
    if let v = env["BURSTEPS"] { w.burrowRampEase = v.split(separator: ",").compactMap { Double($0) } }
    if let v = env["SPITSHOTE"].flatMap(Double.init) { w.spitterDebutShotSpeed = v }
    if let v = env["SPITLEAD"].flatMap(Double.init) { w.spitterDebutLead = v }
    return w
}

private struct RedoubtStats {
    var seed: UInt64 = 0
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
    var spitterShotsByWave: [Int: Int] = [:]
    var livesAtStart: [Int: Int] = [:]
    var burrowSpawnsByWave: [Int: Int] = [:]
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
    /// Of the steps with none, those while the wave still had Skitters to send (mid-wave rather
    /// than the last stragglers on their way in).
    var emptyWithQuota = 0
    var waveSeconds: [Int: Double] = [:]
    /// Distance from the orb (alive) of every enemy as it lands from its telegraph.
    var landings: [Double] = []
    /// Pressure on the orb while it is alive and fighting, per wave: histograms of the enemies
    /// within 120 and within 200 units, and of how many of eight 45-degree sectors round it hold
    /// an enemy within 150 (how surrounded it is). Also all enemies on the floor (sum, peak).
    var near120: [Int: [Int]] = [:]
    var near200: [Int: [Int]] = [:]
    var blocked: [Int: [Int]] = [:]
    var floorSum: [Int: Int] = [:]
    var floorPeak: [Int: Int] = [:]
    /// Each loss of the orb: wave, enemies within 150 just before, sectors blocked, seconds since
    /// an enemy last landed within 250 of it.
    var deaths: [(wave: Int, near: Int, blocked: Int, sinceLanding: Double, cause: String)] = []
    var lastNearLanding = -1e9
    /// Colonist pressure per wave (see `RedoubtSeizures`).
    var seizures: [Int: RedoubtSeizures] = [:]
    var seizedAt: [Int: Double] = [:]
    /// Gleaner telegraphs (first marker only), per wave: seconds from the wave's start, and how
    /// many shared their step with another Gleaner's telegraph.
    var gleanerMarks: [Int: [Double]] = [:]
    var gleanerSameStep: [Int: Int] = [:]
    var gleanerMarked: Set<Int> = []
    /// Each drag's speed on its first step after the seizure (its own movement, units a second).
    var dragSpeeds: [Double] = []
    var dragging: [Int: Int] = [:]
    /// Fighting steps with the quota spent and nothing on the floor or on its way: the wave held
    /// open only by Gleaners still to come.
    var gleanerStallSteps: [Int: Int] = [:]
}

/// How fast a wave's colonists were seized and lost, timed from the wave's start.
private struct RedoubtSeizures {
    var firstSeize: Double?
    /// Distinct colonists seized, and colonists taken (by anything: a Gleaner's drag or a Skitter
    /// or Husk at the end of the line), within 10 s, 20 s and by the wave's end.
    var seized10 = 0, seized20 = 0, seizedAll = 0
    var lost10 = 0, lost20 = 0, lostAll = 0
    var byGleaner = 0
    var crushed = 0
    var freed = 0
    /// Seconds from a seizure to the colonist being lost, for drags nobody broke.
    var drags: [Double] = []
    var seizedIDs: Set<Int> = []
}

/// Enemies within 120 and 200 of the orb, and the sectors of eight holding one within 150.
private func redoubtPressure(_ run: RedoubtRun) -> (Int, Int, Int) {
    var n120 = 0, n200 = 0
    var sectors = [Bool](repeating: false, count: 8)
    let o = run.orb.pos
    for e in run.enemies {
        let d = e.pos - o
        let r = d.length - e.radius
        if r < 200 { n200 += 1 }
        if r < 120 { n120 += 1 }
        if r < 150 {
            var a = atan2(d.y, d.x)
            if a < 0 { a += 2 * .pi }
            sectors[min(Int(a / (.pi / 4)), 7)] = true
        }
    }
    return (n120, n200, sectors.count { $0 })
}

private func bump(_ h: inout [Int: [Int]], _ w: Int, _ v: Int) {
    var a = h[w] ?? []
    if a.count <= v { a += [Int](repeating: 0, count: v + 1 - a.count) }
    a[v] += 1
    h[w] = a
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
    var run = RedoubtRun(seed: seed, tuning: tuning, waves: redoubtWaves())
    var pilot = RedoubtPilot(skill: skill, seed: seed)
    var stats = RedoubtStats()
    stats.seed = seed
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
            if shootable == 0 {
                stats.emptySteps[w, default: 0] += 1
                if run.quota > 0 { stats.emptyWithQuota += 1 }
            }
            stats.floorSum[w, default: 0] += run.enemies.count
            stats.floorPeak[w] = max(stats.floorPeak[w] ?? 0, run.enemies.count)
            if run.orb.isAlive {
                let (a, b, c) = redoubtPressure(run)
                bump(&stats.near120, w, a)
                bump(&stats.near200, w, b)
                bump(&stats.blocked, w, c)
            }
        }
        do {
            let w = run.phase == .fighting ? run.wave : run.wave + 1
            var marks = 0
            for event in events {
                if case .arrivalTelegraphed(let id, .gleaner, _) = event, stats.gleanerMarked.insert(id).inserted {
                    marks += 1
                    // Shown with the opening crowd before the wave began: negative.
                    let at: Double = if case .intermission(let left) = run.phase { -left } else { t - (stats.waveStarts[w] ?? t) }
                    stats.gleanerMarks[w, default: []].append(at)
                }
            }
            if marks >= 2 { stats.gleanerSameStep[w, default: 0] += marks }
            for enemy in run.enemies where enemy.role == .gleaner {
                if case .dragging = enemy.state {
                    // The seizing step leaves it still; the next is its first drag step.
                    stats.dragging[enemy.id, default: 0] += 1
                    if stats.dragging[enemy.id] == 2 { stats.dragSpeeds.append(enemy.vel.length) }
                } else {
                    stats.dragging[enemy.id] = nil
                }
            }
            if run.phase == .fighting, run.quota == 0, run.arrivals.isEmpty, run.enemiesHoldingWave > 0,
               !run.enemies.contains(where: { $0.role.holdsWave }) {
                stats.gleanerStallSteps[run.wave, default: 0] += 1
            }
        }
        for event in events {
            switch event {
            case .enemyArrived(_, _, let at):
                if run.orb.isAlive {
                    stats.landings.append((at - run.orb.pos).length)
                    if (at - run.orb.pos).length < 250 { stats.lastNearLanding = t }
                }
            case .waveStarted(let w, let colonists):
                stats.waveStarts[w] = t
                stats.colonistsByWave[w] = colonists
                stats.livesAtStart[w] = run.orb.lives
            case .waveCleared(let w, let safe, _):
                stats.savedByWave[w, default: 0] += safe
                stats.waveSeconds[w] = t - (stats.waveStarts[w] ?? t)
            case .colonistDelivered:
                stats.savedByWave[run.wave, default: 0] += 1
            case .orbDestroyed:
                stats.deathsByWave[run.wave, default: 0] += 1
                stats.causes[redoubtCause(before), default: 0] += 1
                let (_, _, sectors) = redoubtPressure(before)
                let near = before.enemies.count { ($0.pos - before.orb.pos).length - $0.radius < 150 }
                stats.deaths.append((run.wave, near, sectors, t - stats.lastNearLanding, redoubtCause(before)))
                if stats.firstDeath == nil { stats.firstDeath = t }
            case .colonistTaken(let id, let by, _, _):
                stats.taken[by.rawValue, default: 0] += 1
                stats.lost += 1
                let since = t - (stats.waveStarts[run.wave] ?? t)
                var s = stats.seizures[run.wave] ?? RedoubtSeizures()
                if since <= 10 { s.lost10 += 1 }
                if since <= 20 { s.lost20 += 1 }
                s.lostAll += 1
                if by == .gleaner {
                    s.byGleaner += 1
                    if let at = stats.seizedAt[id] { s.drags.append(t - at) }
                }
                stats.seizedAt[id] = nil
                stats.seizures[run.wave] = s
            case .colonistCrushed(let id, _, _):
                stats.crushed += 1
                stats.lost += 1
                stats.seizures[run.wave, default: RedoubtSeizures()].crushed += 1
                stats.seizedAt[id] = nil
            case .colonistSeized(let id, _, _):
                let since = t - (stats.waveStarts[run.wave] ?? t)
                var s = stats.seizures[run.wave] ?? RedoubtSeizures()
                if s.firstSeize == nil { s.firstSeize = since }
                if s.seizedIDs.insert(id).inserted {
                    if since <= 10 { s.seized10 += 1 }
                    if since <= 20 { s.seized20 += 1 }
                    s.seizedAll += 1
                }
                stats.seizedAt[id] = t
                stats.seizures[run.wave] = s
            case .colonistFreed(let id, _):
                stats.seizures[run.wave, default: RedoubtSeizures()].freed += 1
                stats.seizedAt[id] = nil
            case .powerCutBegan:
                stats.powerCuts += 1
                stats.powerCutWaves.append(run.wave)
            case .enemyFired: stats.spitterShotsByWave[run.wave, default: 0] += 1
            case .burrowSpawned: stats.burrowSpawnsByWave[run.wave, default: 0] += 1
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

/// `MAP=<seed>[,<seed>...]` (optional `MAPWAVES=5`, `MAPBOT=novice`): instead of the statistics,
/// plays each seed with the bot and prints, as each of the first waves is readied, where its
/// opening crowd's arrivals sit: a 45 x 15 grid of the floor (one cell is 20 x 40 units, north at
/// the top), the orb `O`, colonists `+`, and one letter per role (S Skitter, G Gleaner, P Spitter,
/// B Burrow, T Thresher, H Husk; a cell holding several shows the rarest). Under each map: how
/// many arrivals are nearest each wall.
private func printRedoubtMaps(_ spec: String) {
    let env = ProcessInfo.processInfo.environment
    let waves = env["MAPWAVES"].flatMap(Int.init) ?? 5
    let skill = RedoubtPilot.Skill(rawValue: env["MAPBOT"] ?? "novice") ?? .novice
    let letters: [RedoubtRole: Character] = [.skitter: "S", .gleaner: "G", .spitter: "P", .burrow: "B", .thresher: "T", .husk: "H"]
    let rank: [Character: Int] = [" ": 0, "+": 1, "S": 2, "G": 3, "P": 4, "H": 5, "T": 6, "B": 7, "O": 9]
    for seed in spec.split(separator: ",").compactMap({ UInt64($0) }) {
        var run = RedoubtRun(seed: seed, tuning: redoubtTuning(), waves: redoubtWaves())
        var pilot = RedoubtPilot(skill: skill, seed: seed)
        print("== map: seed \(seed), \(skill.rawValue) bot")
        var shown = 0
        while shown < waves, !run.isGameOver, run.tick < 20 * 60 * 120 {
            let events = run.step(pilot.input(for: run))
            guard events.contains(where: { if case .airlockOpened = $0 { true } else { false } }) else { continue }
            shown += 1
            let cols = 45, rows = 15
            let w = run.arenaSize.x, h = run.arenaSize.y
            var grid = [[Character]](repeating: [Character](repeating: " ", count: cols), count: rows)
            func put(_ p: Vec2, _ c: Character) {
                let x = min(max(Int(p.x / w * Double(cols)), 0), cols - 1)
                let y = min(max(rows - 1 - Int(p.y / h * Double(rows)), 0), rows - 1)
                if (rank[c] ?? 0) >= (rank[grid[y][x]] ?? 0) { grid[y][x] = c }
            }
            for c in run.colonists { put(c.pos, "+") }
            var nearest: [String: Int] = ["N": 0, "S": 0, "E": 0, "W": 0]
            for a in run.arrivals {
                put(a.pos, letters[a.role] ?? "?")
                let gaps = [("N", h - a.pos.y), ("S", a.pos.y), ("E", w - a.pos.x), ("W", a.pos.x)]
                nearest[gaps.min { $0.1 < $1.1 }!.0, default: 0] += 1
            }
            put(run.orb.pos, "O")
            print(String(format: "wave %d: %d arrivals, orb at (%.0f, %.0f)", run.wave + 1, run.arrivals.count, run.orb.pos.x, run.orb.pos.y)
                  + "  main wall: \(run.entrySides.first.map { "\($0)" } ?? "-")")
            print("+" + String(repeating: "-", count: cols) + "+")
            for row in grid { print("|" + String(row) + "|") }
            print("+" + String(repeating: "-", count: cols) + "+")
            print("nearest wall:", ["N", "E", "S", "W"].map { "\($0) \(nearest[$0]!)" }.joined(separator: "  "))
        }
        print()
    }
}

func runRedoubt(_ args: [String]) {
    if let spec = ProcessInfo.processInfo.environment["MAP"] {
        printRedoubtMaps(spec)
        return
    }
    let seeds = args.count > 0 ? Int(args[0]) ?? 40 : 40
    let maxMinutes = args.count > 1 ? Double(args[1]) ?? 20 : 20
    let names = args.count > 2 ? Array(args[2...]) : ["idle", "novice", "competent", "wallCircler", "cornerCamper"]
    let tuning = redoubtTuning()
    let debut = Dictionary(uniqueKeysWithValues: RedoubtWaves.debut.map { ($0.wave, $0.role.rawValue) })
    for name in names {
        let skill = RedoubtPilot.Skill(rawValue: name) ?? .competent
        var all: [RedoubtStats] = []
        for i in 0..<seeds {
            all.append(playRedoubt(skill: skill, seed: UInt64((ProcessInfo.processInfo.environment["SEEDBASE"].flatMap(Int.init) ?? 1000) + i * 7919), maxMinutes: maxMinutes, tuning: tuning))
        }
        func col(_ f: (RedoubtStats) -> Double) -> String { q3(all.map(f)) }
        print("== redoubt \(name): \(seeds) seeds, cap \(Int(maxMinutes)) min   median [q1 q3]")
        print("survival s        ", col { $0.survival })
        print("first death s     ", col { $0.firstDeath ?? $0.survival })
        print("wave reached      ", col { Double($0.wave) })
        print("score             ", col { Double($0.score) }, " / min", col { Double($0.score) / max($0.survival / 60, 0.01) })
        print("survival min..max  ", String(format: "%.0f..%.0f s", all.map(\.survival).min() ?? 0, all.map(\.survival).max() ?? 0),
              " wave min..max \(all.map(\.wave).min() ?? 0)..\(all.map(\.wave).max() ?? 0)",
              " reached the cap: \(all.filter { $0.survival >= maxMinutes * 60 - 0.01 }.count)",
              all.contains { $0.survival >= maxMinutes * 60 - 0.01 }
                ? "(seeds \(all.filter { $0.survival >= maxMinutes * 60 - 0.01 }.map { "\($0.seed) w\($0.wave)" }.joined(separator: ", ")))" : "")
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
        // Spitter shots and Burrow spawns per game in each wave (over the games that reached it),
        // the share of those games with no Spitter shot in the wave, and the share of all games
        // ending in it.
        var lives = "lives at wave start", spits = "spitter shots/game ", none = "no spitter shot    ", pours = "burrow spawns/game ", ends = "games ending in    "
        for w in 1...max(min(maxWave, 16), 1) {
            let reached = all.filter { $0.wave >= w }
            guard !reached.isEmpty else { continue }
            let n = Double(reached.count)
            lives += String(format: " w%d:%.2f", w, Double(reached.reduce(0) { $0 + ($1.livesAtStart[w] ?? 0) }) / n)
            spits += String(format: " w%d:%.1f", w, Double(reached.reduce(0) { $0 + ($1.spitterShotsByWave[w] ?? 0) }) / n)
            if w >= 3 { none += String(format: " w%d:%.0f%%", w, 100 * Double(reached.count { ($0.spitterShotsByWave[w] ?? 0) == 0 }) / n) }
            pours += String(format: " w%d:%.1f", w, Double(reached.reduce(0) { $0 + ($1.burrowSpawnsByWave[w] ?? 0) }) / n)
            ends += String(format: " w%d:%.0f%%", w, 100 * Double(all.count { $0.wave == w }) / Double(all.count))
        }
        print(lives)
        print(spits)
        print(none)
        print(pours)
        print(ends)
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
        print(empty, " steps:", all.reduce(0) { total, g in total + g.emptySteps.values.reduce(0, +) },
              " with quota left:", all.reduce(0) { $0 + $1.emptyWithQuota })
        print(mean)
        print(length)
        // Pressure on the orb, per wave: mean and 90th percentile.
        func merged(_ key: KeyPath<RedoubtStats, [Int: [Int]]>, _ w: Int) -> [Int] {
            var h: [Int] = []
            for g in all {
                guard let a = g[keyPath: key][w] else { continue }
                if h.count < a.count { h += [Int](repeating: 0, count: a.count - h.count) }
                for (i, v) in a.enumerated() { h[i] += v }
            }
            return h
        }
        func describe(_ h: [Int]) -> String {
            let n = h.reduce(0, +)
            guard n > 0 else { return "-" }
            let mean = Double(h.enumerated().reduce(0) { $0 + $1.offset * $1.element }) / Double(n)
            var acc = 0, p90 = 0
            for (i, v) in h.enumerated() { acc += v; if Double(acc) >= 0.9 * Double(n) { p90 = i; break } }
            return String(format: "%.1f/%d", mean, p90)
        }
        let lastWave = max(min(maxWave, 16), 1)
        var p120 = "near120 mean/p90   ", p200 = "near200 mean/p90   ", pBlk = "sectors8 mean/p90  "
        var fl = "floor all mean/pk  "
        for w in 1...lastWave {
            let steps = all.reduce(0) { $0 + ($1.fightSteps[w] ?? 0) }
            guard steps > 0 else { continue }
            p120 += " w\(w):" + describe(merged(\.near120, w))
            p200 += " w\(w):" + describe(merged(\.near200, w))
            pBlk += " w\(w):" + describe(merged(\.blocked, w))
            let sum = all.reduce(0) { $0 + ($1.floorSum[w] ?? 0) }
            let peak = all.map { $0.floorPeak[w] ?? 0 }.max() ?? 0
            fl += String(format: " w%d:%.0f/%d", w, Double(sum) / Double(steps), peak)
        }
        print(p120)
        print(p200)
        print(pBlk)
        print(fl)
        var dl = "deaths: near150/sectors/since-landing (mean, median s) by wave"
        for w in 1...min(lastWave, 8) {
            let d = all.flatMap(\.deaths).filter { $0.wave == w }
            guard !d.isEmpty else { continue }
            let since = d.map(\.sinceLanding).sorted()
            var causes: [String: Int] = [:]
            for x in d { causes[x.cause, default: 0] += 1 }
            dl += String(format: " w%d[n%d %.1f %.1f %.1f ", w, d.count, Double(d.reduce(0) { $0 + $1.near }) / Double(d.count),
                         Double(d.reduce(0) { $0 + $1.blocked }) / Double(d.count), since[since.count / 2])
                + causes.sorted { $0.value > $1.value }.map { "\($0.key.prefix(4)):\($0.value)" }.joined(separator: ",") + "]"
        }
        print(dl)
        // Colonist pressure, per wave, over the games that reached it: seconds to the first
        // seizure (median, 10th percentile; a wave with none counts as its length), the share of
        // its colonists seized and lost within 10 s, 20 s and by its end, the games losing 3 or
        // more in its first 20 s, seize-to-lost seconds for unbroken drags (median, min), freed
        // per game.
        print("colonists by wave: first seize med/p10 | seized 10s/20s/end | lost 10s/20s/end (gleaner) | games lost>=3 in 20s | drag med/min s | freed/game | crushed/game | seizures in first 10s")
        for w in 1...min(lastWave, 12) {
            let reached = all.filter { $0.wave >= w && $0.colonistsByWave[w] != nil }
            guard !reached.isEmpty else { continue }
            let total = Double(reached.reduce(0) { $0 + ($1.colonistsByWave[w] ?? 0) })
            let s = reached.map { $0.seizures[w] ?? RedoubtSeizures() }
            let firsts = zip(reached, s).map { g, x in x.firstSeize ?? g.waveSeconds[w] ?? (g.survival - (g.waveStarts[w] ?? 0)) }.sorted()
            func pct(_ a: [Double], _ p: Double) -> Double { a.isEmpty ? .nan : a[min(Int(Double(a.count - 1) * p + 0.5), a.count - 1)] }
            func share(_ f: (RedoubtSeizures) -> Int) -> Double { Double(s.reduce(0) { $0 + f($1) }) / total }
            let drags = s.flatMap(\.drags).sorted()
            let n = Double(reached.count)
            print(String(format: "  w%-2d n%-3d %5.1f/%5.1f | %.2f/%.2f/%.2f | %.2f/%.2f/%.2f (%.2f) | %4.1f%% | %4.1f/%4.1f | %.2f | %.2f | %3.0f%%",
                         w, reached.count, pct(firsts, 0.5), pct(firsts, 0.1),
                         share(\.seized10), share(\.seized20), share(\.seizedAll),
                         share(\.lost10), share(\.lost20), share(\.lostAll), share(\.byGleaner),
                         100 * Double(s.count { $0.lost20 >= 3 }) / n,
                         pct(drags, 0.5), drags.first ?? .nan,
                         Double(s.reduce(0) { $0 + $1.freed }) / n, Double(s.reduce(0) { $0 + $1.crushed }) / n,
                         100 * Double(s.reduce(0) { $0 + $1.seized10 }) / Double(max(s.reduce(0) { $0 + $1.seizedAll }, 1))))
        }
        // Gleaners through the wave: per wave, telegraphs sharing a step with another / all, the
        // largest gap between consecutive ones (s), and seconds per game the wave was held open
        // only by Gleaners still to come.
        var same = "gleaners same step ", gaps = "gleaner max gap s  ", stall = "gleaner stall s/gm "
        var allGaps: [Double] = []
        for w in 1...min(lastWave, 16) {
            let marks = all.compactMap { $0.gleanerMarks[w] }
            guard !marks.isEmpty else { continue }
            let n = marks.reduce(0) { $0 + $1.count }
            same += " w\(w):\(all.reduce(0) { $0 + ($1.gleanerSameStep[w] ?? 0) })/\(n)"
            let g = marks.flatMap { m in zip(m, m.dropFirst()).map { $1 - $0 } }
            allGaps += g
            gaps += String(format: " w%d:%.1f", w, g.max() ?? 0)
            let reached = all.filter { $0.wave >= w }
            stall += String(format: " w%d:%.2f", w, Double(reached.reduce(0) { $0 + ($1.gleanerStallSteps[w] ?? 0) }) * RedoubtRun.timeStep / Double(max(reached.count, 1)))
        }
        print(same)
        print(gaps, String(format: " all max %.2f, min %.2f", allGaps.max() ?? 0, allGaps.min() ?? 0))
        print(stall)
        let speeds = all.flatMap(\.dragSpeeds).sorted()
        if !speeds.isEmpty {
            func at(_ p: Double) -> Double { speeds[min(Int(Double(speeds.count) * p), speeds.count - 1)] }
            print(String(format: "drag speed (first step) n%d  min %.2f  0.5%% %.2f  1%% %.2f  3%% %.2f  median %.1f   under 8: %.2f%%",
                         speeds.count, speeds[0], at(0.005), at(0.01), at(0.03), at(0.5),
                         100 * Double(speeds.count { $0 < 8 - 1e-6 }) / Double(speeds.count)))
        }
        print(String(format: "delivered/game %.1f mean, charges earned %.2f mean, score %.0f mean",
                     Double(all.reduce(0) { $0 + $1.delivered }) / Double(all.count),
                     Double(all.reduce(0) { $0 + $1.delivered / tuning.colonistsPerCharge }) / Double(all.count),
                     Double(all.reduce(0) { $0 + $1.score }) / Double(all.count)))
        let meanWave = Double(all.reduce(0) { $0 + $1.wave }) / Double(all.count)
        let spread = all.reduce(0.0) { $0 + (Double($1.wave) - meanWave) * (Double($1.wave) - meanWave) }
        print(String(format: "mean wave %.2f (standard error %.3f)", meanWave,
                     (spread / Double(max(all.count - 1, 1))).squareRoot() / Double(all.count).squareRoot()))
        print(String(format: "mean wave %.2f, lives lost in w1+w2 %.2f mean",
                     meanWave,
                     Double(all.reduce(0) { $0 + ($1.deathsByWave[1] ?? 0) + ($1.deathsByWave[2] ?? 0) }) / Double(all.count)))
        let totalSteps = all.reduce(0) { $0 + $1.steps }
        let totalTime = all.reduce(0.0) { $0 + $1.stepSeconds }
        print(String(format: "step time          %.2f us mean over %d steps", totalTime / Double(max(totalSteps, 1)) * 1e6, totalSteps))
        print()
    }
}
