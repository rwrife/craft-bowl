import CBCore
import CBPlays
import CBSim
import XCTest

@testable import CBGame

final class DefenderSwatTests: XCTestCase {
    private let spot = Vec2(3, 55)

    private func livePass() throws -> (Match, EntityID, EntityID) {
        let loaded = try Playbook.loadBundled()
        var match = Match(seed: 27, playbook: loaded.playbook, format: loaded.format)
        let choice = try XCTUnwrap(
            match.playChoices.firstIndex {
                loaded.playbook.offense[$0].qbActions.contains(.passLeft)
            })
        match.step(input: TickInput(playSelect: Int8(choice)), ai: [:])
        match.step(input: TickInput(buttons: .snap), ai: [:])
        match.step(input: TickInput(buttons: .passLeft), ai: [:])
        let receiver = try XCTUnwrap(match.world.player(at: .laneLeft)?.id)
        let defender = try XCTUnwrap(match.world.player(at: .cbL)?.id)
        return (match, receiver, defender)
    }

    func testDivingDefenderSwatsBallEvenWhenReceiverIsCloser() throws {
        var (match, receiver, defender) = try livePass()
        match.mutateWorld { world in
            world[receiver].location = spot + Vec2(0.2, 0)
            world[defender].location = spot + Vec2(0, -1.05)
            world.startDive(defender)
        }
        match.resolveCatch(at: spot, target: receiver)
        XCTAssertEqual(match.lastOutcome, .incomplete)
        XCTAssertEqual(match.message, "SWATTED!")
        XCTAssertNil(match.world.ballCarrier)
        XCTAssertEqual(match.homeGame.stats.passAttempts, 1)
        XCTAssertEqual(match.homeGame.turnovers, 0)
    }

    func testDivingDefenderCanSwatBehindCloserStandingDefender() throws {
        var (match, receiver, defender) = try livePass()
        let standing = try XCTUnwrap(match.world.player(at: .cbR)?.id)
        match.mutateWorld { world in
            world[receiver].location = spot + Vec2(0.2, 0)
            world[standing].location = spot + Vec2(0, -0.6)
            world[defender].location = spot + Vec2(0, -1.4)
            world.startDive(defender)
        }
        match.resolveCatch(at: spot, target: receiver)
        XCTAssertEqual(match.lastOutcome, .incomplete)
        XCTAssertEqual(match.message, "SWATTED!")
    }

    func testDistantDiveDoesNotSwat() throws {
        var (match, receiver, defender) = try livePass()
        match.mutateWorld { world in
            world[receiver].location = spot + Vec2(0.2, 0)
            world[defender].location = spot + Vec2(0, -3)
            world.startDive(defender)
        }
        match.resolveCatch(at: spot, target: receiver)
        XCTAssertNotEqual(match.message, "SWATTED!")
    }

    func testLiveFlightArrivalUsesDivingSwat() throws {
        var (match, receiver, defender) = try livePass()
        match.mutateWorld { world in
            for i in world.players.indices { world.players[i].location = Vec2(15, 80) }
            world[receiver].location = spot + Vec2(0.2, 0)
            world[defender].location = spot + Vec2(0, -1.05)
            world.startDive(defender)
            world[defender].velocity = .zero
            world.ball = .held(by: receiver)
            world.throwBall(to: spot, target: receiver, speed: 100, peak: 0.4)
        }
        for _ in 0..<15 where match.phase == .live { match.step(input: .none, ai: [:]) }
        XCTAssertEqual(match.lastOutcome, .incomplete)
        XCTAssertEqual(match.message, "SWATTED!")
        XCTAssertEqual(match.phase, .dead)
    }
}
