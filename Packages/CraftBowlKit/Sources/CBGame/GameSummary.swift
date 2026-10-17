import Foundation

/// One team's whole-game numbers: the passing / rushing box score plus turnovers and time of possession.
public struct TeamGameStats: Sendable, Equatable {
    public var stats = DriveStats()
    /// Interceptions thrown plus turnovers on downs.
    public var turnovers = 0
    /// Game clock used while this team had the ball.
    public var seconds: Float = 0

    public init() {}

    public var timeOfPossession: String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Final box score for both teams, shown once the clock runs out in the 4th quarter.
public struct GameSummary: Sendable, Equatable {
    public enum Winner: Sendable, Equatable { case home, away, tie }

    public var homeScore: Int
    public var awayScore: Int
    public var home: TeamGameStats
    public var away: TeamGameStats

    public init(homeScore: Int, awayScore: Int, home: TeamGameStats, away: TeamGameStats) {
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.home = home
        self.away = away
    }

    public var winner: Winner {
        homeScore == awayScore ? .tie : (homeScore > awayScore ? .home : .away)
    }
}
