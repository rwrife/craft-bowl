import CBCore
import CBPlays
import CBSim
import Foundation
import XCTest

@testable import CBGame

/// Issue #27 acceptance: headless catch-rate targets — an open receiver completes
/// at least 90% of catches, a contested one roughly 50% (tunable).
///
/// Catch resolution is driven directly at the ball-arrival instant so the fixtures
/// measure the live `Match.resolveCatch` rules without AI movement noise: the
/// receiver and defender are placed at controlled distances around the arrival spot.
final class CatchRateAcceptanceTests: XCTestCase {
    /// Spot where the ball arrives; well inside the field.
    private let spot = Vec2(3, 55)

    /// Snaps a left-lane pass, then resolves the catch with the receiver 0.3–0.65 yd
    /// from the ball and (optionally) the nearest defender at a fixed distance.
    /// Returns whether the pass was completed.
    private func catchTrial(
        _ loaded: (format: TeamFormat, playbook: Playbook), seed: UInt64,
        contestedAt contested: Float?, curves: RatingCurves = .default
    ) throws -> Bool {
        var match = Match(seed: seed, playbook: loaded.playbook, format: loaded.format, curves: curves)
        let choice = try XCTUnwrap(
            match.playChoices.firstIndex {
                loaded.playbook.offense[$0].qbActions.contains(.passLeft)
            })
        match.step(input: TickInput(playSelect: Int8(choice)), ai: [:])
        match.step(input: TickInput(buttons: .snap), ai: [:])
        match.step(input: TickInput(buttons: .passLeft), ai: [:])
        let receiver = try XCTUnwrap(match.world.player(at: .laneLeft)?.id)
        // Deterministic arrival offsets and fresh hands (fatigue is tested separately
        // by ReceiverHandsTests; this measures the base open/contested rules).
        let offset = 0.3 + Float(seed % 4) * 0.115
        let defenderID = try contested.map { _ in
            try XCTUnwrap(match.world.players.first { $0.side == .defense && $0.position == .cbL }?.id)
        }
        match.mutateWorld { world in
            world.players[world.players.firstIndex { $0.id == receiver }!].location =
                spot + Vec2(offset, 0)
            world.players[world.players.firstIndex { $0.id == receiver }!].stamina
                .setHealth(1)
            if let contested, let defenderID {
                world.players[world.players.firstIndex { $0.id == defenderID }!]
                    .location = spot + Vec2(0, contested)
            }
        }
        match.resolveCatch(at: spot, target: receiver)
        return match.world.ballCarrier == receiver
    }

    private func catchRate(
        _ loaded: (format: TeamFormat, playbook: Playbook), trials: Int, contestedAt contested: Float?,
        curves: RatingCurves = .default
    ) throws -> Double {
        var catches = 0
        for seed in 1...UInt64(trials) {
            if try catchTrial(loaded, seed: seed, contestedAt: contested, curves: curves) { catches += 1 }
        }
        return Double(catches) / Double(trials)
    }

    /// "Open receiver catch rate ≥ 90%" — no defender within the contest radius.
    func testOpenReceiverCatchRateMeetsNinetyPercent() throws {
        let loaded = try Playbook.loadBundled()
        let rate = try catchRate(loaded, trials: 600, contestedAt: nil)
        XCTAssertGreaterThanOrEqual(rate, 0.90, "open catch rate measured \(rate)")
    }

    /// "Contested ≈ 50% (tunable)" — a defender 1.5 yd from the arrival spot.
    func testContestedCatchRateLandsNearHalf() throws {
        let loaded = try Playbook.loadBundled()
        let rate = try catchRate(loaded, trials: 600, contestedAt: 1.5)
        XCTAssertGreaterThanOrEqual(rate, 0.38, "contested catch rate measured \(rate)")
        XCTAssertLessThanOrEqual(rate, 0.62, "contested catch rate measured \(rate)")
    }

    /// The contest must actually cost completion rate on the same seeds.
    func testContestingLowersCatchRate() throws {
        let loaded = try Playbook.loadBundled()
        let open = try catchRate(loaded, trials: 200, contestedAt: nil)
        let contested = try catchRate(loaded, trials: 200, contestedAt: 1.5)
        XCTAssertLessThan(contested, open - 0.15, "open \(open) vs contested \(contested)")
    }

    /// The tuning must stay wired into the live resolver: a low base chance
    /// drops open completion even when hands are perfect.
    func testLowCatchBaseTuningLowersLiveCatchRate() throws {
        let loaded = try Playbook.loadBundled()
        var curves = RatingCurves.default
        curves.catchBaseChance = 0.05
        curves.receiverHandsMin = 1
        curves.receiverHandsMax = 1
        let rate = try catchRate(loaded, trials: 200, contestedAt: nil, curves: curves)
        XCTAssertLessThan(rate, 0.7, "low-base open catch rate \(rate)")
    }

    /// Zeroing the contest penalty must make a covered throw land like an open one.
    func testZeroContestPenaltyRestoresOpenCatchRate() throws {
        let loaded = try Playbook.loadBundled()
        var curves = RatingCurves.default
        curves.contestedCatchPenalty = 0
        let rate = try catchRate(loaded, trials: 600, contestedAt: 1.5, curves: curves)
        XCTAssertGreaterThanOrEqual(rate, 0.90, "penalty-zero contested rate \(rate)")
    }
}
