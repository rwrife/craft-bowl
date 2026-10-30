import CBCore
import CBPlays
import CBSim
import Foundation
import XCTest

@testable import CBGame

final class QuarterbackArmTests: XCTestCase {
    func testPowerChangesFlightSpeedThroughLivePassAction() throws {
        let weak = try flight(power: 1)
        let strong = try flight(power: 99)
        let weakSpeed = weak.from.distance(to: weak.to) / weak.duration
        let strongSpeed = strong.from.distance(to: strong.to) / strong.duration
        XCTAssertEqual(weakSpeed, 18, accuracy: 0.001)
        XCTAssertEqual(strongSpeed, 26, accuracy: 0.001)
        XCTAssertLessThan(strong.duration, weak.duration)
    }

    func testBundledArmCurveCanBeTunedAndLegacyJSONUsesDefault() throws {
        let ratings = Ratings(power: 99, speed: 50, endurance: 50)
        var curves = RatingCurves.loadBundled()
        XCTAssertEqual(curves.qbArm?.min, 18)
        XCTAssertEqual(curves.qbArm?.max, 26)
        curves.qbArm = QuarterbackArmCurve(min: 12, max: 30)
        XCTAssertEqual(curves.quarterbackPassSpeed(ratings), 30)
        curves.qbArm = nil  // Older serialized tuning resources omit the new field.
        XCTAssertEqual(curves.quarterbackPassSpeed(ratings), 26)

        let data = try JSONEncoder().encode(RatingCurves.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "qbArm")
        let legacy = try JSONDecoder().decode(RatingCurves.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(legacy.quarterbackPassSpeed(ratings), 26)
    }

    func testInvalidArmCurveFallsBackWithoutPoisoningFlight() {
        let ratings = Ratings(power: 50, speed: 50, endurance: 50)
        for arm in [
            QuarterbackArmCurve(min: 0, max: 26),
            QuarterbackArmCurve(min: 26, max: 18),
            QuarterbackArmCurve(min: .nan, max: 26),
            QuarterbackArmCurve(min: 18, max: .infinity),
        ] {
            var curves = RatingCurves.default
            curves.qbArm = arm
            XCTAssertEqual(curves.quarterbackPassSpeed(ratings), 22)
        }
    }

    func testMovingReceiverLeadVariesWithPassSpeed() throws {
        let loaded = try Playbook.loadBundled()
        var slowMatch = Match(seed: 42, playbook: loaded.playbook, format: loaded.format)
        slowMatch.setRoster(
            offense: [.qb: (Ratings(power: 1, speed: 50, endurance: 50, ability: 99), 12)],
            defense: [:])
        let choice = try XCTUnwrap(
            slowMatch.playChoices.firstIndex {
                slowMatch.playbook.offense[$0].qbActions.contains(.passLeft)
            })
        slowMatch.step(input: TickInput(playSelect: Int8(choice)), ai: [:])
        slowMatch.step(input: TickInput(buttons: .snap), ai: [:])

        // Drive the actual intent path to create non-zero receiver velocity before the pass.
        let target = try XCTUnwrap(slowMatch.world.player(at: .laneLeft)?.id)
        let run = PlayerIntent(move: Vec2(0, 1))
        for _ in 0..<30 { slowMatch.step(input: .none, ai: [target: run]) }
        XCTAssertGreaterThan(slowMatch.world[target].velocity.y, 2)
        var fastMatch = slowMatch
        fastMatch.setRoster(
            offense: [.qb: (Ratings(power: 99, speed: 50, endurance: 50, ability: 99), 12)],
            defense: [:])

        slowMatch.step(input: TickInput(buttons: .passLeft), ai: [target: run])
        fastMatch.step(input: TickInput(buttons: .passLeft), ai: [target: run])

        let slowFlight = try XCTUnwrap(slowMatch.world.ballFlight)
        let fastFlight = try XCTUnwrap(fastMatch.world.ballFlight)

        // Slower throw requires more downfield lead (larger destination y) to lead the moving receiver.
        XCTAssertGreaterThan(slowFlight.to.y, fastFlight.to.y)
    }

    func testSubnormalHostileTuningFallsBackInLiveMatch() throws {
        let loaded = try Playbook.loadBundled()
        var match = Match(seed: 42, playbook: loaded.playbook, format: loaded.format)
        match.setRoster(
            offense: [.qb: (Ratings(power: 50, speed: 50, endurance: 50, ability: 99), 12)],
            defense: [:])
        var curves = RatingCurves.default
        curves.qbArm = QuarterbackArmCurve(min: Float.leastNormalMagnitude, max: Float.leastNormalMagnitude)
        match.setCurves(curves)

        let choice = try XCTUnwrap(
            match.playChoices.firstIndex {
                match.playbook.offense[$0].qbActions.contains(.passLeft)
            })
        match.step(input: TickInput(playSelect: Int8(choice)), ai: [:])
        match.step(input: TickInput(buttons: .snap), ai: [:])
        match.step(input: TickInput(buttons: .passLeft), ai: [:])

        let flight = try XCTUnwrap(match.world.ballFlight)
        XCTAssertFalse(flight.to.x.isNaN)
        XCTAssertFalse(flight.to.y.isNaN)
        XCTAssertFalse(flight.duration.isNaN)
        XCTAssertFalse(flight.duration.isInfinite)
        let speed = flight.from.distance(to: flight.to) / flight.duration
        XCTAssertEqual(speed, 22.0, accuracy: 0.1)  // Default curve speed for 50 power QB
    }

    func testPressureWobblesLivePassWithoutChangingLandingOrToss() throws {
        let loaded = try Playbook.loadBundled()
        var clean = Match(seed: 42, playbook: loaded.playbook, format: loaded.format)
        let choice = try XCTUnwrap(
            clean.playChoices.firstIndex {
                clean.playbook.offense[$0].qbActions.contains(.passLeft)
            })
        clean.step(input: TickInput(playSelect: Int8(choice)), ai: [:])
        clean.step(input: TickInput(buttons: .snap), ai: [:])
        let qb = try XCTUnwrap(clean.world.player(at: .qb)?.id)
        let defender = try XCTUnwrap(clean.world.player(at: .mlb)?.id)
        clean.mutateWorld { $0[defender].location = $0[qb].location + Vec2(10, 0) }
        var pressured = clean
        pressured.mutateWorld { $0[defender].location = $0[qb].location + Vec2(1.8, 0) }
        clean.step(input: TickInput(buttons: .passLeft), ai: [:])
        pressured.step(input: TickInput(buttons: .passLeft), ai: [:])
        var calmFlight = try XCTUnwrap(clean.world.ballFlight)
        var wobbleFlight = try XCTUnwrap(pressured.world.ballFlight)
        XCTAssertEqual(calmFlight.wobble, 0)
        XCTAssertGreaterThan(wobbleFlight.wobble, 0)
        wobbleFlight.elapsed = 0
        XCTAssertEqual(wobbleFlight.groundPosition, wobbleFlight.from)
        let straight = wobbleFlight.from + (wobbleFlight.to - wobbleFlight.from) * 0.25
        calmFlight.elapsed = calmFlight.duration * 0.25
        wobbleFlight.elapsed = wobbleFlight.duration * 0.25
        XCTAssertEqual(calmFlight.groundPosition, calmFlight.from + (calmFlight.to - calmFlight.from) * 0.25)
        XCTAssertGreaterThan(wobbleFlight.groundPosition.distance(to: straight), 0.05)
        wobbleFlight.elapsed = wobbleFlight.duration
        XCTAssertEqual(wobbleFlight.groundPosition, wobbleFlight.to)
        var tossWorld = World(seed: 7)
        let carrier = tossWorld.spawn(.qb, ratings: Ratings(power: 50, speed: 50, endurance: 50), number: 1, at: .zero)
        tossWorld.ball = .held(by: carrier)
        tossWorld.throwBall(to: Vec2(2, -2), target: nil, speed: 14, peak: 0.35)
        XCTAssertEqual(tossWorld.ballFlight?.wobble, 0)
    }

    private func flight(power: Int) throws -> BallFlight {
        let loaded = try Playbook.loadBundled()
        var match = Match(seed: 42, playbook: loaded.playbook, format: loaded.format)
        match.setRoster(
            offense: [.qb: (Ratings(power: power, speed: 50, endurance: 50, ability: 99), 12)],
            defense: [:])
        let choice = try XCTUnwrap(
            match.playChoices.firstIndex {
                match.playbook.offense[$0].qbActions.contains(.passLeft)
            })
        match.step(input: TickInput(playSelect: Int8(choice)), ai: [:])
        match.step(input: TickInput(buttons: .snap), ai: [:])
        XCTAssertEqual(match.phase, .live)
        match.step(input: TickInput(buttons: .passLeft), ai: [:])
        return try XCTUnwrap(match.world.ballFlight)
    }
}
