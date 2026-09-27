import CBCore

/// Health + turbo state for one player (docs/PLAN.md §5.5).
///
/// - Health (0...1) drains quickly while the player is part of the play (running a route, carrying the
///   ball) and regenerates over time otherwise. It scales top speed and ability, so a star called on
///   every down wears down while rotating targets keeps them fresh. Endurance sets both rates.
/// - Turbo is a separate burst meter (seconds) that pushes speed above normal; it drains while
///   held and recharges after a short delay. Burning turbo in the play also costs extra health.
public struct Stamina: Sendable, Equatable {
    public private(set) var health: Float = 1
    public private(set) var turbo: Float
    public private(set) var turboCapacity: Float
    public private(set) var isTurboActive = false
    private var rechargeCooldown: Float = 0

    public init(ratings: Ratings, curves: RatingCurves = .default) {
        turboCapacity = curves.turboCapacity(ratings)
        turbo = turboCapacity
    }

    /// Advance one tick.
    /// - Parameters:
    ///   - exerting: part of the current play (health drains) vs resting (health regenerates).
    ///   - carrying: whether this player has the ball (extra drain on top of exerting).
    ///   - cutting: whether the player is turning hard this tick.
    ///   - wantsTurbo: turbo button held.
    public mutating func step(dt: Float, ratings: Ratings, curves: RatingCurves, exerting: Bool,
                              carrying: Bool, cutting: Bool, wantsTurbo: Bool) {
        isTurboActive = wantsTurbo && turbo > 0
        stepHealth(dt: dt, ratings: ratings, curves: curves, exerting: exerting, carrying: carrying, cutting: cutting)
        if isTurboActive {
            turbo = max(0, turbo - dt)
            rechargeCooldown = curves.turboRechargeDelay
        } else if rechargeCooldown > 0 {
            rechargeCooldown -= dt
        } else {
            turbo = min(turboCapacity, turbo + curves.turboRechargePerSecond * dt)
        }
    }

    /// Health only (used while down or diving, when turbo can't be used).
    public mutating func stepHealth(dt: Float, ratings: Ratings, curves: RatingCurves, exerting: Bool,
                                    carrying: Bool = false, cutting: Bool = false) {
        if exerting {
            var drain = curves.playDrain(ratings) + (carrying ? curves.carryDrain(ratings) : 0)
            if cutting { drain *= curves.cutDrainMultiplier }
            if isTurboActive { drain *= curves.turboDrainMultiplier }
            health = max(0, health - drain * dt)
        } else {
            health = min(1, health + curves.regen(ratings) * dt)
        }
    }

    /// Current max speed in yards/second.
    public func maxSpeed(ratings: Ratings, curves: RatingCurves) -> Float {
        let base = curves.topSpeed(ratings) * lerp(curves.exhaustedSpeedFactor, 1, health)
        return isTurboActive ? base * curves.turboSpeedMultiplier : base
    }

    /// Ability (0...1) after fatigue: catching, diving reach, throwing accuracy.
    public func ability(ratings: Ratings, curves: RatingCurves) -> Float {
        ratings.a * lerp(curves.exhaustedAbilityFactor, 1, health)
    }

    /// Between plays: turbo refills. Health only comes back over time (see `stepHealth`).
    public mutating func resetTurbo() {
        turbo = turboCapacity
        isTurboActive = false
        rechargeCooldown = 0
    }

    /// Test/tuning hook.
    public mutating func setHealth(_ value: Float) { health = clamp(value, 0, 1) }

    /// 0...1 for the HUD turbo bar.
    public var turboFraction: Float { turboCapacity > 0 ? turbo / turboCapacity : 0 }
}
