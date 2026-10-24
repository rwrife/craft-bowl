import CBSim
import Foundation
import XCTest

/// Bounded #27 slice contract: catch-rate terms are optional `RatingCurves` tuning
/// with bounded, validated fallback (legacy tuning JSON loads unchanged).
final class CatchRateTuningTests: XCTestCase {
    func testLegacyDefaultsApplyWhenFieldsAbsent() throws {
        let curves = try RatingCurves.loadBundled()
        // Bundled ratings.json predates these fields; defaults must apply.
        XCTAssertNil(curves.catchBaseChance)
        XCTAssertEqual(curves.catchBase(), 0.70, accuracy: 0.001)
        XCTAssertEqual(curves.contestedPenalty(), 0.42, accuracy: 0.001)
        XCTAssertEqual(curves.catchDistancePenalty(), 0.08, accuracy: 0.001)
    }

    func testValidOverridesTakeEffect() throws {
        var curves = RatingCurves.default
        curves.catchBaseChance = 0.5
        curves.contestedCatchPenalty = 0.3
        curves.catchDistancePenaltyPerYard = 0.1
        XCTAssertEqual(curves.catchBase(), 0.5, accuracy: 0.001)
        XCTAssertEqual(curves.contestedPenalty(), 0.3, accuracy: 0.001)
        XCTAssertEqual(curves.catchDistancePenalty(), 0.1, accuracy: 0.001)
    }

    /// Out-of-range / non-finite tuning must fall back, never poison catch chance.
    func testInvalidTuningFallsBackToDefaults() throws {
        var curves = RatingCurves.default
        for bad: Float in [-0.1, 1.5, .nan, .infinity, -.infinity] {
            curves.catchBaseChance = bad
            curves.contestedCatchPenalty = bad
            curves.catchDistancePenaltyPerYard = bad
            XCTAssertEqual(curves.catchBase(), 0.70, accuracy: 0.001, "base \(bad)")
            XCTAssertEqual(curves.contestedPenalty(), 0.42, accuracy: 0.001, "penalty \(bad)")
            XCTAssertEqual(curves.catchDistancePenalty(), 0.08, accuracy: 0.001, "distance \(bad)")
        }
    }
}
