import CBCore
import CBPlays
import CBSim
import XCTest

@testable import CBGame

/// Game clock keeps running after in-bounds plays, the 10 s play clock (untimed on the first snap of each
/// half) with a loss-of-down delay-of-game penalty, and CPU drives burning clock between snaps.
final class GameClockTests: XCTestCase {

    private func makeSim(seed: UInt64) throws -> GameSimulation {
        let loaded = try Playbook.loadBundled()
        return GameSimulation(seed: seed, playbook: loaded.playbook, format: loaded.format)
    }

    /// Snaps once (QB holds the ball → sack, an in-bounds play) and ticks until the next pre-snap.
    private func runSackPlay(_ sim: inout GameSimulation) {
        sim.tick(TickInput(buttons: [.snap], playSelect: 0))
        var ticks = 0
        while sim.match.phase != .preSnap && ticks < 60 * 60 {
            sim.tick(.none)
            ticks += 1
        }
    }

    func testFirstSnapOfTheGameIsUntimed() throws {
        var sim = try makeSim(seed: 3)
        XCTAssertNil(sim.match.playClockRemaining)
        for _ in 0..<(Match.playClockTicks * 3) { sim.tick(.none) }
        XCTAssertEqual(sim.match.phase, .preSnap)
        XCTAssertEqual(sim.match.down, 1)
        XCTAssertEqual(sim.match.delayOfGamePenalties, 0)
        XCTAssertEqual(sim.match.clock, Match.quarterSeconds, "nothing runs the clock before the opening snap")
    }

    func testClockRunsAfterInBoundsPlayAndDelayOfGameCostsADown() throws {
        var sim = try makeSim(seed: 21)
        sim.tick(TickInput(buttons: [.snap], playSelect: 0))
        while sim.match.phase == .live { sim.tick(.none) }
        XCTAssertEqual(sim.match.lastOutcome, .sack)
        XCTAssertTrue(sim.match.isClockRunning, "a sack keeps the clock running")
        let atWhistle = sim.match.clock
        while sim.match.phase != .preSnap { sim.tick(.none) }
        XCTAssertLessThan(sim.match.clock, atWhistle - 2, "the clock runs through the dead-ball period")

        let remaining = try XCTUnwrap(sim.match.playClockRemaining)
        XCTAssertEqual(remaining, 10, accuracy: 0.05)
        let down = sim.match.down
        let los = sim.match.lineOfScrimmage
        let beforeClock = sim.match.clock
        for _ in 0..<Match.playClockTicks { sim.tick(.none) }
        XCTAssertEqual(sim.match.delayOfGamePenalties, 1)
        XCTAssertEqual(sim.match.down, down + 1, "loss of down")
        XCTAssertEqual(sim.match.lineOfScrimmage, los, "no yardage on the penalty")
        XCTAssertEqual(sim.match.phase, .preSnap)
        XCTAssertEqual(sim.match.clock, beforeClock - 10, accuracy: 0.1, "the clock ran while the user dawdled")
        XCTAssertTrue(sim.match.message.hasPrefix("DELAY OF GAME"))

        // The penalty stops the clock until the next snap.
        XCTAssertFalse(sim.match.isClockRunning)
        let stopped = sim.match.clock
        for _ in 0..<120 { sim.tick(.none) }
        XCTAssertEqual(sim.match.clock, stopped)
    }

    func testPickedPlayIsSnappedWhenThePlayClockExpires() throws {
        var sim = try makeSim(seed: 22)
        runSackPlay(&sim)
        sim.tick(TickInput(playSelect: 1))
        for _ in 0..<Match.playClockTicks where sim.match.phase == .preSnap { sim.tick(.none) }
        XCTAssertEqual(sim.match.phase, .live)
        XCTAssertEqual(sim.match.delayOfGamePenalties, 0)
    }

    func testDelayOfGameOnFourthDownTurnsItOver() throws {
        var sim = try makeSim(seed: 23)
        for _ in 0..<3 { runSackPlay(&sim) }
        XCTAssertEqual(sim.match.down, 4)
        let userYard = Int((sim.match.lineOfScrimmage - Field.ownGoalLine).rounded())
        for _ in 0..<Match.playClockTicks where sim.match.opponentDrive == nil { sim.tick(.none) }
        let drive = try XCTUnwrap(sim.match.opponentDrive)
        XCTAssertEqual(drive.trigger, .downs)
        XCTAssertEqual(drive.startYard, 100 - userYard, "the opponent takes over at the spot")
        XCTAssertEqual(sim.match.homeGame.turnovers, 1)
    }

    func testSecondHalfOpensWithAnUntimedSnap() throws {
        var sim = try makeSim(seed: 24)
        runSackPlay(&sim)
        sim.setGameClock(quarter: 2, clock: 0.2)
        runSackPlay(&sim)
        XCTAssertEqual(sim.match.quarter, 3)
        XCTAssertEqual(sim.match.clock, Match.quarterSeconds)
        XCTAssertNil(sim.match.playClockRemaining, "no play clock on the first snap of the half")
        for _ in 0..<(Match.playClockTicks * 2) { sim.tick(.none) }
        XCTAssertEqual(sim.match.delayOfGamePenalties, 0)
        XCTAssertEqual(sim.match.clock, Match.quarterSeconds)
    }

    func testOpponentDrivesBurnClockBetweenSnaps() throws {
        let loaded = try Playbook.loadBundled()
        var totalSeconds: Float = 0
        var totalPlays = 0
        for seed in UInt64(1)...20 {
            var sim = OpponentDriveSimulator(
                seed: seed, playbook: loaded.playbook, format: loaded.format, curves: .default,
                offense: [:], defense: [:])
            let r = sim.run(
                team: "TEST", trigger: .touchdown, startLine: 35, quarter: 1, clock: Match.quarterSeconds,
                scoreDelta: 0)
            let d = r.drive
            XCTAssertEqual(d.startQuarter, 1)
            XCTAssertEqual(d.startClock, Match.quarterSeconds)
            XCTAssertEqual(d.endQuarter, r.quarter)
            XCTAssertEqual(d.endClock, r.clock)
            if d.endQuarter == 1 {
                XCTAssertEqual(d.endClock, Match.quarterSeconds - d.seconds, accuracy: 0.01)
            }
            totalSeconds += d.seconds
            totalPlays += d.plays
        }
        XCTAssertGreaterThan(totalSeconds / Float(totalPlays), 6, "huddle + play clock time is run off between snaps")
    }
}
