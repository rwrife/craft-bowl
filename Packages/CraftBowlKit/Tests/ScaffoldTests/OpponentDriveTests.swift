import CBCore
import CBPlays
import CBSim
import XCTest

@testable import CBGame

/// The opposing possession is played out snap by snap on the real engine, and field position carries
/// across the change of possession in both directions.
final class OpponentDriveTests: XCTestCase {

    private func simulate(seed: UInt64, start: Float = 35, clock: Float = Match.quarterSeconds)
        throws -> OpponentDriveSimulator.Result
    {
        let loaded = try Playbook.loadBundled()
        var sim = OpponentDriveSimulator(
            seed: seed, playbook: loaded.playbook, format: loaded.format, curves: .default,
            offense: [:], defense: [:])
        return sim.run(team: "TEST", trigger: .touchdown, startLine: start, quarter: 1, clock: clock, scoreDelta: 0)
    }

    func testDrivesAreSimulatedPlayByPlayWithConsistentStats() throws {
        var endings: Set<String> = []
        var passAttempts = 0
        var rushAttempts = 0
        for seed in UInt64(1)...30 {
            let r = try simulate(seed: seed)
            let d = r.drive
            let s = d.stats
            endings.insert(d.ending.rawValue)
            passAttempts += s.passAttempts
            rushAttempts += s.rushAttempts
            XCTAssertGreaterThan(d.plays, 0)
            XCTAssertEqual(d.playByPlay.count, d.plays, "one log line per snap or kick")
            XCTAssertLessThanOrEqual(s.completions, s.passAttempts)
            XCTAssertLessThanOrEqual(s.interceptions, s.passAttempts - s.completions)
            XCTAssertEqual(d.startYard, 25, "kickoff drives start at the opponent's own 25")
            XCTAssertTrue((1...99).contains(d.resumeYard))
            XCTAssertEqual(r.userLineOfScrimmage, Field.ownGoalLine + Float(d.resumeYard))
            switch d.ending {
            case .touchdown:
                XCTAssertEqual(d.points, 7)
                XCTAssertEqual(d.resumeYard, 25, "the user receives the kickoff at their own 25")
                XCTAssertEqual(s.passTouchdowns + s.rushTouchdowns, 1)
            case .fieldGoal:
                XCTAssertEqual(d.points, 3)
                XCTAssertEqual(d.resumeYard, 25)
            case .downs:
                XCTAssertEqual(d.points, 0)
                XCTAssertEqual(d.resumeYard, 100 - d.endYard, "the user takes over where the drive died")
            default:
                break
            }
        }
        XCTAssertGreaterThan(passAttempts, 0)
        XCTAssertGreaterThan(rushAttempts, 0)
        XCTAssertGreaterThan(endings.count, 1, "different seeds must produce different drives")
    }

    func testDriveSimulationIsDeterministic() throws {
        let a = try simulate(seed: 99)
        let b = try simulate(seed: 99)
        XCTAssertEqual(a.drive, b.drive)
        XCTAssertEqual(a.userLineOfScrimmage, b.userLineOfScrimmage)
    }

    func testDriveRunsOffTheClock() throws {
        let r = try simulate(seed: 5, clock: 20)
        XCTAssertGreaterThan(r.drive.seconds, 0)
        XCTAssertTrue(r.quarter == 2 || r.clock < 20, "the drive must spend game clock")
    }

    /// Four straight sacks: the opponent takes over at the spot of the last play, and the user resumes
    /// wherever the simulated drive ended.
    func testTurnoverOnDownsHandsOverAtTheSpot() throws {
        let loaded = try Playbook.loadBundled()
        var sim = GameSimulation(seed: 77, playbook: loaded.playbook, format: loaded.format)
        var lastSpot: Float = 0
        var ticks = 0
        while sim.match.opponentDrive == nil && ticks < 60 * 200 {
            let m = sim.match
            var input = TickInput()
            if m.phase == .preSnap && m.phaseTicks == 5 { input = TickInput(buttons: [.snap], playSelect: 0) }
            // The QB holds the ball and never throws, so every play ends in a sack behind the line.
            let wasLive = m.phase == .live
            sim.tick(input)
            if wasLive, sim.match.phase == .dead, case .dead(let at) = sim.world.ball { lastSpot = at.y }
            ticks += 1
        }
        let drive = try XCTUnwrap(sim.match.opponentDrive, "the user should turn it over on downs")
        XCTAssertEqual(drive.trigger, .downs)
        let userYard = Int(clamp(lastSpot.rounded(), Field.ownGoalLine + 1, Field.goalLine - 1) - Field.ownGoalLine)
        XCTAssertEqual(drive.startYard, 100 - userYard, "the opponent starts where the user's drive ended")

        // After the whistle the formation resets at the user's new spot, and the recap holds the play clock.
        for _ in 0...Match.deadBallTicks { sim.tick(.none) }
        XCTAssertTrue(sim.match.isShowingDriveRecap || drive.ending == .endOfGame)
        if sim.match.isShowingDriveRecap {
            XCTAssertEqual(sim.match.lineOfScrimmage, Field.ownGoalLine + Float(drive.resumeYard))
            for _ in 0..<(Match.autoSnapTicks + 10) { sim.tick(.none) }
            XCTAssertEqual(sim.match.phase, .preSnap, "no auto-snap while the recap is up")
            sim.tick(TickInput(buttons: [.snap]))
            XCTAssertNil(sim.match.opponentDrive, "any button dismisses the recap")
            XCTAssertEqual(sim.match.phase, .preSnap, "dismissing doesn't snap the ball")
        }
    }
}
