import CBCore
import CBSim
import Foundation
import XCTest

final class ContactPowerTests: XCTestCase {
    func testTunedPowerChangesLiveContactPush() {
        var curves = RatingCurves.default
        curves.blockStrengthMin = 1
        curves.blockStrengthMax = 9
        var world = World(seed: 42, curves: curves)
        let strong = world.spawn(
            .lt, ratings: Ratings(power: 99, speed: 50, endurance: 50), number: 1, at: Vec2(0, 40))
        let weak = world.spawn(
            .deL, ratings: Ratings(power: 1, speed: 50, endurance: 50), number: 2, at: Vec2(0, 40))
        world.step(intents: [:])
        let movedStrong = abs(world[strong].location.x)
        let movedWeak = abs(world[weak].location.x)
        XCTAssertGreaterThan(movedStrong, 0)
        XCTAssertEqual(movedWeak / movedStrong, 9, accuracy: 0.001)
        XCTAssertEqual(
            world[strong].location.distance(to: world[weak].location),
            World.playerRadius * 2,
            accuracy: 0.001)
    }

    func testMalformedAndLegacyBlockCurvesFallBack() throws {
        var curves = RatingCurves.loadBundled()
        XCTAssertEqual(curves.blockStrengthMin, 1)
        XCTAssertEqual(curves.blockStrengthMax, 99)
        let strong = Ratings(power: 99, speed: 50, endurance: 50)
        let weak = Ratings(power: 1, speed: 50, endurance: 50)
        for bounds: (Float, Float) in [(0, 9), (9, 1), (.nan, 9), (1, .infinity)] {
            curves.blockStrengthMin = bounds.0
            curves.blockStrengthMax = bounds.1
            XCTAssertEqual(curves.blockStrength(strong), 99)
            XCTAssertEqual(curves.blockStrength(weak), 1)
        }
        let data = try JSONEncoder().encode(RatingCurves.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "blockStrengthMin")
        object.removeValue(forKey: "blockStrengthMax")
        let legacy = try JSONDecoder().decode(RatingCurves.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(legacy.blockStrength(strong), 99)
    }
}
