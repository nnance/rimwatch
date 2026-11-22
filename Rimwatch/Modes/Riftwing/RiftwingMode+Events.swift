import Foundation
import GameCore
import RiftwingCore
import SpriteKit
import UIKit

// Riftwing's events turned into what the player sees: banners, popups, bursts, flashes, rings,
// the rider's recoil and the pods' squash. An event added to the game later falls to the
// `default` of `handle` (nothing shown) and to nil in `position(of:)` until it is given a look
// here.

extension RiftwingMode {
    /// Every word a popup shows. Each has one look (`popupLook`), so the prewarm warms exactly
    /// what the game shows.
    enum PopupWord: CaseIterable {
        case stoop, freed, caught, taken, lost, hatching, husk, intoTheRift, caughtInGas, mine, hunted
    }

    /// The text, colour and size (against the callouts' text size) of a popup word.
    func popupLook(_ word: PopupWord) -> (text: String, color: RGB, scale: CGFloat) {
        let palette = theme.palette
        let mint = theme.color(of: .pod)
        return switch word {
        case .stoop: ("STOOP!", palette.reward, 0.9)
        case .freed: ("FREED", mint, 0.85)
        case .caught: ("CAUGHT x2", mint, 0.9)
        case .taken: ("TAKEN!", palette.warning, 0.85)
        case .lost: ("LOST", palette.warning, 0.9)
        case .hatching: ("HATCHING", palette.warning, 0.75)
        // Every hatched rig becomes a Striker or a Warden, or its own kind: one colour for all,
        // the Husk's warning, so the word is warmed once.
        case .husk: ("HUSK!", palette.warning, 0.95)
        case .intoTheRift: ("INTO THE RIFT", palette.warning, 0.85)
        case .caughtInGas: ("CAUGHT IN THE GAS", palette.warning, 0.85)
        case .mine: ("MINE", palette.warning, 0.85)
        case .hunted: ("HUNTED", palette.warning, 0.75)
        }
    }

    /// Where an event happened, if it has a place.
    func position(of event: RiftwingEvent) -> Vec2? {
        switch event {
        case .flapped(let at, _), .landed(let at, _), .bumpedLedge(let at), .bumpedRoof(let at), .diveBegan(let at),
             .wingsOpening(let at), .wingsOpened(let at), .ventEntered(_, let at), .clashWon(_, _, let at, _),
             .clashBounced(_, _, let at), .clashLost(_, _, let at), .gleanerBumped(_, let at), .riderLost(let at, _, _),
             .riderRespawned(let at, _), .arrivalTelegraphed(_, _, _, let at), .opponentArrived(_, _, let at),
             .opponentDived(_, _, let at), .opponentHit(_, _, let at, _), .opponentDestroyed(_, _, let at, _, _),
             .opponentFell(_, _, let at, _), .opponentWithdrew(_, _, let at), .mineLaid(_, _, let at),
             .mineCleared(_, let at, _), .podDropped(_, let at, _), .podLanded(_, let at, _), .podFreed(_, let at, _, _),
             .podCaught(_, let at, _, _), .podSeized(_, _, let at), .podCarried(_, _, let at), .podLost(_, let at, _),
             .hatchWarning(_, let at, _), .podHatched(_, _, _, let at):
            return at
        default:
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
        let r = tuning.riderRadius

        for event in events {
            #if DEBUG
            switch event {
            case .hatchWarning, .podSeized, .podCarried, .mineLaid, .cavernShifting, .cavernShifted, .riftWarning,
                 .riftFillWarning, .lampsFailed, .lampsRestored, .podHatched, .waveStarted:
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
                    // A debut: the newcomer's own figure beside the wave, its name and what it does.
                    banner("WAVE \(wave)", subtitle: "New: \(theme.displayName(for: role)). \(Self.hint(role))",
                           color: palette.heading, subtitleColor: theme.color(of: role).lightened(0.3), life: 2.0,
                           icon: bannerIcon(.opponent(role, role == .gleaner ? .raised : .spread)))
                } else if wave == 1 {
                    banner("WAVE 1", subtitle: "Win by height. Free the colonists in the pods.",
                           color: palette.heading, subtitleColor: mint.lightened(0.2), life: 1.8)
                } else {
                    banner("WAVE \(wave)", color: palette.heading, life: 0.9)
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
                // The ledges crumble and rise in `syncLedges`, from the layout change.
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
            case .riftFillWarning:
                // The last step of the breath: the gas fills the gallery to the roof. Worse than
                // any breath: a red wash, a hard shake and the notice that nowhere is high enough.
                callouts.notice("THE RIFT ERUPTS. NOWHERE IS SAFE: FINISH THE FIGHT!", color: palette.warning, life: 4.5)
                callouts.flash(palette.warning, strength: 0.16, duration: 0.8)
                addShake(6)
            case .riftBreathed:
                if run.isBreathFilling {
                    callouts.flash(palette.warning, strength: 0.14, duration: 0.7)
                    addShake(6)
                } else {
                    callouts.flash(palette.gas, strength: 0.06, duration: 0.5)
                    addShake(2)
                }

            // The rider
            case .flapped(let at, let fromLedge):
                if fromLedge {
                    // A kick off the rock: dust both ways.
                    effects.spray(at: at - Vec2(0, r * 0.8), angle: 0, spread: 0.3, color: palette.rock, count: 2, speed: 70,
                                  life: 0.25, size: 0.7)
                    effects.spray(at: at - Vec2(0, r * 0.8), angle: Double.pi, spread: 0.3, color: palette.rock, count: 2,
                                  speed: 70, life: 0.25, size: 0.7)
                } else {
                    // The beat: a breath of air pushed down by the wings.
                    effects.spray(at: at - Vec2(0, r * 0.5), angle: -Double.pi / 2, spread: 0.55, color: cyan.scaled(0.55),
                                  count: 2, speed: 85, life: 0.2, size: 0.6, length: 1.4, drag: 5)
                }
            case .landed(let at, _):
                effects.spray(at: at - Vec2(0, r * 0.8), angle: Double.pi / 2, spread: 1.3, color: palette.rock, count: 3,
                              speed: 50, life: 0.25, size: 0.6)
            case .bumpedLedge(let at), .bumpedRoof(let at):
                effects.burst(at: at + Vec2(0, r * 0.6), color: palette.rock, count: 3, speed: 60, life: 0.25, size: 0.7)
                kickRider(0.12)
            case .diveBegan(let at):
                effects.spray(at: at, angle: Double.pi / 2, spread: 0.5, color: cyan, count: 3, speed: 70, life: 0.25, size: 0.7)
            case .clashWon(_, let role, let at, let stoop):
                // A spark at the blow and the rider recoiling from it; a stoop's strike is in
                // `opponentDestroyed`, sized by the fall.
                effects.flash(at: at, radius: (stoop ? 34 : 24) * fig, color: stoop ? palette.reward : cyan, life: 0.2,
                              strength: 0.9)
                effects.spray(at: at, angle: Double.pi / 2, spread: 1.1, color: cyan.lightened(0.4), count: 6, speed: 170,
                              life: 0.3, size: 0.8, length: 1.6)
                kickRider(stoop ? 0.3 : 0.2)
                if stoop { popup(.stoop, at: at + Vec2(0, 20 * fig)) }
                if role == .gleaner { effects.burst(at: at, color: theme.color(of: role), count: 10, speed: 160, life: 0.4) }
            case .clashBounced(_, let role, let at):
                // Level: both thrown apart sideways, with a clang of white.
                let color = theme.color(of: role).lightened(0.4)
                effects.spray(at: at, angle: 0, spread: 0.45, color: color, count: 4, speed: 150, life: 0.25, size: 0.8)
                effects.spray(at: at, angle: Double.pi, spread: 0.45, color: cyan, count: 4, speed: 150, life: 0.25, size: 0.8)
                effects.flash(at: at, radius: 16 * fig, color: RGB(1, 1, 1), life: 0.12, strength: 0.7)
                effects.ring(at: at, color: RGB(1, 1, 1), from: 6 * fig, to: 24 * fig, duration: 0.22, width: 0.7)
                kickRider(0.25)
            case .clashLost(_, let role, let at):
                // A hard hit from above.
                effects.flash(at: at, radius: 40 * fig, color: theme.color(of: role), life: 0.25, strength: 0.95)
                effects.spray(at: at, angle: -Double.pi / 2, spread: 0.8, color: cyan, count: 10, speed: 220, life: 0.4,
                              size: 1.1, length: 1.8)
                callouts.flash(palette.warning, strength: 0.12, duration: 0.3)
                addShake(5)
            case .gleanerBumped(_, let at):
                effects.burst(at: at, color: theme.color(of: .gleaner), count: 5, speed: 90, life: 0.25, size: 0.8)
                kickRider(0.18)
            case .riderLost(let at, let livesLeft, let cause):
                effects.burst(at: at, color: cyan, count: 30, speed: 220, life: 0.8, size: 1.2)
                effects.feathers(at: at, color: cyan, count: 8)
                effects.shards(at: at, color: cyan, count: 6, speed: 140, life: 0.9, size: 1.5)
                effects.flash(at: at, radius: 60, color: palette.warning, life: 0.45, strength: 0.7)
                callouts.flash(palette.warning, strength: 0.1, duration: 0.35)
                hud.flash(.lives, at: clock)
                addShake(6)
                switch cause {
                case .rift: popup(.intoTheRift, at: at)
                case .breath: popup(.caughtInGas, at: at)
                case .mine: popup(.mine, at: at)
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
            case .opponentArrived(_, let role, let at):
                effects.burst(at: at, color: theme.color(of: role), count: 5, speed: 80, life: 0.3, size: 0.8)
            case .opponentHit(let id, let role, let at, _):
                hitAt[id] = clock
                // Its armour breaks off.
                effects.shards(at: at, color: theme.color(of: role).lightened(0.3), count: 6, speed: 120, life: 0.5)
                effects.flash(at: at, radius: 20 * fig, color: RGB(1, 1, 1), life: 0.12, strength: 0.6)
                callouts.popup("+\(tuning.hitPoints)", at: screenPoint(at), color: palette.reward, scale: 0.8)
            case .opponentDestroyed(let id, let role, let at, let points, let stoopBonus):
                hitAt[id] = nil
                let color = theme.color(of: role)
                if role.isRig {
                    // Knocked off its rig: the frame sheds feathers of light and broken pieces.
                    effects.feathers(at: at, color: color, count: 7)
                    effects.shards(at: at, color: color.lightened(0.2), count: 5, speed: 150, life: 0.6, size: 1.2)
                } else {
                    effects.shards(at: at, color: color, count: 7, speed: 160, life: 0.6, size: 1.2)
                }
                effects.burst(at: at, color: color.lightened(0.3), count: 10, speed: 190, life: 0.4)
                effects.flash(at: at, radius: 26 * fig, color: color, life: 0.2, strength: 0.85)
                effects.pop(at: at, color: color, radius: 20 * fig, life: 0.3)
                if stoopBonus > 0 {
                    // A stoop: a strike that grows with the fall (bonus 50 ... 1,000).
                    let size = min(Double(stoopBonus) / 1000, 1)
                    effects.ring(at: at, color: palette.reward, from: 8 * fig, to: (34 + 60 * size) * fig,
                                 duration: 0.3 + 0.2 * size, width: CGFloat(0.8 + 0.8 * size))
                    effects.flash(at: at, radius: (36 + 40 * size) * fig, color: palette.reward, life: 0.3, strength: 0.9)
                    effects.spray(at: at, angle: -Double.pi / 2, spread: 0.35, color: palette.reward, count: 6 + Int(10 * size),
                                  speed: 260 + 200 * size, life: 0.35, size: 0.9, length: 2.6)
                    addShake(CGFloat(3 + 4 * size))
                } else {
                    addShake(role == .warden || role == .sower ? 3 : 2)
                }
                callouts.popup("+\(groupedDigits(points))", at: screenPoint(at), color: palette.reward,
                               scale: stoopBonus > 0 ? 1.15 : 1)
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
                // It drops with a pop, then trails mint as it falls (`syncPods`).
                effects.pop(at: at, color: mint, radius: 14 * fig, life: 0.3)
                effects.burst(at: at, color: mint, count: 5, speed: 70, life: 0.3, size: 0.7)
            case .podLanded(let id, let at, _):
                podLandedAt[id] = clock
                effects.spray(at: at - Vec2(0, tuning.podRadius), angle: 0, spread: 0.35, color: palette.rock, count: 2,
                              speed: 60, life: 0.3, size: 0.7)
                effects.spray(at: at - Vec2(0, tuning.podRadius), angle: Double.pi, spread: 0.35, color: palette.rock, count: 2,
                              speed: 60, life: 0.3, size: 0.7)
                effects.burst(at: at, color: mint, count: 3, speed: 40, life: 0.25, size: 0.6)
            case .podFreed(_, let at, _, let points):
                // The pod opens, the colonist climbs out and away, and the score rises.
                effects.colonist(at: at)
                effects.burst(at: at, color: mint, count: 14, speed: 140, life: 0.5)
                effects.flash(at: at, radius: 30 * fig, color: mint, life: 0.3, strength: 0.8)
                effects.ring(at: at, color: mint, from: 8 * fig, to: 34 * fig, duration: 0.35, width: 0.8)
                callouts.popup("+\(groupedDigits(points))", at: screenPoint(at), color: palette.reward, scale: 1.15)
                popup(.freed, at: at + Vec2(0, -24 * fig))
                hud.flash(.saved, at: clock)
            case .podCaught(_, let at, _, let points):
                effects.colonist(at: at)
                effects.burst(at: at, color: mint, count: 20, speed: 180, life: 0.55)
                effects.flash(at: at, radius: 40 * fig, color: palette.reward, life: 0.35, strength: 0.9)
                effects.ring(at: at, color: palette.reward, from: 10 * fig, to: 50 * fig, duration: 0.45, width: 1.2)
                callouts.popup("+\(groupedDigits(points))", at: screenPoint(at), color: palette.reward, scale: 1.3)
                popup(.caught, at: at + Vec2(0, -24 * fig))
                hud.flash(.saved, at: clock)
            case .podSeized(_, _, let at):
                popup(.taken, at: at)
                effects.ring(at: at, color: palette.warning, from: 26 * fig, to: 10 * fig, duration: 0.3, width: 0.8)
            case .podLost(_, let at, let cause):
                effects.burst(at: at, color: palette.warning, count: 10, speed: 110, life: 0.5)
                switch cause {
                case .rift, .breath, .carried: popup(.lost, at: at)
                case .hatched: break
                }
            case .hatchWarning(_, let at, _):
                popup(.hatching, at: at)
            case .podHatched(_, _, let role, let at):
                let color = theme.color(of: role)
                // The shell bursts open and the Husk gathers out of it.
                effects.shards(at: at, color: mint, count: 8, speed: 130, life: 0.5, size: 1.1)
                effects.implode(at: at, radius: 40 * fig, color: color, count: 14, life: 0.4)
                effects.flash(at: at, radius: 36 * fig, color: color, life: 0.45, strength: 0.9)
                popup(.husk, at: at)
                addShake(2)

            default:
                // Quiet on screen: wings opening, vents, arrival glows (drawn by `syncArrivals`),
                // an opponent's dive, a pod carried, the gas settling, game over; and any event
                // added to the game after this was written.
                break
            }
        }
        pruneHits()
    }

    /// The rider recoils (squashes and springs back) with `strength` 0 ... 0.35.
    private func kickRider(_ strength: CGFloat) {
        riderKickAt = clock
        riderKick = strength
    }

    /// A small figure for a debut banner, at the size of the banner's text.
    private func bannerIcon(_ thing: RiftwingShape) -> SKNode {
        let sprite = SKSpriteNode()
        RiftwingSprites.dress(sprite, with: glyphs.glyph(thing, pointsPerUnit: pointsPerUnit), factory: factory)
        // Gallery units to points, then up to about the banner's heading height.
        let height = max(sprite.size.height, 1)
        sprite.setScale(callouts.textSize * 1.8 / height)
        return sprite
    }

    /// Rock falling from the roof as the cavern shifts.
    private func rockfall(count: Int) {
        var rng = SeededRNG(seed: UInt64(clock * 1000) & 0xFFFF_FFFF)
        for _ in 0..<count {
            let at = Vec2(rng.range(20...(tuning.width - 20)), tuning.height - 4)
            effects.spray(at: at, angle: -Double.pi / 2, spread: 0.25, color: theme.palette.rock, count: 2, speed: 160,
                          life: 1.1, size: 1, drag: 0.4, gravity: 200)
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
                        life: TimeInterval = 1.1, icon: SKNode? = nil) {
        callouts.banner(title, subtitle: subtitle, color: color, subtitleColor: subtitleColor, life: life, icon: icon)
    }

    /// A popup word over a gallery point, kept clear of the rider (`RiftwingCallouts`).
    func popup(_ word: PopupWord, at pos: Vec2) {
        let look = popupLook(word)
        callouts.popup(look.text, at: screenPoint(pos), color: look.color, scale: look.scale)
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
