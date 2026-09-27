import CBPlays
import CBSim

/// Produces intents for every non-user-controlled player each tick (issues A1/A2).
public protocol PlayerBrain: Sendable {
    mutating func intents(world: World, offense: OffensivePlay, defense: DefensivePlay,
                          controlled: Set<EntityID>) -> [EntityID: PlayerIntent]
}

/// Picks play calls for the CPU side (issue A3).
public protocol CoachBrain: Sendable {
    mutating func callOffense(from book: [OffensivePlay], situation: Situation) -> OffensivePlay
    mutating func callDefense(from book: [DefensivePlay], situation: Situation) -> DefensivePlay
}

public struct Situation: Sendable, Equatable {
    public var down: Int
    public var yardsToGo: Float
    public var yardLine: Float
    public var scoreDelta: Int
    public var secondsLeft: Double
    public init(down: Int, yardsToGo: Float, yardLine: Float, scoreDelta: Int, secondsLeft: Double) {
        self.down = down; self.yardsToGo = yardsToGo; self.yardLine = yardLine
        self.scoreDelta = scoreDelta; self.secondsLeft = secondsLeft
    }
}

/// Placeholder brain: everyone stands still. Replaced by real AI in M7.
public struct IdleBrain: PlayerBrain {
    public init() {}
    public mutating func intents(world: World, offense: OffensivePlay, defense: DefensivePlay,
                                 controlled: Set<EntityID>) -> [EntityID: PlayerIntent] { [:] }
}
