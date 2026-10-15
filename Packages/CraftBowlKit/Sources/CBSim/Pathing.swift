import CBCore
import Foundation

/// Steering primitives shared by pathing callers (issue #25).
///
/// Every helper returns a *desired velocity* in unit-less units (magnitude 0...1, scaled by the
/// caller's `scale`), matching `PlayerIntent.move`. They are pure and stateless so a replay of the
/// same world state produces identical steering.
public struct Arrive: Sendable {
    /// Distance under which steering starts to fade, in yards.
    public var radius: Float
    /// Distance under which steering is fully stopped; keeps a target from jittering at the center.
    /// The bound is inclusive: `distance <= stopRadius` yields zero steering.
    public var stopRadius: Float

    public init(radius: Float = 1.5, stopRadius: Float = 0.25) {
        self.radius = radius
        self.stopRadius = stopRadius
    }

    /// Unit-scaled steering toward `to`, eased over the last `radius` yards.
    public func steer(from: Vec2, to: Vec2) -> Vec2 {
        steer(remaining: (to - from).length, direction: to - from)
    }

    /// Same fade for a caller that already knows its heading (`Pursue` lead point, debug draw).
    public func steer(remaining distance: Float, direction: Vec2) -> Vec2 {
        guard distance.isFinite, distance > max(stopRadius, 0),
            direction.x.isFinite, direction.y.isFinite,
            direction.length.isFinite, direction.length > 0
        else { return .zero }
        // Non-positive or non-finite radius means "no easing": a full-speed step toward the target.
        let scale = radius > 0 && radius.isFinite ? min(1, distance / radius) : 1
        return direction.normalized * scale
    }
}

/// Lead pursuit: aim where a moving target is about to be rather than where it is.
public struct Pursue: Sendable {
    public var arrive: Arrive
    /// Seconds of target velocity to project ahead.
    public var lookahead: Float

    public init(arrive: Arrive = Arrive(), lookahead: Float = 0.5) {
        self.arrive = arrive
        self.lookahead = lookahead
    }

    public func steer(from: Vec2, toward target: Vec2, velocity: Vec2) -> Vec2 {
        let horizon = lookahead.isFinite ? max(0, lookahead) : 0
        let lead = target + velocity * horizon
        return arrive.steer(remaining: from.distance(to: lead), direction: lead - from)
    }
}

/// Obstacle avoidance: rotate the desired heading away from the nearest blocker on the path
/// until the projected segment actually clears every threat's clearance radius.
public struct Avoid: Sendable {
    /// Center-to-center distance the projected path must stay clear of (usually 2 × player radius).
    public var clearance: Float
    /// How many yards ahead of the mover the corridor is checked.
    public var ahead: Float
    /// Degrees per search step when rotating away from a blocker.
    public var stepDegrees: Float
    /// Widest rotation considered; beyond this the caller's collision resolution takes over.
    public var maxDeflectionDegrees: Float

    public init(
        clearance: Float = World.playerRadius * 2, ahead: Float = 2,
        stepDegrees: Float = 20, maxDeflectionDegrees: Float = 160
    ) {
        self.clearance = clearance
        self.ahead = ahead
        self.stepDegrees = stepDegrees
        self.maxDeflectionDegrees = maxDeflectionDegrees
    }

    /// `desired` is the un-resolved steering (direction × 0...1 speed). Returns the same magnitude
    /// with the blocking component removed. Non-finite threats are ignored; a non-finite `desired`
    /// yields no movement rather than NaN.
    public func steer(from: Vec2, desired: Vec2, avoiding threats: [Vec2]) -> Vec2 {
        let speed = desired.length
        guard speed.isFinite, speed > 0 else { return .zero }
        let valid = threats.filter { $0.x.isFinite && $0.y.isFinite }
        guard !valid.isEmpty else { return desired }

        let clear = clearance.isFinite ? max(0, clearance) : 0
        let range = ahead.isFinite ? max(0, ahead) : 0
        let step = stepDegrees.isFinite ? min(180, max(1, stepDegrees)) : 20
        let maxDeflection = maxDeflectionDegrees.isFinite ? min(180, max(0, maxDeflectionDegrees)) : 0
        let steps = Int(maxDeflection / step)

        // Alternate sides (clockwise = right of travel first) so ties resolve deterministically.
        for index in 0...steps {
            let magnitude = Float(index) * step
            for degrees in index == 0 ? [Float(0)] : [-magnitude, magnitude] {
                let candidate = rotate(desired / speed, byDegrees: degrees)
                if isClear(from: from, heading: candidate, threats: valid, clear: clear, range: range) {
                    return candidate * speed
                }
            }
        }
        return rotate(desired / speed, byDegrees: -maxDeflection) * speed
    }

    /// True when the projected segment keeps every threat outside `clearance`.
    private func isClear(from: Vec2, heading: Vec2, threats: [Vec2], clear: Float, range: Float) -> Bool {
        for threat in threats {
            let delta = threat - from
            let along = max(0, min(range, (delta * heading).sum()))
            guard (delta - heading * along).length < clear else { continue }
            return false
        }
        return true
    }

    private func rotate(_ v: Vec2, byDegrees degrees: Float) -> Vec2 {
        let radians = degrees * .pi / 180
        let (s, c) = (sin(radians), cos(radians))
        return Vec2(c * v.x - s * v.y, s * v.x + c * v.y)
    }
}
