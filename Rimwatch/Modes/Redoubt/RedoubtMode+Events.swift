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
                if let debut = RedoubtWaves.debut.first(where: { $0.wave == wave }) {
                    banner("WAVE \(wave)", subtitle: "New: \(theme.displayName(for: debut.role)). \(Self.hint(debut.role))",
                           color: palette.heading, subtitleColor: theme.color(of: .enemy(debut.role)).lightened(0.3))
                } else {
                    banner("WAVE \(wave)", subtitle: "\(colonists) colonists. Lead them to the airlock.",
                           color: palette.heading, subtitleColor: mint.lightened(0.2))
                }
            case .waveCleared(let wave, let safe, let bonus):
                banner("WAVE \(wave) CLEAR",
                       subtitle: safe > 0 ? "Survivor bonus +\(groupedDigits(bonus))" : "No colonists left to save",
                       color: palette.hud, subtitleColor: safe > 0 ? palette.reward : palette.warning, life: 0.7)
                if bonus > 0 { popup("+\(groupedDigits(bonus))", at: run.orb.pos, color: palette.reward, scale: 1.3) }
            case .airlockOpened(_, let at):
                effects.ring(at: at, color: mint, from: 10, to: 60, duration: 0.5)
            case .airlockClosed:
                break
            case .allColonistsLost:
                callouts.notice("EVERY COLONIST LOST", color: palette.warning)
            case .powerCutBegan:
                banner("POWER CUT", subtitle: "Deliver a colonist to bring the lights back", color: palette.warning)
            case .powerCutEnded:
                banner("POWER RESTORED", color: mint)
                callouts.flash(mint, strength: 0.18)

            // The orb
            case .orbFired:
                muzzleGlow = 1
            case .shotEnded(_, let at, let reason):
                if reason == .wall { effects.burst(at: at, color: RGB(hex: 0xC8FFFF), count: 2, speed: 90, life: 0.2, size: 0.6) }
            case .shockwave(let at, _):
                effects.ring(at: at, color: palette.shockwave, from: 20, to: tuning.shockwaveClearRadius,
                             duration: 0.3, width: 2)
                effects.ring(at: at, color: palette.shockwave, from: 60, to: tuning.shockwavePushRadius,
                             duration: 0.55, width: 1)
                effects.burst(at: at, color: palette.shockwave, count: 30, speed: 420, life: 0.5)
                callouts.flash(palette.shockwave, strength: 0.22, duration: 0.4)
                addShake(5)
            case .chargeEarned:
                callouts.notice("SHOCKWAVE CHARGED", color: palette.shockwave)
                hud.flash(.charges, at: clock)
            case .orbDestroyed(let at, let livesLeft, _):
                let cyan = theme.color(of: .orb)
                effects.burst(at: at, color: cyan, count: 40, speed: 260, life: 0.8, size: 1.3)
                effects.burst(at: at, color: palette.warning, count: 16, speed: 160, life: 0.6)
                effects.ring(at: at, color: palette.warning, from: 8, to: 90, duration: 0.5, width: 1.5)
                callouts.flash(palette.warning, strength: 0.3, duration: 0.5)
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
            case .arrivalTelegraphed, .enemyArrived, .spitterWindUp:
                break
            case .burrowSpawned(_, _, let at):
                effects.burst(at: at, color: theme.color(of: .enemy(.burrow)), count: 3, speed: 60, life: 0.3)
            case .enemyFired(_, let at, _):
                effects.burst(at: at, color: theme.color(of: .enemyShot), count: 4, speed: 80, life: 0.25)
            case .enemyHit(let id, let role, let at):
                hitAt[id] = clock
                if role == .thresher {
                    effects.burst(at: at, color: RGB(hex: 0xFFE0E8), count: 2, speed: 120, life: 0.2, size: 0.7)
                }
            case .enemyDestroyed(let id, let role, let at, let points, _):
                hitAt[id] = nil
                destroyed(role, at: at, points: points)
            case .huskFormed(_, let at):
                let magenta = theme.color(of: .enemy(.husk))
                effects.ring(at: at, color: magenta, from: 50, to: 8, duration: 0.45)
                effects.burst(at: at, color: magenta, count: 12, speed: 140, life: 0.5)
                popup("HUSK", at: at, color: magenta, scale: 0.9)
            case .enemyWithdrew(_, let role, let at):
                effects.pop(at: at, color: theme.color(of: .enemy(role)), radius: 20, life: 0.5)

            // Colonists
            case .colonistPickedUp(_, let at, _):
                effects.pop(at: at, color: mint, radius: 10, life: 0.3)
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
            // One popup per delivery, the line's worth together.
            effects.ring(at: delivered.at, color: mint, from: 12, to: 70, duration: 0.5, width: 1.5)
            effects.burst(at: delivered.at, color: mint, count: 8 + 3 * delivered.count, speed: 120, life: 0.5)
            popup("+\(groupedDigits(delivered.points))", at: delivered.at, color: palette.reward, scale: 1.3)
            popup(delivered.count == 1 ? "SAVED" : "\(delivered.count) SAVED", at: delivered.at, color: mint, scale: 0.9)
            hud.flash(.colonists, at: clock)
        }
        pruneHits()
    }

    /// A kill: sparks in the role's colour, sized by how much it mattered, cheap enough for the
    /// several hundred a minute a good player makes.
    private func destroyed(_ role: RedoubtRole, at: Vec2, points: Int) {
        let color = theme.color(of: .enemy(role))
        switch role {
        case .skitter:
            effects.burst(at: at, color: color, count: 5, speed: 130, life: 0.35)
        case .gleaner, .spitter, .husk:
            effects.burst(at: at, color: color, count: 10, speed: 160, life: 0.45)
            effects.pop(at: at, color: color, radius: 16)
        case .burrow, .thresher:
            effects.burst(at: at, color: color, count: 26, speed: 220, life: 0.7, size: 1.3)
            effects.pop(at: at, color: color, radius: 40, life: 0.45)
            popup("+\(groupedDigits(points))", at: at, color: theme.palette.reward, scale: 1.1)
            addShake(3)
        }
    }

    private func pruneHits() {
        guard hitAt.count > 24 || (!hitAt.isEmpty && Int(clock * 4) % 8 == 0) else { return }
        let now = clock
        hitAt = hitAt.filter { now - $0.value < 0.2 }
    }

    private func banner(_ title: String, subtitle: String? = nil, color: RGB, subtitleColor: RGB? = nil,
                        life: TimeInterval = 1.8) {
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
