import XCTest

@testable import CraftBowl

/// Smoke test for the app-target build graph and the `xcodebuild test` CI lane (#2).
/// Deliberately shallow: it proves the app scheme has a wired, runnable test target
/// on the iOS Simulator. Deeper journeys land with their own feature issues.
final class AppSmokeTests: XCTestCase {
    func testHUDStateDefaults() {
        let hud = HUDState()
        XCTAssertEqual(hud.homeScore, 0)
        XCTAssertEqual(hud.awayScore, 0)
        XCTAssertEqual(hud.quarter, 1)
        XCTAssertEqual(hud.clock, "5:00")
        XCTAssertEqual(hud.downDistance, "1ST & 10")
        XCTAssertFalse(hud.runner)
    }
}
