/// Fixed-timestep accumulator. The simulation always advances in `tickDuration` steps (60 Hz);
/// the renderer uses `interpolationAlpha` to blend between the previous and current sim states.
public struct GameClock: Sendable {
    public static let ticksPerSecond: Double = 60
    public let tickDuration: Double = 1.0 / GameClock.ticksPerSecond
    /// Upper bound on catch-up ticks per frame, preventing a spiral of death after a hitch.
    public var maxTicksPerFrame: Int = 5
    /// 1 = normal speed, < 1 = slow motion (big plays), 0 = paused.
    public var timeScale: Double = 1

    public private(set) var tick: UInt64 = 0
    private var accumulator: Double = 0

    public init() {}

    /// Feed real elapsed seconds; returns how many sim ticks should run this frame.
    public mutating func advance(by elapsed: Double) -> Int {
        accumulator += max(0, elapsed) * timeScale
        var steps = 0
        while accumulator >= tickDuration && steps < maxTicksPerFrame {
            accumulator -= tickDuration
            steps += 1
        }
        if steps == maxTicksPerFrame { accumulator = min(accumulator, tickDuration) }
        tick &+= UInt64(steps)
        return steps
    }

    /// Fraction of a tick left in the accumulator, in [0, 1).
    public var interpolationAlpha: Double { accumulator / tickDuration }
}
