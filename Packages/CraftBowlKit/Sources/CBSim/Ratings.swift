import CBCore

/// The core ratings (1–99) that make each player feel different (docs/PLAN.md §5.5).
public struct Ratings: Codable, Hashable, Sendable {
    /// Break tackles, win blocks, tackle strength.
    public var power: Int
    /// Starting (fresh) top speed and acceleration.
    public var speed: Int
    /// How slowly health drains while in the play (speed held over time), recovery rate and turbo capacity.
    public var endurance: Int
    /// Hands and athleticism: catching, jumping/diving reach, and QB throwing accuracy.
    public var ability: Int

    public init(power: Int, speed: Int, endurance: Int, ability: Int = 60) {
        self.power = clamp(power, 1, 99)
        self.speed = clamp(speed, 1, 99)
        self.endurance = clamp(endurance, 1, 99)
        self.ability = clamp(ability, 1, 99)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            power: try c.decode(Int.self, forKey: .power), speed: try c.decode(Int.self, forKey: .speed),
            endurance: try c.decode(Int.self, forKey: .endurance),
            ability: try c.decodeIfPresent(Int.self, forKey: .ability) ?? 60)
    }

    /// Normalized 0...1 helpers.
    public var p: Float { Float(power - 1) / 98 }
    public var s: Float { Float(speed - 1) / 98 }
    public var e: Float { Float(endurance - 1) / 98 }
    public var a: Float { Float(ability - 1) / 98 }
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

/// QB throw velocity in yards/second at Power ratings 1 and 99.
public struct QuarterbackArmCurve: Codable, Sendable {
    public var min: Float
    public var max: Float

    public init(min: Float, max: Float) {
        self.min = min
        self.max = max
    }

    public static let `default` = QuarterbackArmCurve(min: 18, max: 26)

    /// Tuning JSON is hot-reloadable in debug; bound flight speeds to avoid overflow or inverted trajectories.
    public var isValid: Bool { min.isFinite && max.isFinite && min >= 10 && min <= max && max <= 60 }

    public func speed(at p: Float) -> Float { lerp(min, max, p) }
}

/// Curves turning ratings into movement numbers. Loaded from `Tuning/ratings.json`.
public struct RatingCurves: Codable, Sendable {
    /// Top speed in yards/second at speed rating 1 and 99.
    public var topSpeedMin: Float
    public var topSpeedMax: Float
    public var accelMin: Float
    public var accelMax: Float
    /// Extra health lost per second while carrying the ball, at endurance 1 and 99.
    public var carryDrainMin: Float
    public var carryDrainMax: Float
    /// Extra drain multiplier while cutting hard.
    public var cutDrainMultiplier: Float
    /// Fraction of top speed kept at zero health.
    public var exhaustedSpeedFactor: Float
    /// Health lost per second while in the play (running a route, carrying), at endurance 1 and 99.
    public var playDrainMin: Float
    public var playDrainMax: Float
    /// Health regained per second while resting (not in the play, between plays), at endurance 1 and 99.
    public var regenMin: Float
    public var regenMax: Float
    /// Extra drain multiplier while turbo is burning.
    public var turboDrainMultiplier: Float
    /// Fraction of ability (catching, diving, accuracy) kept at zero health.
    public var exhaustedAbilityFactor: Float
    /// Turbo: speed multiplier, capacity (seconds) at endurance 1/99, recharge per second, recharge delay.
    public var turboSpeedMultiplier: Float
    public var turboCapacityMin: Float
    public var turboCapacityMax: Float
    public var turboRechargePerSecond: Float
    public var turboRechargeDelay: Float
    /// Optional for compatibility with older tuning JSON; absent values use the default arm curve.
    public var qbArm: QuarterbackArmCurve? = nil
    /// Speed-derived steering ceiling in radians/second. Optional for legacy tuning JSON.
    public var turnRateMin: Float? = nil
    public var turnRateMax: Float? = nil

    public func turnRate(_ r: Ratings) -> Float {
        let low = turnRateMin ?? 6
        let high = turnRateMax ?? 10
        guard low.isFinite, high.isFinite, low >= 0.1, low <= high, high <= 30 else {
            return lerp(6, 10, r.s)
        }
        return lerp(low, high, r.s)
    }

    public static let `default` = RatingCurves(
        topSpeedMin: 6.5, topSpeedMax: 9.8, accelMin: 9, accelMax: 16,
        carryDrainMin: 0.06, carryDrainMax: 0.025, cutDrainMultiplier: 1.4,
        exhaustedSpeedFactor: 0.6,
        playDrainMin: 0.2, playDrainMax: 0.09, regenMin: 0.022, regenMax: 0.055,
        turboDrainMultiplier: 1.6, exhaustedAbilityFactor: 0.5,
        turboSpeedMultiplier: 1.22, turboCapacityMin: 1.4, turboCapacityMax: 2.6,
        turboRechargePerSecond: 0.35, turboRechargeDelay: 0.6,
        turnRateMin: 6, turnRateMax: 10)

    /// Power controls QB arm strength; accuracy remains a separate fatigue-adjusted Ability trait.
    /// A non-finite, non-positive or inverted tuning curve falls back to the default: tuning JSON is
    /// hot-reloadable in debug and a bad `duration = distance/speed` would wedge ball flight.
    public func quarterbackPassSpeed(_ r: Ratings) -> Float {
        guard let arm = qbArm, arm.isValid else { return QuarterbackArmCurve.default.speed(at: r.p) }
        return lerp(arm.min, arm.max, r.p)
    }

    public func topSpeed(_ r: Ratings) -> Float { lerp(topSpeedMin, topSpeedMax, r.s) }
    public func acceleration(_ r: Ratings) -> Float { lerp(accelMin, accelMax, r.s) }
    public func carryDrain(_ r: Ratings) -> Float { lerp(carryDrainMin, carryDrainMax, r.e) }
    public func playDrain(_ r: Ratings) -> Float { lerp(playDrainMin, playDrainMax, r.e) }
    public func regen(_ r: Ratings) -> Float { lerp(regenMin, regenMax, r.e) }
    public func turboCapacity(_ r: Ratings) -> Float { lerp(turboCapacityMin, turboCapacityMax, r.e) }
}

/// Roster strength on the same 1...99 scale as player ratings. Physical traits carry
/// slightly more weight than endurance and ability for a fast, contact-heavy game.
public enum TeamRating {
    public static func overall(_ roster: [Ratings]) -> Int {
        guard !roster.isEmpty else { return 0 }
        let total = roster.reduce(0) { sum, player in
            sum + 3 * player.power + 3 * player.speed + 2 * player.endurance + 2 * player.ability
        }
        return total / (roster.count * 10)
    }
}

/// Lets `[Position: …]` dictionaries encode as JSON objects keyed by raw value.
extension Position: CodingKeyRepresentable {}
