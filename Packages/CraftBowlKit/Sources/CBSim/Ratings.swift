import CBCore

/// The three core ratings (1–99) that make each player feel different (docs/PLAN.md §5.5).
public struct Ratings: Codable, Hashable, Sendable {
    /// Break tackles, win blocks, tackle strength.
    public var power: Int
    /// Top speed and acceleration.
    public var speed: Int
    /// Energy drain rate and turbo capacity.
    public var endurance: Int

    public init(power: Int, speed: Int, endurance: Int) {
        self.power = clamp(power, 1, 99)
        self.speed = clamp(speed, 1, 99)
        self.endurance = clamp(endurance, 1, 99)
    }

    /// Normalized 0...1 helpers.
    public var p: Float { Float(power - 1) / 98 }
    public var s: Float { Float(speed - 1) / 98 }
    public var e: Float { Float(endurance - 1) / 98 }
}

public enum Side: String, Codable, Sendable { case offense, defense }

/// 9v9 positions (docs/PLAN.md §5.1).
public enum Position: String, Codable, CaseIterable, Sendable {
    // Offense (9): QB, RB, 3 lane players, 4 linemen
    case qb, rb, laneLeft, laneCenter, laneRight, lt, lg, rg, rt
    // Defense (9): 3 DL, MLB, OLB, 2 CB, 2 S
    case deL, nt, deR, mlb, olb, cbL, cbR, fs, ss

    public var side: Side {
        switch self {
        case .qb, .rb, .laneLeft, .laneCenter, .laneRight, .lt, .lg, .rg, .rt: .offense
        default: .defense
        }
    }
}

/// Curves turning ratings into movement numbers. Loaded from `Tuning/ratings.json`.
public struct RatingCurves: Codable, Sendable {
    /// Top speed in yards/second at speed rating 1 and 99.
    public var topSpeedMin: Float
    public var topSpeedMax: Float
    public var accelMin: Float
    public var accelMax: Float
    /// Energy lost per second while carrying the ball, at endurance 1 and 99.
    public var carryDrainMin: Float
    public var carryDrainMax: Float
    /// Extra drain multiplier while cutting hard.
    public var cutDrainMultiplier: Float
    /// Fraction of top speed kept at zero energy.
    public var exhaustedSpeedFactor: Float
    /// Turbo: speed multiplier, capacity (seconds) at endurance 1/99, recharge per second, recharge delay.
    public var turboSpeedMultiplier: Float
    public var turboCapacityMin: Float
    public var turboCapacityMax: Float
    public var turboRechargePerSecond: Float
    public var turboRechargeDelay: Float

    public static let `default` = RatingCurves(
        topSpeedMin: 6.5, topSpeedMax: 9.8, accelMin: 9, accelMax: 16,
        carryDrainMin: 0.11, carryDrainMax: 0.045, cutDrainMultiplier: 1.6,
        exhaustedSpeedFactor: 0.72,
        turboSpeedMultiplier: 1.22, turboCapacityMin: 1.4, turboCapacityMax: 2.6,
        turboRechargePerSecond: 0.35, turboRechargeDelay: 0.6)

    public func topSpeed(_ r: Ratings) -> Float { lerp(topSpeedMin, topSpeedMax, r.s) }
    public func acceleration(_ r: Ratings) -> Float { lerp(accelMin, accelMax, r.s) }
    public func carryDrain(_ r: Ratings) -> Float { lerp(carryDrainMin, carryDrainMax, r.e) }
    public func turboCapacity(_ r: Ratings) -> Float { lerp(turboCapacityMin, turboCapacityMax, r.e) }
}

/// Lets `[Position: …]` dictionaries encode as JSON objects keyed by raw value.
extension Position: CodingKeyRepresentable {}
