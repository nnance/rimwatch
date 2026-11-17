import Foundation
import GameCore

// Usage: Harness [seeds] [maxMinutes] [skill...]
let args = CommandLine.arguments
let seeds = args.count > 1 ? Int(args[1]) ?? 40 : 40
let maxMinutes = args.count > 2 ? Double(args[2]) ?? 20 : 20
let skillNames = args.count > 3 ? Array(args[3...]) : ["idle", "novice", "competent"]

/// Environment overrides for sweeps, e.g. SAFE=120 LIFT=45.
let tuningOverride: Tuning = {
    var t = Tuning()
    let env = ProcessInfo.processInfo.environment
    if let v = env["SAFE"].flatMap(Double.init) { t.safeFallHeight = v }
    if let v = env["LIFT"].flatMap(Double.init) { t.liftSpeed = v }
    if let v = env["HSPEED"].flatMap(Double.init) { t.harvesterSpeed = v }
    if let v = env["HDESC"].flatMap(Double.init) { t.harvesterDescentSpeed = v }
    if let v = env["SUPPLY"].flatMap(Double.init) { t.supplyDelay = v }
    if let v = env["GROW"].flatMap(Double.init) { t.abductionGrowthPerWave = v }
    if let v = env["MAXS"].flatMap(Double.init) { t.abductionMaxScale = v }
    if let v = env["LGROW"].flatMap(Double.init) { t.liftGrowthPerWave = v }
    if let v = env["CATCH"].flatMap(Double.init) { t.catchRadius = v }
    if let v = env["FROM"].flatMap(Int.init) { t.abductionGrowthStart = v }
    return t
}()

FileHandle.standardError.write("tuning: safe \(tuningOverride.safeFallHeight) lift \(tuningOverride.liftSpeed)\n".data(using: .utf8)!)
struct GameStats {
    var survival = 0.0
    var wave = 0
    var score = 0
    var saved = 0
    var lost = 0
    var lostByWave5 = 0
    var colonistsAtWave6Start: Int?
    var deathsByWave: [Int: Int] = [:]
    var overheats = 0
    var blackouts = 0
    var blackoutEnds = 0
    var lossCauses: [String: Int] = [:]
    var grabs = 0
    var firstBlackoutWave: Int?
    var nearShotGaps: [Double] = []
    var waveStarts: [Int: Double] = [:]
    var firstDeath: Double?
    var firstNearShot: Double?
    var caught = 0
    var dropped = 0
    var landed = 0
    var fireHeldSeconds = 0.0
    var causes: [String: Int] = [:]
}

/// What most likely touched the ship: the closest enemy shot or enemy before the step.
func likelyCause(_ sim: Simulation) -> String {
    var best = ("?", 1e9)
    for shot in sim.projectiles where shot.owner == .enemy {
        let d = sim.world.distance(shot.pos, sim.player.pos)
        if d < best.1 { best = ("shot", d) }
    }
    for enemy in sim.enemies {
        let d = sim.world.distance(enemy.pos, sim.player.pos) - enemy.radius
        if d < best.1 { best = (enemy.kind.rawValue, d) }
    }
    return best.0
}

func play(skill: Autopilot.Skill, seed: UInt64) -> GameStats {
    var sim = Simulation(seed: seed, tuning: tuningOverride)
    var pilot = Autopilot(skill: skill, seed: seed)
    var stats = GameStats()
    let maxSteps = Int(maxMinutes * 60 * 120)
    var lastNearShot: Double?
    for _ in 0..<maxSteps {
        let input = pilot.input(for: sim)
        if input.fire { stats.fireHeldSeconds += Simulation.timeStep }
        let before = sim
        let events = sim.step(input)
        let t = Double(sim.tick) * Simulation.timeStep
        for event in events {
            switch event {
            case .waveStarted(let w):
                stats.waveStarts[w] = t
                if w == 6 { stats.colonistsAtWave6Start = sim.survivingColonists }
            case .playerDestroyed:
                stats.deathsByWave[sim.wave, default: 0] += 1
                stats.causes[likelyCause(before), default: 0] += 1
                if stats.firstDeath == nil { stats.firstDeath = t }
            case .playerOverheated: stats.overheats += 1
            case .blackoutBegan:
                stats.blackouts += 1
                if stats.firstBlackoutWave == nil { stats.firstBlackoutWave = sim.wave }
            case .blackoutEnded: stats.blackoutEnds += 1
            case .colonistGrabbed: stats.grabs += 1
            case .colonistLost(let id, _):
                let state = before.colonists.first { $0.id == id }?.state
                let cause: String = switch state {
                case .falling: "fall"
                case .held: "abducted"
                case .grounded: "outpost"
                default: "other"
                }
                stats.lossCauses[cause, default: 0] += 1
                stats.lost += 1
                if sim.wave <= 5 { stats.lostByWave5 += 1 }
            case .colonistCaught: stats.caught += 1
            case .colonistDropped: stats.dropped += 1
            case .colonistLanded: stats.landed += 1
            case .enemyFired(let at):
                if sim.world.distance(at, sim.player.pos) < 500 {
                    if let last = lastNearShot { stats.nearShotGaps.append(t - last) }
                    if stats.firstNearShot == nil { stats.firstNearShot = t }
                    lastNearShot = t
                }
            default: break
            }
        }
        if sim.isGameOver { break }
    }
    stats.survival = Double(sim.tick) * Simulation.timeStep
    stats.wave = sim.wave
    stats.score = sim.score
    stats.saved = sim.colonistsSaved
    return stats
}

func quartiles(_ values: [Double]) -> String {
    guard !values.isEmpty else { return "-" }
    let s = values.sorted()
    func q(_ p: Double) -> Double { s[min(Int(Double(s.count - 1) * p + 0.5), s.count - 1)] }
    return String(format: "%7.1f [%6.1f %6.1f]", q(0.5), q(0.25), q(0.75))
}

for name in skillNames {
    let skill: Autopilot.Skill = switch name {
    case "idle": .idle
    case "novice": .novice
    case "shooter": .shooter
    default: .competent
    }
    var all: [GameStats] = []
    for i in 0..<seeds {
        all.append(play(skill: skill, seed: UInt64(1000 + i * 7919)))
    }
    func col(_ f: (GameStats) -> Double) -> String { quartiles(all.map(f)) }
    print("== \(name): \(seeds) seeds, cap \(Int(maxMinutes)) min   median [q1 q3]")
    print("survival s        ", col { $0.survival })
    print("first death s     ", col { $0.firstDeath ?? $0.survival })
    print("wave reached      ", col { Double($0.wave) })
    print("score             ", col { Double($0.score) })
    print("colonists saved   ", col { Double($0.saved) })
    print("colonists lost    ", col { Double($0.lost) })
    print("lost by end w5    ", col { Double($0.lostByWave5) })
    print("alive at w6 start ", quartiles(all.compactMap { $0.colonistsAtWave6Start.map(Double.init) }),
          " (games reaching w6: \(all.filter { $0.colonistsAtWave6Start != nil }.count))")
    print("caught/dropped    ", col { Double($0.caught) }, "/", col { Double($0.dropped) },
          " landed safely", col { Double($0.landed) })
    print("overheats / min   ", col { Double($0.overheats) / max($0.survival / 60, 0.01) })
    print("fire held frac    ", col { $0.fireHeldSeconds / max($0.survival, 1) })
    print("blackouts / game  ", col { Double($0.blackouts) }, " games with blackout: \(all.filter { $0.blackouts > 0 }.count)")
    let withBlackout = all.filter { $0.blackouts > 0 }
    print("first blackout w  ", quartiles(withBlackout.compactMap { $0.firstBlackoutWave.map(Double.init) }),
          " recovered (ended at least once): \(withBlackout.filter { $0.blackoutEnds > 0 }.count)/\(withBlackout.count)")
    var losses: [String: Int] = [:]
    for g in all { for (k, v) in g.lossCauses { losses[k, default: 0] += v } }
    print("loss causes (all) ", losses.sorted { $0.value > $1.value }.map { "\($0.key):\($0.value)" }.joined(separator: " "),
          " grabs/game", col { Double($0.grabs) })
    print("first near shot s ", col { $0.firstNearShot ?? $0.survival })
    print("near-shot gap s   ", quartiles(all.flatMap(\.nearShotGaps)))
    var causes: [String: Int] = [:]
    for g in all { for (k, v) in g.causes { causes[k, default: 0] += v } }
    print("death causes      ", causes.sorted { $0.value > $1.value }.map { "\($0.key):\($0.value)" }.joined(separator: " "))
    var waveHist: [Int: Int] = [:]
    for g in all { waveHist[g.wave, default: 0] += 1 }
    print("final wave hist   ", waveHist.sorted { $0.key < $1.key }.map { "w\($0.key):\($0.value)" }.joined(separator: " "))
    // Deaths per wave: total deaths in wave w / games that reached wave w.
    let maxWave = all.map(\.wave).max() ?? 0
    var line = "deaths/game by wave"
    var startLine = "wave start t (med) "
    for w in 0...min(maxWave, 16) {
        let reached = all.filter { $0.wave >= w }.count
        let deaths = all.reduce(0) { $0 + ($1.deathsByWave[w] ?? 0) }
        line += String(format: " w%d:%.2f", w, reached > 0 ? Double(deaths) / Double(reached) : 0)
        let starts = all.compactMap { $0.waveStarts[w] }.sorted()
        if !starts.isEmpty { startLine += String(format: " w%d:%.0f", w, starts[starts.count / 2]) }
    }
    print(line)
    print(startLine)
    print()
}
