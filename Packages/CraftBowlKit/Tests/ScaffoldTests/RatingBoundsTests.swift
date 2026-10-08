import CBCore
import CBSim
import Foundation
import XCTest

final class RatingBoundsTests: XCTestCase {
    func testRatingMutationCannotEscapeOneToNinetyNine() throws {
        var ratings = Ratings(power: 50, speed: 50, endurance: 50, ability: 50)
        ratings.power = -1
        ratings.speed = 200
        ratings.endurance = Int.min
        ratings.ability = Int.max
        XCTAssertEqual([ratings.power, ratings.speed, ratings.endurance, ratings.ability], [1, 99, 1, 99])
        XCTAssertEqual(ratings.p, 0)
        XCTAssertEqual(ratings.s, 1)
        XCTAssertEqual(ratings.e, 0)
        XCTAssertEqual(ratings.a, 1)

        let decoded = try JSONDecoder().decode(
            Ratings.self,
            from: Data(#"{"power":-1,"speed":200,"endurance":-2,"ability":300}"#.utf8))
        XCTAssertEqual([decoded.power, decoded.speed, decoded.endurance, decoded.ability], [1, 99, 1, 99])
    }

    func testMutatedPowerKeepsContactSeparationFinite() {
        var world = World(seed: 1)
        let offense = world.spawn(
            .rb, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 1, at: Vec2(0, 40))
        let defense = world.spawn(
            .mlb, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 2, at: Vec2(0, 40))
        world[offense].ratings.power = 0
        world[defense].ratings.power = 0
        world.step(intents: [:])
        XCTAssertTrue(world[offense].location.x.isFinite)
        XCTAssertTrue(world[defense].location.x.isFinite)
        XCTAssertGreaterThanOrEqual(
            world[offense].location.distance(to: world[defense].location), World.playerRadius * 2 - 0.0001)
    }
}
