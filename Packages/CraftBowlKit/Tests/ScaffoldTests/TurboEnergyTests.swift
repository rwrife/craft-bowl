import CBCore
import CBSim
import XCTest

final class TurboEnergyTests: XCTestCase {
    private let ratings = Ratings(power: 50, speed: 50, endurance: 50)

    func testDefenderTurboUsesHealthEvenWhenNotAssignedToRoute() {
        var world = World(seed: 26)
        let defender = world.spawn(.cbL, ratings: ratings, number: 1, at: Vec2(0, 40))
        let baseline = world[defender].stamina
        world.step(intents: [defender: PlayerIntent(move: Vec2(0, 1), turbo: true)])
        XCTAssertTrue(world[defender].stamina.isTurboActive)
        XCTAssertLessThan(world[defender].stamina.turbo, baseline.turbo)
        XCTAssertLessThan(
            world[defender].health, baseline.health,
            "A boosting defender must not regenerate health while sprinting")
    }

    func testDefenderWithoutTurboRecoversAndTurboRechargesAfterDelay() {
        var world = World(seed: 27)
        let defender = world.spawn(.cbL, ratings: ratings, number: 1, at: Vec2(0, 40))
        world[defender].stamina.setHealth(0.5)
        let baseline = world[defender].health
        world.step(intents: [defender: PlayerIntent(move: Vec2(0, 1))])
        XCTAssertGreaterThan(world[defender].health, baseline)
        world.step(intents: [defender: PlayerIntent(move: Vec2(0, 1), turbo: true)])
        let spent = world[defender].stamina.turbo
        world.step(intents: [:])
        XCTAssertEqual(
            world[defender].stamina.turbo, spent,
            "Turbo must respect the recharge delay")
        for _ in 0..<90 { world.step(intents: [:]) }
        XCTAssertGreaterThan(world[defender].stamina.turbo, spent)
    }

    func testTurboRetainsEnduranceCapacityAndSpeedAdvantage() {
        func boosted(_ endurance: Int) -> PlayerState {
            var world = World(seed: 28)
            let rating = Ratings(power: 50, speed: 50, endurance: endurance)
            let id = world.spawn(.cbL, ratings: rating, number: 1, at: Vec2(0, 40))
            world.step(intents: [id: PlayerIntent(move: Vec2(0, 1), turbo: true)])
            return world[id]
        }
        let low = boosted(1), high = boosted(99)
        XCTAssertGreaterThan(high.stamina.turboCapacity, low.stamina.turboCapacity)
        XCTAssertGreaterThan(high.stamina.turbo, low.stamina.turbo)
        var unboosted = World(seed: 28)
        let id = unboosted.spawn(.cbL, ratings: high.ratings, number: 1, at: Vec2(0, 40))
        unboosted.step(intents: [id: PlayerIntent(move: Vec2(0, 1))])
        XCTAssertGreaterThan(
            high.stamina.maxSpeed(ratings: high.ratings, curves: .default),
            unboosted[id].stamina.maxSpeed(ratings: high.ratings, curves: .default))
    }
}
