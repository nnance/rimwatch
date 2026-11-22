import Foundation
import GameCore
import RiftwingCore

// `Harness riftwing [seeds] [maxMinutes] [skill...]`: runs Riftwing's scripted pilots over many
// seeds and prints difficulty and rescue statistics. Skills: idle, novice, competent,
// topLedgeSitter, roofHoverer, ventRider, lowHider, levelBouncer (default: all of them).
// SEEDBASE moves the seed set (default 1000) to check a result is not luck of the seeds.
// Environment overrides for the main tuning numbers (see `riftwingTuning` and `riftwingWaves`):
// flight GRAV FLAP MAXRISE AIRACC AIRMAX REOPEN DIVEG; the clash MARGIN ROOFBAND LENIENCY;
// lives SAFE INVULN EXTRA LIVES0; pods PODLIFE0 PODSHRINK PODFLOOR PODKNOCK PODGRAV PODTERM;
// the breath BREATH BREATHREP BREATHLVL BREATHGROW; opponents SKIP STRCLIMB STRREACH STRTIME
// STRREC STRPAT WARDH WARDDIVE MINEGAP GLSPEED GLCARRY; waves RAMP=1,0.7,... CONC=2,2,3,...
// SENDGAP GLDELAY GLDELAYEASE GLSLOW GLGRABEASE GLCARRYEASE; FIGURE for the size factor.
// TRACE=<seed> (TRACEBOT, TRACEFROM, TRACETO, TRACEEVERY) prints one game; GOLDEN=1 prints the
// determinism test's fingerprint from this build.

private func riftwingTuning() -> RiftwingTuning {
    var t = RiftwingTuning()
    let env = ProcessInfo.processInfo.environment
    if let v = env["FIGURE"].flatMap(Double.init) { t.figureScale = v }
    if let v = env["GRAV"].flatMap(Double.init) { t.gravity = v }
    if let v = env["FLAP"].flatMap(Double.init) { t.flapImpulse = v }
    if let v = env["MAXRISE"].flatMap(Double.init) { t.maxRise = v }
    if let v = env["AIRACC"].flatMap(Double.init) { t.airAccel = v }
    if let v = env["AIRMAX"].flatMap(Double.init) { t.maxAirSpeed = v }
    if let v = env["MARGIN"].flatMap(Double.init) { t.clashMargin = v }
    if let v = env["ROOFBAND"].flatMap(Double.init) { t.roofBand = v }
    if let v = env["REOPEN"].flatMap(Double.init) { t.wingReopen = v }
    if let v = env["DIVEG"].flatMap(Double.init) { t.diveGravity = v }
    if let v = env["SAFE"].flatMap(Double.init) { t.safeDistance = v }
    if let v = env["INVULN"].flatMap(Double.init) { t.respawnInvulnerability = v }
    if let v = env["EXTRA"].flatMap(Int.init) { t.extraLifeEvery = v }
    if let v = env["PODLIFE0"].flatMap(Double.init) { t.podLifeFirst = v }
    if let v = env["PODSHRINK"].flatMap(Double.init) { t.podLifeShrink = v }
    if let v = env["PODFLOOR"].flatMap(Double.init) { t.podLifeFloor = v }
    if let v = env["BREATH"].flatMap(Double.init) { t.breathAfter = v }
    if let v = env["BREATHREP"].flatMap(Double.init) { t.breathRepeat = v }
    if let v = env["BREATHLVL"].flatMap(Double.init) { t.breathLevel = v }
    if let v = env["BREATHGROW"].flatMap(Double.init) { t.breathGrowth = v }
    if let v = env["MINEGAP"].flatMap(Double.init) { t.mineInterval = v }
    if let v = env["GLSPEED"].flatMap(Double.init) { t.gleanerSpeed = v }
    if let v = env["GLCARRY"].flatMap(Double.init) { t.gleanerMinCarry = v }
    if let v = env["STRCLIMB"].flatMap(Double.init) { t.strikerClimb = v }
    if let v = env["WARDH"].flatMap(Double.init) { t.wardenHeight = v }
    if let v = env["SKIP"].flatMap(Double.init) { t.gliderSkip = v }
    if let v = env["PODKNOCK"].flatMap(Double.init) { t.podKnock = v }
    if let v = env["STRREACH"].flatMap(Double.init) { t.strikerStrikeReach = v }
    if let v = env["STRTIME"].flatMap(Double.init) { t.strikerStrikeTime = v }
    if let v = env["STRREC"].flatMap(Double.init) { t.strikerRecover = v }
    if let v = env["STRPAT"].flatMap(Double.init) { t.strikerPatience = v }
    if let v = env["WARDDIVE"].flatMap(Double.init) { t.wardenDiveReach = v }
    if let v = env["PODGRAV"].flatMap(Double.init) { t.podGravity = v }
    if let v = env["PODTERM"].flatMap(Double.init) { t.podTerminal = v }
    // Lives to start with (and the most the rig can hold): a large number lets a weak bot play
    // on into waves it would not reach, to measure them.
    if let v = env["LIVES0"].flatMap(Int.init) { t.startingLives = v; t.maxLives = max(t.maxLives, v) }
    return t
}

private func riftwingWaves() -> RiftwingWaves {
    var w = RiftwingWaves()
    let env = ProcessInfo.processInfo.environment
    if let v = env["RAMP"] { w.rampEase = v.split(separator: ",").compactMap { Double($0) } }
    if let v = env["CONC"] { w.concurrency = v.split(separator: ",").compactMap { Int($0) } }
    if let v = env["SENDGAP"].flatMap(Double.init) { w.sendGap = v }
    if let v = env["LENIENCY"].flatMap(Double.init) { w.clashLeniency = v }
    if let v = env["GLDELAY"].flatMap(Double.init) { w.gleanerDelayBase = v }
    if let v = env["GLDELAYEASE"].flatMap(Double.init) { w.gleanerDelayEase = v }
    if let v = env["GLSLOW"].flatMap(Double.init) { w.gleanerSlowdown = v }
    if let v = env["GLGRABEASE"].flatMap(Double.init) { w.gleanerGrabEase = v }
    if let v = env["GLCARRYEASE"].flatMap(Double.init) { w.gleanerCarryEase = v }
    return w
}

/// One wave's measurements in one game.
private struct RiftwingWaveStats {
    var length: Double?
    var livesLost = 0
    var dropped = 0
    var freed = 0
    var caught = 0
    var lost: [String: Int] = [:]
    var lieTimes: [Double] = []
    var firstLoss: Double?
    var breaths = 0
    var carryTimes: [Double] = []
}

private struct RiftwingStats {
    var survival = 0.0
    var wave = 0
    var score = 0
    var saved = 0
    var causes: [String: Int] = [:]
    var waves: [Int: RiftwingWaveStats] = [:]
    var flaps = 0
    var stoops = 0
    var clashes: [String: Int] = [:]
    var extraLives = 0
    var lampsOut = 0
    var landings: [Double] = []
    var stepSeconds = 0.0
    var steps = 0
}

private func cause(_ c: RiftwingLossCause) -> String {
    switch c {
    case .clash(_, let role): "clash-\(role.rawValue)"
    case .mine: "mine"
    case .rift: "rift"
    case .breath: "breath"
    }
}

private func playRiftwing(skill: RiftwingPilot.Skill, seed: UInt64, maxMinutes: Double) -> RiftwingStats {
    var run = RiftwingRun(seed: seed, tuning: riftwingTuning(), waves: riftwingWaves())
    var pilot = RiftwingPilot(skill: skill, seed: seed)
    var stats = RiftwingStats()
    var waveStart = 0.0
    var carriedAt: [Int: Double] = [:]
    let clock = ContinuousClock()
    for _ in 0..<Int(maxMinutes * 60 * 120) {
        let input = pilot.input(for: run)
        let before = run
        let start = clock.now
        let events = run.step(input)
        let took = clock.now - start
        stats.stepSeconds += Double(took.components.seconds) + Double(took.components.attoseconds) / 1e18
        stats.steps += 1
        let t = Double(run.tick) * RiftwingRun.timeStep
        let w = run.wave
        for event in events {
            switch event {
            case .waveStarted:
                waveStart = t
                stats.waves[w, default: RiftwingWaveStats()] = stats.waves[w] ?? RiftwingWaveStats()
            case .waveCleared(let cleared, _, _):
                stats.waves[cleared, default: RiftwingWaveStats()].length = t - waveStart
            case .riderLost(_, _, let c):
                stats.waves[w, default: RiftwingWaveStats()].livesLost += 1
                stats.causes[cause(c), default: 0] += 1
            case .podDropped:
                stats.waves[w, default: RiftwingWaveStats()].dropped += 1
            case .podFreed(let id, _, _, _):
                stats.waves[w, default: RiftwingWaveStats()].freed += 1
                if let pod = before.pod(id) { stats.waves[w, default: RiftwingWaveStats()].lieTimes.append(pod.restedFor) }
            case .podCaught:
                stats.waves[w, default: RiftwingWaveStats()].freed += 1
                stats.waves[w, default: RiftwingWaveStats()].caught += 1
            case .podCarried(let id, _, _):
                carriedAt[id] = t
            case .podLost(let id, _, let c):
                let name: String = switch c {
                case .rift: "rift"
                case .hatched: "hatched"
                case .carried: "carried"
                case .breath: "breath"
                }
                stats.waves[w, default: RiftwingWaveStats()].lost[name, default: 0] += 1
                if stats.waves[w]?.firstLoss == nil { stats.waves[w]?.firstLoss = t - waveStart }
                if c == .carried, let at = carriedAt[id] { stats.waves[w, default: RiftwingWaveStats()].carryTimes.append(t - at) }
            case .riftBreathed:
                stats.waves[w, default: RiftwingWaveStats()].breaths += 1
            case .flapped: stats.flaps += 1
            case .clashWon(_, _, _, let stoop):
                stats.clashes["won", default: 0] += 1
                if stoop { stats.stoops += 1 }
            case .clashBounced: stats.clashes["bounced", default: 0] += 1
            case .clashLost: stats.clashes["lost", default: 0] += 1
            case .extraLife: stats.extraLives += 1
            case .lampsFailed: stats.lampsOut += 1
            case .opponentArrived(_, _, let at):
                if before.rider.isAlive { stats.landings.append(before.wrapDistance(at, before.rider.pos)) }
            default: break
            }
        }
        if run.isGameOver { break }
    }
    stats.survival = Double(run.tick) * RiftwingRun.timeStep
    stats.wave = run.wave
    stats.score = run.score
    stats.saved = run.colonistsSaved
    return stats
}

private func q3(_ values: [Double]) -> String {
    guard !values.isEmpty else { return "-" }
    let s = values.sorted()
    func q(_ p: Double) -> Double { s[min(Int(Double(s.count - 1) * p + 0.5), s.count - 1)] }
    return String(format: "%7.1f [%6.1f %6.1f]", q(0.5), q(0.25), q(0.75))
}

private func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return .nan }
    let s = values.sorted()
    return s[s.count / 2]
}

/// `TRACE=<seed> [TRACEBOT=novice] [TRACEFROM=0 TRACETO=60 TRACEEVERY=0.5]`: prints one game's
/// state every so often and its events (flaps left out), to see what a bot and the opponents do.
private func traceRiftwing(seed: UInt64) {
    let env = ProcessInfo.processInfo.environment
    let skill = RiftwingPilot.Skill(rawValue: env["TRACEBOT"] ?? "novice") ?? .novice
    let from = env["TRACEFROM"].flatMap(Double.init) ?? 0
    let to = env["TRACETO"].flatMap(Double.init) ?? 60
    let every = max(Int((env["TRACEEVERY"].flatMap(Double.init) ?? 0.5) * 120), 1)
    var run = RiftwingRun(seed: seed, tuning: riftwingTuning(), waves: riftwingWaves())
    var pilot = RiftwingPilot(skill: skill, seed: seed)
    func f(_ p: Vec2) -> String { String(format: "(%.0f,%.0f)", p.x, p.y) }
    while !run.isGameOver, Double(run.tick) / 120 < to {
        let input = pilot.input(for: run)
        let events = run.step(input)
        let t = Double(run.tick) / 120
        guard t >= from else { continue }
        for event in events {
            if case .flapped = event { continue }
            print(String(format: "%7.2f  ", t) + "\(event)")
        }
        if run.tick % every == 0 {
            let r = run.rider
            var line = String(format: "%7.2f  w%d rider ", t, run.wave) + f(r.pos) + " v" + f(r.vel)
            line += (r.isAlive ? "" : " DEAD") + (r.body.isGrounded ? " ground" : "") + (r.body.isDiving ? " dive" : "")
            line += " lives \(r.lives) tgt" + f(pilot.lastTarget) + " |"
            for o in run.opponents { line += " \(o.role.rawValue.prefix(3))\(o.id)" + f(o.pos) }
            for p in run.pods { line += " pod\(p.id)" + f(p.pos) }
            print(line)
        }
    }
}

/// `GOLDEN=1`: the fingerprint `RiftwingDeterminismTests` pins (three minutes of the competent
/// pilot on seed 1), computed in this (release) build, to check Debug and Release agree.
private func riftwingGolden() {
    var r = RiftwingRun(seed: 1)
    var pilot = RiftwingPilot(skill: .competent, seed: 1)
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    var total = 0
    func mix(_ text: String) {
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3 }
    }
    for _ in 0..<(180 * 120) {
        let events = r.step(pilot.input(for: r))
        total += events.count
        for event in events { mix("\(r.tick) \(event);") }
        if r.isGameOver { break }
    }
    mix("\(r.score) \(r.wave) \(r.colonistsSaved) \(r.rider.lives) \(r.tick)")
    print("RIFTWING GOLDEN hash \(hash) events \(total) score \(r.score) wave \(r.wave) saved \(r.colonistsSaved) lives \(r.rider.lives) tick \(r.tick)")
}

func runRiftwing(_ args: [String]) {
    if ProcessInfo.processInfo.environment["GOLDEN"] != nil {
        riftwingGolden()
        return
    }
    if let seed = ProcessInfo.processInfo.environment["TRACE"].flatMap(UInt64.init) {
        traceRiftwing(seed: seed)
        return
    }
    let seeds = args.count > 0 ? Int(args[0]) ?? 200 : 200
    let maxMinutes = args.count > 1 ? Double(args[1]) ?? 20 : 20
    let names = args.count > 2 ? Array(args[2...]) : RiftwingPilot.Skill.allCases.map(\.rawValue)
    let seedBase = ProcessInfo.processInfo.environment["SEEDBASE"].flatMap(Int.init) ?? 1000
    for name in names {
        guard let skill = RiftwingPilot.Skill(rawValue: name) else {
            print("unknown skill \(name)")
            continue
        }
        var all: [RiftwingStats] = []
        for i in 0..<seeds {
            all.append(playRiftwing(skill: skill, seed: UInt64(seedBase + i * 7919), maxMinutes: maxMinutes))
        }
        func col(_ f: (RiftwingStats) -> Double) -> String { q3(all.map(f)) }
        let waves = all.map { Double($0.wave) }
        let mean = waves.reduce(0, +) / Double(waves.count)
        let sd = (waves.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(waves.count - 1, 1))).squareRoot()
        print("== riftwing \(name): \(seeds) seeds from \(seedBase), cap \(Int(maxMinutes)) min   median [q1 q3]")
        print(String(format: "wave reached       median %.0f  mean %.2f ± %.2f (s.e.)", median(waves), mean, sd / Double(waves.count).squareRoot()))
        print("survival s        ", col { $0.survival }, " capped: \(all.filter { $0.survival >= maxMinutes * 60 - 0.01 }.count)")
        print("score             ", col { Double($0.score) }, " / min", col { Double($0.score) / max($0.survival / 60, 0.01) })
        print("colonists saved   ", col { Double($0.saved) }, " extra lives", col { Double($0.extraLives) },
              " lamps out/game", String(format: "%.2f", Double(all.reduce(0) { $0 + $1.lampsOut }) / Double(all.count)))
        var clashes: [String: Int] = [:]
        for g in all { for (k, v) in g.clashes { clashes[k, default: 0] += v } }
        print("clashes / game    ", clashes.sorted { $0.key < $1.key }.map { "\($0.key) \(String(format: "%.1f", Double($0.value) / Double(all.count)))" }.joined(separator: "  "),
              String(format: "  stoops %.1f  flaps/min %.0f", Double(all.reduce(0) { $0 + $1.stoops }) / Double(all.count),
                     Double(all.reduce(0) { $0 + $1.flaps }) / max(all.reduce(0) { $0 + $1.survival } / 60, 0.01)))
        var causes: [String: Int] = [:]
        for g in all { for (k, v) in g.causes { causes[k, default: 0] += v } }
        print("lives lost to     ", causes.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }.joined(separator: " "))
        let landings = all.flatMap(\.landings).sorted()
        if !landings.isEmpty {
            print(String(format: "arrival distance   min %.0f  1%% %.0f  median %.0f", landings[0],
                         landings[min(landings.count / 100, landings.count - 1)], landings[landings.count / 2]))
        }
        var hist: [Int: Int] = [:]
        for g in all { hist[g.wave, default: 0] += 1 }
        print("final wave hist   ", hist.sorted { $0.key < $1.key }.map { "w\($0.key):\($0.value)" }.joined(separator: " "))
        print("per wave: games reaching | lives lost/game | ending here | length s med | pods/game dropped freed caught | lost/game rift hatched carried breath | lost % | lie s med | first loss s med (games) | carry s min | breaths/game")
        let top = min(all.map(\.wave).max() ?? 0, 20)
        if top >= 1 {
            for w in 1...top {
                let reached = all.filter { $0.wave >= w }
                guard !reached.isEmpty else { continue }
                let n = Double(reached.count)
                let ws = reached.compactMap { $0.waves[w] }
                func sum(_ f: (RiftwingWaveStats) -> Int) -> Double { Double(ws.reduce(0) { $0 + f($1) }) }
                let ending = Double(all.filter { $0.wave == w && $0.survival < maxMinutes * 60 - 0.01 }.count) / Double(all.count)
                let lengths = ws.compactMap(\.length)
                let lost = { (k: String) in sum { $0.lost[k] ?? 0 } }
                let totalLost = lost("rift") + lost("hatched") + lost("carried") + lost("breath")
                let dropped = sum(\.dropped)
                let firsts = ws.compactMap(\.firstLoss)
                let carries = ws.flatMap(\.carryTimes)
                print(String(format: "  w%-2d %4d | %.2f | %4.1f%% | %5.1f | %.2f %.2f %.2f | %.2f %.2f %.2f %.2f | %4.1f%% | %5.1f | %5.1f (%d) | %4.1f | %.2f",
                             w, reached.count, sum(\.livesLost) / n, ending * 100, median(lengths),
                             dropped / n, sum(\.freed) / n, sum(\.caught) / n,
                             lost("rift") / n, lost("hatched") / n, lost("carried") / n, lost("breath") / n,
                             dropped > 0 ? totalLost / dropped * 100 : 0, median(ws.flatMap(\.lieTimes)),
                             median(firsts), firsts.count, carries.min() ?? .nan, sum(\.breaths) / n))
            }
        }
        let early = all.reduce(0) { $0 + ($1.waves[1]?.livesLost ?? 0) + ($1.waves[2]?.livesLost ?? 0) }
        let earlyDropped = all.reduce(0) { $0 + ($1.waves[1]?.dropped ?? 0) + ($1.waves[2]?.dropped ?? 0) }
        let earlyLost = all.reduce(0) { total, g in total + [1, 2].reduce(0) { $0 + (g.waves[$1]?.lost.values.reduce(0, +) ?? 0) } }
        print(String(format: "summary: mean wave %.2f, lives lost in w1+w2 %.2f a game, pods lost in w1+w2 %.1f%%, step %.2f us",
                     mean, Double(early) / Double(all.count), earlyDropped > 0 ? Double(earlyLost) / Double(earlyDropped) * 100 : 0,
                     all.reduce(0) { $0 + $1.stepSeconds } / Double(max(all.reduce(0) { $0 + $1.steps }, 1)) * 1e6))
        print()
    }
}
