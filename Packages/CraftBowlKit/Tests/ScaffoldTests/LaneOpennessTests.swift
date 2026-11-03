import CBCore
import CBPlays
import CBSim
import XCTest

final class LaneOpennessTests: XCTestCase {
    func testOpennessTracksLiveSeparationAndIgnoresDownDefenders() {
        var world = World(seed: 30)
        let ratings = Ratings(power: 50, speed: 50, endurance: 50)
        let receiver = world.spawn(.laneLeft, ratings: ratings, number: 11, at: Vec2(-10, 55))
        let defender = world.spawn(.cbL, ratings: ratings, number: 21, at: Vec2(-10, 58))
        XCTAssertEqual(world.receiverOpenness(receiver), 3, accuracy: 0.001)

        world[defender].location = Vec2(-10, 56)
        XCTAssertEqual(world.receiverOpenness(receiver), 1, accuracy: 0.001)
        world[defender].isDown = true
        XCTAssertEqual(world.receiverOpenness(receiver), 6, accuracy: 0.001)
        XCTAssertNil(world.receiverOpenness(for: .laneCenter))
    }

    func testCorridorThreatAffectsLiveLaneAndIgnoresQBPressureAndDownPlayers() {
        var world = World(seed: 32)
        let ratings = Ratings(power: 50, speed: 50, endurance: 50)
        let qb = world.spawn(.qb, ratings: ratings, number: 1, at: Vec2(0, 40))
        let receiver = world.spawn(.laneLeft, ratings: ratings, number: 11, at: Vec2(-10, 60))
        world.ball = .held(by: qb)
        let threat = world.spawn(.cbL, ratings: ratings, number: 21, at: Vec2(-7.5, 55))
        XCTAssertEqual(world.receiverOpenness(receiver), 0.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(world.receiverOpenness(for: .laneLeft)), 0.5, accuracy: 0.001)

        world[threat].location = Vec2(0, 42)  // Behind the receiving half.
        XCTAssertEqual(world.receiverOpenness(receiver), 6, accuracy: 0.001)
        world[threat].location = Vec2(-7.5, 55)
        world[threat].isDown = true
        XCTAssertEqual(world.receiverOpenness(receiver), 6, accuracy: 0.001)
        world.step(intents: [:])
        XCTAssertEqual(try XCTUnwrap(world.receiverOpenness(for: .laneLeft)), 6, accuracy: 0.01)
    }

    func testCrowdedReceivingCorridorTightensOpennessMetric() {
        var world = World(seed: 33)
        let ratings = Ratings(power: 50, speed: 50, endurance: 50)
        let qb = world.spawn(.qb, ratings: ratings, number: 1, at: Vec2(0, 40))
        let receiver = world.spawn(.laneCenter, ratings: ratings, number: 15, at: Vec2(0, 60))
        world.ball = .held(by: qb)

        _ = world.spawn(.mlb, ratings: ratings, number: 50, at: Vec2(1.5, 52))
        XCTAssertEqual(world.receiverOpenness(receiver), 3.5, accuracy: 0.001)

        // Second defender farther from route still crowds receiving half.
        let second = world.spawn(.fs, ratings: ratings, number: 20, at: Vec2(-2, 56))
        XCTAssertEqual(world.receiverOpenness(receiver), 3, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(world.receiverOpenness(for: .center)), 3, accuracy: 0.001)

        world[second].isDown = true
        XCTAssertEqual(world.receiverOpenness(receiver), 3.5, accuracy: 0.001)
        world[second].isDown = false
        world[second].location = Vec2(-2, 42)  // QB-side pressure is not a receiving threat.
        XCTAssertEqual(world.receiverOpenness(receiver), 3.5, accuracy: 0.001)
    }

    func testThrowCorridorStaysAnchoredAtReleaseDuringFlight() {
        var world = World(seed: 34)
        let ratings = Ratings(power: 50, speed: 50, endurance: 50)
        let qb = world.spawn(.qb, ratings: ratings, number: 1, at: Vec2(0, 40))
        let receiver = world.spawn(.laneCenter, ratings: ratings, number: 15, at: Vec2(0, 60))
        world.ball = .held(by: qb)
        _ = world.spawn(.fs, ratings: ratings, number: 20, at: Vec2(1, 52))
        let before = world.receiverOpenness(receiver)
        XCTAssertEqual(before, 2.5, accuracy: 0.001)

        world.throwBall(to: Vec2(0, 60), target: receiver, speed: 20, peak: 4)
        for _ in 0..<40 { world.step(intents: [:]) }
        XCTAssertNotNil(world.ballFlight)
        XCTAssertGreaterThan(world.ballLocation.y, 50)
        XCTAssertEqual(world.receiverOpenness(receiver), before, accuracy: 0.001)
    }

    func testOpennessUsesReceiverMovementAndNearestDefender() {
        var world = World(seed: 31)
        let ratings = Ratings(power: 50, speed: 50, endurance: 50)
        let receiver = world.spawn(.laneRight, ratings: ratings, number: 12, at: Vec2(10, 55))
        world[receiver].velocity = Vec2(0, 5)
        _ = world.spawn(.cbR, ratings: ratings, number: 22, at: Vec2(10, 58))
        _ = world.spawn(.fs, ratings: ratings, number: 23, at: Vec2(10, 59))
        XCTAssertEqual(world.receiverOpenness(receiver), 1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(world.receiverOpenness(for: Lane.right)), 1, accuracy: 0.001)
    }
}
