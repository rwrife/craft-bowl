/// Deterministic PCG32 random number generator.
///
/// All simulation randomness MUST come from a seeded `PCG32` owned by the sim world so that
/// recorded input streams replay identically (see docs/PLAN.md §2). Never use the system
/// generator from sim code — call `PCG32.nextUInt32()` / `unitFloat()` instead.
public struct PCG32: RandomNumberGenerator, Sendable, Equatable {
    private var state: UInt64
    private let increment: UInt64

    public init(seed: UInt64, stream: UInt64 = 0xDA3E_39CB_94B9_5BDB) {
        increment = (stream << 1) | 1
        state = 0
        _ = nextUInt32()
        state &+= seed
        _ = nextUInt32()
    }

    public mutating func nextUInt32() -> UInt32 {
        let old = state
        state = old &* 6_364_136_223_846_793_005 &+ increment
        let xorshifted = UInt32(truncatingIfNeeded: ((old >> 18) ^ old) >> 27)
        let rot = UInt32(truncatingIfNeeded: old >> 59)
        return (xorshifted >> rot) | (xorshifted << ((~rot &+ 1) & 31))
    }

    public mutating func next() -> UInt64 {
        (UInt64(nextUInt32()) << 32) | UInt64(nextUInt32())
    }

    /// Uniform float in [0, 1).
    public mutating func unitFloat() -> Float {
        Float(nextUInt32() >> 8) * (1.0 / 16_777_216.0)
    }
}
