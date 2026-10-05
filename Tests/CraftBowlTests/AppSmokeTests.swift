import CBAssets
import CBSim
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

    func testTeamOverallUsesWeightedRosterRating() {
        let roster = [
            PlayerProfile(
                id: .qb, name: "A", number: 1,
                ratings: Ratings(power: 90, speed: 90, endurance: 10, ability: 10)),
            PlayerProfile(
                id: .rb, name: "B", number: 2,
                ratings: Ratings(power: 90, speed: 90, endurance: 10, ability: 10)),
        ]
        let team = TeamDefinition(
            id: "test", city: "Test", nickname: "Team", abbreviation: "TST",
            uniform: .blue, roster: roster)
        XCTAssertEqual(team.overall, 58)  // 60% physical traits, 40% other traits
        XCTAssertEqual(team.overall, TeamRating.overall(roster.map(\.ratings)))
    }
}
