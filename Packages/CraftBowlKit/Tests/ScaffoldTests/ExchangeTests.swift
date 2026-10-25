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

    func testTossMissingRunnerDoesNotTeleportBall() throws {
        var match = try start(.toss)
        let qb = try XCTUnwrap(match.world.player(at: .qb)?.id)
        let rb = try XCTUnwrap(match.world.player(at: .rb)?.id)
        match.mutateWorld { $0[rb].location = $0[qb].location + Vec2(-3, -2) }
        match.step(input: TickInput(buttons: .handoff), ai: [:])
        match.mutateWorld { $0[rb].location = Vec2(15, 60) }
        for _ in 0..<60 where match.phase == .live && match.world.ballCarrier == nil {
            match.step(input: TickInput(), ai: [:])
        }
        XCTAssertNotEqual(match.world.ballCarrier, rb)
        XCTAssertEqual(match.lastOutcome, .missedToss)
        XCTAssertEqual(match.homeGame.stats.rushAttempts, 1)
        XCTAssertEqual(match.homeGame.stats.passAttempts, 0)
        let spot = match.world.ballLocation.y.rounded()
        XCTAssertLessThan(spot, 35)
        for _ in 0...Match.deadBallTicks { match.step(input: .none, ai: [:]) }
        XCTAssertEqual(match.lineOfScrimmage, spot)
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
