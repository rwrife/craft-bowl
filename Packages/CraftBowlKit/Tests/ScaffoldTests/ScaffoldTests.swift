import CBGame
import CBPlays
import XCTest

final class ScaffoldTests: XCTestCase {
    func testBundledPlaybookLoadsAndSimulationTicks() throws {
        let loaded = try Playbook.loadBundled()

        XCTAssertEqual(loaded.format.playersPerSide, 9)
        XCTAssertFalse(loaded.playbook.offense.isEmpty)
        XCTAssertFalse(loaded.playbook.defense.isEmpty)

        var sim = GameSimulation(seed: 42, playbook: loaded.playbook, format: loaded.format)
        XCTAssertEqual(sim.world.tick, 0)

        sim.tick(.none)
        XCTAssertEqual(sim.world.tick, 1)
    }
}
