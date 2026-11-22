import Foundation
import GameCore

/// One Riftwing run: the whole state of the cavern gallery and its rules. It advances in fixed
/// steps and is deterministic for a given seed and input sequence. It knows roles and
/// positions, never how anything looks or sounds.
///
/// The gallery is `size` (900 x 600 by default) seen from the side, the origin at the
/// bottom-left and y up. Its left and right edges join: anything leaving one side comes in at
/// the other, and distances and contacts are measured round the join. The roof stops a rig;
/// the Rift along the bottom (below `RiftwingTuning.riftLevel`) takes anything that falls in.
/// Everything a renderer needs is public and read-only: `rider`, `opponents`, `pods`, `mines`,
/// `arrivals`, `layout` (ledges and vents), `breath` and `gasLevel`, `phase`, the counters,
/// `isLampsOut`.
public struct RiftwingRun: Sendable {
    /// Seconds per step: 120 steps a second, matching the display.
    public static let timeStep = 1.0 / 120.0

    public let tuning: RiftwingTuning
    /// The wave makeup and eases.
    public let director: RiftwingWaves
    public internal(set) var rider: RiftwingRider
    /// Every opponent in the gallery: rigs and Gleaners.
    public internal(set) var opponents: [RiftwingOpponent] = []
    /// This wave's pods, in every state (freed and lost ones stay until the next wave).
    public internal(set) var pods: [RiftwingPod] = []
    public internal(set) var mines: [RiftwingMine] = []
    /// Opponents whose glow shows in a tunnel mouth.
    public internal(set) var arrivals: [RiftwingArrival] = []
    /// Which of `RiftwingCavern.layouts` the gallery is in.
    public internal(set) var layoutIndex: Int
    public internal(set) var phase: RiftwingPhase
    public internal(set) var breath: RiftwingBreath = .calm
    /// Breaths this wave, counting one whose warning has begun.
    public internal(set) var breathsThisWave = 0
    public internal(set) var score = 0
    /// The wave on now (0 before the first).
    public internal(set) var wave = 0
    public internal(set) var tick = 0
    /// Seconds since the current wave began.
    public internal(set) var waveClock = 0.0
    /// Colonists freed this run.
    public internal(set) var colonistsSaved = 0
    /// This wave: pods dropped, colonists freed, colonists lost.
    public internal(set) var waveDropped = 0
    public internal(set) var waveFreed = 0
    public internal(set) var waveLost = 0
    /// The gallery's lamps are out: the renderer darkens it to a pool of light round the rider.
    public internal(set) var isLampsOut = false
    /// Every colonist of a wave was lost: the lamps fail when the next wave starts. True from
    /// that moment, through the break, until then.
    public internal(set) var lampsOutPending = false
    public internal(set) var isGameOver = false

    var rng: SeededRNG
    var events: [RiftwingEvent] = []
    /// Tests turn this off to set up a scene by hand: no waves start and none clear.
    var wavesEnabled = true
    /// The wave's rigs in the order they are sent, and how many have been sent.
    var toSend: [RiftwingRole] = []
    var sendIndex = 0
    /// Seconds a place for a rig has been free.
    var sendTimer = 0.0
    /// Gleaners this wave still has to send, and the wave-clock time the next may come.
    var gleanersLeft = 0
    var gleanerNextAt = 0.0
    /// The step since which no place in the mouths has been clear for a new arrival.
    var arrivalBlockedSince: Int?
    /// Wave-clock time of the next breath's warning.
    var nextBreathAt = 0.0
    /// The next wave's layout is ready (applied in the last second of the break).
    var waveReady = false
    /// The layout the cavern is shifting to in this break.
    var shiftTo: Int?
    #if DEBUG
    /// DEBUG only (`Config.lampsOutAtWave`): this wave begins with the lamps out.
    var forcedLampsOutWave: Int?
    #endif

    private var nextID = 1
    private var nextExtraLifeScore: Int

    public init(seed: UInt64, tuning: RiftwingTuning = RiftwingTuning(), waves: RiftwingWaves = RiftwingWaves()) {
        self.tuning = tuning
        director = waves
        rng = SeededRNG(seed: seed ^ 0x21F7_3A1D_C0DE_9E11)
        nextExtraLifeScore = tuning.extraLifeEvery
        phase = .intermission(remaining: tuning.firstWaveDelay)
        nextBreathAt = tuning.breathAfter
        layoutIndex = 0
        let start = RiftwingCavern.layouts[0]
        var body = RiftwingBody(pos: .zero, radius: tuning.riderRadius)
        body.pos = Self.standingPoint(on: start.ledges[start.startLedge], radius: body.radius, tuning: tuning)
        body.ledge = start.startLedge
        rider = RiftwingRider(body: body, lives: tuning.startingLives)
    }

    // MARK: Reading

    public var size: Vec2 { Vec2(tuning.width, tuning.height) }
    public var layout: RiftwingLayout { RiftwingCavern.layouts[layoutIndex] }
    public var ledges: [RiftwingLedge] { layout.ledges }
    public var vents: [RiftwingVent] { layout.vents }

    /// The top of the Rift's gas: the Rift's own level while calm, up to
    /// `breathLevel` while it breathes.
    public var gasLevel: Double {
        let low = tuning.riftLevel, high = breathLevel
        switch breath {
        case .calm, .warning: return low
        case .rising(let remaining):
            return low + (high - low) * (1 - remaining / max(tuning.breathRise, 1e-9))
        case .holding: return high
        case .falling(let remaining):
            return low + (high - low) * (remaining / max(tuning.breathFall, 1e-9))
        }
    }

    /// The height the current (or next) breath of this wave rises to: `RiftwingTuning.breathLevel`
    /// for the first, `breathGrowth` higher for each after it, up to the roof, so a wave that
    /// stalls anywhere is ended in the end.
    public var breathLevel: Double {
        min(tuning.breathLevel + tuning.breathGrowth * Double(max(breathsThisWave - 1, 0)), tuning.roof)
    }

    /// Seconds until the current breath stops taking what is under it (0 while calm or falling).
    public var breathDeadlyTimeLeft: Double {
        switch breath {
        case .calm, .falling: 0
        case .warning(let remaining): remaining + tuning.breathRise + tuning.breathHold
        case .rising(let remaining): remaining + tuning.breathHold
        case .holding(let remaining): remaining
        }
    }

    /// True while the gas takes whatever is under `gasLevel`.
    public var isBreathDeadly: Bool {
        switch breath {
        case .rising, .holding: true
        case .calm, .warning, .falling: false
        }
    }

    /// Rigs that must still be knocked down (in the gallery, on their way in, or still to be
    /// sent) before the wave can end.
    public var rigsHoldingWave: Int {
        opponents.count { !$0.isDead && $0.role.isRig } + arrivals.count { $0.role.isRig }
            + max(toSend.count - sendIndex, 0)
    }

    /// Pods still in play: falling, resting or in a Gleaner's grip.
    public var podsInPlay: Int { pods.count { $0.isUnsettled } }

    public func opponent(_ id: Int) -> RiftwingOpponent? { opponents.first { $0.id == id } }
    public func pod(_ id: Int) -> RiftwingPod? { pods.first { $0.id == id } }

    /// Where a rig of `radius` stands on `ledge`, at its middle.
    public static func standingPoint(on ledge: RiftwingLedge, radius: Double, tuning: RiftwingTuning) -> Vec2 {
        Vec2(ledge.midX, ledge.top + radius * tuning.feetShare)
    }

    // MARK: Stepping

    /// Advances the run by one `timeStep` and returns what happened.
    public mutating func step(_ input: RiftwingInput) -> [RiftwingEvent] {
        guard !isGameOver else { return [] }
        events.removeAll(keepingCapacity: true)
        tick += 1
        let dt = Self.timeStep
        // Nothing happens after the game is over, even later in the step that ended it, so the
        // score `gameOver` announced is the final score.
        updatePhase(dt)
        updateRider(input, dt)
        if isGameOver { return events }
        updateOpponents(dt)
        updatePods(dt)
        updateMines(dt)
        resolveContacts()
        if isGameOver { return events }
        applyBreath()
        if isGameOver { return events }
        opponents.removeAll { $0.isDead }
        checkWaveCleared()
        return events
    }

    // MARK: Waves

    private mutating func updatePhase(_ dt: Double) {
        updateArrivals(dt)
        guard wavesEnabled else {
            if phase == .fighting {
                waveClock += dt
                updateBreath(dt)
            }
            return
        }
        switch phase {
        case .intermission(let remaining):
            let left = remaining - dt
            // The last second of the break: the rock settles into the next layout.
            if !waveReady, left <= tuning.telegraphTime { prepareWave() }
            if left <= 0 {
                startWave()
            } else {
                phase = .intermission(remaining: left)
            }
        case .fighting:
            waveClock += dt
            sendRigs(dt)
            sendGleaners()
            updateBreath(dt)
        }
    }

    /// Readies the next wave in the last second of the break: the new layout, if the cavern is
    /// shifting.
    mutating func prepareWave() {
        waveReady = true
        if let next = shiftTo {
            shiftTo = nil
            applyLayout(next)
        }
    }

    /// Puts the gallery in layout `index`. Nothing is left inside rock: a rider (or rig) that
    /// was standing ends standing on the nearest ledge of the new layout, one flying is moved
    /// out of any rock into free space, and pods are treated the same way (a resting pod rests
    /// on the nearest new ledge). The shift itself never costs the rider a life.
    mutating func applyLayout(_ index: Int) {
        layoutIndex = index
        events.append(.cavernShifted(layout: index))
        if rider.isAlive { settleAfterShift(&rider.body) }
        for i in opponents.indices where !opponents[i].isDead {
            settleAfterShift(&opponents[i].body)
        }
        let r = tuning.podRadius
        for i in pods.indices {
            switch pods[i].state {
            case .resting:
                let (ledge, p) = nearestStand(to: pods[i].pos, lift: r)
                pods[i].pos = p
                pods[i].state = .resting(ledge: ledge)
            case .falling:
                pods[i].pos.y = outOfRock(pods[i].pos, feet: r, head: r)
            case .seized, .freed, .lost:
                break
            }
        }
    }

    /// A body after the cavern shifted: standing, it stands on the nearest new ledge; flying, it
    /// is moved out of any rock it is now inside.
    private func settleAfterShift(_ b: inout RiftwingBody) {
        let feet = b.radius * tuning.feetShare, head = b.radius * tuning.headShare
        if b.isGrounded {
            let (ledge, p) = nearestStand(to: b.pos, lift: feet)
            b.pos = p
            b.vel = .zero
            b.ledge = ledge
            b.isDiving = false
            b.reopen = 0
        } else {
            b.pos.y = outOfRock(b.pos, feet: feet, head: head)
        }
    }

    /// The ledge whose standing surface is nearest `p` (with `lift` from the feet to the
    /// centre), and the point on it, a little in from its ends.
    func nearestStand(to p: Vec2, lift: Double) -> (Int, Vec2) {
        var best = 0
        var bestPoint = p
        var bestGap = Double.infinity
        for (index, ledge) in ledges.enumerated() {
            let inset = min(2, ledge.length / 2)
            let q = Vec2(clamp(p.x, ledge.minX + inset, ledge.maxX - inset), ledge.top + lift)
            let gap = hypot(q.x - p.x, q.y - p.y)
            if gap < bestGap {
                bestGap = gap
                best = index
                bestPoint = q
            }
        }
        return (best, bestPoint)
    }

    /// A height for something at `p` (reaching `feet` below its centre and `head` above) that is
    /// clear of every ledge's rock: unchanged if it is clear, else moved to the nearer of just
    /// above or just below the rock it is in.
    func outOfRock(_ p: Vec2, feet: Double, head: Double) -> Double {
        var y = p.y
        for _ in 0..<3 {
            guard let ledge = ledges.first(where: { l in
                l.spans(p.x) && y - feet < l.top && y + head > l.top - tuning.ledgeThickness
            }) else { break }
            let up = ledge.top + feet + 0.5, down = ledge.top - tuning.ledgeThickness - head - 0.5
            y = up - y <= y - down ? up : down
        }
        return y
    }

    mutating func startWave() {
        if !waveReady { prepareWave() }
        waveReady = false
        wave += 1
        phase = .fighting
        waveClock = 0
        waveDropped = 0
        waveFreed = 0
        waveLost = 0
        pods.removeAll()
        toSend = director.rigs(forWave: wave)
        sendIndex = 0
        sendTimer = 0
        gleanersLeft = director.count(of: .gleaner, inWave: wave)
        gleanerNextAt = director.gleanerDelay(forWave: wave)
        nextBreathAt = tuning.breathAfter
        breath = .calm
        breathsThisWave = 0
        #if DEBUG
        if forcedLampsOutWave == wave { lampsOutPending = true }
        #endif
        if lampsOutPending {
            lampsOutPending = false
            if !isLampsOut {
                isLampsOut = true
                events.append(.lampsFailed)
            }
        }
        events.append(.waveStarted(wave: wave, layout: layoutIndex))
    }

    private mutating func checkWaveCleared() {
        guard wavesEnabled, !isGameOver, phase == .fighting, rigsHoldingWave == 0, podsInPlay == 0 else { return }
        clearWave()
    }

    mutating func clearWave() {
        let bonus = waveFreed * tuning.waveBonusPerColonist
        addScore(bonus)
        events.append(.waveCleared(wave: wave, freed: waveFreed, bonus: bonus))
        // Gleaners leave with the wave; mines go with it.
        for index in opponents.indices where !opponents[index].isDead {
            opponents[index].isDead = true
            events.append(.opponentWithdrew(id: opponents[index].id, role: opponents[index].role, at: opponents[index].pos))
        }
        opponents.removeAll()
        arrivals.removeAll()
        for mine in mines { events.append(.mineCleared(id: mine.id, at: mine.pos, reason: .waveEnded)) }
        mines.removeAll()
        gleanersLeft = 0
        if breath != .calm {
            breath = .calm
            events.append(.riftSettled)
        }
        if waveDropped > 0, waveFreed == 0 {
            events.append(.allColonistsLost(wave: wave))
            lampsOutPending = true
        }
        #if DEBUG
        // Lamps forced out show as pending through the break before, like real ones.
        if forcedLampsOutWave == wave + 1 { lampsOutPending = true }
        #endif
        var pause = tuning.intermission
        let next = RiftwingCavern.layoutIndex(forWave: wave + 1, wavesPerLayout: tuning.wavesPerLayout)
        if next != layoutIndex {
            shiftTo = next
            pause += tuning.shiftPause
            events.append(.cavernShifting(from: layoutIndex, to: next))
        }
        phase = .intermission(remaining: pause)
    }

    #if DEBUG
    /// DEBUG only: the next wave to start is `start`, in its layout.
    mutating func skipToWave(_ start: Int) {
        wave = start - 1
        let index = RiftwingCavern.layoutIndex(forWave: start, wavesPerLayout: tuning.wavesPerLayout)
        layoutIndex = index
        let ledge = layout.startLedge
        rider.body.pos = Self.standingPoint(on: ledges[ledge], radius: rider.body.radius, tuning: tuning)
        rider.body.ledge = ledge
    }
    #endif

    // MARK: Sending opponents

    /// Sends the wave's rigs a few at a time: while fewer than the wave's concurrency are in the
    /// gallery or on their way, the next is sent once a place has been free for the gap (the
    /// opening ones `openingGap` apart, the first at once).
    private mutating func sendRigs(_ dt: Double) {
        guard sendIndex < toSend.count else { return }
        let active = opponents.count { !$0.isDead && $0.role.isRig } + arrivals.count { $0.role.isRig }
        guard active < director.concurrency(forWave: wave) else {
            sendTimer = 0
            return
        }
        sendTimer += dt
        let opening = sendIndex < director.concurrency(forWave: wave)
        let gap = sendIndex == 0 ? 0 : (opening ? director.openingGap : director.sendGap)
        guard sendTimer >= gap - 1e-9 else { return }
        if telegraph(toSend[sendIndex]) {
            sendIndex += 1
            sendTimer = 0
        }
    }

    /// Sends the wave's Gleaners singly, late, and only while a pod rests on a ledge for one to
    /// go for.
    private mutating func sendGleaners() {
        guard gleanersLeft > 0, waveClock >= gleanerNextAt,
              !opponents.contains(where: { !$0.isDead && $0.role == .gleaner }),
              !arrivals.contains(where: { $0.role == .gleaner }),
              pods.contains(where: { if case .resting = $0.state { true } else { false } }) else { return }
        if telegraph(.gleaner) { gleanersLeft -= 1 }
    }

    /// Starts an arrival's glow in a tunnel mouth at a height at least `safeDistance` from the
    /// rider (and from where it will return while it is down). False when no mouth is clear;
    /// the caller tries again next step. Once no mouth has been clear for
    /// `arrivalPatience`, it glows anyway at the farthest place, for longer, and will come out.
    @discardableResult
    mutating func telegraph(_ role: RiftwingRole) -> Bool {
        let r = tuning.stats(for: role).radius
        for _ in 0..<10 {
            let side: RiftwingSide = rng.chance(0.5) ? .left : .right
            let y = rng.range(tuning.arrivalHeights)
            let p = Vec2(side == .left ? r : tuning.width - r, y)
            guard isClearOfRider(p, by: tuning.safeDistance) else { continue }
            arrivalBlockedSince = nil
            let id = takeID()
            arrivals.append(RiftwingArrival(id: id, role: role, side: side, pos: p, remaining: tuning.telegraphTime,
                                            glowTime: tuning.telegraphTime))
            events.append(.arrivalTelegraphed(id: id, role: role, side: side, at: p))
            return true
        }
        let since = arrivalBlockedSince ?? tick
        arrivalBlockedSince = since
        guard Double(tick - since) * Self.timeStep >= tuning.arrivalPatience - 1e-9 else { return false }
        arrivalBlockedSince = nil
        forceArrival(id: takeID(), role: role)
        return true
    }

    /// An arrival that waited too long for a clear place glows at the place in the mouths
    /// farthest from the rider, for `forcedTelegraphTime`, and comes out there whatever happens.
    private mutating func forceArrival(id: Int, role: RiftwingRole) {
        let r = tuning.stats(for: role).radius
        let heights = tuning.arrivalHeights
        var best = Vec2(r, heights.lowerBound)
        var bestSide = RiftwingSide.left
        var bestGap = -Double.infinity
        for side in RiftwingSide.allCases {
            for i in 0...20 {
                let y = heights.lowerBound + (heights.upperBound - heights.lowerBound) * Double(i) / 20
                let p = Vec2(side == .left ? r : tuning.width - r, y)
                let gap = wrapDistance(p, rider.body.pos)
                if gap > bestGap + 1e-9 {
                    bestGap = gap
                    best = p
                    bestSide = side
                }
            }
        }
        arrivals.append(RiftwingArrival(id: id, role: role, side: bestSide, pos: best,
                                        remaining: tuning.forcedTelegraphTime, glowTime: tuning.forcedTelegraphTime,
                                        isForced: true))
        events.append(.arrivalTelegraphed(id: id, role: role, side: bestSide, at: best))
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
            // The rider came close to the mouth while it glowed: the arrival moves to a clear
            // height (or the other mouth) and glows again there, so nothing ever appears on top
            // of the rider. A forced arrival comes out regardless.
            if !arrival.isForced, !isClearOfRider(arrival.pos, by: tuning.safeDistance) {
                arrivals.remove(at: index)
                retelegraph(arrival)
                continue
            }
            arrivals.remove(at: index)
            addOpponent(arrival.role, at: arrival.pos, id: arrival.id, heading: arrival.side == .left ? 1 : -1)
            events.append(.opponentArrived(id: arrival.id, role: arrival.role, at: arrival.pos))
        }
    }

    /// An arrival that could not come out where it glowed glows again at a clear place, keeping
    /// its id; if none is clear it waits a moment where it is, and once it has waited
    /// `arrivalPatience` it is forced out at the farthest place.
    private mutating func retelegraph(_ arrival: RiftwingArrival) {
        let r = tuning.stats(for: arrival.role).radius
        for _ in 0..<10 {
            let side: RiftwingSide = rng.chance(0.5) ? .left : .right
            let p = Vec2(side == .left ? r : tuning.width - r, rng.range(tuning.arrivalHeights))
            guard isClearOfRider(p, by: tuning.safeDistance) else { continue }
            arrivals.append(RiftwingArrival(id: arrival.id, role: arrival.role, side: side, pos: p,
                                            remaining: tuning.telegraphTime, glowTime: tuning.telegraphTime))
            events.append(.arrivalTelegraphed(id: arrival.id, role: arrival.role, side: side, at: p))
            return
        }
        var waiting = arrival
        waiting.waited += 0.25
        if waiting.waited >= tuning.arrivalPatience - 1e-9 {
            forceArrival(id: arrival.id, role: arrival.role)
            return
        }
        waiting.remaining = 0.25
        arrivals.append(waiting)
    }

    /// True when `p` is at least `gap` from the rider round the join (and, while it is down,
    /// from every ledge it might return on).
    func isClearOfRider(_ p: Vec2, by gap: Double) -> Bool {
        if rider.isAlive { return wrapDistance(p, rider.body.pos) >= gap }
        return wrapDistance(p, rider.body.pos) >= gap
            && ledges.allSatisfy { wrapDistance(p, Self.standingPoint(on: $0, radius: rider.body.radius, tuning: tuning)) >= gap * 0.6 }
    }

    /// Adds an opponent in its role's usual starting state, eased for its appearance this wave.
    @discardableResult
    mutating func addOpponent(_ role: RiftwingRole, at pos: Vec2, id: Int? = nil, heading: Double = 1) -> Int {
        let stats = tuning.stats(for: role)
        var body = RiftwingBody(pos: pos, radius: stats.radius)
        body.facing = heading
        body.vel = Vec2(heading * tuning.arrivalSpeed, 0)
        let ease = director.ease(of: role, inWave: max(wave, 1))
        var opponent = RiftwingOpponent(id: id ?? takeID(), role: role, body: body,
                                        state: role == .gleaner ? .seeking(pod: nil) : .flying, blows: stats.blows)
        opponent.ease = ease
        opponent.speed = stats.maxSpeed * speedScale(role, ease: ease)
        opponent.goal = pos
        opponent.timer = rng.range(0...0.3)
        switch role {
        case .sower:
            opponent.drift = heading
            opponent.goal = Vec2(pos.x, rng.range(tuning.sowerBand))
            opponent.mineTimer = tuning.mineInterval * (1 + director.sowerIntervalEase * ease) * rng.range(0.5...1)
        case .gleaner:
            opponent.speed = tuning.gleanerSpeed * director.gleanerSpeedScale(forWave: max(wave, 1))
        case .glider, .striker, .warden:
            break
        }
        opponents.append(opponent)
        return opponent.id
    }

    /// The share of its top speed a role flies at with `ease` left.
    func speedScale(_ role: RiftwingRole, ease: Double) -> Double {
        switch role {
        case .glider: 1 - director.gliderSpeedEase * ease
        case .striker: 1 - director.strikerSpeedEase * ease
        case .warden: 1 - director.wardenSpeedEase * ease
        case .sower: 1 - director.sowerSpeedEase * ease
        case .gleaner: 1
        }
    }

    // MARK: The Rift's breath

    private mutating func updateBreath(_ dt: Double) {
        switch breath {
        case .calm:
            if waveClock >= nextBreathAt {
                breathsThisWave += 1
                breath = .warning(remaining: tuning.breathWarning)
                events.append(.riftWarning(level: breathLevel))
            }
        case .warning(let remaining):
            if remaining - dt <= 0 {
                breath = .rising(remaining: tuning.breathRise)
                events.append(.riftBreathed(level: breathLevel))
            } else {
                breath = .warning(remaining: remaining - dt)
            }
        case .rising(let remaining):
            breath = remaining - dt <= 0 ? .holding(remaining: tuning.breathHold) : .rising(remaining: remaining - dt)
        case .holding(let remaining):
            breath = remaining - dt <= 0 ? .falling(remaining: tuning.breathFall) : .holding(remaining: remaining - dt)
        case .falling(let remaining):
            if remaining - dt <= 0 {
                breath = .calm
                nextBreathAt = waveClock + tuning.breathRepeat
                events.append(.riftSettled)
            } else {
                breath = .falling(remaining: remaining - dt)
            }
        }
    }

    /// While the gas rises or holds, whatever is under it is lost: the rider (unless protected),
    /// opponents, and pods falling or resting.
    private mutating func applyBreath() {
        guard isBreathDeadly else { return }
        let level = gasLevel
        if rider.isAlive, !rider.isInvulnerable, rider.body.pos.y < level {
            loseRider(cause: .breath)
        }
        for index in opponents.indices where !opponents[index].isDead && opponents[index].pos.y < level {
            opponentFell(at: index, cause: .breath)
        }
        for index in pods.indices where pods[index].pos.y < level {
            switch pods[index].state {
            case .falling, .resting: losePod(at: index, cause: .breath)
            case .seized, .freed, .lost: break
            }
        }
    }

    // MARK: The rider

    private mutating func updateRider(_ input: RiftwingInput, _ dt: Double) {
        guard rider.isAlive else {
            if rider.lives > 0 {
                rider.respawnTimer -= dt
                if rider.respawnTimer <= 0 { respawnRider() }
            }
            return
        }
        rider.invulnerableTimer = max(0, rider.invulnerableTimer - dt)
        let flap = input.flap && !rider.flapHeld
        rider.flapHeld = input.flap
        let control = RigControl(steer: input.steer, flap: flap, dive: input.wantsDive(tuning))
        let wasGrounded = rider.body.isGrounded
        let result = fly(&rider.body, control, riderFlight, dt)
        let at = rider.body.pos
        if result.diveBegan { events.append(.diveBegan(at: at)) }
        if result.wingsOpening { events.append(.wingsOpening(at: at)) }
        if result.wingsOpened { events.append(.wingsOpened(at: at)) }
        if result.flapped { events.append(.flapped(at: at, fromLedge: wasGrounded)) }
        if let ledge = result.landed { events.append(.landed(at: at, ledge: ledge)) }
        if result.bumped { events.append(.bumpedLedge(at: at)) }
        if result.vent != rider.vent {
            rider.vent = result.vent
            if let vent = result.vent { events.append(.ventEntered(vent: vent, at: at)) }
        }
        if rider.body.pos.y < tuning.riftLevel {
            loseRider(cause: .rift)
        }
    }

    /// The rider's flight numbers.
    var riderFlight: FlightParams {
        FlightParams(maxSpeed: tuning.maxAirSpeed, airAccel: tuning.airAccel, flapImpulse: tuning.flapImpulse,
                     flapThrust: tuning.flapThrust, maxRise: tuning.maxRise, runSpeed: tuning.runSpeed)
    }

    /// The rider is lost (it does nothing while protected).
    mutating func loseRider(cause: RiftwingLossCause) {
        guard rider.isAlive else { return }
        if case .rift = cause {} else if rider.isInvulnerable { return }
        rider.isAlive = false
        rider.lives -= 1
        rider.vent = nil
        rider.flapHeld = false
        rider.body.vel = .zero
        rider.body.isDiving = false
        rider.body.reopen = 0
        rider.body.ledge = nil
        events.append(.riderLost(at: rider.body.pos, livesLeft: rider.lives, cause: cause))
        if rider.lives <= 0 {
            isGameOver = true
            events.append(.gameOver(score: score))
        } else {
            rider.respawnTimer = tuning.respawnDelay
        }
    }

    /// Returns the rider standing on the ledge farthest from the fight (opponents, mines and
    /// arrivals), above the gas while the Rift is breathing if any ledge is, protected for a
    /// moment. If every ledge is under the gas it returns anyway, protected until the gas has
    /// gone, so a respawn is never lost to the breath already in the gallery.
    private mutating func respawnRider() {
        let r = rider.body.radius
        var best = layout.startLedge
        var bestGap = -Double.infinity
        for (index, ledge) in ledges.enumerated() {
            let p = Self.standingPoint(on: ledge, radius: r, tuning: tuning)
            if breath != .calm, p.y < breathLevel + r { continue }
            var gap = Double.infinity
            for opponent in opponents where !opponent.isDead { gap = min(gap, wrapDistance(p, opponent.pos)) }
            for mine in mines { gap = min(gap, wrapDistance(p, mine.pos) * 1.5) }
            for arrival in arrivals { gap = min(gap, wrapDistance(p, arrival.pos)) }
            if gap > bestGap {
                bestGap = gap
                best = index
            }
        }
        rider.isAlive = true
        rider.body.pos = Self.standingPoint(on: ledges[best], radius: r, tuning: tuning)
        rider.body.vel = .zero
        rider.body.ledge = best
        rider.body.isDiving = false
        rider.body.reopen = 0
        rider.invulnerableTimer = tuning.respawnInvulnerability
        if breath != .calm, rider.body.pos.y < breathLevel + r {
            rider.invulnerableTimer = max(rider.invulnerableTimer, breathDeadlyTimeLeft + 0.25)
        }
        events.append(.riderRespawned(at: rider.body.pos, ledge: best))
    }

    mutating func addScore(_ points: Int) {
        score += points
        while score >= nextExtraLifeScore {
            nextExtraLifeScore += tuning.extraLifeEvery
            if rider.lives < tuning.maxLives {
                rider.lives += 1
                events.append(.extraLife(lives: rider.lives))
            }
        }
    }

    // MARK: Helpers

    /// `x` brought into the gallery, across the join.
    public func wrapX(_ x: Double) -> Double {
        var x = x.truncatingRemainder(dividingBy: tuning.width)
        if x < 0 { x += tuning.width }
        return x
    }

    /// The shortest way across from `a` to `b`, round the join: -width/2...width/2.
    public func dxWrap(_ a: Double, _ b: Double) -> Double {
        var dx = (b - a).truncatingRemainder(dividingBy: tuning.width)
        if dx > tuning.width / 2 { dx -= tuning.width }
        if dx < -tuning.width / 2 { dx += tuning.width }
        return dx
    }

    /// Distance between two points round the join.
    public func wrapDistance(_ a: Vec2, _ b: Vec2) -> Double {
        hypot(dxWrap(a.x, b.x), b.y - a.y)
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
/// `exp`, never inlined for the same reason.
@inline(never) func expo(_ x: Double) -> Double { exp(x) }
