import CBCore
import CBPlays
import CBSim
import XCTest

@testable import CBGame

final class BigHitFumbleTests: XCTestCase {
    private func liveMatch(chance: Float) throws -> Match {
        let loaded = try Playbook.loadBundled()
        var curves = RatingCurves.default
        curves.bigHitFumbleChance = chance
        var match = Match(seed: 27, playbook: loaded.playbook, format: loaded.format, curves: curves)
        match.step(input: TickInput(playSelect: 0), ai: [:])
        match.step(input: TickInput(buttons: .snap), ai: [:])
        return match
    }

    private func placeContact(_ match: inout Match, diving: Bool) throws {
        let qb = try XCTUnwrap(match.world.player(at: .qb)?.id)
        let defender = try XCTUnwrap(match.world.player(at: .mlb)?.id)
        match.mutateWorld { world in
            world[qb].ratings = Ratings(power: 1, speed: 1, endurance: 50)
            world[defender].ratings = Ratings(power: 99, speed: 50, endurance: 50)
            world[defender].location = world[qb].location + Vec2(0, 0.85)
            if diving { world[defender].diveTicks = 8 }
        }
    }

    func testBigHitForcedFumbleTurnsBallOverAndRecordsRush() throws {
        var match = try liveMatch(chance: 1)
        try placeContact(&match, diving: true)
        match.resolveCarrierContact()
        XCTAssertEqual(match.lastOutcome, .fumble)
        XCTAssertEqual(match.phase, .dead)
        XCTAssertNil(match.world.ballCarrier)
        XCTAssertEqual(match.homeGame.turnovers, 1)
        XCTAssertEqual(match.homeGame.stats.rushAttempts, 1)
        XCTAssertEqual(match.homeGame.stats.interceptions, 0)
        XCTAssertEqual(match.opponentDrive?.trigger, .fumble)
    }

    func testNormalTackleCannotFumbleEvenWhenConfiguredToAlwaysFumble() throws {
        var match = try liveMatch(chance: 1)
        try placeContact(&match, diving: false)
        match.resolveCarrierContact()
        XCTAssertNotEqual(match.lastOutcome, .fumble)
    }

    func testZeroFumbleChancePreservesBigHitTackle() throws {
        var match = try liveMatch(chance: 0)
        try placeContact(&match, diving: true)
        match.resolveCarrierContact()
        XCTAssertEqual(match.lastOutcome, .sack)
        XCTAssertEqual(match.homeGame.turnovers, 0)
    }

    func testReceiverCatchFumbleRecordsPassCompletionAndTurnover() throws {
        var match = try liveMatch(chance: 1)
        let wr = try XCTUnwrap(match.world.player(at: .laneLeft)?.id)
        let cb = try XCTUnwrap(match.world.player(at: .cbL)?.id)
        match.mutateWorld { world in
            world[wr].ratings = Ratings(power: 1, speed: 50, endurance: 50)
            world[cb].ratings = Ratings(power: 99, speed: 50, endurance: 50)
            world.ball = .held(by: wr)
            world[cb].location = world[wr].location + Vec2(0, 0.85)
            world[cb].diveTicks = 8
        }
        // Force the play to have been thrown and caught.
        match.markPlayCaughtForTesting()
        match.step(input: TickInput(), ai: [:])
        XCTAssertEqual(match.lastOutcome, .fumble)
        XCTAssertEqual(match.homeGame.turnovers, 1)
        XCTAssertEqual(match.homeGame.stats.passAttempts, 1)
        XCTAssertEqual(match.homeGame.stats.completions, 1)
        XCTAssertEqual(match.homeGame.stats.rushAttempts, 0)
    }

    func testLegacyAndInvalidFumbleTuningUseSafeFallback() throws {
        var curves = RatingCurves.default
        XCTAssertNil(curves.bigHitFumbleChance)
        XCTAssertEqual(curves.fumbleChance(), 0.02)
        for bad: Float in [-0.1, 1.1, .nan, .infinity] {
            curves.bigHitFumbleChance = bad
            XCTAssertEqual(curves.fumbleChance(), 0.02)
        }
        curves.bigHitFumbleChance = 0.5
        XCTAssertEqual(curves.fumbleChance(), 0.5)
        let encoded = try JSONEncoder().encode(RatingCurves.default)
        let legacy = try JSONDecoder().decode(RatingCurves.self, from: encoded)
        XCTAssertEqual(legacy.fumbleChance(), 0.02)
    }

    func testOpponentDriveFumbleIncrementsAwayTurnovers() throws {
        var match = try liveMatch(chance: 0)
        let drive = OpponentDrive(
            team: "OPPONENT", trigger: .fumble, ending: .fumble, plays: 2, yards: 5, points: 0, seconds: 12,
            startYard: 35, endYard: 40)
        let result = OpponentDriveSimulator.Result(
            drive: drive, userLineOfScrimmage: 40, opponentPoints: 0, userPoints: 0, quarter: 1, clock: 100)
        match.recordOpponentDriveResultForTesting(result)
        XCTAssertEqual(match.awayGame.turnovers, 1)
    }
}
