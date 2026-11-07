import CBAI
import CBCore
import CBGame
import CBPlays
import CBSim
import XCTest

/// Bounded #25 slice: verify Arrive and Avoid reach live AI intents, not only standalone tests.
final class LivePathingTests: XCTestCase {
    func testDeepVerticalFollowsLaneCenterInCardAndLiveAI() throws {
        let loaded = try Playbook.loadBundled()
        let offense = try XCTUnwrap(loaded.playbook.offense.first { $0.id == "four_verts" })
        let defense = try XCTUnwrap(loaded.playbook.defense.first)
        let los: Float = 40
        var world = World(seed: 30)
        let ratings = Ratings(power: 50, speed: 50, endurance: 50)
        let qb = world.spawn(.qb, ratings: ratings, number: 12, at: Vec2(0, los - 4.5))
        world.ball = .held(by: qb)
        let columns: [(Lane, Float, Float)] = [
            (.left, -17, Field.laneCenterX(-1)), (.center, 7, 7),
            (.right, 17, Field.laneCenterX(1)),
        ]
        let card = PlayDiagram(play: offense)
        for (lane, startX, targetX) in columns {
            XCTAssertEqual(SandboxBrain.routeWaypoints(lane: lane, route: .deep), [Vec2(targetX, 32)])
            let stroke = try XCTUnwrap(
                card.strokes.first {
                    $0.style == .route && $0.points.first?.x == startX
                        && $0.points.last?.y == PlayDiagram.maxY
                })
            XCTAssertEqual(stroke.points.last?.x, startX + (targetX - startX) * (PlayDiagram.maxY + 1) / 33)
            world.spawn(lane.slotPosition, ratings: ratings, number: 88, at: Vec2(startX, los - 1))
        }
        let context = PlayContext(
            offense: offense, defense: defense, lineOfScrimmage: los,
            isLive: true, liveTicks: 1, controlled: qb, runnerPhase: false)
        var brain = SandboxBrain()
        _ = brain.intents(world: world, context: context)
        for (lane, _, targetX) in columns {
            let receiver = try XCTUnwrap(world.player(at: lane.slotPosition))
            XCTAssertEqual(brain.aimPoints[receiver.id], Vec2(targetX, los + 32))
        }
    }

    func testCenterSlotRoutesStartFromItsFormationSide() throws {
        let loaded = try Playbook.loadBundled()
        let offense = try XCTUnwrap(loaded.playbook.offense.first { $0.id == "spread_pass" })
        let defense = try XCTUnwrap(loaded.playbook.defense.first)
        let los: Float = 40
        let start = Vec2(7, -1.5)  // Center slot's formation position.
        let waypoints = SandboxBrain.routeWaypoints(lane: .center, route: .short)
        XCTAssertEqual(waypoints.count, 1)
        XCTAssertEqual(waypoints[0].x, start.x, accuracy: 0.001)
        let stroke = try XCTUnwrap(
            PlayDiagram(play: offense).strokes.first {
                $0.style == .route && $0.points.first == start
            })
        XCTAssertEqual(stroke.points[1], waypoints[0])

        var world = World(seed: 30)
        let ratings = Ratings(power: 50, speed: 50, endurance: 50)
        let qb = world.spawn(.qb, ratings: ratings, number: 12, at: Vec2(0, los - 4.5))
        let receiver = world.spawn(
            .laneCenter, ratings: ratings, number: 88,
            at: Vec2(start.x, los + start.y))
        world.ball = .held(by: qb)
        let context = PlayContext(
            offense: offense, defense: defense, lineOfScrimmage: los,
            isLive: true, liveTicks: 0, controlled: qb, runnerPhase: false)
        var brain = SandboxBrain()
        _ = brain.intents(world: world, context: context)
        XCTAssertEqual(brain.aimPoints[receiver], Vec2(start.x, los + waypoints[0].y))
    }

    func testMidRouteHoldsStemUntilReceiverReachesIt() throws {
        let loaded = try Playbook.loadBundled()
        let offense = try XCTUnwrap(loaded.playbook.offense.first { $0.id == "pa_shot" })
        let defense = try XCTUnwrap(loaded.playbook.defense.first)
        let waypoints = SandboxBrain.routeWaypoints(lane: .center, route: .mid)
        XCTAssertEqual(waypoints.count, 2)
        let stroke = try XCTUnwrap(
            PlayDiagram(play: offense).strokes.first {
                $0.style == .route && $0.points.first == Vec2(7, -1.5)
            })
        XCTAssertEqual(stroke.points, [Vec2(7, -1.5)] + waypoints)

        var world = World(seed: 31)
        let ratings = Ratings(power: 50, speed: 50, endurance: 50)
        let qb = world.spawn(.qb, ratings: ratings, number: 12, at: Vec2(0, 35.5))
        let receiver = world.spawn(.laneCenter, ratings: ratings, number: 88, at: Vec2(7, 38.5))
        world.ball = .held(by: qb)
        let context = PlayContext(
            offense: offense, defense: defense, lineOfScrimmage: 40,
            isLive: true, liveTicks: 120, controlled: qb, runnerPhase: false)
        var brain = SandboxBrain()
        _ = brain.intents(world: world, context: context)
        XCTAssertEqual(brain.aimPoints[receiver], Vec2(waypoints[0].x, 40 + waypoints[0].y))

        world[receiver].location = Vec2(waypoints[0].x, 40 + waypoints[0].y)
        _ = brain.intents(world: world, context: context)
        XCTAssertEqual(brain.aimPoints[receiver], Vec2(waypoints[1].x, 40 + waypoints[1].y))

        world[receiver].location = Vec2(waypoints[0].x, 40 + waypoints[0].y - 4)
        _ = brain.intents(world: world, context: context)
        XCTAssertEqual(brain.aimPoints[receiver], Vec2(waypoints[1].x, 40 + waypoints[1].y))

        // Regression state: receiver already beyond the stem and outside its arrival radius.
        // It must latch the break once it has reached or passed the stem depth.
        var overshootBrain = SandboxBrain()
        world[receiver].location = Vec2(waypoints[0].x, 40 + waypoints[0].y + 3.2)
        _ = overshootBrain.intents(world: world, context: context)
        XCTAssertEqual(overshootBrain.aimPoints[receiver], Vec2(waypoints[1].x, 40 + waypoints[1].y))

        var offsetBrain = SandboxBrain()
        world[receiver].location = Vec2(waypoints[0].x + 4, 40 + waypoints[0].y + 3.2)
        _ = offsetBrain.intents(world: world, context: context)
        XCTAssertEqual(offsetBrain.aimPoints[receiver], Vec2(waypoints[0].x, 40 + waypoints[0].y))

        let nextPlay = PlayContext(
            offense: offense, defense: defense, lineOfScrimmage: 40,
            isLive: true, liveTicks: 0, controlled: qb, runnerPhase: false)
        _ = brain.intents(world: world, context: nextPlay)
        XCTAssertEqual(brain.aimPoints[receiver], Vec2(waypoints[0].x, 40 + waypoints[0].y))
    }

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
