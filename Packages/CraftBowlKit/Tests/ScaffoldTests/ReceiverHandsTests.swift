import CBCore
import CBGame
import CBPlays
import CBSim
import Foundation
import XCTest

/// Bounded #24 slice: tunable Ability-derived receiver hands in the live catch path
/// (`Match.resolveCatch`), matching the QB accuracy pattern.
final class ReceiverHandsTests: XCTestCase {
    func testTunedHandsChangeLiveCatchOutcomes() throws {
        let loaded = try Playbook.loadBundled()
        var sure = RatingCurves.default
        sure.receiverHandsMin = 1
        sure.receiverHandsMax = 1
        // Ignoring the curve in the live path makes both totals identical.
        let baseline = try catches(loaded, curves: .default)
        let tuned = try catches(loaded, curves: sure)
        XCTAssertGreaterThan(tuned, baseline)
    }

    func testHandsCurveIsBoundedAndLegacyTuningFallsBack() throws {
        var curves = RatingCurves.loadBundled()
        let low = Ratings(power: 50, speed: 50, endurance: 50, ability: 1)
        let high = Ratings(power: 50, speed: 50, endurance: 50, ability: 99)
        XCTAssertEqual(curves.receiverHandsMin, 0)
        XCTAssertEqual(curves.receiverHandsMax, 1)
        XCTAssertEqual(curves.receiverHands(low), 0, accuracy: 0.001)
        XCTAssertEqual(curves.receiverHands(high), 1, accuracy: 0.001)

        curves.receiverHandsMin = 0.2
        curves.receiverHandsMax = 0.8
        XCTAssertEqual(curves.receiverHands(low), 0.2, accuracy: 0.001)
        XCTAssertEqual(curves.receiverHands(high), 0.8, accuracy: 0.001)

        for bounds: (Float, Float) in [(-0.1, 0.8), (0.2, 1.1), (0.8, 0.2), (.nan, 0.8), (0.2, .infinity)] {
            curves.receiverHandsMin = bounds.0
            curves.receiverHandsMax = bounds.1
            XCTAssertEqual(curves.receiverHands(low), 0, accuracy: 0.001)
            XCTAssertEqual(curves.receiverHands(high), 1, accuracy: 0.001)
        }

        let encoded = try JSONEncoder().encode(RatingCurves.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "receiverHandsMin")
        object.removeValue(forKey: "receiverHandsMax")
        let legacy = try JSONDecoder().decode(
            RatingCurves.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.receiverHandsMin)
        XCTAssertNil(legacy.receiverHandsMax)
        let middle = Ratings(power: 50, speed: 50, endurance: 50, ability: 50)
        XCTAssertEqual(legacy.receiverHands(middle), middle.a, accuracy: 0.001)
    }

    /// Completed catches across seeds for a weak-handed left-lane receiver.
    private func catches(_ loaded: (format: TeamFormat, playbook: Playbook), curves: RatingCurves) throws -> Int {
        var total = 0
        for seed in 1...80 {
            var match = Match(seed: UInt64(seed), playbook: loaded.playbook, format: loaded.format, curves: curves)
            match.setRoster(
                offense: [
                    .qb: (Ratings(power: 50, speed: 50, endurance: 50, ability: 99), 12),
                    .laneLeft: (Ratings(power: 50, speed: 50, endurance: 50, ability: 1), 80),
                ],
                defense: [:])
            let choice = try XCTUnwrap(
                match.playChoices.firstIndex {
                    loaded.playbook.offense[$0].qbActions.contains(.passLeft)
                })
            match.step(input: TickInput(playSelect: Int8(choice)), ai: [:])
            match.step(input: TickInput(buttons: .snap), ai: [:])
            match.step(input: TickInput(buttons: .passLeft), ai: [:])
            let receiver = try XCTUnwrap(match.world.player(at: .laneLeft)?.id)
            var arrived = false
            for _ in 0..<600 {
                match.step(input: .none, ai: [:])
                if match.world.events.contains(where: {
                    if case .ballArrived = $0 { return true }
                    return false
                }) {
                    arrived = true
                    break
                }
                if match.phase != .live { break }
            }
            XCTAssertTrue(arrived, "seed \(seed) never reached receiver")
            if match.world.ballCarrier == receiver { total += 1 }
        }
        return total
    }
}
