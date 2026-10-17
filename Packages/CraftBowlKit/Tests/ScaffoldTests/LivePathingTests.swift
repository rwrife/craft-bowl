import CBAI
import CBCore
import CBPlays
import CBSim
import XCTest

/// Bounded #25 slice: verify Arrive and Avoid reach live AI intents, not only standalone tests.
final class LivePathingTests: XCTestCase {
    func testLiveReceiverArrivesAtRoutePoint() throws {
        let loaded = try Playbook.loadBundled()
        let offense = try XCTUnwrap(loaded.playbook.offense.first { $0.id == "toss_left" })
        let defense = try XCTUnwrap(loaded.playbook.defense.first)
        var brain = SandboxBrain()
        var world = World(seed: 123)
        let qb = world.spawn(.qb, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 12, at: Vec2(0, 20))
        let receiver = world.spawn(
            .laneLeft, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 88, at: Vec2(0, 30))
        world.ball = .held(by: qb)
        let context = PlayContext(
            offense: offense, defense: defense, lineOfScrimmage: 25, isLive: true,
            liveTicks: 0, controlled: nil, runnerPhase: false
        )
        let target = Vec2(Field.laneCenterX(-1), 30.5)

        world[receiver].location = Vec2(target.x, target.y - 10)
        let far = try XCTUnwrap(brain.intents(world: world, context: context)[receiver])
        XCTAssertEqual(far.move.length, 1, accuracy: 0.0001)
        XCTAssertEqual(brain.aimPoints[receiver], target)

        world[receiver].location = Vec2(target.x, target.y - 0.75)
        let near = try XCTUnwrap(brain.intents(world: world, context: context)[receiver])
        XCTAssertEqual(near.move.length, 0.5, accuracy: 0.0001)

        world[receiver].location = Vec2(target.x, target.y - 0.2)
        let stopped = try XCTUnwrap(brain.intents(world: world, context: context)[receiver])
        XCTAssertEqual(stopped.move, .zero)
    }

    func testLiveRouteAvoidsStationaryTeammateWithoutChangingSpeed() throws {
        let loaded = try Playbook.loadBundled()
        let offense = try XCTUnwrap(loaded.playbook.offense.first { $0.id == "toss_left" })
        let defense = try XCTUnwrap(loaded.playbook.defense.first)
        var brain = SandboxBrain()
        var world = World(seed: 789)
        let qb = world.spawn(.qb, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 12, at: Vec2(0, 20))
        let receiver = world.spawn(
            .laneLeft, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 88, at: Vec2(-10, 20))
        world.ball = .held(by: qb)
        let context = PlayContext(
            offense: offense, defense: defense, lineOfScrimmage: 25, isLive: true,
            liveTicks: 0, controlled: qb, runnerPhase: false
        )
        let target = Vec2(Field.laneCenterX(-1), 30.5)
        world[receiver].location = Vec2(target.x, target.y - 6)
        let baseline = try XCTUnwrap(brain.intents(world: world, context: context)[receiver]).move
        XCTAssertEqual(baseline, Vec2(0, 1))

        world.spawn(
            .rb, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 22,
            at: world[receiver].location + Vec2(0, 1))
        // Intent order cannot change receiver steering; all threats come from world snapshot.
        let steered = try XCTUnwrap(brain.intents(world: world, context: context)[receiver]).move
        XCTAssertGreaterThan(steered.x, 0)
        XCTAssertEqual(steered.length, baseline.length, accuracy: 0.0001)
    }

    func testLiveDefenderPursuesMovingQuarterback() throws {
        let loaded = try Playbook.loadBundled()
        let offense = try XCTUnwrap(loaded.playbook.offense.first)
        let defense = try XCTUnwrap(loaded.playbook.defense.first { $0.assignments[.mlb] == .rush })
        var brain = SandboxBrain()
        var world = World(seed: 456)
        let qb = world.spawn(.qb, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 12, at: Vec2(0, 20))
        let mlb = world.spawn(.mlb, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 54, at: Vec2(0, 26))
        world.ball = .held(by: qb)
        let context = PlayContext(
            offense: offense, defense: defense, lineOfScrimmage: 25, isLive: true,
            liveTicks: 0, controlled: nil, runnerPhase: false
        )
        world[qb].velocity = Vec2(4, 0)
        let move = try XCTUnwrap(brain.intents(world: world, context: context)[mlb]).move
        XCTAssertGreaterThan(move.x, 0.2)
        XCTAssertLessThan(move.y, 0)
    }

    func testLiveDefenderDivePreservedWithTeammateNearby() throws {
        let loaded = try Playbook.loadBundled()
        let offense = try XCTUnwrap(loaded.playbook.offense.first)
        let defense = try XCTUnwrap(loaded.playbook.defense.first)
        var brain = SandboxBrain()
        var world = World(seed: 321)
        let qb = world.spawn(
            .qb, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 12, at: Vec2(0, 20))
        let mlb = world.spawn(
            .mlb, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 54, at: Vec2(0, 18.5))
        world.spawn(
            .ss, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 31, at: Vec2(0.6, 19.6))
        world.ball = .held(by: qb)
        world[qb].velocity = Vec2(0, 5)
        let context = PlayContext(
            offense: offense, defense: defense, lineOfScrimmage: 25, isLive: true,
            liveTicks: 0, controlled: nil, runnerPhase: true
        )
        let intent = try XCTUnwrap(brain.intents(world: world, context: context)[mlb])
        XCTAssertTrue(intent.dive)
        XCTAssertLessThan(intent.move.x, 0)  // Steered away from teammate on right (+x)
        XCTAssertGreaterThan(intent.move.y, 0)
    }
}
