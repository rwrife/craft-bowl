import CBCore
import CBGame
import CBPlays
import CBSim
import Foundation
import XCTest

/// Bounded #24 slice: tunable Power-derived tackle strength in the live
/// carrier-contact path (`Match.checkCarrier`), matching the block-strength pattern.
final class TacklePowerTests: XCTestCase {
    func testTunedTackleStrengthChangesLiveCarrierOutcome() throws {
        let loaded = try Playbook.loadBundled()
        var defaults = RatingCurves.default
        defaults.tackleStrengthMin = 1
        defaults.tackleStrengthMax = 99
        var flat = RatingCurves.default
        flat.tackleStrengthMin = 50
        flat.tackleStrengthMax = 50
        let baseline = try ticksToWhistle(playbook: loaded.playbook, format: loaded.format, curves: defaults)
        let flattened = try ticksToWhistle(playbook: loaded.playbook, format: loaded.format, curves: flat)
        // A flat curve erases the Power edge, so broken tackles buy the QB extra time.
        // Ignoring the curve in the live path makes both totals identical (canary: 8054 vs 8054).
        XCTAssertGreaterThan(flattened, baseline)
    }

    func testTackleCurveIsBoundedAndLegacyTuningFallsBack() throws {
        var curves = RatingCurves.loadBundled()
        let weak = Ratings(power: 1, speed: 50, endurance: 50)
        let strong = Ratings(power: 99, speed: 50, endurance: 50)
        XCTAssertEqual(curves.tackleStrength(weak), 1)
        XCTAssertEqual(curves.tackleStrength(strong), 99)
        curves.tackleStrengthMin = 10
        curves.tackleStrengthMax = 90
        XCTAssertEqual(curves.tackleStrength(weak), 10)
        XCTAssertEqual(curves.tackleStrength(strong), 90)
        for bounds: (Float, Float) in [(0, 90), (90, 10), (.nan, 90), (10, .infinity)] {
            curves.tackleStrengthMin = bounds.0
            curves.tackleStrengthMax = bounds.1
            XCTAssertEqual(curves.tackleStrength(weak), 1)
            XCTAssertEqual(curves.tackleStrength(strong), 99)
        }
        let encoded = try JSONEncoder().encode(RatingCurves.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "tackleStrengthMin")
        object.removeValue(forKey: "tackleStrengthMax")
        let legacy = try JSONDecoder().decode(
            RatingCurves.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.tackleStrengthMin)
        XCTAssertEqual(legacy.tackleStrength(strong), 99)
    }

    /// Weak QB vs a relentless MLB: total ticks to the whistle across seeds. The
    /// tackle-success edge decides how many broken tackles buy extra time.
    private func ticksToWhistle(
        playbook: Playbook, format: TeamFormat, curves: RatingCurves
    ) throws -> Int {
        var total = 0
        for seed in 1...60 {
            var match = Match(seed: UInt64(seed), playbook: playbook, format: format, curves: curves)
            match.setRoster(
                offense: [.qb: (Ratings(power: 1, speed: 1, endurance: 99), 12)],
                defense: [.mlb: (Ratings(power: 99, speed: 1, endurance: 99), 55)])
            match.step(input: TickInput(playSelect: 0), ai: [:])
            match.step(input: TickInput(buttons: .snap), ai: [:])
            let qb = try XCTUnwrap(match.world.player(at: .qb)?.id)
            let mlb = try XCTUnwrap(match.world.player(at: .mlb)?.id)
            var ticks = 0
            while match.phase == .live && ticks < 900 {
                let aim = (match.world[qb].location - match.world[mlb].location).normalized
                match.step(input: .none, ai: [mlb: PlayerIntent(move: aim)])
                ticks += 1
            }
            XCTAssertEqual(match.lastOutcome, .sack, "seed \(seed) never got sacked")
            total += ticks
        }
        return total
    }
}
