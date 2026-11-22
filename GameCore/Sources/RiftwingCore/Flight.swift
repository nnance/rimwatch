import GameCore

/// What a rig is asked to do this step: by the player for the rider, by its role's behaviour for
/// an opponent.
struct RigControl: Sendable {
    /// -1...1.
    var steer = 0.0
    /// Flap now (the rider flaps once per press: the press edge, not the hold).
    var flap = false
    /// Wings folded while true.
    var dive = false
}

/// The flight numbers that differ between rigs.
struct FlightParams: Sendable {
    var maxSpeed: Double
    var airAccel: Double
    var flapImpulse: Double
    var flapThrust: Double
    var maxRise: Double
    var runSpeed: Double
    /// How much harder than usual rock knocks it down (the rider pressing against rock again and
    /// again: `RiftwingTuning.pressedKnockGrowth`).
    var knockScale = 1.0
}

/// What happened to a rig in one step of flight.
struct FlightResult: Sendable {
    var flapped = false
    var landed: Int?
    var bumped = false
    /// It flew up into the roof and was knocked down.
    var bumpedRoof = false
    var diveBegan = false
    var wingsOpening = false
    var wingsOpened = false
    /// The vent it is in, if any.
    var vent: Int?
}

extension RiftwingRun {
    /// One step of flight for any rig: running on a ledge, or in the air under gravity with
    /// flaps, a lean against momentum, the glide, the dive and the wings reopening, vents, the
    /// roof, ledges to land on or bump under, and the join at the sides. The Rift is the
    /// caller's to check.
    func fly(_ b: inout RiftwingBody, _ c: RigControl, _ p: FlightParams, _ dt: Double) -> FlightResult {
        var result = FlightResult()
        b.sinceFlap += dt
        if abs(c.steer) > 0.1 { b.facing = c.steer > 0 ? 1 : -1 }
        let feet = b.radius * tuning.feetShare, head = b.radius * tuning.headShare

        if let index = b.ledge {
            let ledge = ledges[index]
            if c.flap {
                // Taking off.
                b.ledge = nil
                b.vel.y = p.flapImpulse
                b.vel.x += c.steer * p.flapThrust
                b.sinceFlap = 0
                result.flapped = true
            } else {
                // Running along the ledge.
                let target = c.steer * p.runSpeed
                let change = clamp(target - b.vel.x, -tuning.runAccel * dt, tuning.runAccel * dt)
                b.vel.x += change
                b.vel.y = 0
                b.pos.x += b.vel.x * dt
                if ledge.spans(b.pos.x) {
                    b.pos.y = ledge.top + feet
                    b.isDiving = false
                    b.reopen = 0
                    return result
                }
                // Ran off the end.
                b.ledge = nil
                b.pos.x = wrapX(b.pos.x)
                return result
            }
        }

        // The dive: wings fold while it is held, and take a moment to open after.
        if c.dive, !b.isDiving {
            b.isDiving = true
            b.diveStart = b.pos.y
            result.diveBegan = true
        } else if !c.dive, b.isDiving {
            b.isDiving = false
            b.reopen = tuning.wingReopen
            result.wingsOpening = true
        }
        if b.reopen > 0, !b.isDiving {
            b.reopen -= dt
            if b.reopen <= 0 {
                b.reopen = 0
                result.wingsOpened = true
            }
        }

        let fallBefore = b.vel.y
        b.vel.y -= (b.isDiving ? tuning.diveGravity : tuning.gravity) * dt
        if c.flap, !b.isDiving, b.reopen == 0, !result.flapped {
            b.vel.y = max(b.vel.y, min(b.vel.y + p.flapImpulse, p.maxRise))
            b.vel.x += c.steer * p.flapThrust
            b.sinceFlap = 0
            result.flapped = true
        }

        // Leaning against momentum, or gliding.
        let authority = b.isDiving ? tuning.diveSteer : 1
        if abs(c.steer) > 0.05 {
            b.vel.x += c.steer * p.airAccel * authority * dt
        } else {
            b.vel.x *= expo(-tuning.airDrag * dt)
        }
        if abs(b.vel.x) > p.maxSpeed {
            let excess = abs(b.vel.x) - p.maxSpeed
            b.vel.x -= (b.vel.x > 0 ? 1 : -1) * min(excess, 2 * p.airAccel * dt)
        }

        // Rising air.
        if !b.isDiving, let vent = ventIndex(at: b.pos) {
            result.vent = vent
            if b.vel.y < tuning.ventRise {
                b.vel.y = min(b.vel.y + tuning.ventLift * dt, tuning.ventRise)
            }
        }

        // Falling speed: the dive's limit; with the wings open, never past the open-wing limit,
        // and easing back to it after a dive.
        if b.isDiving {
            b.vel.y = max(b.vel.y, -tuning.diveTerminal)
        } else if b.vel.y < -tuning.terminalFall {
            if fallBefore >= -tuning.terminalFall {
                b.vel.y = -tuning.terminalFall
            } else {
                b.vel.y = min(b.vel.y + (-tuning.terminalFall - b.vel.y) * (1 - expo(-tuning.overspeedDrag * dt)),
                              -tuning.terminalFall)
                b.vel.y = max(b.vel.y, fallBefore)
            }
        }

        let previous = b.pos
        b.pos = b.pos + b.vel * dt
        b.pos.x = wrapX(b.pos.x)
        // The roof stops it and does no harm, but nothing can cling to it: flying up into it
        // knocks the rig down a little, so it bobs below the rock.
        if b.pos.y > tuning.roof - b.radius {
            b.pos.y = tuning.roof - b.radius
            if b.vel.y > 0 {
                b.vel.y = -max(tuning.ceilingKnock * p.knockScale, b.vel.y * 0.25)
                result.bumpedRoof = true
            } else {
                b.vel.y = min(b.vel.y, 0)
            }
        }

        // Ledges: land on top, bump the head underneath.
        for (index, ledge) in ledges.enumerated() where ledge.spans(b.pos.x) {
            let top = ledge.top, bottom = ledge.top - tuning.ledgeThickness
            guard b.pos.y - feet < top, b.pos.y + head > bottom else { continue }
            let fromAbove = previous.y - feet >= top - 1
            let fromBelow = previous.y + head <= bottom + 1
            if fromAbove || (!fromBelow && b.pos.y >= (top + bottom) / 2) {
                guard b.vel.y <= 0 || !fromAbove else { continue }
                b.pos.y = top + feet
                b.vel.y = 0
                b.vel.x = clamp(b.vel.x, -p.runSpeed, p.runSpeed)
                b.ledge = index
                b.isDiving = false
                b.reopen = 0
                result.landed = index
                result.vent = nil
                break
            } else {
                // Its head strikes the underside: knocked down a little, as at the roof.
                b.pos.y = bottom - head
                b.vel.y = -max(tuning.ledgeKnock * p.knockScale, abs(b.vel.y) * 0.25)
                result.bumped = true
            }
        }
        return result
    }

    /// The vent whose rising air is at `p`, if any.
    func ventIndex(at p: Vec2) -> Int? {
        for (index, vent) in vents.enumerated()
        where abs(dxWrap(vent.x, p.x)) <= tuning.ventHalfWidth && p.y < vent.top && p.y > tuning.riftLevel {
            return index
        }
        return nil
    }
}
