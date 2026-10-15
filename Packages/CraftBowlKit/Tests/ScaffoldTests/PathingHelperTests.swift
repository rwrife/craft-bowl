import CBCore
import CBSim
import XCTest

/// Issue #25 acceptance slice: reusable arrive/pursue/avoid pathing helpers and
/// explicit out-of-bounds detection.
final class PathingHelperTests: XCTestCase {
    func testArriveFadesInsideSlowRadiusAndStopsAtTarget() {
        let arrive = Arrive(radius: 2)
        XCTAssertEqual(arrive.steer(from: Vec2(10, 40), to: Vec2(10, 50)), Vec2(0, 1))
        XCTAssertEqual(arrive.steer(from: Vec2(10, 49), to: Vec2(10, 50)), Vec2(0, 0.5))
        XCTAssertEqual(arrive.steer(from: Vec2(10, 49.5), to: Vec2(10, 50)), Vec2(0, 0.25))
        XCTAssertEqual(arrive.steer(from: Vec2(10, 50), to: Vec2(10, 50)), .zero)
        XCTAssertEqual(arrive.steer(remaining: 1, direction: Vec2(.infinity, 0)), .zero)
        XCTAssertEqual(arrive.steer(remaining: 1, direction: Vec2(.nan, 0)), .zero)
        XCTAssertEqual(arrive.steer(remaining: 0.25, direction: Vec2(0, 1)), .zero)
    }

    /// A hostile slow radius must not invert or scale steering (tuning JSON is hot-reloadable).
    func testArriveIgnoresNonPositiveSlowRadius() {
        for radius: Float in [-1, 0, .nan, .infinity] {
            XCTAssertEqual(Arrive(radius: radius).steer(from: Vec2(10, 49), to: Vec2(10, 50)), Vec2(0, 1))
        }
    }

    func testPursueLeadsMovingTargetProportionally() {
        let pursue = Pursue(arrive: Arrive(radius: 2), lookahead: 0.5)
        let from = Vec2(10, 45)
        let target = Vec2(10, 48)
        // Closing target: the lead point is near, so steering decelerates.
        XCTAssertEqual(pursue.steer(from: from, toward: target, velocity: .zero), Vec2(0, 1))
        XCTAssertEqual(pursue.steer(from: from, toward: target, velocity: Vec2(0, -4)), Vec2(0, 0.5))
        // Fleeing target: the lead point is further downfield, so steering stays full.
        XCTAssertEqual(pursue.steer(from: from, toward: target, velocity: Vec2(0, 4)), Vec2(0, 1))
    }

    func testPursueIgnoresNonFiniteLookahead() {
        let pursue = Pursue(arrive: Arrive(radius: 1), lookahead: .nan)
        XCTAssertEqual(pursue.steer(from: Vec2(10, 45), toward: Vec2(10, 50), velocity: Vec2(0, 3)), Vec2(0, 1))
    }

    func testAvoidSteersAroundBlockingPlayer() {
        let avoid = Avoid(clearance: World.playerRadius * 2, ahead: 2)
        // Dead-ahead blocker: deterministic rightward deflection at desired speed.
        let around = avoid.steer(from: Vec2(0, 40), desired: Vec2(0, 1), avoiding: [Vec2(0, 41)])
        XCTAssertGreaterThan(around.x, 0)
        XCTAssertEqual(around.length, 1, accuracy: 1e-6)
        let trapped = Avoid(clearance: 2, ahead: 2, maxDeflectionDegrees: 20)
        let fallback = trapped.steer(from: Vec2(0, 40), desired: Vec2(0, 1), avoiding: [Vec2(0, 40.5)])
        XCTAssertGreaterThan(fallback.x, 0)  // exhausted search must still choose right first
        // Explicit clearance 0.8, blocker 0.9 away: clearance is geometrically possible.
        // A 45-degree turn still clips the projected segment; require actual clearance.
        let corridor = Avoid(clearance: 0.8, ahead: 2)
        let near = corridor.steer(from: Vec2(0, 40), desired: Vec2(0, 1), avoiding: [Vec2(0, 40.9)])
        let along = max(0, min(2, (Vec2(0, 0.9) * near).sum()))
        let closest = Vec2(0, 0.9) - near * along
        XCTAssertGreaterThanOrEqual(closest.length, corridor.clearance)
        // No blocker inside the lookahead corridor leaves the desired direction alone.
        XCTAssertEqual(avoid.steer(from: Vec2(0, 40), desired: Vec2(0, 1), avoiding: [Vec2(0, 50)]), Vec2(0, 1))
        // A blocker ahead and east pushes the steering west.
        XCTAssertLessThan(avoid.steer(from: Vec2(0, 40), desired: Vec2(0, 1), avoiding: [Vec2(0.3, 41)]).x, 0)
    }

    func testAvoidRejectsNonFiniteInputs() {
        let avoid = Avoid(clearance: 1, ahead: 2)
        XCTAssertEqual(avoid.steer(from: Vec2(0, 40), desired: Vec2(0, 1), avoiding: [Vec2(.nan, 41)]), Vec2(0, 1))
        XCTAssertEqual(
            avoid.steer(from: Vec2(0, 40), desired: Vec2(0, 1), avoiding: [Vec2(.infinity, 41)]),
            Vec2(0, 1))
        XCTAssertEqual(avoid.steer(from: Vec2(0, 40), desired: Vec2(.infinity, 1), avoiding: [Vec2(0, 41)]), .zero)
        XCTAssertEqual(avoid.steer(from: Vec2(0, 40), desired: Vec2(0, 1), avoiding: [Vec2(.nan, .nan)]), Vec2(0, 1))
    }

    func testOutOfBoundsDetectionMatchesFieldBounds() {
        XCTAssertFalse(Field.isOutOfBounds(Vec2(0, 40)))
        XCTAssertFalse(Field.isOutOfBounds(Vec2(-Field.halfWidth, 40)))
        XCTAssertFalse(Field.isOutOfBounds(Vec2(0, Field.length)))
        XCTAssertTrue(Field.isOutOfBounds(Vec2(Field.halfWidth + 0.001, 40)))
        XCTAssertTrue(Field.isOutOfBounds(Vec2(-Field.halfWidth - 0.001, 40)))
        XCTAssertTrue(Field.isOutOfBounds(Vec2(0, -0.001)))
        XCTAssertTrue(Field.isOutOfBounds(Vec2(0, Field.length + 0.001)))
    }

    /// Invisible walls keep the player circle inside the sidelines, so a clamped position is
    /// always inside the wall box even though the sideline itself is out of bounds.
    func testWallClampKeepsPlayersInsideSidelines() {
        let clamped = Field.clampToWalls(Vec2(Field.halfWidth + 5, 40), radius: World.playerRadius)
        XCTAssertLessThanOrEqual(abs(clamped.x), Field.wallHalfWidth - World.playerRadius + 1e-6)
        XCTAssertTrue(Field.isOutOfBounds(clamped))
        XCTAssertEqual(clamped.x, Field.wallHalfWidth - World.playerRadius, accuracy: 1e-6)
    }
}
