import CBCore
import CBSim
import XCTest

/// Issue #25 acceptance: "Players never overlap".
final class CollisionOverlapTests: XCTestCase {
    private let minDist = World.playerRadius * 2
    /// Float slack for the final position write-back.
    private let slack: Float = 0.005

    private func worstOverlap(_ world: World) -> Float {
        let standing = world.players.filter { !$0.isDown }
        var worst: Float = 0
        for (i, a) in standing.enumerated() {
            for b in standing[(i + 1)...] where !(a.isDiving && b.isDiving) {
                worst = max(worst, minDist - a.location.distance(to: b.location))
            }
        }
        return worst
    }

    /// A diver is immovable, so the standing player must take the whole separation (not half of it).
    func testStandingPlayerFullySeparatesFromDiver() {
        var world = World(seed: 1)
        let diver = world.spawn(
            .cbL, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 1, at: Vec2(0, 40))
        let other = world.spawn(
            .lt, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 2, at: Vec2(0.3, 40))
        world.startDive(diver)
        XCTAssertTrue(world[diver].isDiving)
        world.step(intents: [:])
        XCTAssertGreaterThanOrEqual(
            world[diver].location.distance(to: world[other].location), minDist - slack)
    }

    /// Pair iteration order must not change the full-push rule.
    func testStandingPlayerSpawnedBeforeDiverSeparates() {
        var world = World(seed: 2)
        let other = world.spawn(
            .lt, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 1, at: Vec2(0.3, 40))
        let diver = world.spawn(
            .cbL, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 2, at: Vec2(0, 40))
        world.startDive(diver)
        world.step(intents: [:])
        XCTAssertGreaterThanOrEqual(
            world[other].location.distance(to: world[diver].location), minDist - slack)
    }

    /// A pile of players stacked in a few square yards eventually resolves to a non-overlapping layout.
    func testDensePileResolvesWithoutOverlap() {
        var world = World(seed: 7)
        let positions: [Position] = [.qb, .rb, .laneLeft, .laneCenter, .laneRight, .lt, .lg, .rg, .rt]
        for (i, position) in positions.enumerated() {
            let angle = Float(i) * 0.7
            world.spawn(
                position, ratings: Ratings(power: 10 + i * 10, speed: 50, endurance: 50),
                number: i, at: Vec2(sin(angle) * 0.35, 40 + cos(angle) * 0.35))
        }
        for _ in 0..<30 { world.step(intents: [:]) }
        XCTAssertLessThanOrEqual(worstOverlap(world), slack)
    }

    /// Pressing against the sideline wall must not squeeze players back into each other.
    func testWallDoesNotSqueezePlayersTogether() {
        var world = World(seed: 3)
        let x = Field.wallHalfWidth - World.playerRadius
        for i in 0..<4 {
            world.spawn(
                i % 2 == 0 ? .lt : .deL, ratings: Ratings(power: 30 + i * 20, speed: 60, endurance: 50),
                number: i, at: Vec2(x - Float(i) * 0.2, 40 + Float(i) * 0.1))
        }
        let push = Dictionary(uniqueKeysWithValues: world.players.map { ($0.id, PlayerIntent(move: Vec2(1, 0))) })
        for _ in 0..<60 { world.step(intents: push) }
        XCTAssertLessThanOrEqual(worstOverlap(world), slack)
        for p in world.players {
            XCTAssertLessThanOrEqual(p.location.x, Field.wallHalfWidth - World.playerRadius + 1e-4)
        }
    }

    /// One touching pair produces one contact event.
    func testContactEventEmittedOncePerPair() {
        var world = World(seed: 5)
        let a = world.spawn(
            .lt, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 1, at: Vec2(0, 40))
        let b = world.spawn(
            .deL, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 2, at: Vec2(0.2, 40))
        world.step(intents: [:])
        XCTAssertEqual(world.events.filter { $0 == .contact(a, b) }.count, 1)
    }

    /// Resolution stays deterministic for identical inputs.
    func testResolutionIsDeterministic() {
        func run() -> UInt64 {
            var world = World(seed: 11)
            for i in 0..<9 {
                world.spawn(
                    .lt, ratings: Ratings(power: 10 + i * 10, speed: 50, endurance: 50), number: i,
                    at: Vec2(Float(i % 3) * 0.3, 40 + Float(i / 3) * 0.3))
            }
            for _ in 0..<20 { world.step(intents: [:]) }
            return world.checksum
        }
        XCTAssertEqual(run(), run())
    }
}
