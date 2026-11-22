import Foundation
import GameCore
import RiftwingCore
import SpriteKit
import UIKit

// Riftwing's events turned into what the player sees: banners, popups, bursts and flashes.
// (Stage 15e polishes these; this is the readable minimum.)

extension RiftwingMode {
    /// Where an event happened, if it has a place.
    func position(of event: RiftwingEvent) -> Vec2? {
        switch event {
        case .flapped(let at, _), .landed(let at, _), .bumpedLedge(let at), .diveBegan(let at), .wingsOpening(let at),
             .wingsOpened(let at), .ventEntered(_, let at), .clashWon(_, _, let at, _), .clashBounced(_, _, let at),
             .clashLost(_, _, let at), .gleanerBumped(_, let at), .riderLost(let at, _, _), .riderRespawned(let at, _),
             .arrivalTelegraphed(_, _, _, let at), .opponentArrived(_, _, let at), .opponentDived(_, _, let at),
             .opponentHit(_, _, let at, _), .opponentDestroyed(_, _, let at, _, _), .opponentFell(_, _, let at, _),
             .opponentWithdrew(_, _, let at), .mineLaid(_, _, let at), .mineCleared(_, let at, _),
             .podDropped(_, let at, _), .podLanded(_, let at, _), .podFreed(_, let at, _, _), .podCaught(_, let at, _, _),
             .podSeized(_, _, let at), .podCarried(_, _, let at), .podLost(_, let at, _), .hatchWarning(_, let at, _),
             .podHatched(_, _, _, let at):
            return at
        case .waveStarted, .waveCleared, .cavernShifting, .cavernShifted, .allColonistsLost, .lampsFailed,
             .lampsRestored, .riftWarning, .riftBreathed, .riftSettled, .extraLife, .gameOver:
            return nil
        }
    }

    func handle(_ events: [RiftwingEvent], run: RiftwingRun) {
        guard !events.isEmpty else {
            pruneHits()
            return
        }
        let palette = theme.palette
        let mint = theme.color(of: .pod)
        let cyan = theme.color(of: .rider(.spread))
        let fig = tuning.figureScale

        for event in events {
            #if DEBUG
            switch event {
            case .hatchWarning, .podSeized, .podCarried, .mineLaid, .cavernShifting, .cavernShifted, .riftWarning,
                 .lampsFailed, .lampsRestored, .podHatched, .waveStarted:
                debugLog("[Rimwatch riftwing] \(String(format: "%.1f", clock)) \(event)")
            default:
                break
            }
            #endif
            switch event {
            // Waves and the cavern
            case .waveStarted(let wave, _):
                if events.contains(.lampsFailed) {
                    // The lamps fail as this wave starts: their banner says so, and a newcomer
                    // is named in the notice instead.
                    if let role = debut(inWave: wave) {
                        callouts.notice("New: \(theme.displayName(for: role)). \(Self.hint(role))",
                                        color: theme.color(of: role).lightened(0.3), life: 2.4)
                    }
                } else if let role = debut(inWave: wave) {
                    banner("WAVE \(wave)", subtitle: "New: \(theme.displayName(for: role)). \(Self.hint(role))",
                           color: palette.heading, subtitleColor: theme.color(of: role).lightened(0.3), life: 1.8)
                } else if wave == 1 {
                    banner("WAVE 1", subtitle: "Win by height. Free the colonists in the pods.",
                           color: palette.heading, subtitleColor: mint.lightened(0.2), life: 1.8)
                } else {
                    banner("WAVE \(wave)", color: palette.heading)
                }
            case .waveCleared(let wave, let freed, let bonus):
                banner("WAVE \(wave) CLEAR",
                       subtitle: freed > 0 ? "\(freed) freed. Bonus +\(groupedDigits(bonus))" : "No colonists freed",
                       color: palette.hud, subtitleColor: freed > 0 ? palette.reward : palette.warning, life: 0.9)
            case .cavernShifting:
                isShifting = true
                callouts.notice("THE CAVERN SHIFTS", color: palette.rock.lightened(0.4), life: 2.2)
                addShake(4)
                rockfall(count: 14)
            case .cavernShifted:
                isShifting = false
                addShake(6)
                rockfall(count: 10)
                callouts.flash(palette.rock, strength: 0.12, duration: 0.4)
            case .allColonistsLost:
                callouts.notice("EVERY COLONIST LOST", color: palette.warning)
            case .lampsFailed:
                banner("LAMPS OUT", subtitle: "Free a colonist to bring them back", color: palette.warning, life: 1.8)
            case .lampsRestored:
                banner("LAMPS RESTORED", color: mint)
                callouts.flash(palette.reward, strength: 0.15, duration: 0.5)
            case .riftWarning:
                callouts.notice("THE RIFT IS BREATHING. CLIMB!", color: palette.gas, life: 2.4)
            case .riftBreathed:
                callouts.flash(palette.gas, strength: 0.06, duration: 0.5)
                addShake(2)
            case .riftSettled:
                break

            // The rider
            case .flapped, .landed, .wingsOpening, .wingsOpened, .ventEntered:
                break
            case .bumpedLedge(let at):
                effects.burst(at: at + Vec2(0, tuning.riderRadius * 0.6), color: palette.rock, count: 3, speed: 60, life: 0.25,
                              size: 0.7)
            case .diveBegan(let at):
                effects.spray(at: at, angle: Double.pi / 2, spread: 0.5, color: cyan, count: 3, speed: 70, life: 0.25, size: 0.7)
            case .clashWon(_, let role, let at, let stoop):
                effects.flash(at: at, radius: (stoop ? 34 : 24) * fig, color: stoop ? palette.reward : cyan, life: 0.2,
                              strength: 0.9)
                if stoop { popup("STOOP!", at: at + Vec2(0, 20), color: palette.reward, scale: 0.9) }
                if role == .gleaner { effects.burst(at: at, color: theme.color(of: role), count: 10, speed: 160, life: 0.4) }
            case .clashBounced(_, let role, let at):
                effects.spray(at: at, angle: Double.pi / 2, spread: 1.3, color: theme.color(of: role).lightened(0.4), count: 6,
                              speed: 120, life: 0.25, size: 0.8)
                effects.flash(at: at, radius: 14 * fig, color: RGB(1, 1, 1), life: 0.1, strength: 0.6)
            case .clashLost(_, let role, let at):
                effects.flash(at: at, radius: 26 * fig, color: theme.color(of: role), life: 0.2, strength: 0.8)
            case .gleanerBumped(_, let at):
                effects.burst(at: at, color: theme.color(of: .gleaner), count: 5, speed: 90, life: 0.25, size: 0.8)
            case .riderLost(let at, let livesLeft, let cause):
                effects.burst(at: at, color: cyan, count: 30, speed: 220, life: 0.8, size: 1.2)
                effects.shards(at: at, color: cyan, count: 8, speed: 140, life: 0.9, size: 1.5)
                effects.flash(at: at, radius: 60, color: palette.warning, life: 0.45, strength: 0.7)
                callouts.flash(palette.warning, strength: 0.1, duration: 0.35)
                hud.flash(.lives, at: clock)
                addShake(6)
                switch cause {
                case .rift: popup("INTO THE RIFT", at: at, color: palette.warning, scale: 0.85)
                case .breath: popup("CAUGHT IN THE GAS", at: at, color: palette.warning, scale: 0.85)
                case .mine: popup("MINE", at: at, color: palette.warning, scale: 0.85)
                case .clash: break
                }
                if livesLeft > 0 {
                    callouts.notice(livesLeft == 1 ? "LAST LIFE" : "\(livesLeft) LIVES LEFT", color: palette.warning)
                }
            case .riderRespawned(let at, _):
                effects.flash(at: at, radius: 40 * fig, color: cyan, life: 0.4, strength: 0.7)
                effects.implode(at: at, radius: 50 * fig, color: cyan, count: 14, life: 0.35)
            case .extraLife:
                callouts.notice("EXTRA LIFE", color: palette.reward)
                hud.flash(.lives, at: clock)

            // Opponents
            case .arrivalTelegraphed:
                break
            case .opponentArrived(_, let role, let at):
                effects.burst(at: at, color: theme.color(of: role), count: 5, speed: 80, life: 0.3, size: 0.8)
            case .opponentDived:
                break
            case .opponentHit(let id, let role, let at, _):
                hitAt[id] = clock
                // Its armour breaks off.
                effects.shards(at: at, color: theme.color(of: role).lightened(0.3), count: 6, speed: 120, life: 0.5)
                popup("+\(tuning.hitPoints)", at: at, color: palette.reward, scale: 0.8)
            case .opponentDestroyed(let id, let role, let at, let points, let stoopBonus):
                hitAt[id] = nil
                let color = theme.color(of: role)
                effects.shards(at: at, color: color, count: role.isRig ? 9 : 6, speed: 160, life: 0.6, size: 1.2)
                effects.burst(at: at, color: color.lightened(0.3), count: 10, speed: 190, life: 0.4)
                effects.flash(at: at, radius: 26 * fig, color: color, life: 0.2, strength: 0.85)
                effects.pop(at: at, color: color, radius: 20 * fig, life: 0.3)
                popup("+\(groupedDigits(points))", at: at, color: palette.reward, scale: stoopBonus > 0 ? 1.15 : 1)
                addShake(role == .warden || role == .sower ? 3 : 2)
            case .opponentFell(_, let role, let at, _):
                effects.burst(at: at, color: theme.color(of: role), count: 8, speed: 100, life: 0.5)
            case .opponentWithdrew(_, let role, let at):
                effects.pop(at: at, color: theme.color(of: role), radius: 18 * fig, life: 0.4)
            case .mineLaid(_, _, let at):
                effects.pop(at: at, color: theme.color(of: .mine), radius: 10 * fig, life: 0.3)
            case .mineCleared(_, let at, let reason):
                let pink = theme.color(of: .mine)
                switch reason {
                case .struck, .sowerDown:
                    effects.burst(at: at, color: pink, count: 10, speed: 150, life: 0.45)
                    effects.flash(at: at, radius: 20 * fig, color: pink, life: 0.2, strength: 0.8)
                case .expired, .waveEnded:
                    effects.pop(at: at, color: pink, radius: 12 * fig, life: 0.3)
                }

            // Pods
            case .podDropped(_, let at, _):
                effects.pop(at: at, color: mint, radius: 14 * fig, life: 0.3)
            case .podLanded(_, let at, _):
                effects.burst(at: at, color: mint, count: 4, speed: 50, life: 0.25, size: 0.7)
            case .podFreed(_, let at, _, let points):
                effects.burst(at: at, color: mint, count: 14, speed: 140, life: 0.5)
                effects.flash(at: at, radius: 30 * fig, color: mint, life: 0.3, strength: 0.8)
                popup("+\(groupedDigits(points))", at: at, color: palette.reward, scale: 1.15)
                popup("FREED", at: at + Vec2(0, -24), color: mint, scale: 0.85)
                hud.flash(.saved, at: clock)
            case .podCaught(_, let at, _, let points):
                effects.burst(at: at, color: mint, count: 20, speed: 180, life: 0.55)
                effects.flash(at: at, radius: 40 * fig, color: palette.reward, life: 0.35, strength: 0.9)
                popup("+\(groupedDigits(points))", at: at, color: palette.reward, scale: 1.3)
                popup("CAUGHT x2", at: at + Vec2(0, -24), color: mint, scale: 0.9)
                hud.flash(.saved, at: clock)
            case .podSeized(_, _, let at):
                popup("TAKEN!", at: at, color: palette.warning, scale: 0.85)
            case .podCarried:
                break
            case .podLost(_, let at, let cause):
                effects.burst(at: at, color: palette.warning, count: 10, speed: 110, life: 0.5)
                switch cause {
                case .rift, .breath, .carried: popup("LOST", at: at, color: palette.warning, scale: 0.9)
                case .hatched: break
                }
            case .hatchWarning(_, let at, _):
                popup("HATCHING", at: at, color: palette.warning, scale: 0.75)
            case .podHatched(_, _, let role, let at):
                let color = theme.color(of: role)
                effects.burst(at: at, color: mint, count: 10, speed: 120, life: 0.4)
                effects.implode(at: at, radius: 40 * fig, color: color, count: 14, life: 0.4)
                effects.flash(at: at, radius: 36 * fig, color: color, life: 0.45, strength: 0.9)
                popup("HUSK!", at: at, color: color, scale: 0.95)
                addShake(2)

            case .gameOver:
                break
            }
        }
        pruneHits()
    }

    /// Rock falling from the roof as the cavern shifts.
    private func rockfall(count: Int) {
        var rng = SeededRNG(seed: UInt64(clock * 1000) & 0xFFFF_FFFF)
        for _ in 0..<count {
            let at = Vec2(rng.range(20...(tuning.width - 20)), tuning.height - 4)
            effects.spray(at: at, angle: -Double.pi / 2, spread: 0.25, color: theme.palette.rock, count: 2, speed: 160,
                          life: 1.1, size: 1, drag: 0.4)
        }
    }

    /// The role a wave brings in for the first time, if any.
    private func debut(inWave wave: Int) -> RiftwingRole? {
        RiftwingRole.allCases.first { session.run.director.debut(of: $0) == wave && wave > 1 }
    }

    private func pruneHits() {
        guard hitAt.count > 12 else { return }
        let now = clock
        hitAt = hitAt.filter { now - $0.value < 0.3 }
    }

    private func banner(_ title: String, subtitle: String? = nil, color: RGB, subtitleColor: RGB? = nil,
                        life: TimeInterval = 1.1) {
        callouts.banner(title, subtitle: subtitle, color: color, subtitleColor: subtitleColor, life: life)
    }

    private func popup(_ text: String, at pos: Vec2, color: RGB, scale: CGFloat = 1) {
        callouts.popup(text, at: screenPoint(pos), color: color, scale: scale)
    }

    /// What a newcomer does, for its debut wave's banner.
    static func hint(_ role: RiftwingRole) -> String {
        switch role {
        case .glider: "Get above it and come down."
        case .striker: "It climbs to strike from above."
        case .warden: "Two blows, or one stoop."
        case .gleaner: "It steals resting pods."
        case .sower: "Strike it to clear its mines."
        }
    }
}
