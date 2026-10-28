import CBCore
import CBPlays
import CBSim
import XCTest

@testable import CBGame

final class ExchangeTests: XCTestCase {
    private func start(_ route: RouteKind) throws -> Match {
        let loaded = try Playbook.loadBundled()
        var playbook = loaded.playbook
        // Make every deal card use this route; the fixture must not depend on RNG picking a play.
        for i in playbook.offense.indices {
            playbook.offense[i].slots[.backfield] = SlotAssignment(role: .target, route: route)
        }
        var match = Match(seed: 27, playbook: playbook, format: loaded.format)
        XCTAssertFalse(match.playChoices.isEmpty)
        match.step(input: TickInput(playSelect: 0), ai: [:])
        match.step(input: TickInput(buttons: .snap), ai: [:])
        return match
    }

    func testHandoffRequiresRunnerWithinExchangeWindow() throws {
        var match = try start(.handoff)
        let qb = try XCTUnwrap(match.world.player(at: .qb)?.id)
        let rb = try XCTUnwrap(match.world.player(at: .rb)?.id)
        match.step(input: TickInput(buttons: .handoff), ai: [:])
        XCTAssertEqual(match.world.ballCarrier, qb)
        XCTAssertFalse(match.runnerPhase)
        match.mutateWorld { $0[rb].location = $0[qb].location + Vec2(0, -1) }
        match.step(input: TickInput(buttons: .handoff), ai: [:])
        XCTAssertEqual(match.world.ballCarrier, rb)
        XCTAssertEqual(match.controlled, rb)
        XCTAssertTrue(match.runnerPhase)
    }

    func testTossUsesFlightAndLandsOnRunner() throws {
        var match = try start(.toss)
        let qb = try XCTUnwrap(match.world.player(at: .qb)?.id)
        let rb = try XCTUnwrap(match.world.player(at: .rb)?.id)
        match.mutateWorld { $0[rb].location = $0[qb].location + Vec2(-3, -2) }
        match.step(input: TickInput(buttons: .handoff), ai: [:])
        XCTAssertNil(match.world.ballCarrier)
        XCTAssertEqual(match.world.ballFlight?.target, rb)
        XCTAssertNil(match.controlled)
        for _ in 0..<60 where match.phase == .live && match.world.ballCarrier == nil {
            match.step(input: TickInput(), ai: [:])
        }
        XCTAssertEqual(match.world.ballCarrier, rb)
        XCTAssertTrue(match.runnerPhase)
        XCTAssertEqual(match.controlled, rb)
    }

    func testUnrecoveredBackwardTossExpiresAsTurnoverAtLandingSpot() throws {
        var match = try start(.toss)
        let qb = try XCTUnwrap(match.world.player(at: .qb)?.id)
        let rb = try XCTUnwrap(match.world.player(at: .rb)?.id)
        match.mutateWorld { $0[rb].location = $0[qb].location + Vec2(-3, -2) }
        match.step(input: TickInput(buttons: .handoff), ai: [:])
        let spot = try XCTUnwrap(match.world.ballFlight?.to)
        match.mutateWorld { world in
            for i in world.players.indices { world.players[i].location = Vec2(15, 80) }
        }
        for _ in 0..<150 where match.phase == .live { match.step(input: .none, ai: [:]) }
        XCTAssertEqual(match.lastOutcome, .fumble)
        XCTAssertEqual(match.world.ballLocation, spot)
        XCTAssertEqual(match.homeGame.stats.rushAttempts, 1)
        XCTAssertEqual(match.homeGame.stats.passAttempts, 0)
        XCTAssertEqual(match.homeGame.turnovers, 1)
        XCTAssertEqual(match.opponentDrive?.trigger, .fumble)
    }

    func testDefenseCanRecoverBackwardToss() throws {
        var match = try start(.toss)
        let qb = try XCTUnwrap(match.world.player(at: .qb)?.id)
        let rb = try XCTUnwrap(match.world.player(at: .rb)?.id)
        let defender = try XCTUnwrap(match.world.player(at: .mlb)?.id)
        match.mutateWorld { $0[rb].location = $0[qb].location + Vec2(-3, -2) }
        match.step(input: TickInput(buttons: .handoff), ai: [:])
        let spot = try XCTUnwrap(match.world.ballFlight?.to)
        match.mutateWorld { world in
            for i in world.players.indices { world.players[i].location = Vec2(15, 80) }
            world[defender].location = spot + Vec2(0, -0.9)
        }
        for _ in 0..<60 where match.phase == .live { match.step(input: .none, ai: [:]) }
        XCTAssertEqual(match.lastOutcome, .fumble)
        XCTAssertEqual(match.world.ballLocation, spot)
        XCTAssertEqual(match.homeGame.turnovers, 1)
        XCTAssertEqual(match.opponentDrive?.trigger, .fumble)
    }

    func testMissedBackwardTossCanBeRecoveredByOffense() throws {
        var match = try start(.toss)
        let qb = try XCTUnwrap(match.world.player(at: .qb)?.id)
        let rb = try XCTUnwrap(match.world.player(at: .rb)?.id)
        match.mutateWorld { $0[rb].location = $0[qb].location + Vec2(-3, -2) }
        match.step(input: TickInput(buttons: .handoff), ai: [:])
        let landing = try XCTUnwrap(match.world.ballFlight?.to)
        match.mutateWorld { world in
            for i in world.players.indices { world.players[i].location = Vec2(15, 80) }
            world[qb].location = landing + Vec2(0, -2)
        }
        for _ in 0..<60 where match.phase == .live && match.world.ballFlight != nil {
            match.step(input: .none, ai: [:])
        }
        XCTAssertEqual(match.phase, .live)
        XCTAssertEqual(match.world.ball, .loose(at: landing))
        match.mutateWorld { $0[qb].location = landing + Vec2(0, -0.9) }
        match.step(input: .none, ai: [:])
        XCTAssertEqual(match.world.ballCarrier, qb)
        XCTAssertEqual(match.controlled, qb)
        XCTAssertTrue(match.runnerPhase)
        XCTAssertEqual(match.homeGame.turnovers, 0)
    }

    func testForwardTossTargetWaitsForBackwardWindow() throws {
        var match = try start(.toss)
        let qb = try XCTUnwrap(match.world.player(at: .qb)?.id)
        let rb = try XCTUnwrap(match.world.player(at: .rb)?.id)
        match.mutateWorld { $0[rb].location = $0[qb].location + Vec2(-2, 3) }
        match.step(input: TickInput(buttons: .handoff), ai: [:])
        XCTAssertEqual(match.world.ballCarrier, qb)
        XCTAssertNil(match.world.ballFlight)
        XCTAssertEqual(match.controlled, qb)
    }
}
