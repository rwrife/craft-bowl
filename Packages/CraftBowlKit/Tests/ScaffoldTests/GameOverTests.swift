import CBCore
import CBPlays
import CBSim
import XCTest

@testable import CBGame

/// The final gun ends the game on a held final-score screen (no silent reset), both teams' box scores are
/// tracked all game, and a button press starts a rematch.
final class GameOverTests: XCTestCase {

    private func makeSim(seed: UInt64) throws -> GameSimulation {
        let loaded = try Playbook.loadBundled()
        return GameSimulation(seed: seed, playbook: loaded.playbook, format: loaded.format)
    }

    /// Snaps every play and has the QB hold the ball, so each snap ends in a sack.
    private func tickHoldingTheBall(_ sim: inout GameSimulation) {
        let m = sim.match
        if m.phase == .preSnap && !m.isShowingDriveRecap && m.phaseTicks == 5 {
            sim.tick(TickInput(buttons: [.snap], playSelect: 0))
        } else {
            sim.tick(.none)
        }
    }

    func testFinalGunHoldsTheFinalScoreUntilRematch() throws {
        var sim = try makeSim(seed: 11)
        sim.setGameClock(quarter: 4, clock: 0.3)
        var ticks = 0
        while !sim.match.isGameOver && ticks < 60 * 60 {
            tickHoldingTheBall(&sim)
            ticks += 1
        }
        XCTAssertTrue(sim.match.isGameOver, "the 4th quarter ending must end the game")
        XCTAssertNil(sim.match.opponentDrive, "no opposing possession is simulated after the final gun")
        XCTAssertEqual(sim.match.phase, .dead)
        let summary = sim.match.gameSummary
        XCTAssertEqual(summary.home.stats.plays, 1)
        XCTAssertEqual(summary.winner, .tie)

        // The final screen holds — no auto-snap, no score reset — and ignores an immediate button mash.
        for _ in 0..<(Match.autoSnapTicks * 2) { sim.tick(.none) }
        XCTAssertTrue(sim.match.isGameOver)
        XCTAssertEqual(sim.match.gameSummary, summary)
        XCTAssertEqual(sim.match.quarter, 4)

        sim.tick(TickInput(buttons: [.snap]))
        XCTAssertFalse(sim.match.isGameOver, "any button starts a rematch")
        XCTAssertEqual(sim.match.phase, .preSnap)
        XCTAssertEqual(sim.match.quarter, 1)
        XCTAssertEqual(sim.match.clock, Match.quarterSeconds)
        XCTAssertEqual(sim.match.homeScore, 0)
        XCTAssertEqual(sim.match.awayScore, 0)
        XCTAssertEqual(sim.match.homeGame, TeamGameStats())
        XCTAssertEqual(sim.match.awayGame, TeamGameStats())
    }

    func testRematchIgnoresButtonsRightAfterTheFinalGun() throws {
        var sim = try makeSim(seed: 12)
        sim.setGameClock(quarter: 4, clock: 0.3)
        var ticks = 0
        while !sim.match.isGameOver && ticks < 60 * 60 {
            tickHoldingTheBall(&sim)
            ticks += 1
        }
        XCTAssertTrue(sim.match.isGameOver)
        sim.tick(TickInput(buttons: [.snap]))
        XCTAssertTrue(sim.match.isGameOver, "a late button from the last play doesn't skip the final screen")
    }

    func testBoxScoresTrackBothTeams() throws {
        var sim = try makeSim(seed: 77)
        var outcomes: [PlayOutcome] = []
        var ticks = 0
        while sim.match.opponentDrive == nil && ticks < 60 * 200 {
            let wasLive = sim.match.phase == .live
            tickHoldingTheBall(&sim)
            if wasLive, sim.match.phase == .dead, let o = sim.match.lastOutcome { outcomes.append(o) }
            ticks += 1
        }
        let drive = try XCTUnwrap(sim.match.opponentDrive)
        XCTAssertEqual(drive.trigger, .downs)
        let home = sim.match.homeGame
        XCTAssertEqual(home.stats.plays, outcomes.count, "every user snap is in the box score")
        XCTAssertEqual(home.stats.sacks, outcomes.filter { $0 == .sack }.count)
        XCTAssertEqual(home.turnovers, 1, "turnover on downs")
        XCTAssertGreaterThan(home.seconds, 0)

        let away = sim.match.awayGame
        XCTAssertEqual(away.stats, drive.stats, "the opponent's totals are their simulated drives")
        XCTAssertEqual(away.seconds, drive.seconds, accuracy: 0.001)
        XCTAssertEqual(away.turnovers, drive.ending == .interception || drive.ending == .downs ? 1 : 0)
        if sim.match.quarter == 1 {
            XCTAssertEqual(
                home.seconds + away.seconds, Match.quarterSeconds - sim.match.clock, accuracy: 0.05,
                "time of possession adds up to the game clock used")
        }
    }

    /// The opponent's drive uses the last of the clock: their drive recap is shown first, then dismissing it
    /// ends the game.
    func testOpponentRunningOutTheClockShowsRecapThenFinal() throws {
        var found = false
        for seed in UInt64(1)...40 {
            var sim = try makeSim(seed: seed)
            sim.setGameClock(quarter: 4, clock: 16)
            var ticks = 0
            while sim.match.opponentDrive == nil && !sim.match.isGameOver && ticks < 60 * 120 {
                tickHoldingTheBall(&sim)
                ticks += 1
            }
            guard let drive = sim.match.opponentDrive, sim.match.quarter == 4, sim.match.clock <= 0 else { continue }
            found = true
            if drive.ending == .endOfGame { XCTAssertEqual(drive.resumeText, "THAT'S THE GAME") }
            for _ in 0...Match.deadBallTicks { sim.tick(.none) }
            XCTAssertTrue(sim.match.isShowingDriveRecap, "the recap still shows before the final screen")
            XCTAssertFalse(sim.match.isGameOver)
            for _ in 0..<Match.driveRecapMinTicks { sim.tick(.none) }
            sim.tick(TickInput(buttons: [.snap]))
            XCTAssertTrue(sim.match.isGameOver, "closing the end-of-game recap goes to the final screen")
            XCTAssertNil(sim.match.opponentDrive)
            break
        }
        XCTAssertTrue(found, "some seed should let the opponent run out the clock")
    }
}
