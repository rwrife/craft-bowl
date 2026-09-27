import CBCore

/// Energy + turbo state for one player (docs/PLAN.md §5.5).
///
/// - Energy (0...1) drains while carrying the ball, so runners slowly slow down.
/// - Turbo is a separate burst meter (seconds) that pushes speed above normal; it drains while
///   held and recharges after a short delay. Tired runners must time turbo to break away.
public struct Stamina: Sendable, Equatable {
    public private(set) var energy: Float = 1
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
    ///   - carrying: whether this player has the ball (only carriers lose energy).
    ///   - cutting: whether the player is turning hard this tick.
    ///   - wantsTurbo: turbo button held.
    public mutating func step(dt: Float, ratings: Ratings, curves: RatingCurves,
                              carrying: Bool, cutting: Bool, wantsTurbo: Bool) {
        if carrying {
            let drain = curves.carryDrain(ratings) * (cutting ? curves.cutDrainMultiplier : 1)
            energy = max(0, energy - drain * dt)
        }
        isTurboActive = wantsTurbo && turbo > 0
        if isTurboActive {
            turbo = max(0, turbo - dt)
            rechargeCooldown = curves.turboRechargeDelay
        } else if rechargeCooldown > 0 {
            rechargeCooldown -= dt
        } else {
            turbo = min(turboCapacity, turbo + curves.turboRechargePerSecond * dt)
        }
    }

    /// Current max speed in yards/second.
    public func maxSpeed(ratings: Ratings, curves: RatingCurves) -> Float {
        let base = curves.topSpeed(ratings) * lerp(curves.exhaustedSpeedFactor, 1, energy)
        return isTurboActive ? base * curves.turboSpeedMultiplier : base
    }

    /// Between plays: partial energy recovery.
    public mutating func recover(amount: Float = 0.35) {
        energy = min(1, energy + amount)
        turbo = turboCapacity
        isTurboActive = false
        rechargeCooldown = 0
    }

    /// 0...1 for the HUD turbo bar.
    public var turboFraction: Float { turboCapacity > 0 ? turbo / turboCapacity : 0 }
}
