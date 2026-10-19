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
            for b in standing[(i + 1)...] {
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

    /// Divers can meet head-on; both must separate without changing their lunge velocities.
    func testTwoDiversSeparateAndReportContactOnce() {
        var world = World(seed: 41)
        let rating = Ratings(power: 50, speed: 50, endurance: 50)
        let a = world.spawn(.lt, ratings: rating, number: 1, at: Vec2(0, 40))
        let b = world.spawn(.deL, ratings: rating, number: 2, at: Vec2(0, 40))
        world.startDive(a)
        world.startDive(b)
        let velocityA = world[a].velocity, velocityB = world[b].velocity
        world.step(intents: [:])
        XCTAssertTrue(world[a].isDiving && world[b].isDiving)
        XCTAssertLessThanOrEqual(worstOverlap(world), slack)
        XCTAssertEqual(world.events.filter { $0 == .contact(a, b) }.count, 1)
        XCTAssertEqual(world[a].velocity.x, velocityA.x * 0.965, accuracy: 1e-5)
        XCTAssertEqual(world[a].velocity.y, velocityA.y * 0.965, accuracy: 1e-5)
        XCTAssertEqual(world[b].velocity.x, velocityB.x * 0.965, accuracy: 1e-5)
        XCTAssertEqual(world[b].velocity.y, velocityB.y * 0.965, accuracy: 1e-5)
    }

    func testSameSideDiversSeparateWithoutOpponentContact() {
        var world = World(seed: 42)
        let rating = Ratings(power: 50, speed: 50, endurance: 50)
        let a = world.spawn(.lt, ratings: rating, number: 1, at: Vec2(0, 40))
        let b = world.spawn(.lg, ratings: rating, number: 2, at: Vec2(0, 40))
        world.startDive(a)
        world.startDive(b)
        world.step(intents: [:])
        XCTAssertLessThanOrEqual(worstOverlap(world), slack)
        XCTAssertFalse(
            world.events.contains {
                if case .contact = $0 { return true }; return false
            })
    }

    /// Dense piles must resolve within the current tick, not over several frames of clipping.
    func testDensePileSeparatesOnFirstTick() {
        var world = World(seed: 7)
        let positions: [Position] = [.qb, .rb, .laneLeft, .laneCenter, .laneRight, .lt, .lg, .rg, .rt]
        for (i, position) in positions.enumerated() {
            let angle = Float(i) * 0.7
            world.spawn(
                position, ratings: Ratings(power: 10 + i * 10, speed: 50, endurance: 50),
                number: i, at: Vec2(sin(angle) * 0.35, 40 + cos(angle) * 0.35))
        }
        world.step(intents: [:])
        XCTAssertLessThanOrEqual(worstOverlap(world), slack)
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

    /// Players initially apart can collide when both get clamped back from outside a wall.
    func testWallClampCreatesOverlapThatMustResolve() {
        var world = World(seed: 23)
        let x = Field.wallHalfWidth - World.playerRadius
        let rating = Ratings(power: 50, speed: 50, endurance: 50)
        let a = world.spawn(.lt, ratings: rating, number: 1, at: Vec2(x + 1, 40))
        let b = world.spawn(.deL, ratings: rating, number: 2, at: Vec2(x + 2, 40))
        world.step(intents: [:])
        XCTAssertLessThanOrEqual(worstOverlap(world), slack)
        XCTAssertEqual(world.events.filter { $0 == .contact(a, b) }.count, 1)
        XCTAssertTrue(world.players.allSatisfy { $0.location.x <= x + 1e-4 })
    }

    /// Collision relaxation must account for wall clamp within the same tick.
    func testWallPileSeparatesOnFirstTick() {
        var world = World(seed: 3)
        let x = Field.wallHalfWidth - World.playerRadius
        for i in 0..<4 {
            world.spawn(
                i % 2 == 0 ? .lt : .deL, ratings: Ratings(power: 30 + i * 20, speed: 60, endurance: 50),
                number: i, at: Vec2(x - Float(i) * 0.2, 40 + Float(i) * 0.1))
        }
        world.step(intents: [:])
        XCTAssertLessThanOrEqual(worstOverlap(world), slack)
        XCTAssertTrue(world.players.allSatisfy { $0.location.x <= x + 1e-4 })
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

    /// A pair pushed together by a different pair must still report contact once this tick.
    func testContactCreatedDuringSeparationIsReportedOnce() {
        var world = World(seed: 32)
        let rating = Ratings(power: 50, speed: 50, endurance: 50)
        world.spawn(.lt, ratings: rating, number: 1, at: Vec2(0, 40))
        let blocker = world.spawn(.lg, ratings: rating, number: 2, at: Vec2(0.2, 40))
        let defender = world.spawn(.deL, ratings: rating, number: 3, at: Vec2(1.1, 40))
        world.step(intents: [:])
        XCTAssertEqual(world.events.filter { $0 == .contact(blocker, defender) }.count, 1)
        XCTAssertEqual(world[blocker].engagedTicks, 8)
        XCTAssertEqual(world[defender].engagedTicks, 8)
    }

    /// Relaxation reduces remaining dense-pile overlap monotonically, even when the first tick cannot separate every wall pair.
    func testDenseWallPileMonotonicallySeparates() {
        var world = World(seed: 31)
        let x = Field.wallHalfWidth - World.playerRadius
        for i in 0..<5 {
            world.spawn(
                i % 2 == 0 ? .lt : .deL,
                ratings: Ratings(power: 10 + i * 20, speed: 60, endurance: 50),
                number: i, at: Vec2(x - Float(i) * 0.08, 40 + Float(i) * 0.04))
        }
        var previous = worstOverlap(world)
        for _ in 0..<8 {
            world.step(intents: [:])
            let current = worstOverlap(world)
            XCTAssertLessThanOrEqual(current, previous + slack)
            previous = current
        }
        XCTAssertLessThanOrEqual(previous, slack)
    }

    /// Bounded collision relaxation must keep dense-pile resolution deterministic.
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
