import CBCore
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

    func testSpeedControlsTurnRateInLiveMovement() {
        let ratingsLow = Ratings(power: 50, speed: 1, endurance: 50)
        let ratingsHigh = Ratings(power: 50, speed: 99, endurance: 50)
        var curves = RatingCurves.loadBundled()
        XCTAssertLessThan(curves.turnRate(ratingsLow), curves.turnRate(ratingsHigh))

        func turnedFacing(_ ratings: Ratings) -> Float {
            var world = World(seed: 7, curves: curves)
            let id = world.spawn(.rb, ratings: ratings, number: 28, at: Vec2(0, 40))
            world[id].velocity = Vec2(0, 5)
            world.step(intents: [id: PlayerIntent(move: Vec2(1, 0))])
            return world[id].facing
        }
        let slowTurn = turnedFacing(ratingsLow)
        let fastTurn = turnedFacing(ratingsHigh)
        XCTAssertGreaterThan(slowTurn, 0)
        XCTAssertGreaterThan(fastTurn, slowTurn)
        XCTAssertLessThan(fastTurn, Float.pi / 2)

        curves.turnRateMin = 2
        curves.turnRateMax = 3
        XCTAssertEqual(curves.turnRate(ratingsHigh), 3)
        curves.turnRateMin = .nan
        XCTAssertEqual(curves.turnRate(ratingsHigh), 10, "invalid hot-reload values use safe defaults")
        curves.turnRateMin = nil
        curves.turnRateMax = nil
        XCTAssertEqual(curves.turnRate(ratingsLow), 6, "older tuning resources still load")
    }

    func testTuningChangesLiveSteeringWithoutChangingAcceleration() {
        func step(rate: Float, heading: Float, move: Vec2) -> PlayerState {
            var curves = RatingCurves.default
            curves.turnRateMin = rate
            curves.turnRateMax = rate
            var world = World(seed: 7, curves: curves)
            let id = world.spawn(
                .rb, ratings: Ratings(power: 50, speed: 50, endurance: 50),
                number: 28, at: Vec2(0, 40))
            world[id].velocity = Vec2(sin(heading), cos(heading)) * 5
            world.step(intents: [id: PlayerIntent(move: move)])
            return world[id]
        }
        let slow = step(rate: 1, heading: 0, move: Vec2(1, 0))
        let fast = step(rate: 20, heading: 0, move: Vec2(1, 0))
        XCTAssertGreaterThan(fast.facing, slow.facing)
        XCTAssertLessThanOrEqual(slow.facing, World.dt + 0.0001)
        let braking = step(rate: 1, heading: 0, move: .zero)
        XCTAssertLessThan(braking.velocity.length, 5)
        XCTAssertEqual(braking.facing, 0)
        // Cross the -pi/pi seam along the short arc, not a near-full-circle turn.
        let wrapped = step(
            rate: 20, heading: Float.pi - 0.01,
            move: Vec2(sin(-Float.pi + 0.01), cos(-Float.pi + 0.01)))
        XCTAssertLessThan(wrapped.velocity.x, 0.05)
        XCTAssertLessThan(wrapped.velocity.y, -4)
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
