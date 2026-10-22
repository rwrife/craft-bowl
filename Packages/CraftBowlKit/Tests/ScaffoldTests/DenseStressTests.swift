import CBCore
import CBSim
import XCTest

/// Issue #25 acceptance: "Players never overlap".
/// Follow-up coverage for hostile dense layouts pressing against a sideline,
/// where relaxation, wall clamping, and movement intents interact in one tick.
final class DenseStressTests: XCTestCase {
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

    /// A full 9v9 roster jammed against the sideline and all driven into the wall:
    /// the pile must never clip beyond the tick slack.
    func testDenseWallPilePushedIntoSidelineNeverOverlaps() {
        var world = World(seed: 11)
        let x = Field.wallHalfWidth - World.playerRadius
        for i in 0..<18 {
            world.spawn(
                i % 2 == 0 ? .lt : .deL,
                ratings: Ratings(power: 30 + (i % 4) * 20, speed: 60, endurance: 50),
                number: i,
                at: Vec2(x - Float(i % 2) * 0.15, 40 + Float(i) * 0.1))
        }
        let push = Dictionary(uniqueKeysWithValues: world.players.map { ($0.id, PlayerIntent(move: Vec2(1, 0))) })
        for _ in 0..<60 {
            world.step(intents: push)
            XCTAssertLessThanOrEqual(worstOverlap(world), slack, "overlap grew at tick \(world.tick)")
            for p in world.players {
                XCTAssertLessThanOrEqual(p.location.x, x + 1e-4, "player escaped the wall at tick \(world.tick)")
            }
        }
    }

    /// Maximum-power players grinding the sideline for two simulated seconds: the last relaxation
    /// sweep must never leave anyone outside the invisible wall (walls re-clamp each sweep).
    func testExtremePowerWallSqueezeNeverLeavesTheField() {
        var world = World(seed: 13)
        let x = Field.wallHalfWidth - World.playerRadius
        for i in 0..<18 {
            world.spawn(
                i % 2 == 0 ? .lt : .deL,
                ratings: Ratings(power: 99, speed: 99, endurance: 99),
                number: i,
                at: Vec2(x - Float(i % 2) * 0.15, 40 + Float(i) * 0.1))
        }
        let push = Dictionary(uniqueKeysWithValues: world.players.map { ($0.id, PlayerIntent(move: Vec2(1, 0))) })
        for _ in 0..<120 {
            world.step(intents: push)
            XCTAssertLessThanOrEqual(worstOverlap(world), slack, "overlap grew at tick \(world.tick)")
            XCTAssertTrue(
                world.players.allSatisfy { $0.location.x <= x + 1e-4 },
                "player escaped the wall at tick \(world.tick)")
        }
    }

    /// Six players arranged in a tight ring, all driven toward the ring centre:
    /// the crush must stay non-overlapping every tick.
    func testCrushedRingNeverOverlaps() {
        var world = World(seed: 12)
        let rating = Ratings(power: 50, speed: 50, endurance: 50)
        var ids: [EntityID] = []
        for i in 0..<6 {
            let angle = Float(i) * (.pi / 3)
            ids.append(
                world.spawn(
                    i % 2 == 0 ? .lt : .deL, ratings: rating, number: i,
                    at: Vec2(cos(angle) * 0.6, 40 + sin(angle) * 0.6)))
        }
        var intents: [EntityID: PlayerIntent] = [:]
        for (i, id) in ids.enumerated() {
            let angle = Float(i) * (.pi / 3)
            intents[id] = PlayerIntent(move: Vec2(-cos(angle), -sin(angle)))
        }
        for _ in 0..<60 {
            world.step(intents: intents)
            XCTAssertLessThanOrEqual(worstOverlap(world), slack, "overlap grew at tick \(world.tick)")
        }
    }
}
