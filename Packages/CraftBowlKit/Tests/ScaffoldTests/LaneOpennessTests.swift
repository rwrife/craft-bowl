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
