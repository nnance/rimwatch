import Foundation
import GameCore

/// One Redoubt run: the whole state of the dome floor and its rules. It advances in fixed steps
/// and is deterministic for a given seed and input sequence. It knows roles and positions,
/// never how anything looks or sounds.
///
/// The floor is `arenaSize` (900 x 600 by default) with the origin at the bottom-left corner
/// and y up, walled on all four sides. Everything a renderer needs is public and read-only:
/// `orb`, `enemies`, `shots`, `colonists`, `line`, `airlock`, `arrivals`, `phase`, the counters
/// and `isPowerCut`.
public struct RedoubtRun: Sendable {
    /// Seconds per step: 120 steps a second, matching the display.
    public static let timeStep = 1.0 / 120.0

    public let tuning: RedoubtTuning
    public internal(set) var orb: Orb
    /// Everything on the floor that is not the orb, a colonist or a shot.
    public internal(set) var enemies: [RedoubtEnemy] = []
    public internal(set) var shots: [RedoubtShot] = []
    /// This wave's colonists, in every state (delivered and lost ones stay until the next wave).
    public internal(set) var colonists: [RedoubtColonist] = []
    /// Ids of the colonists following the orb, first (right behind it) to last.
    public internal(set) var line: [Int] = []
    public internal(set) var airlock: Airlock
    /// Enemies telegraphed and about to appear.
    public internal(set) var arrivals: [RedoubtArrival] = []
    public internal(set) var phase: RedoubtPhase
    public internal(set) var score = 0
    /// The wave on now (0 before the first).
    public internal(set) var wave = 0
    public internal(set) var tick = 0
    /// Colonists delivered through the airlock this run.
    public internal(set) var colonistsDelivered = 0
    /// Colonists saved this run: delivered, plus those still safe when their wave was cleared.
    public internal(set) var colonistsSaved = 0
    /// The dome's power is out: the renderer darkens the floor to a pool of light round the orb.
    public internal(set) var isPowerCut = false
    public internal(set) var isGameOver = false

    var rng: SeededRNG
    var events: [RedoubtEvent] = []
    /// Tests turn this off to set up a scene by hand: no waves start and none clear.
    var wavesEnabled = true
    var grid: SpatialGrid
    /// The largest enemy radius, for grid queries.
    let maxEnemyRadius: Double
    let director: RedoubtWaves
    /// The walls this wave's crowd comes in from (`RedoubtWaves.entrySides`), the main wall
    /// first; empty for anywhere on the floor. The main push of the opening crowd lands along
    /// them and the rest is scattered (`RedoubtWaves.scatterShare`).
    public internal(set) var entrySides: [ArenaWall] = []
    /// The main wall of the last wave that had entry walls: the next one avoids it.
    var lastMainWall: ArenaWall?
    /// Which end of an entry wall the push leans toward when the orb is level with its middle
    /// (the high end: north or east). Drawn each wave.
    var pushLeansHigh = false

    /// The wave's opening spawns not yet telegraphed, and how far into the wave it is.
    var pending: [RedoubtSpawn] = []
    var pendingIndex = 0
    var waveClock = 0.0
    /// Skitters this wave still has to send in to keep the floor full.
    public internal(set) var quota = 0
    var groupCooldown = 0.0
    /// The next wave's colonists and opening crowd are already out.
    var waveReady = false
    var nextAirlock: Airlock?
    /// Every colonist of a wave was lost: the power fails when the next wave starts. True from
    /// that moment, through the break (when the next wave's colonists are already out), until then.
    public internal(set) var powerCutPending = false
    var waveColonists = 0
    var waveLost = 0
    #if DEBUG
    /// DEBUG only (`Config.powerCutAtWave`): this wave begins under a power cut, as if every
    /// colonist had been lost in the wave before. Nil in ordinary runs.
    var forcedPowerCutWave: Int?
    #endif

    private var nextID = 1
    private var nextExtraLifeScore: Int

    public init(seed: UInt64, tuning: RedoubtTuning = RedoubtTuning(), waves: RedoubtWaves = RedoubtWaves()) {
        self.tuning = tuning
        director = waves
        rng = SeededRNG(seed: seed ^ 0x0D0E_5EED_7A11_0C4B)
        grid = SpatialGrid(width: tuning.arenaWidth, height: tuning.arenaHeight, cellSize: 40)
        maxEnemyRadius = tuning.maxEnemyRadius
        nextExtraLifeScore = tuning.extraLifeEvery
        phase = .intermission(remaining: tuning.firstWaveDelay)
        orb = Orb(pos: Vec2(tuning.arenaWidth / 2, tuning.arenaHeight / 2),
                  lives: tuning.startingLives, charges: tuning.startingCharges)
        airlock = Airlock(wall: .north, pos: Vec2(tuning.arenaWidth / 2, tuning.arenaHeight),
                          width: tuning.airlockWidth, isOpen: false)
        airlock = pickAirlock(awayFrom: nil)
    }

    // MARK: Reading

    public var arenaSize: Vec2 { Vec2(tuning.arenaWidth, tuning.arenaHeight) }
    /// Where the orb starts and respawns.
    public var centre: Vec2 { Vec2(tuning.arenaWidth / 2, tuning.arenaHeight / 2) }

    /// Colonists still to be saved this wave: sheltering, following or being dragged away.
    public var colonistsLeft: Int { colonists.count { $0.isSafeOrSeized } }

    /// Enemies that must still be destroyed (or are on their way) before the wave clears.
    public var enemiesHoldingWave: Int {
        enemies.count { !$0.isDead && $0.role.holdsWave } + arrivals.count + (pending.count - pendingIndex) + quota
    }

    /// Shootable enemies on the floor, telegraphed or still to be telegraphed: what the floor
    /// target counts.
    public var shootableOnFloor: Int {
        enemies.count { !$0.isDead && $0.role.holdsWave } + arrivals.count { $0.role.holdsWave }
            + pending[pendingIndex...].count { $0.role.holdsWave }
    }

    public func enemy(_ id: Int) -> RedoubtEnemy? { enemies.first { $0.id == id } }
    public func colonist(_ id: Int) -> RedoubtColonist? { colonists.first { $0.id == id } }

    // MARK: Stepping

    /// Advances the run by one `timeStep` and returns what happened.
    public mutating func step(_ input: RedoubtInput) -> [RedoubtEvent] {
        guard !isGameOver else { return [] }
        events.removeAll(keepingCapacity: true)
        tick += 1
        let dt = Self.timeStep
        updatePhase(dt)
        updateOrb(input, dt)
        grid.rebuild(enemies)
        updateEnemies(dt)
        separateEnemies()
        grid.rebuild(enemies)
        updateShots(dt)
        updateColonists(dt)
        resolveContacts()
        enemies.removeAll { $0.isDead }
        checkWaveCleared()
        return events
    }

    // MARK: Waves

    private mutating func updatePhase(_ dt: Double) {
        guard wavesEnabled else {
            updateArrivals(dt)
            return
        }
        switch phase {
        case .intermission(let remaining):
            updateArrivals(dt)
            let left = remaining - dt
            // The last second of the break: the next wave's colonists appear, the airlock opens
            // and its opening crowd is telegraphed, so the crowd lands as the wave begins.
            if !waveReady, left <= tuning.telegraphTime {
                prepareWave(startingIn: max(left, 0))
            }
            if left <= 0 {
                startWave()
            } else {
                phase = .intermission(remaining: left)
            }
        case .fighting:
            // Arrivals count down before new ones join, so each is shown for exactly
            // `telegraphTime` from the step its telegraph starts.
            updateArrivals(dt)
            waveClock += dt
            while pendingIndex < pending.count, pending[pendingIndex].delay <= waveClock {
                telegraph(pending[pendingIndex].role)
                pendingIndex += 1
            }
            topUpFloor(dt)
        }
    }

    /// Readies the next wave `startingIn` seconds before it begins: its colonists, the airlock at
    /// its new place, and the opening crowd's telegraphs, timed to land from the wave's start.
    mutating func prepareWave(startingIn lead: Double) {
        waveReady = true
        let next = wave + 1
        if let moved = nextAirlock {
            airlock = moved
            nextAirlock = nil
        }
        airlock.isOpen = true
        events.append(.airlockOpened(wall: airlock.wall, at: airlock.pos))
        line.removeAll()
        colonists.removeAll()
        let count = director.colonists(forWave: next)
        placeColonists(count)
        waveColonists = count
        waveLost = 0
        pending = []
        pendingIndex = 0
        chooseEntrySides(count: director.entrySides(forWave: next))
        for (index, spawn) in director.spawns(forWave: next).enumerated() {
            // A spawn landing more than a telegraph's length into the wave (the early waves'
            // Gleaners: `RedoubtWaves.gleanerDebutDelay`) is telegraphed from `pending` when the
            // wave clock reaches it, so its marker shows for the usual time. It holds the wave
            // and counts toward the floor target while it waits.
            let lands = director.landing(of: spawn, inWave: next)
            if lands > tuning.telegraphTime {
                pending.append(RedoubtSpawn(delay: lands - tuning.telegraphTime, role: spawn.role))
                continue
            }
            let scattered = !entrySides.isEmpty && director.isScattered(index, forWave: next)
            telegraph(spawn.role, showingFor: lead + lands, scattered: scattered)
        }
    }

    mutating func startWave() {
        if !waveReady { prepareWave(startingIn: 0) }
        waveReady = false
        wave += 1
        phase = .fighting
        waveClock = 0
        quota = director.quota(forWave: wave)
        groupCooldown = 0
        #if DEBUG
        if forcedPowerCutWave == wave { powerCutPending = true }
        #endif
        if powerCutPending {
            powerCutPending = false
            if !isPowerCut {
                isPowerCut = true
                events.append(.powerCutBegan)
            }
        }
        events.append(.waveStarted(wave: wave, colonists: waveColonists))
    }

    private mutating func checkWaveCleared() {
        guard wavesEnabled, phase == .fighting, enemiesHoldingWave == 0 else { return }
        clearWave()
    }

    mutating func clearWave() {
        let safe = colonists.count { $0.state == .sheltering || $0.state == .following }
        let bonus = safe * tuning.waveBonusPerColonist
        colonistsSaved += safe
        addScore(bonus)
        events.append(.waveCleared(wave: wave, safe: safe, bonus: bonus))
        // Threshers need not be destroyed: they leave with the wave.
        for index in enemies.indices where !enemies[index].isDead {
            enemies[index].isDead = true
            events.append(.enemyWithdrew(id: enemies[index].id, role: enemies[index].role, at: enemies[index].pos))
        }
        enemies.removeAll()
        clearShots { $0.owner == .enemy }
        airlock.isOpen = false
        events.append(.airlockClosed(at: airlock.pos))
        nextAirlock = pickAirlock(awayFrom: airlock.pos)
        phase = .intermission(remaining: tuning.intermission)
        #if DEBUG
        // A forced power cut shows as pending through the break before it, like a real one.
        if forcedPowerCutWave == wave + 1 { powerCutPending = true }
        #endif
    }

    /// A new airlock: a random wall, away from the corners and at least `airlockMinMove` from the
    /// last one.
    private mutating func pickAirlock(awayFrom previous: Vec2?) -> Airlock {
        var best: Airlock?
        for _ in 0..<24 {
            let wall = ArenaWall.allCases[Int(rng.next() % 4)]
            let along = rng.range(0.15...0.85)
            let pos: Vec2 = switch wall {
            case .north: Vec2(along * tuning.arenaWidth, tuning.arenaHeight)
            case .south: Vec2(along * tuning.arenaWidth, 0)
            case .east: Vec2(tuning.arenaWidth, along * tuning.arenaHeight)
            case .west: Vec2(0, along * tuning.arenaHeight)
            }
            best = Airlock(wall: wall, pos: pos, width: tuning.airlockWidth, isOpen: false)
            guard let previous else { break }
            if distance(pos, previous) >= tuning.airlockMinMove { break }
        }
        return best!
    }

    // MARK: Arrivals

    /// Keeps the floor at its target (counting the opening crowd's Gleaners still to come):
    /// whenever the shootable count falls short, a group of Skitters from the quota is telegraphed at once, from a random side.
    private mutating func topUpFloor(_ dt: Double) {
        groupCooldown -= dt
        guard quota > 0, groupCooldown <= 0 else { return }
        let short = director.floorTarget(forWave: wave) - shootableOnFloor
        guard short > 0 else { return }
        let count = min(short, quota, RedoubtWaves.groupSize)
        telegraphGroup(count)
        quota -= count
        groupCooldown = RedoubtWaves.groupGap
    }

    /// Telegraphs `count` Skitters clustered near one wall, clear of the orb: on its path ahead
    /// if it is running the wall, else at one of the wave's entry walls (any wall when it has
    /// none). With `RedoubtWaves.pushAndScatter` on and entry walls, the group lands at the
    /// farthest from the orb of `groupSpotDraws` clear spots along them.
    private mutating func telegraphGroup(_ count: Int) {
        let margin = tuning.spawnWallMargin
        var centre = wallRunAhead()
        var spots: [Vec2] = []
        let wanted = director.pushAndScatter && !entrySides.isEmpty ? max(tuning.groupSpotDraws, 1) : 1
        for _ in 0..<12 where centre == nil {
            let inset = rng.range(40...100)
            let along = rng.range(0.1...0.9)
            let wall = entrySides.isEmpty ? ArenaWall.allCases[Int(rng.next() % 4)]
                : entrySides[Int(rng.next() % UInt64(entrySides.count))]
            let p: Vec2 = switch wall {
            case .north: Vec2(along * tuning.arenaWidth, tuning.arenaHeight - inset)
            case .south: Vec2(along * tuning.arenaWidth, inset)
            case .east: Vec2(tuning.arenaWidth - inset, along * tuning.arenaHeight)
            case .west: Vec2(inset, along * tuning.arenaHeight)
            }
            if isClearOfOrb(p, by: tuning.safeDistance + 60) {
                spots.append(p)
                if spots.count >= wanted { break }
            }
        }
        if centre == nil {
            centre = spots.max { gapToOrb($0) < gapToOrb($1) }
        }
        for _ in 0..<count {
            var pos: Vec2?
            if let centre {
                for _ in 0..<6 {
                    let angle = rng.range(0...(2 * .pi))
                    let p = clampToFloor(centre + unitVector(angle) * rng.range(0...60), radius: margin)
                    if isClearOfOrb(p, by: tuning.safeDistance) {
                        pos = p
                        break
                    }
                }
            }
            let at = pos ?? spawnPoint(for: .skitter)
            let id = takeID()
            arrivals.append(RedoubtArrival(id: id, role: .skitter, pos: at, remaining: tuning.telegraphTime))
            events.append(.arrivalTelegraphed(id: id, role: .skitter, at: at))
        }
    }

    /// Where a top-up group lands while the orb runs along a wall (see `RedoubtTuning.wallRunGap`):
    /// a point on its path, `wallRunReach` ahead, kept clear of it. Nil when it is not running
    /// the wall, or the point ahead is not clear (a corner close ahead).
    private mutating func wallRunAhead() -> Vec2? {
        guard tuning.wallRunGap > 0, orb.isAlive else { return nil }
        let w = tuning.arenaWidth, h = tuning.arenaHeight, p = orb.pos, v = orb.vel
        let toSide = min(p.x, w - p.x), toEnd = min(p.y, h - p.y)
        let speed = v.length
        // The speed along the nearest wall.
        let along = toSide < toEnd ? abs(v.y) : abs(v.x)
        guard min(toSide, toEnd) < tuning.wallRunGap, speed > tuning.wallRunSpeed,
              along >= tuning.wallRunAlong * speed else { return nil }
        let ahead = clampToFloor(p + v * (rng.range(tuning.wallRunReach) / speed), radius: 40)
        return isClearOfOrb(ahead, by: tuning.safeDistance + 60) ? ahead : nil
    }

    /// Picks the `count` walls this wave's crowd comes in from (four means anywhere on the
    /// floor). With `RedoubtWaves.pushAndScatter` on, the main wall (first) is drawn at random
    /// from the walls the orb (or, while it is down, its respawn point) is not nearest, never the
    /// last wave's main wall, each weighted by its distance from the orb raised to
    /// `mainWallWeighting`; any others are drawn evenly from the rest the orb is not nearest.
    /// Off, each wall scores its distance from the orb plus up to `entrySideJitter` and the
    /// highest win.
    mutating func chooseEntrySides(count: Int) {
        guard count < 4 else {
            entrySides = []
            return
        }
        let p = orb.isAlive ? orb.pos : centre
        if director.pushAndScatter {
            let near = nearestWall(p)
            let open = ArenaWall.allCases.filter { $0 != near }
            let choices = open.filter { $0 != lastMainWall }
            let weights = choices.map { power(wallGap($0, from: p), tuning.mainWallWeighting) }
            var pick = rng.range(0...weights.reduce(0, +))
            var main = choices[choices.count - 1]
            for (wall, weight) in zip(choices, weights) {
                if pick < weight {
                    main = wall
                    break
                }
                pick -= weight
            }
            var rest = open.filter { $0 != main }
            var walls = [main]
            while walls.count < count, !rest.isEmpty {
                walls.append(rest.remove(at: Int(rng.next() % UInt64(rest.count))))
            }
            entrySides = walls
            lastMainWall = main
            pushLeansHigh = rng.next() % 2 == 0
            return
        }
        let scored = ArenaWall.allCases.map { wall -> (ArenaWall, Double) in
            let gap: Double = switch wall {
            case .north: tuning.arenaHeight - p.y
            case .south: p.y
            case .east: tuning.arenaWidth - p.x
            case .west: p.x
            }
            return (wall, gap + rng.range(0...tuning.entrySideJitter))
        }
        entrySides = scored.sorted { $0.1 > $1.1 }.prefix(max(count, 1)).map(\.0)
    }

    /// How far `p` is from the orb (and, while it is down, from where it will respawn).
    func gapToOrb(_ p: Vec2) -> Double {
        orb.isAlive ? distance(p, orb.pos) : min(distance(p, orb.pos), distance(p, centre))
    }

    /// How far `p` is from a wall.
    func wallGap(_ wall: ArenaWall, from p: Vec2) -> Double {
        switch wall {
        case .north: tuning.arenaHeight - p.y
        case .south: p.y
        case .east: tuning.arenaWidth - p.x
        case .west: p.x
        }
    }

    /// The wall nearest `p` (north, then south, east, west on a tie).
    func nearestWall(_ p: Vec2) -> ArenaWall {
        ArenaWall.allCases.min { wallGap($0, from: p) < wallGap($1, from: p) }!
    }

    /// Starts an arrival's telegraph at a free spot away from the orb: with the main push along
    /// the entry walls, or scattered over the floor (`scattered`).
    mutating func telegraph(_ role: RedoubtRole, showingFor seconds: Double? = nil, scattered: Bool = false) {
        let pos = spawnPoint(for: role, scattered: scattered)
        let id = takeID()
        arrivals.append(RedoubtArrival(id: id, role: role, pos: pos,
                                       remaining: max(seconds ?? tuning.telegraphTime, tuning.telegraphTime)))
        events.append(.arrivalTelegraphed(id: id, role: role, at: pos))
    }

    private mutating func updateArrivals(_ dt: Double) {
        guard !arrivals.isEmpty else { return }
        var index = 0
        while index < arrivals.count {
            arrivals[index].remaining -= dt
            // A little slack so 120 steps of 1/120 s make a second despite rounding.
            guard arrivals[index].remaining <= 1e-9 else {
                index += 1
                continue
            }
            let arrival = arrivals[index]
            // The orb flew onto it: it moves somewhere clear and is telegraphed again there, so
            // the orb never has something appear on it and cannot hold a wave open by sitting
            // on an arrival.
            if !isClearOfOrb(arrival.pos, by: tuning.safeDistance * 0.5) {
                // Anywhere on the floor, not only along the entry walls: an orb running along an
                // entry wall would otherwise keep meeting the arrivals it had moved.
                let pos = spawnPoint(for: arrival.role, anywhere: true)
                arrivals[index].pos = pos
                arrivals[index].remaining = tuning.telegraphTime
                events.append(.arrivalTelegraphed(id: arrival.id, role: arrival.role, at: pos))
                index += 1
                continue
            }
            if enemies.count >= tuning.maxEnemies {
                arrivals[index].remaining = 0.2
                index += 1
                continue
            }
            arrivals.remove(at: index)
            addEnemy(arrival.role, at: arrival.pos, id: arrival.id)
            events.append(.enemyArrived(id: arrival.id, role: arrival.role, at: arrival.pos))
        }
    }

    /// True when `p` is at least `gap` from the orb (and, while it is down, from where it will
    /// respawn).
    func isClearOfOrb(_ p: Vec2, by gap: Double) -> Bool {
        if orb.isAlive { return distance(p, orb.pos) >= gap }
        return distance(p, orb.pos) >= gap && distance(p, centre) >= gap
    }

    /// A free spot away from the orb: anywhere on the floor, or in a band along one of the
    /// wave's entry walls when it has them (unless `anywhere`). A `scattered` spot is anywhere
    /// on the floor, at least `scatterClearance` from the orb.
    private mutating func spawnPoint(for role: RedoubtRole, anywhere: Bool = false, scattered: Bool = false) -> Vec2 {
        let clearance = scattered ? max(tuning.scatterClearance, tuning.safeDistance) : tuning.safeDistance
        let orbRef = orb.isAlive ? orb.pos : centre
        let margin = role == .burrow ? tuning.figure(60) : tuning.spawnWallMargin
        var best = centre
        var bestScore = -Double.infinity
        for attempt in 0..<24 {
            let p: Vec2
            if entrySides.isEmpty || anywhere || scattered {
                p = Vec2(rng.range(margin...(tuning.arenaWidth - margin)),
                         rng.range(margin...(tuning.arenaHeight - margin)))
            } else {
                // In a band along one of the wave's entry walls.
                let wall = entrySides[Int(rng.next() % UInt64(entrySides.count))]
                let inset = director.pushAndScatter
                    ? margin + max(tuning.pushDepth - margin, 0) * power(rng.range(0...1), tuning.pushFalloff)
                    : rng.range(margin...max(tuning.entryBandDepth, margin))
                let w = tuning.arenaWidth, h = tuning.arenaHeight
                if director.pushAndScatter {
                    // Along the wall: the nearest to one end of `pushAlongDraws` draws, so the push
                    // leans toward the end away from the orb (with the orb level with the middle,
                    // the end drawn for the wave).
                    let horizontal = wall == .north || wall == .south
                    let length = horizontal ? w : h
                    let orbAlong = horizontal ? orbRef.x : orbRef.y
                    let high = abs(orbAlong - length / 2) < 0.1 * length ? pushLeansHigh : orbAlong < length / 2
                    var along = rng.range(margin...(length - margin))
                    for _ in 1..<max(tuning.pushAlongDraws, 1) {
                        let other = rng.range(margin...(length - margin))
                        along = high ? max(along, other) : min(along, other)
                    }
                    p = switch wall {
                    case .north: Vec2(along, h - inset)
                    case .south: Vec2(along, inset)
                    case .east: Vec2(w - inset, along)
                    case .west: Vec2(inset, along)
                    }
                } else {
                    p = switch wall {
                    case .north: Vec2(rng.range(margin...(w - margin)), h - inset)
                    case .south: Vec2(rng.range(margin...(w - margin)), inset)
                    case .east: Vec2(w - inset, rng.range(margin...(h - margin)))
                    case .west: Vec2(inset, rng.range(margin...(h - margin)))
                    }
                }
            }
            // How well it keeps the rules; the first that keeps them all wins.
            var ok = isClearOfOrb(p, by: clearance)
            var score = gapToOrb(p)
            if role == .burrow {
                ok = ok && distance(p, centre) >= tuning.burrowCentreClearance
                    && !enemies.contains { $0.role == .burrow && !$0.isDead && distance($0.pos, p) < tuning.figure(120) }
                    && !arrivals.contains { $0.role == .burrow && distance($0.pos, p) < tuning.figure(120) }
            }
            if role == .thresher || role == .burrow {
                // Not on top of a colonist: it would crush them before anyone could react.
                ok = ok && !colonists.contains { $0.state == .sheltering && distance($0.pos, p) < tuning.figure(60) }
            }
            if ok { return p }
            score -= Double(attempt)
            if score > bestScore {
                bestScore = score
                best = p
            }
        }
        return best
    }

    /// Adds an enemy in the usual starting state for its role.
    @discardableResult
    mutating func addEnemy(_ role: RedoubtRole, at pos: Vec2, id: Int? = nil, parent: Int? = nil) -> Int {
        let stats = tuning.stats(for: role)
        var enemy = RedoubtEnemy(id: id ?? takeID(), role: role, pos: clampToFloor(pos, radius: stats.radius),
                                 radius: stats.radius, hp: stats.hp, state: Self.initialState(for: role))
        enemy.parent = parent
        let toOrb = orb.pos - pos
        enemy.heading = atan2(toOrb.y, toOrb.x)
        switch role {
        case .skitter:
            enemy.trait = rng.range(tuning.skitterSpeedSpread)
            enemy.timer = rng.range(0...(2 * .pi))
        case .spitter:
            enemy.trait = rng.chance(0.5) ? 1 : -1
            enemy.timer = rng.range(tuning.spitterFireInterval) * director.spitterFireScale(forWave: wave, tuning: tuning)
        case .burrow:
            enemy.timer = tuning.burrowSpawnInterval * 0.5
        case .gleaner:
            enemy.timer = rng.range(0...(2 * .pi))
        case .thresher, .husk:
            break
        }
        enemies.append(enemy)
        return enemy.id
    }

    static func initialState(for role: RedoubtRole) -> RedoubtEnemy.State {
        switch role {
        case .skitter, .thresher, .husk: .hunting
        case .gleaner: .seeking(colonist: nil)
        case .spitter: .keepingDistance
        case .burrow: .pouring
        }
    }

    // MARK: The orb

    private mutating func updateOrb(_ input: RedoubtInput, _ dt: Double) {
        guard orb.isAlive else {
            orb.respawnTimer -= dt
            if orb.respawnTimer <= 0 { respawnOrb() }
            return
        }
        orb.invulnerableTimer = max(0, orb.invulnerableTimer - dt)

        // Direct steering with a short glide: velocity eases toward what the stick asks for.
        let target = input.move.clampedToUnit * tuning.orbMaxSpeed
        let k = 1 - exp(-dt / max(tuning.orbResponse, 1e-6))
        orb.vel = orb.vel + (target - orb.vel) * k
        var pos = orb.pos + orb.vel * dt
        let r = tuning.orbRadius
        if pos.x < r || pos.x > tuning.arenaWidth - r { orb.vel.x = 0 }
        if pos.y < r || pos.y > tuning.arenaHeight - r { orb.vel.y = 0 }
        pos = clampToFloor(pos, radius: r)
        orb.pos = pos

        let aim = input.aim.clampedToUnit
        orb.isFiring = aim.length >= tuning.aimThreshold
        if orb.isFiring {
            orb.heading = atan2(aim.y, aim.x)
        } else if orb.vel.length > 20 {
            orb.heading = atan2(orb.vel.y, orb.vel.x)
        }
        // A steady cadence: the cooldown carries its remainder so the rate is exact.
        orb.fireCooldown -= dt
        if orb.isFiring {
            if orb.fireCooldown <= 0 {
                fireOrbShot()
                orb.fireCooldown += tuning.shotInterval
                if orb.fireCooldown < 0 { orb.fireCooldown = 0 }
            }
        } else if orb.fireCooldown < 0 {
            orb.fireCooldown = 0
        }

        if input.shockwave, !orb.shockwaveHeld, orb.charges > 0 {
            fireShockwave()
        }
        orb.shockwaveHeld = input.shockwave
    }

    private mutating func fireOrbShot() {
        let dir = unitVector(orb.heading)
        let muzzle = orb.pos + dir * (tuning.orbRadius + tuning.figure(2))
        shots.append(RedoubtShot(id: takeID(), owner: .orb, pos: muzzle, vel: dir * tuning.shotSpeed,
                                 radius: tuning.shotRadius, timeLeft: tuning.shotLifetime))
        events.append(.orbFired(at: muzzle, heading: orb.heading))
    }

    mutating func fireShockwave() {
        orb.charges -= 1
        var destroyed = 0
        for index in enemies.indices where !enemies[index].isDead {
            let offset = enemies[index].pos - orb.pos
            let d = offset.length
            if d < tuning.shockwaveClearRadius + enemies[index].radius {
                destroyEnemy(at: index, byShockwave: true)
                destroyed += 1
            } else if d < tuning.shockwavePushRadius, enemies[index].role != .burrow {
                let strength = tuning.shockwavePush * max(1 - d / tuning.shockwavePushRadius, 0.3)
                enemies[index].push = enemies[index].push + offset * (strength / d)
            }
        }
        let origin = orb.pos, clearRadius = tuning.shockwaveClearRadius
        clearShots { $0.owner == .enemy && distance($0.pos, origin) < clearRadius }
        events.append(.shockwave(at: orb.pos, destroyed: destroyed))
    }

    /// Something touched the orb.
    mutating func destroyOrb(cause: RedoubtHitCause) {
        guard orb.isAlive, !orb.isInvulnerable else { return }
        orb.isAlive = false
        orb.lives -= 1
        orb.vel = .zero
        orb.isFiring = false
        orb.fireCooldown = 0
        events.append(.orbDestroyed(at: orb.pos, livesLeft: orb.lives, cause: cause))
        scatterLine()
        if orb.lives <= 0 {
            isGameOver = true
            events.append(.gameOver(score: score))
        } else {
            orb.respawnTimer = tuning.respawnDelay
        }
    }

    private mutating func respawnOrb() {
        orb.isAlive = true
        orb.pos = centre
        orb.vel = .zero
        orb.invulnerableTimer = tuning.respawnInvulnerability
        orb.charges = max(orb.charges, tuning.startingCharges)
        // Room to breathe: shove away whatever is near the centre and drop shots there.
        for index in enemies.indices where !enemies[index].isDead && enemies[index].role != .burrow {
            let offset = enemies[index].pos - centre
            let d = offset.length
            guard d < tuning.respawnClearRadius else { continue }
            let dir = d > 0.5 ? offset * (1 / d) : Vec2(1, 0)
            enemies[index].push = enemies[index].push + dir * tuning.respawnPush
        }
        let middle = centre, clearRadius = tuning.respawnClearRadius
        clearShots { $0.owner == .enemy && distance($0.pos, middle) < clearRadius }
        events.append(.orbRespawned(at: orb.pos))
    }

    mutating func addScore(_ points: Int) {
        score += points
        while score >= nextExtraLifeScore {
            nextExtraLifeScore += tuning.extraLifeEvery
            if orb.lives < tuning.maxLives {
                orb.lives += 1
                events.append(.extraLife(lives: orb.lives))
            }
        }
    }

    // MARK: Shots

    private mutating func updateShots(_ dt: Double) {
        guard !shots.isEmpty else { return }
        let reach = tuning.shotRadius + maxEnemyRadius
        var kept = 0
        var index = 0
        while index < shots.count {
            var shot = shots[index]
            index += 1
            shot.timeLeft -= dt
            guard shot.timeLeft > 0 else {
                events.append(.shotEnded(id: shot.id, at: shot.pos, reason: .expired))
                continue
            }
            let travel = shot.vel * dt
            switch shot.owner {
            case .orb:
                if let hit = firstEnemyHit(shot, travel: travel, reach: reach) {
                    damageEnemy(at: hit, from: shot.vel)
                    events.append(.shotEnded(id: shot.id, at: shot.pos, reason: .hit))
                    continue
                }
            case .enemy:
                if orb.isAlive, !orb.isInvulnerable,
                   Collision.sweepTime(center: orb.pos - shot.pos, travel: travel,
                                       radius: shot.radius + tuning.orbHitRadius) != nil {
                    events.append(.shotEnded(id: shot.id, at: shot.pos, reason: .hit))
                    destroyOrb(cause: .shot(id: shot.id))
                    continue
                }
            }
            shot.pos = shot.pos + travel
            guard shot.pos.x > 0, shot.pos.x < tuning.arenaWidth, shot.pos.y > 0,
                  shot.pos.y < tuning.arenaHeight else {
                let wall = clampToFloor(shot.pos, radius: 0)
                events.append(.shotEnded(id: shot.id, at: wall, reason: .wall))
                continue
            }
            shots[kept] = shot
            kept += 1
        }
        let extra = shots.count - kept
        shots.removeLast(extra)
    }

    /// The live enemy a shot reaches first this step, if any.
    private func firstEnemyHit(_ shot: RedoubtShot, travel: Vec2, reach: Double) -> Int? {
        let end = shot.pos + travel
        var best = -1
        var bestTime = 2.0
        grid.forEach(minX: min(shot.pos.x, end.x) - reach, minY: min(shot.pos.y, end.y) - reach,
                     maxX: max(shot.pos.x, end.x) + reach, maxY: max(shot.pos.y, end.y) + reach) { index in
            let enemy = enemies[index]
            guard !enemy.isDead,
                  let t = Collision.sweepTime(center: enemy.pos - shot.pos, travel: travel,
                                              radius: shot.radius + enemy.radius) else { return }
            // Ties go to the earlier index, so the result never depends on grid order.
            if t < bestTime || (t == bestTime && index < best) {
                bestTime = t
                best = index
            }
        }
        return best >= 0 ? best : nil
    }

    /// One shot landed, travelling along `direction`.
    mutating func damageEnemy(at index: Int, from direction: Vec2) {
        let enemy = enemies[index]
        if enemy.role == .thresher {
            let len = direction.length
            if len > 0 {
                enemies[index].push = enemies[index].push + direction * (tuning.thresherShotPush / len)
            }
            events.append(.enemyHit(id: enemy.id, role: enemy.role, at: enemy.pos))
            return
        }
        enemies[index].hp -= 1
        if enemies[index].hp <= 0 {
            destroyEnemy(at: index, byShockwave: false)
        } else {
            events.append(.enemyHit(id: enemy.id, role: enemy.role, at: enemy.pos))
        }
    }

    /// Marks an enemy destroyed (removed at the end of the step) and scores it.
    mutating func destroyEnemy(at index: Int, byShockwave: Bool) {
        let enemy = enemies[index]
        guard !enemy.isDead else { return }
        enemies[index].isDead = true
        if case .dragging(let colonistID, _) = enemy.state, let c = colonistIndex(colonistID),
           colonists[c].state == .seized(by: enemy.id) {
            colonists[c].state = .sheltering
            colonists[c].vel = .zero
            colonists[c].pos = clampToFloor(colonists[c].pos, radius: tuning.colonistRadius)
            events.append(.colonistFreed(id: colonistID, at: colonists[c].pos))
        }
        for c in colonists.indices where colonists[c].claimedBy == enemy.id {
            colonists[c].claimedBy = nil
        }
        let points = tuning.stats(for: enemy.role).points
        addScore(points)
        events.append(.enemyDestroyed(id: enemy.id, role: enemy.role, at: enemy.pos, points: points,
                                      byShockwave: byShockwave))
    }

    /// Removes the shots matching `wiped` (a Shockwave, a respawn, a wave's end), saying so.
    private mutating func clearShots(_ wiped: (RedoubtShot) -> Bool) {
        var kept: [RedoubtShot] = []
        kept.reserveCapacity(shots.count)
        for shot in shots {
            if wiped(shot) {
                events.append(.shotEnded(id: shot.id, at: shot.pos, reason: .cleared))
            } else {
                kept.append(shot)
            }
        }
        shots = kept
    }

    // MARK: Contact

    private mutating func resolveContacts() {
        // The orb touching an enemy.
        if orb.isAlive, !orb.isInvulnerable {
            var toucher: Int?
            grid.forEach(near: orb.pos, reach: tuning.orbHitRadius + maxEnemyRadius) { index in
                let enemy = enemies[index]
                guard !enemy.isDead, distance(enemy.pos, orb.pos) < tuning.orbHitRadius + enemy.radius else { return }
                // The lowest index, so the cause never depends on grid order.
                if toucher == nil || index < toucher! { toucher = index }
            }
            if let toucher {
                destroyOrb(cause: .enemy(id: enemies[toucher].id, role: enemies[toucher].role))
            }
        }

        // A Skitter or Husk reaching the end of the line takes the last follower.
        if let tailID = line.last, let tail = colonistIndex(tailID) {
            let tailPos = colonists[tail].pos
            var taker: Int?
            grid.forEach(near: tailPos, reach: tuning.colonistRadius + maxEnemyRadius) { index in
                let enemy = enemies[index]
                guard !enemy.isDead, enemy.role == .skitter || (enemy.role == .husk && enemy.state == .hunting),
                      distance(enemy.pos, tailPos) < tuning.colonistRadius + enemy.radius else { return }
                if taker == nil || index < taker! { taker = index }
            }
            if let taker {
                line.removeLast()
                loseColonist(at: tail, takenBy: enemies[taker].role, enemy: enemies[taker].id)
            }
        }

        // Threshers crush whoever they move over.
        for e in enemies.indices where enemies[e].role == .thresher && !enemies[e].isDead {
            let reach = enemies[e].radius + tuning.colonistRadius
            for c in colonists.indices where colonists[c].isSafeOrSeized
                && distance(colonists[c].pos, enemies[e].pos) < reach {
                crushColonist(at: c, by: enemies[e].id)
            }
        }
    }

    // MARK: Helpers

    func clampToFloor(_ p: Vec2, radius: Double) -> Vec2 {
        Vec2(clamp(p.x, radius, tuning.arenaWidth - radius), clamp(p.y, radius, tuning.arenaHeight - radius))
    }

    mutating func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }
}

/// The unit vector at `angle` radians. Every cos and sin pair in the mode goes through here. An
/// optimised build may turn a cos and a sin of the same angle into one combined call that rounds
/// the last bit differently, and then Debug and Release runs of the same seed drift apart; each
/// is kept in a function of its own, never inlined, so the pair is never seen together.
func unitVector(_ angle: Double) -> Vec2 {
    Vec2(cosine(angle), sine(angle))
}

@inline(never) func cosine(_ x: Double) -> Double { cos(x) }
@inline(never) func sine(_ x: Double) -> Double { sin(x) }
/// `pow`, never inlined for the same reason: an optimised build may rewrite a power it can see
/// into other operations that round differently.
@inline(never) func power(_ x: Double, _ y: Double) -> Double { pow(x, y) }

@inline(__always)
func distance(_ a: Vec2, _ b: Vec2) -> Double {
    (a - b).length
}
