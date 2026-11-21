import Foundation
import GameCore
import RedoubtCore
import SpriteKit
import UIKit

// Redoubt's events turned into what the player sees: banners, popups, bursts and rings.

extension RedoubtMode {
    /// Where an event happened, if it has a place.
    func position(of event: RedoubtEvent) -> Vec2? {
        switch event {
        case .airlockClosed(let at), .airlockOpened(_, let at), .orbFired(let at, _), .shotEnded(_, let at, _),
             .shockwave(let at, _), .orbDestroyed(let at, _, _), .orbRespawned(let at),
             .arrivalTelegraphed(_, _, let at), .enemyArrived(_, _, let at), .burrowSpawned(_, _, let at),
             .spitterWindUp(_, let at), .enemyFired(_, let at, _), .enemyHit(_, _, let at),
             .enemyDestroyed(_, _, let at, _, _), .huskFormed(_, let at), .enemyWithdrew(_, _, let at),
             .colonistPickedUp(_, let at, _), .colonistSeized(_, _, let at), .colonistFreed(_, let at),
             .colonistTaken(_, _, _, let at), .colonistCrushed(_, _, let at), .colonistDelivered(_, let at, _, _):
            return at
        case .waveStarted, .waveCleared, .allColonistsLost, .powerCutBegan, .powerCutEnded, .chargeEarned,
             .lineScattered, .extraLife, .gameOver:
            return nil
        }
    }

    func handle(_ events: [RedoubtEvent], run: RedoubtRun) {
        guard !events.isEmpty else {
            pruneHits()
            return
        }
        let palette = theme.palette
        let mint = theme.color(of: .colonist)
        var delivered: (count: Int, points: Int, at: Vec2)?

        for event in events {
            switch event {
            // Waves
            case .waveStarted(let wave, let colonists):
                if events.contains(.powerCutBegan) {
                    // The lights fail as this wave starts: the power-cut banner says so, and a
                    // newcomer is named in the notice instead.
                    if let debut = RedoubtWaves.debut.first(where: { $0.wave == wave }) {
                        callouts.notice("New: \(theme.displayName(for: debut.role)). \(Self.hint(debut.role))",
                                        color: theme.color(of: .enemy(debut.role)).lightened(0.3), life: 2.4)
                    }
                } else if let debut = RedoubtWaves.debut.first(where: { $0.wave == wave }) {
                    banner("WAVE \(wave)", subtitle: "New: \(theme.displayName(for: debut.role)). \(Self.hint(debut.role))",
                           color: palette.heading, subtitleColor: theme.color(of: .enemy(debut.role)).lightened(0.3), life: 1.8)
                } else {
                    banner("WAVE \(wave)", subtitle: "\(colonists) colonists. Lead them to the airlock.",
                           color: palette.heading, subtitleColor: mint.lightened(0.2))
                }
            case .waveCleared(let wave, let safe, let bonus):
                banner("WAVE \(wave) CLEAR",
                       subtitle: safe > 0 ? "Survivor bonus +\(groupedDigits(bonus))" : "No colonists left to save",
                       color: palette.hud, subtitleColor: safe > 0 ? palette.reward : palette.warning, life: 0.6)
                if bonus > 0 { popup("+\(groupedDigits(bonus))", at: run.orb.pos, color: palette.reward, scale: 1.3) }
            case .airlockOpened(_, let at):
                effects.ring(at: at, color: mint, from: 10, to: 60, duration: 0.5)
            case .airlockClosed:
                break
            case .allColonistsLost:
                callouts.notice("EVERY COLONIST LOST", color: palette.warning)
            case .powerCutBegan:
                banner("POWER CUT", subtitle: "Deliver a colonist to bring the lights back",
                       color: palette.warning, life: 1.8)
                // The lights stutter out, in step with the failing hum.
                lightsFlicker = LightsFlicker(failing: true, since: clock)
            case .powerCutEnded:
                banner("POWER RESTORED", color: mint)
                // The generators spin up and the lights stutter back on with the rising chord.
                lightsFlicker = LightsFlicker(failing: false, since: clock)

            // The orb
            case .orbFired(let at, let heading):
                muzzleGlow = 1
                // A small flash of light on the floor in front of the emitter, and in the dark
                // the beam ahead brightens with each shot.
                effects.flash(at: at + Vec2(cos(heading), sin(heading)) * 4, radius: 16, color: RGB(hex: 0x9FF8FF),
                              life: 0.07, strength: 0.55)
                fireLight += (1 - fireLight) * 0.45
            case .shotEnded(_, let at, let reason):
                switch reason {
                case .hit:
                    // A spark where the shot struck, kicked back toward where it came from.
                    let back = atan2(run.orb.pos.y - at.y, run.orb.pos.x - at.x)
                    effects.spray(at: at, angle: back, spread: 1.0, color: RGB(hex: 0xD8FFFF), count: 3, speed: 130,
                                  life: 0.16, size: 0.6)
                    effects.flash(at: at, radius: 9, color: RGB(hex: 0xBFFBFF), life: 0.08, strength: 0.7)
                case .wall:
                    effects.burst(at: at, color: RGB(hex: 0xC8FFFF), count: 2, speed: 90, life: 0.2, size: 0.6)
                    effects.flash(at: at, radius: 7, color: RGB(hex: 0x9FF8FF), life: 0.07, strength: 0.5)
                case .expired, .cleared:
                    break
                }
            case .shockwave(let at, _):
                effects.ring(at: at, color: palette.shockwave, from: 20, to: tuning.shockwaveClearRadius,
                             duration: 0.3, width: 2)
                effects.ring(at: at, color: palette.shockwave, from: 60, to: tuning.shockwavePushRadius,
                             duration: 0.55, width: 1)
                effects.burst(at: at, color: palette.shockwave, count: 30, speed: 420, life: 0.5)
                effects.flash(at: at, radius: tuning.shockwaveClearRadius * 1.3, color: palette.shockwave, life: 0.4,
                              strength: 0.5)
                callouts.flash(palette.shockwave, strength: 0.14, duration: 0.35)
                // In a power cut the blast lights the whole room for a moment.
                roomLight = 1
                addShake(5)
            case .chargeEarned:
                callouts.notice("SHOCKWAVE CHARGED", color: palette.shockwave)
                hud.flash(.charges, at: clock)
            case .orbDestroyed(let at, let livesLeft, _):
                let cyan = theme.color(of: .orb)
                // The loss is told at the orb (a burst, the hull in pieces, a ring and a flash of
                // light) and by a light red tint, not a hard wash of the whole screen.
                effects.burst(at: at, color: cyan, count: 40, speed: 260, life: 0.8, size: 1.3)
                effects.shards(at: at, color: cyan, count: 10, speed: 150, life: 0.9, size: 1.6)
                effects.burst(at: at, color: palette.warning, count: 16, speed: 160, life: 0.6)
                effects.flash(at: at, radius: 70, color: palette.warning, life: 0.45, strength: 0.7)
                effects.ring(at: at, color: palette.warning, from: 8, to: 90, duration: 0.5, width: 1.5)
                callouts.flash(palette.warning, strength: 0.1, duration: 0.35)
                hud.flash(.lives, at: clock)
                addShake(7)
                if livesLeft > 0 {
                    callouts.notice(livesLeft == 1 ? "LAST LIFE" : "\(livesLeft) LIVES LEFT", color: palette.warning)
                }
            case .lineScattered(let count):
                popup(count == 1 ? "COLONIST DROPPED" : "LINE SCATTERED", at: run.orb.pos, color: palette.warning, scale: 0.9)
            case .orbRespawned(let at):
                effects.ring(at: at, color: theme.color(of: .orb), from: 120, to: 14, duration: 0.4, width: 1.5)
            case .extraLife:
                callouts.notice("EXTRA LIFE", color: palette.reward)
                hud.flash(.lives, at: clock)

            // Enemies
            case .enemyArrived(_, let role, let at):
                // Something bigger than a Skitter lands with a puff in its colour (Skitters come
                // by the dozen, so they just appear).
                if role != .skitter {
                    let color = theme.color(of: .enemy(role))
                    effects.pop(at: at, color: color, radius: tuning.stats(for: role).radius * 1.6, life: 0.3)
                    effects.burst(at: at, color: color, count: 4, speed: 70, life: 0.3, size: 0.8)
                }
            case .arrivalTelegraphed, .spitterWindUp:
                break
            case .burrowSpawned(_, _, let at):
                effects.burst(at: at, color: theme.color(of: .enemy(.burrow)), count: 3, speed: 60, life: 0.3)
            case .enemyFired(_, let at, _):
                effects.burst(at: at, color: theme.color(of: .enemyShot), count: 4, speed: 80, life: 0.25)
            case .enemyHit(let id, let role, let at):
                hitAt[id] = clock
                if role == .thresher {
                    // Sparks off the plate on the side facing the orb, thrown back at it.
                    let toward = atan2(run.orb.pos.y - at.y, run.orb.pos.x - at.x)
                    let plate = at + Vec2(cos(toward), sin(toward)) * 15
                    effects.spray(at: plate, angle: toward, spread: 0.8, color: RGB(hex: 0xFFE0E8), count: 3, speed: 150,
                                  life: 0.22, size: 0.7)
                    effects.flash(at: plate, radius: 10, color: RGB(hex: 0xFF9AAE), life: 0.09, strength: 0.8)
                } else if role == .burrow {
                    effects.spray(at: at, angle: atan2(run.orb.pos.y - at.y, run.orb.pos.x - at.x), spread: 1.2,
                                  color: theme.color(of: .enemy(.burrow)), count: 2, speed: 80, life: 0.3, size: 0.8)
                }
            case .enemyDestroyed(let id, let role, let at, let points, _):
                hitAt[id] = nil
                destroyed(role, at: at, points: points)
            case .huskFormed(_, let at):
                // A moment: the colonist's mint torn away in a burst, magenta drawn in, a flash,
                // a ring closing on the new Husk and a short shake.
                let magenta = theme.color(of: .enemy(.husk))
                effects.burst(at: at, color: mint, count: 10, speed: 120, life: 0.4)
                effects.implode(at: at, radius: 46, color: magenta, count: 16, life: 0.4)
                effects.flash(at: at, radius: 40, color: magenta, life: 0.5, strength: 0.9)
                effects.ring(at: at, color: magenta, from: 60, to: 8, duration: 0.5, width: 1.5)
                effects.pop(at: at, color: magenta, radius: 22, life: 0.5)
                popup("HUSK!", at: at, color: magenta, scale: 1.0)
                addShake(2)
            case .enemyWithdrew(_, let role, let at):
                effects.pop(at: at, color: theme.color(of: .enemy(role)), radius: 20, life: 0.5)

            // Colonists
            case .colonistPickedUp(_, let at, _):
                effects.pop(at: at, color: mint, radius: 10, life: 0.3)
                effects.flash(at: at, radius: 14, color: mint, life: 0.2, strength: 0.6)
            case .colonistSeized(_, _, let at):
                popup("HELP!", at: at, color: palette.warning, scale: 0.85)
            case .colonistFreed(_, let at):
                popup("FREED", at: at, color: mint, scale: 0.85)
            case .colonistTaken(_, _, _, let at):
                effects.burst(at: at, color: palette.warning, count: 10, speed: 110, life: 0.5)
                popup("LOST", at: at, color: palette.warning, scale: 0.9)
                hud.flash(.colonists, at: clock)
            case .colonistCrushed(_, _, let at):
                effects.burst(at: at, color: palette.warning, count: 12, speed: 120, life: 0.5)
                popup("CRUSHED", at: at, color: palette.warning, scale: 0.9)
                hud.flash(.colonists, at: clock)
            case .colonistDelivered(_, let at, _, let points):
                delivered = (count: (delivered?.count ?? 0) + 1, points: (delivered?.points ?? 0) + points, at: at)

            case .gameOver:
                break
            }
        }
        if let delivered {
            // The line runs in through the door one after another from where each colonist was,
            // then the door answers: a ring, a burst and a glow that grow with the line, and one
            // popup for the line's worth together.
            sendThroughAirlock(count: delivered.count, door: delivered.at)
            let n = Double(min(delivered.count, 10))
            effects.ring(at: delivered.at, color: mint, from: 12, to: 60 + 10 * n, duration: 0.5 + 0.03 * n, width: 1.5)
            effects.burst(at: delivered.at, color: mint, count: 8 + 3 * delivered.count, speed: 120 + 10 * n, life: 0.55)
            effects.flash(at: delivered.at, radius: 40 + 8 * n, color: mint, life: 0.5, strength: 0.8)
            popup("+\(groupedDigits(delivered.points))", at: delivered.at, color: palette.reward, scale: 1.2 + 0.04 * n)
            popup(delivered.count == 1 ? "SAVED" : "\(delivered.count) SAVED", at: delivered.at, color: mint, scale: 0.9)
            hud.flash(.colonists, at: clock)
        }
        pruneHits()
    }

    /// A kill, each role its own way and in proportion to its worth (the same split as the
    /// sounds): a Skitter a quick small spark, cheap enough for several hundred a minute; a
    /// Gleaner its claw snapping into shards; a Spitter bursting into a spray of venom; a Husk
    /// torn apart in a spinning star of shards; a Burrow caving in; a Thresher wrecked.
    private func destroyed(_ role: RedoubtRole, at: Vec2, points: Int) {
        let color = theme.color(of: .enemy(role))
        switch role {
        case .skitter:
            effects.burst(at: at, color: color, count: 4, speed: 120, life: 0.28, size: 0.8)
            effects.flash(at: at, radius: 11, color: color, life: 0.1, strength: 0.6)
        case .gleaner:
            effects.shards(at: at, color: color, count: 6, speed: 110, life: 0.5, size: 1.1)
            effects.burst(at: at, color: color, count: 8, speed: 170, life: 0.4)
            effects.flash(at: at, radius: 22, color: color, life: 0.18, strength: 0.7)
        case .spitter:
            effects.burst(at: at, color: color, count: 10, speed: 160, life: 0.45)
            effects.burst(at: at, color: theme.color(of: .enemyShot), count: 8, speed: 70, life: 0.7, size: 0.8)
            effects.pop(at: at, color: color, radius: 18, life: 0.3)
            effects.flash(at: at, radius: 24, color: color, life: 0.2, strength: 0.8)
        case .husk:
            effects.shards(at: at, color: color, count: 9, speed: 170, life: 0.55, size: 1.2)
            effects.burst(at: at, color: color.lightened(0.4), count: 8, speed: 200, life: 0.35)
            effects.pop(at: at, color: color, radius: 20, life: 0.3)
            effects.flash(at: at, radius: 26, color: color, life: 0.2, strength: 0.85)
        case .burrow:
            // The pit caves in: rubble drawn into the hole, dust thrown up, a shrinking rim.
            effects.implode(at: at, radius: 34, color: color, count: 18, life: 0.45, size: 1.1)
            effects.burst(at: at, color: color.lightened(0.2), count: 16, speed: 110, life: 0.8, size: 1.1)
            effects.ring(at: at, color: color, from: 30, to: 4, duration: 0.45, width: 1.4)
            effects.flash(at: at, radius: 50, color: color, life: 0.45, strength: 0.8)
            popup("+\(groupedDigits(points))", at: at, color: theme.palette.reward, scale: 1.1)
            addShake(3)
        case .thresher:
            // The hull breaks up: plates and blade teeth flung out spinning, a hot core, a ring.
            effects.shards(at: at, color: color, count: 16, speed: 200, life: 1.0, size: 1.9)
            effects.shards(at: at, color: RGB(hex: 0xFF9AAE), count: 8, speed: 140, life: 0.9, size: 1.4)
            effects.burst(at: at, color: RGB(hex: 0xFFE0E8), count: 24, speed: 260, life: 0.6, size: 1.2)
            effects.flash(at: at, radius: 80, color: color, life: 0.6, strength: 1)
            effects.ring(at: at, color: color, from: 14, to: 110, duration: 0.55, width: 1.8)
            popup("+\(groupedDigits(points))", at: at, color: theme.palette.reward, scale: 1.3)
            addShake(5)
        }
    }

    private func pruneHits() {
        guard hitAt.count > 24 || (!hitAt.isEmpty && Int(clock * 4) % 8 == 0) else { return }
        let now = clock
        hitAt = hitAt.filter { now - $0.value < 0.2 }
    }

    private func banner(_ title: String, subtitle: String? = nil, color: RGB, subtitleColor: RGB? = nil,
                        life: TimeInterval = 1.1) {
        callouts.banner(title, subtitle: subtitle, color: color, subtitleColor: subtitleColor, life: life)
    }

    private func popup(_ text: String, at pos: Vec2, color: RGB, scale: CGFloat = 1) {
        callouts.popup(text, at: screenPoint(pos), color: color, scale: scale)
    }

    /// What a newcomer does, for its debut wave's banner.
    static func hint(_ role: RedoubtRole) -> String {
        switch role {
        case .skitter: "They come in floods."
        case .gleaner: "It drags colonists away."
        case .spitter: "Weave through its shots."
        case .burrow: "Shoot the hole shut."
        case .thresher: "Shots only push it back."
        case .husk: "A colonist turned. Fast."
        }
    }
}
