import CBAI
import CBCore
import CBPlays
import CBSim

/// One deterministic game: rules + AI, advanced one fixed tick at a time. Pure value type — copy it to
/// snapshot the entire game (used by record/replay). Runs headless (no UIKit/Metal).
public struct GameSimulation: Sendable {
    public private(set) var match: Match
    public private(set) var brain = SandboxBrain()

    public init(seed: UInt64, playbook: Playbook, format: TeamFormat = .nineOnNine, curves: RatingCurves = .default) {
        match = Match(seed: seed, playbook: playbook, format: format, curves: curves)
    }

    public var world: World { match.world }

    public mutating func tick(_ input: TickInput) {
        let ai = brain.intents(world: match.world, context: match.playContext)
        match.step(input: input, ai: ai)
    }

    public mutating func setCurves(_ curves: RatingCurves) { match.setCurves(curves) }

    public mutating func setRoster(offense: [Position: (ratings: Ratings, number: Int)],
                                   defense: [Position: (ratings: Ratings, number: Int)]) {
        match.setRoster(offense: offense, defense: defense)
    }
}

/// Records the input stream from a starting simulation so a bug can be reproduced exactly.
public struct InputRecording: Sendable {
    public let start: GameSimulation
    public private(set) var inputs: [TickInput] = []
    public private(set) var finalChecksum: UInt64

    public init(start: GameSimulation) {
        self.start = start
        finalChecksum = start.world.checksum
    }

    public var tickCount: Int { inputs.count }
    public var seconds: Double { Double(inputs.count) / GameClock.ticksPerSecond }

    public mutating func append(_ input: TickInput, resultingChecksum: UInt64) {
        inputs.append(input)
        finalChecksum = resultingChecksum
    }

    /// Re-runs every recorded input from the start state.
    /// - Returns: the replayed simulation and whether it ended bit-identical to the recording.
    public func replay() -> (simulation: GameSimulation, matches: Bool) {
        var sim = start
        for input in inputs { sim.tick(input) }
        return (sim, sim.world.checksum == finalChecksum)
    }
}
