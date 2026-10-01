import CBCore
import CBGame
import CBPlays
import CBSim
import XCTest

/// Issue #3 acceptance: replay determinism and headless sim execution.
///
/// The simulation is seeded and deterministic; the renderer interpolates between ticks.
/// These tests prove that (1) a recorded input stream replays bit-identically,
/// (2) the checksum actually detects divergence, and (3) the sim runs headlessly
/// for thousands of ticks without a device or GPU.
final class ReplayDeterminismTests: XCTestCase {

    /// Replaying a recorded input stream reproduces identical positions and checksum.
    func testReplayReproducesIdenticalPositions() throws {
        let loaded = try Playbook.loadBundled()
        var sim = GameSimulation(seed: 1234, playbook: loaded.playbook, format: loaded.format)
        var recording = InputRecording(start: sim)

        let inputs = Self.driveInputs()
        for input in inputs {
            sim.tick(input)
            recording.append(input, resultingChecksum: sim.world.checksum)
        }

        XCTAssertEqual(recording.tickCount, inputs.count)

        let (replayed, matches) = recording.replay()
        XCTAssertTrue(matches, "replay must reproduce the recorded checksum")
        XCTAssertEqual(replayed.world.checksum, sim.world.checksum)
        XCTAssertEqual(
            replayed.world.players.map(\.location),
            sim.world.players.map(\.location),
            "replayed player positions must match the recording exactly")

        // Sanity: the drive actually moved players (otherwise determinism is vacuous).
        let startPositions = recording.start.world.players.map(\.location)
        XCTAssertNotEqual(
            sim.world.players.map(\.location), startPositions,
            "the input stream must change the world state")
    }

    /// Two runs of the same seed with different inputs must diverge, proving the
    /// checksum isn't trivially constant (guards the replay test above against
    /// both replays silently being the same static pre-snap state).
    func testDifferentInputsProduceDifferentChecksum() throws {
        let loaded = try Playbook.loadBundled()
        var driven = GameSimulation(seed: 99, playbook: loaded.playbook, format: loaded.format)
        var idle = GameSimulation(seed: 99, playbook: loaded.playbook, format: loaded.format)

        let inputs = Self.driveInputs()
        for input in inputs {
            driven.tick(input)
            idle.tick(.none)
        }
        XCTAssertEqual(driven.world.tick, idle.world.tick)
        XCTAssertNotEqual(
            driven.world.checksum, idle.world.checksum,
            "a recorded drive and an idle run of the same seed must not collapse to one checksum")
    }

    /// The sim must run headless for many ticks without a device (no UIKit/Metal in the loop).
    func testSimRunsHeadlessForThousandsOfTicks() throws {
        let loaded = try Playbook.loadBundled()
        var sim = GameSimulation(seed: 42, playbook: loaded.playbook, format: loaded.format)
        let startTick = sim.world.tick
        for _ in 0..<60 * 60 { sim.tick(.none) }
        XCTAssertEqual(sim.world.tick, startTick + 60 * 60)
    }

    /// A deterministic drive: pick a play card, snap, then run the ball carrier.
    static func driveInputs() -> [TickInput] {
        var inputs: [TickInput] = []
        inputs.append(TickInput(playSelect: 0))
        inputs.append(TickInput(buttons: .snap))
        for i in 0..<240 {
            let dive: TickInput.Buttons = i == 90 ? .dive : []
            inputs.append(TickInput(move: Vec2(0.4, 1.0), turbo: i % 30 < 15, buttons: dive))
        }
        return inputs
    }
}
