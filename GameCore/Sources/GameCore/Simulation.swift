import Foundation

/// The whole game state and its rules. It advances in fixed steps and is deterministic for a
/// given seed and input sequence. It knows nothing about how anything looks or sounds.
public struct Simulation: Sendable {
    /// Seconds per step: 120 steps a second, matching the display.
    public static let timeStep = 1.0 / 120.0

    public let tuning: Tuning
    public let world: World
    public internal(set) var player: Player
    public internal(set) var colonists: [Colonist] = []
    public internal(set) var enemies: [Enemy] = []
    public internal(set) var projectiles: [Projectile] = []
    /// One entry per outpost, indexed by outpost id. 1 is undamaged, 0 is destroyed.
    public internal(set) var outpostIntegrity: [Double]
    public internal(set) var score = 0
    public internal(set) var wave = 0
    public internal(set) var tick = 0
    /// True from the loss of the last colonist until a supply drop arrives. Harvesters become
    /// Husks, and the app should darken the terrain and switch the scanner off.
    public internal(set) var isBlackout = false
    public internal(set) var isGameOver = false
    /// Colonists brought home to an outpost this run.
    public internal(set) var colonistsSaved = 0

    var rng: SeededRNG
    var events: [GameEvent] = []
    var pendingSpawns: [ScheduledSpawn] = []
    var waveTimer: Double
    var supplyTimer: Double
    /// Tests turn this off to set up a scene by hand.
    var wavesEnabled = true

    private var nextID = 1
    private var nextExtraLifeScore: Int
    private var waveBonusPaid = true
    private let director = WaveDirector()

    public init(seed: UInt64, tuning: Tuning = Tuning()) {
        self.tuning = tuning
        world = World(tuning: tuning, seed: seed)
        rng = SeededRNG(seed: seed ^ 0xA5A5_5A5A_C3C3_3C3C)
        waveTimer = tuning.firstWaveDelay
        supplyTimer = tuning.supplyDelay
        nextExtraLifeScore = tuning.extraLifeEvery
        outpostIntegrity = Array(repeating: 1, count: world.outposts.count)
        player = Player(
            pos: Vec2(tuning.worldWidth / 2, tuning.worldHeight / 2),
            lives: tuning.startingLives,
            shockwaves: tuning.startingShockwaves
        )
        for outpost in world.outposts {
            addColonists(at: outpost)
        }
    }

    /// Colonists who have not been lost.
    public var survivingColonists: Int {
        colonists.count { $0.state != .lost }
    }

    public func isOutpostIntact(_ id: Int) -> Bool {
        outpostIntegrity[id] > 0
    }

    /// Advances the game by one `timeStep` and returns what happened.
    public mutating func step(_ input: InputState) -> [GameEvent] {
        guard !isGameOver else { return [] }
        events.removeAll(keepingCapacity: true)
        tick += 1
        let dt = Simulation.timeStep
        updateWaves(dt)
        updatePlayer(input, dt)
        updateEnemies(dt)
        updateColonists(dt)
        updateProjectiles(dt)
        resolvePlayerContacts()
        updateSupply(dt)
        return events
    }

    // MARK: Waves

    private mutating func updateWaves(_ dt: Double) {
        guard wavesEnabled else { return }
        if !pendingSpawns.isEmpty {
            for index in pendingSpawns.indices {
                pendingSpawns[index].delay -= dt
            }
            let due = pendingSpawns.filter { $0.delay <= 0 }
            pendingSpawns.removeAll { $0.delay <= 0 }
            for spawn in due {
                spawnEnemy(spawn.kind)
            }
        } else if !enemies.contains(where: { $0.kind != .mine }) {
            // Leftover mines don't hold a wave open; they expire on their own.
            if wave > 0, !waveBonusPaid {
                waveBonusPaid = true
                let bonus = tuning.waveBonusPerColonist * survivingColonists * min(wave, 5)
                addScore(bonus)
                events.append(.waveCleared(wave: wave, bonus: bonus))
            }
            waveTimer -= dt
            if waveTimer <= 0 {
                wave += 1
                pendingSpawns = director.spawns(forWave: wave)
                waveTimer = tuning.waveInterval
                waveBonusPaid = false
                if wave % tuning.wavesPerShockwave == 0 {
                    player.shockwaves = min(player.shockwaves + 1, tuning.maxShockwaves)
                }
                events.append(.waveStarted(wave))
            }
        }
    }

    private mutating func spawnEnemy(_ requested: EnemyKind) {
        // With nobody left to abduct, Harvesters arrive already turned.
        let kind = requested == .harvester && isBlackout ? .husk : requested
        let side = rng.chance(0.5) ? 1.0 : -1.0
        let offset = rng.range(tuning.spawnClearance...(world.width / 2))
        let pos = Vec2(world.wrap(player.pos.x + side * offset), world.ceiling - rng.range(10...60))
        let id = addEnemy(kind: kind, at: pos)
        events.append(.enemySpawned(id: id, kind: kind))
    }

    /// Adds an enemy. With no `state` given it starts in the usual one for its kind.
    @discardableResult
    mutating func addEnemy(kind: EnemyKind, at pos: Vec2, state: Enemy.State? = nil) -> Int {
        let stats = tuning.stats(for: kind)
        let side = rng.chance(0.5) ? 1.0 : -1.0
        var enemy = Enemy(
            id: takeID(),
            kind: kind,
            pos: pos,
            radius: stats.radius,
            hp: stats.hp,
            state: state ?? Simulation.initialState(for: kind)
        )
        switch kind {
        case .harvester:
            enemy.fireTimer = rng.range(tuning.harvesterFireInterval)
        case .sower:
            enemy.vel = Vec2(side * tuning.sowerSpeed, 0)
            enemy.fireTimer = tuning.mineInterval
        case .brood:
            enemy.vel = Vec2(side * tuning.broodSpeed, 0)
        case .lancer:
            enemy.vel = Vec2(side * tuning.lancerPatrolSpeed, 0)
        case .mine:
            enemy.timer = tuning.mineLifetime
        case .mote:
            let angle = rng.range(0...(2 * .pi))
            enemy.vel = Vec2(cos(angle), sin(angle)) * tuning.moteBurstSpeed
        case .husk, .anchor:
            break
        }
        enemies.append(enemy)
        return enemy.id
    }

    private static func initialState(for kind: EnemyKind) -> Enemy.State {
        switch kind {
        case .harvester: .seeking(target: nil)
        case .husk, .mote: .hunting
        case .sower, .brood: .drifting
        case .mine: .armed
        case .lancer: .patrolling
        case .anchor: .roaming
        }
    }

    // MARK: Player

    private mutating func updatePlayer(_ input: InputState, _ dt: Double) {
        guard player.isAlive else {
            player.respawnTimer -= dt
            if player.respawnTimer <= 0 {
                player.isAlive = true
                player.pos.y = world.height / 2
                player.vel = .zero
                player.heat = 0
                player.isOverheated = false
                player.invulnerableTimer = tuning.respawnInvulnerability
                events.append(.playerRespawned)
            }
            return
        }

        player.invulnerableTimer = max(0, player.invulnerableTimer - dt)
        let move = Vec2(clamp(input.move.x, -1, 1), clamp(input.move.y, -1, 1))
        if abs(move.x) > 0.15 {
            player.facing = move.x > 0 ? 1 : -1
        }

        // Blink: jump in the stick direction, or straight ahead if the stick is centred.
        player.blinkCooldown = max(0, player.blinkCooldown - dt)
        if input.blink, !player.blinkHeld, player.blinkCooldown <= 0 {
            let aim = move.length > 0.3 ? move * (1 / move.length) : Vec2(player.facing, 0)
            let from = player.pos
            player.pos.x = world.wrap(player.pos.x + aim.x * tuning.blinkDistance)
            // Land within the flying band, so the event reports where the ship really is.
            let blinkFloor = world.groundHeight(at: player.pos.x) + tuning.playerRadius + 2
            player.pos.y = clamp(player.pos.y + aim.y * tuning.blinkDistance, blinkFloor, world.ceiling)
            player.blinkCooldown = tuning.blinkCooldown
            player.invulnerableTimer = max(player.invulnerableTimer, tuning.blinkInvulnerability)
            events.append(.playerBlinked(from: from, to: player.pos))
        }
        player.blinkHeld = input.blink

        player.vel.x += move.x * tuning.thrust * dt
        player.vel.x *= exp(-tuning.drag * dt)
        player.vel.x = clamp(player.vel.x, -tuning.maxSpeed, tuning.maxSpeed)
        player.vel.y = move.y * tuning.verticalSpeed

        player.pos.x = world.wrap(player.pos.x + player.vel.x * dt)
        let floor = world.groundHeight(at: player.pos.x) + tuning.playerRadius + 2
        player.pos.y = clamp(player.pos.y + player.vel.y * dt, floor, world.ceiling)

        player.heat = max(0, player.heat - tuning.coolingRate * dt)
        if player.isOverheated, player.heat <= tuning.overheatRecovery {
            player.isOverheated = false
        }
        player.fireCooldown = max(0, player.fireCooldown - dt)
        if input.fire, !player.isOverheated, player.fireCooldown <= 0 {
            let muzzle = Vec2(world.wrap(player.pos.x + player.facing * 18), player.pos.y)
            projectiles.append(Projectile(
                id: takeID(),
                pos: muzzle,
                vel: Vec2(player.facing * tuning.shotSpeed + player.vel.x, 0),
                owner: .player,
                radius: tuning.shotRadius,
                timeLeft: tuning.shotLifetime
            ))
            events.append(.playerFired(at: muzzle, facing: player.facing))
            player.fireCooldown = tuning.shotInterval
            player.heat += tuning.heatPerShot
            if player.heat >= 1 {
                player.heat = 1
                player.isOverheated = true
                events.append(.playerOverheated)
            }
        }

        if input.shockwave, !player.shockwaveHeld, player.shockwaves > 0 {
            fireShockwave()
        }
        player.shockwaveHeld = input.shockwave
    }

    private mutating func fireShockwave() {
        player.shockwaves -= 1
        events.append(.shockwave(at: player.pos))
        let origin = player.pos.x
        let range = tuning.shockwaveRange
        // Backwards, because destroying an enemy removes it from the array.
        for index in enemies.indices.reversed()
        where abs(world.delta(from: origin, to: enemies[index].pos.x)) < range {
            destroyEnemy(at: index, split: false)
        }
        projectiles.removeAll {
            $0.owner == .enemy && abs(world.delta(from: origin, to: $0.pos.x)) < range
        }
    }

    /// Something hit the ship. A full shield takes the hit; otherwise the ship is lost.
    private mutating func hitPlayer() {
        guard player.isAlive, player.invulnerableTimer <= 0 else { return }
        if player.shield >= 1 {
            player.shield = 0
            player.invulnerableTimer = tuning.shieldBreakInvulnerability
            events.append(.shieldBroken)
        } else {
            destroyPlayer()
        }
    }

    private mutating func destroyPlayer() {
        guard player.isAlive else { return }
        player.isAlive = false
        player.lives -= 1
        player.vel = .zero
        for id in player.carried {
            if let index = colonistIndex(id) {
                dropColonist(at: index)
            }
        }
        player.carried.removeAll()
        events.append(.playerDestroyed(at: player.pos, livesLeft: player.lives))
        if player.lives <= 0 {
            isGameOver = true
            events.append(.gameOver(score: score))
        } else {
            player.respawnTimer = tuning.respawnDelay
        }
    }

    mutating func addScore(_ points: Int) {
        score += points
        while score >= nextExtraLifeScore {
            nextExtraLifeScore += tuning.extraLifeEvery
            if player.lives < tuning.maxLives {
                player.lives += 1
                events.append(.extraLife)
            }
        }
    }

    // MARK: Enemies

    private mutating func updateEnemies(_ dt: Double) {
        // Enemies added during the loop (mines) take their first turn next step.
        for index in enemies.indices {
            switch enemies[index].kind {
            case .harvester:
                updateHarvester(at: index, dt)
            case .husk:
                updateChaser(at: index, dt, acceleration: tuning.huskAcceleration,
                             maxSpeed: tuning.huskMaxSpeed, jitter: 0)
            case .mote:
                updateChaser(at: index, dt, acceleration: tuning.moteAcceleration,
                             maxSpeed: tuning.moteMaxSpeed, jitter: tuning.moteJitter)
            case .sower, .brood:
                updateDrifter(at: index, dt)
            case .mine:
                updateMine(at: index, dt)
            case .lancer:
                updateLancer(at: index, dt)
            case .anchor:
                updateAnchor(at: index, dt)
            }
        }
        enemies.removeAll { $0.expired }
    }

    /// One lance hit.
    private mutating func damageEnemy(at index: Int) {
        enemies[index].hp -= 1
        if enemies[index].hp <= 0 {
            destroyEnemy(at: index)
        } else {
            events.append(.enemyHit(id: enemies[index].id, at: enemies[index].pos))
        }
    }

    /// Removes an enemy and scores it. `split` lets a Brood burst into Motes.
    mutating func destroyEnemy(at index: Int, split: Bool = true) {
        let enemy = enemies.remove(at: index)
        switch enemy.state {
        case .lifting(let colonistID):
            if let held = colonistIndex(colonistID) {
                dropColonist(at: held)
            }
        case .drilling(let outpost):
            // Stopping the drill in time saves the outpost outright.
            if isOutpostIntact(outpost) {
                outpostIntegrity[outpost] = 1
            }
        default:
            break
        }
        for i in colonists.indices where colonists[i].claimedBy == enemy.id {
            colonists[i].claimedBy = nil
        }
        let points = tuning.stats(for: enemy.kind).points
        addScore(points)
        events.append(.enemyDestroyed(id: enemy.id, kind: enemy.kind, at: enemy.pos, points: points))

        if split, enemy.kind == .brood {
            for _ in 0..<tuning.motesPerBrood {
                let id = addEnemy(kind: .mote, at: enemy.pos)
                events.append(.enemySpawned(id: id, kind: .mote))
            }
        }
    }

    mutating func fireEnemyShot(from origin: Vec2) {
        guard player.isAlive else { return }
        let dx = world.delta(from: origin.x, to: player.pos.x)
        let dy = player.pos.y - origin.y
        let distance = hypot(dx, dy)
        guard distance > 1, distance < tuning.harvesterFireRange else { return }
        projectiles.append(Projectile(
            id: takeID(),
            pos: origin,
            vel: Vec2(dx / distance, dy / distance) * tuning.enemyShotSpeed,
            owner: .enemy,
            radius: tuning.enemyShotRadius,
            timeLeft: tuning.enemyShotLifetime
        ))
        events.append(.enemyFired(at: origin))
    }

    // MARK: Colonists and outposts

    func colonistIndex(_ id: Int) -> Int? {
        colonists.firstIndex { $0.id == id }
    }

    /// Where the nth colonist stands relative to an outpost: alternating sides, moving outward.
    private static func standingOffset(slot: Int) -> Double {
        let side = slot % 2 == 0 ? -1.0 : 1.0
        return side * (16 + 14 * Double(slot / 2))
    }

    private mutating func addColonists(at outpost: Outpost) {
        for slot in 0..<tuning.colonistsPerOutpost {
            let x = world.wrap(outpost.x + Simulation.standingOffset(slot: slot))
            colonists.append(Colonist(
                id: takeID(),
                pos: Vec2(x, world.groundHeight(at: x)),
                home: outpost.id
            ))
        }
    }

    private mutating func dropColonist(at index: Int) {
        let pos = colonists[index].pos
        let height = max(0, pos.y - world.groundHeight(at: pos.x))
        colonists[index].state = .falling(speed: 0, from: height)
        events.append(.colonistDropped(id: colonists[index].id))
    }

    private mutating func loseColonist(at index: Int) {
        colonists[index].state = .lost
        colonists[index].claimedBy = nil
        events.append(.colonistLost(id: colonists[index].id, at: colonists[index].pos))
    }

    private mutating func updateColonists(_ dt: Double) {
        for index in colonists.indices {
            guard case .falling(let speed, let from) = colonists[index].state else { continue }
            let newSpeed = min(speed + tuning.gravity * dt, tuning.terminalFallSpeed)
            colonists[index].pos.y -= newSpeed * dt
            let ground = world.groundHeight(at: colonists[index].pos.x)
            if colonists[index].pos.y > ground {
                colonists[index].state = .falling(speed: newSpeed, from: from)
            } else {
                colonists[index].pos.y = ground
                if from > tuning.safeFallHeight {
                    loseColonist(at: index)
                } else {
                    colonists[index].state = .grounded
                    events.append(.colonistLanded(id: colonists[index].id))
                }
            }
        }

        guard player.isAlive, !player.carried.isEmpty else { return }
        for (slot, id) in player.carried.enumerated() {
            if let index = colonistIndex(id) {
                colonists[index].pos = Vec2(player.pos.x, player.pos.y - 16 - 10 * Double(slot))
            }
        }
        deliverCarriedColonists()
    }

    private mutating func deliverCarriedColonists() {
        guard let outpost = world.outposts.first(where: {
            isOutpostIntact($0.id) && abs(world.delta(from: player.pos.x, to: $0.x)) < tuning.deliveryRadius
        }), player.pos.y - outpost.groundY < tuning.deliveryAltitude else { return }

        // Bringing several home at once is worth more for each of them.
        let points = tuning.deliveryPoints * player.carried.count
        for (slot, id) in player.carried.enumerated() {
            guard let index = colonistIndex(id) else { continue }
            let x = world.wrap(outpost.x + Simulation.standingOffset(slot: slot))
            colonists[index].pos = Vec2(x, world.groundHeight(at: x))
            colonists[index].state = .grounded
            colonists[index].home = outpost.id
            let wasCharged = player.shield >= 1
            player.shield = min(1, player.shield + tuning.shieldPerDelivery)
            colonistsSaved += 1
            addScore(points)
            events.append(.colonistDelivered(id: id, outpost: outpost.id, points: points))
            if !wasCharged, player.shield >= 1 {
                events.append(.shieldCharged)
            }
        }
        player.carried.removeAll()
    }

    /// Nearest outpost that is still standing, if any.
    func nearestIntactOutpost(to x: Double) -> Int? {
        world.outposts
            .filter { isOutpostIntact($0.id) }
            .min { abs(world.delta(from: x, to: $0.x)) < abs(world.delta(from: x, to: $1.x)) }?
            .id
    }

    mutating func destroyOutpost(_ id: Int) {
        outpostIntegrity[id] = 0
        events.append(.outpostDestroyed(id: id))
        let x = world.outposts[id].x
        for index in colonists.indices
        where colonists[index].state == .grounded
            && abs(world.delta(from: x, to: colonists[index].pos.x)) < tuning.outpostBlastRadius {
            loseColonist(at: index)
        }
    }

    /// Starts a Blackout when the last colonist is lost, and sends a supply drop when there is
    /// nobody left to save or nowhere left to bring them.
    private mutating func updateSupply(_ dt: Double) {
        let noColonists = survivingColonists == 0
        if noColonists, !isBlackout {
            isBlackout = true
            events.append(.blackoutBegan)
            for index in enemies.indices where enemies[index].kind == .harvester {
                var enemy = enemies[index]
                turnIntoHusk(&enemy)
                enemies[index] = enemy
            }
        }

        guard noColonists || !outpostIntegrity.contains(where: { $0 > 0 }) else {
            supplyTimer = tuning.supplyDelay
            return
        }
        supplyTimer -= dt
        guard supplyTimer <= 0 else { return }
        supplyTimer = tuning.supplyDelay

        // Rebuild a ruined outpost if there is one, otherwise reinforce a standing one.
        let ruined = world.outposts.filter { !isOutpostIntact($0.id) }
        let candidates = ruined.isEmpty ? world.outposts : ruined
        let outpost = candidates[Int(rng.next() % UInt64(candidates.count))]
        outpostIntegrity[outpost.id] = 1
        addColonists(at: outpost)
        events.append(.outpostRestored(id: outpost.id))
        if isBlackout {
            isBlackout = false
            events.append(.blackoutEnded)
        }
    }

    func turnIntoHusk(_ enemy: inout Enemy) {
        let stats = tuning.stats(for: .husk)
        enemy.kind = .husk
        enemy.state = .hunting
        enemy.vel = .zero
        enemy.radius = stats.radius
        enemy.hp = stats.hp
    }

    // MARK: Projectiles and contact

    private mutating func updateProjectiles(_ dt: Double) {
        var survivors: [Projectile] = []
        survivors.reserveCapacity(projectiles.count)
        for var shot in projectiles {
            shot.timeLeft -= dt
            guard shot.timeLeft > 0 else { continue }
            let travel = shot.vel * dt

            switch shot.owner {
            case .player:
                if let hit = firstEnemyHit(from: shot.pos, travel: travel, radius: shot.radius) {
                    damageEnemy(at: hit)
                    continue
                }
            case .enemy:
                if player.isAlive, player.invulnerableTimer <= 0,
                   sweepTime(from: shot.pos, travel: travel, to: player.pos,
                             radius: shot.radius + tuning.playerRadius) != nil {
                    hitPlayer()
                    continue
                }
            }

            shot.pos = Vec2(world.wrap(shot.pos.x + travel.x), shot.pos.y + travel.y)
            if shot.pos.y < world.groundHeight(at: shot.pos.x) || shot.pos.y > world.height {
                continue
            }
            survivors.append(shot)
        }
        projectiles = survivors
    }

    private func sweepTime(from origin: Vec2, travel: Vec2, to target: Vec2, radius: Double) -> Double? {
        let relative = Vec2(world.delta(from: origin.x, to: target.x), target.y - origin.y)
        return Collision.sweepTime(center: relative, travel: travel, radius: radius)
    }

    /// Index of the enemy a shot reaches first during this step, if any.
    private func firstEnemyHit(from origin: Vec2, travel: Vec2, radius: Double) -> Int? {
        var best: (index: Int, time: Double)?
        for (index, enemy) in enemies.enumerated() {
            guard let time = sweepTime(from: origin, travel: travel, to: enemy.pos,
                                       radius: radius + enemy.radius) else { continue }
            if best == nil || time < best!.time {
                best = (index, time)
            }
        }
        return best?.index
    }

    private mutating func resolvePlayerContacts() {
        guard player.isAlive else { return }

        for index in colonists.indices {
            guard case .falling = colonists[index].state,
                  world.distance(player.pos, colonists[index].pos) < tuning.catchRadius else { continue }
            colonists[index].state = .carried
            player.carried.append(colonists[index].id)
            addScore(tuning.catchPoints)
            events.append(.colonistCaught(id: colonists[index].id))
        }

        guard player.invulnerableTimer <= 0 else { return }
        if let index = enemies.firstIndex(where: {
            world.distance(player.pos, $0.pos) < tuning.playerRadius + $0.radius
        }) {
            // Ramming destroys the enemy whatever its strength, and costs the shield or the ship.
            destroyEnemy(at: index)
            hitPlayer()
        }
    }

    private mutating func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }
}
