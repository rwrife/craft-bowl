import CBCore
import CBGame
import CBPlays
import CBSim
import Foundation
import XCTest

final class QuarterbackAccuracyTests: XCTestCase {
    func testTunedAccuracyChangesLivePassAim() throws {
        let loaded = try Playbook.loadBundled()
        var match = Match(seed: 42, playbook: loaded.playbook, format: loaded.format)
        match.setRoster(
            offense: [.qb: (Ratings(power: 50, speed: 50, endurance: 50, ability: 1), 12)],
            defense: [:])
        let choice = try XCTUnwrap(
            match.playChoices.firstIndex { loaded.playbook.offense[$0].qbActions.contains(.passLeft) })
        match.step(input: TickInput(playSelect: Int8(choice)), ai: [:])
        match.step(input: TickInput(buttons: .snap), ai: [:])
        let target = try XCTUnwrap(match.world.player(at: .laneLeft)?.location)
        var accurate = match
        var curves = RatingCurves.default
        curves.qbAccuracyMin = 1
        curves.qbAccuracyMax = 1
        accurate.setCurves(curves)
        match.step(input: TickInput(buttons: .passLeft), ai: [:])
        accurate.step(input: TickInput(buttons: .passLeft), ai: [:])
        let baseline = try XCTUnwrap(match.world.ballFlight)
        let tuned = try XCTUnwrap(accurate.world.ballFlight)
        XCTAssertGreaterThan(baseline.to.distance(to: target), 0.01)
        XCTAssertEqual(tuned.to.distance(to: target), 0, accuracy: 0.001)
    }

    func testAccuracyCurveIsBoundedAndLegacyTuningFallsBack() throws {
        var curves = RatingCurves.loadBundled()
        let low = Ratings(power: 50, speed: 50, endurance: 50, ability: 1)
        let high = Ratings(power: 50, speed: 50, endurance: 50, ability: 99)
        XCTAssertEqual(curves.quarterbackAccuracy(low), 0, accuracy: 0.001)
        XCTAssertEqual(curves.quarterbackAccuracy(high), 1, accuracy: 0.001)

        curves.qbAccuracyMin = 0.2
        curves.qbAccuracyMax = 0.8
        XCTAssertEqual(curves.quarterbackAccuracy(low), 0.2, accuracy: 0.001)
        XCTAssertEqual(curves.quarterbackAccuracy(high), 0.8, accuracy: 0.001)

        for bounds: (Float, Float) in [(-0.1, 0.8), (0.2, 1.1), (0.8, 0.2), (.nan, 0.8), (0.2, .infinity)] {
            curves.qbAccuracyMin = bounds.0
            curves.qbAccuracyMax = bounds.1
            XCTAssertEqual(curves.quarterbackAccuracy(low), 0, accuracy: 0.001)
            XCTAssertEqual(curves.quarterbackAccuracy(high), 1, accuracy: 0.001)
        }

        let encoded = try JSONEncoder().encode(RatingCurves.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "qbAccuracyMin")
        object.removeValue(forKey: "qbAccuracyMax")
        let legacy = try JSONDecoder().decode(
            RatingCurves.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.qbAccuracyMin)
        XCTAssertNil(legacy.qbAccuracyMax)
        XCTAssertEqual(legacy.quarterbackAccuracy(low), 0, accuracy: 0.001)
        let middle = Ratings(power: 50, speed: 50, endurance: 50, ability: 50)
        XCTAssertEqual(legacy.quarterbackAccuracy(middle), middle.a, accuracy: 0.001)
        XCTAssertEqual(legacy.quarterbackAccuracy(high), 1, accuracy: 0.001)
    }

    func testBundledRatingsHasAccuracyKeys() {
        let curves = RatingCurves.loadBundled()
        XCTAssertEqual(curves.qbAccuracyMin, 0)
        XCTAssertEqual(curves.qbAccuracyMax, 1)
    }
}
