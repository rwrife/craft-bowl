import CBSim
import XCTest

final class TeamRatingTests: XCTestCase {
    func testWeightedOverallRewardsPowerAndSpeedMoreThanAbility() {
        let baseline = Ratings(power: 50, speed: 50, endurance: 50, ability: 50)
        let stronger = Ratings(power: 60, speed: 50, endurance: 50, ability: 50)
        let skilled = Ratings(power: 50, speed: 50, endurance: 50, ability: 60)

        XCTAssertEqual(TeamRating.overall([baseline]), 50)
        XCTAssertGreaterThan(TeamRating.overall([stronger]), TeamRating.overall([skilled]))
    }

    func testOverallAveragesTheWholeRosterBeforeRoundingAndHandlesEmpty() {
        // Each individual score has a 0.9 remainder. Averaging first yields 51,
        // while rounding each player first would yield 50.
        let first = Ratings(power: 53, speed: 50, endurance: 50, ability: 50)
        let second = Ratings(power: 54, speed: 51, endurance: 51, ability: 51)
        XCTAssertEqual(TeamRating.overall([first, second]), 51)
        XCTAssertEqual(TeamRating.overall([]), 0)
    }

    func testSpeedAndEnduranceCurvesKeepTheirExpectedDirection() {
        let slow = Ratings(power: 50, speed: 1, endurance: 1)
        let fast = Ratings(power: 50, speed: 99, endurance: 99)
        let curves = RatingCurves.loadBundled()
        XCTAssertGreaterThan(curves.topSpeed(fast), curves.topSpeed(slow))
        XCTAssertLessThan(curves.playDrain(fast), curves.playDrain(slow))
        XCTAssertLessThan(curves.carryDrain(fast), curves.carryDrain(slow))
    }
}
