import CBCore
import Foundation

/// Minimal per-tick state the renderer needs. The game loop keeps the last two snapshots and
/// interpolates with `GameClock.interpolationAlpha` so 120 Hz displays stay smooth on a 60 Hz sim.
public struct WorldSnapshot: Sendable {
    public struct Player: Sendable {
        public var id: EntityID
        public var position: Position
        public var number: Int
        public var location: Vec2
        public var velocity: Vec2
        public var facing: Float
        public var isDown: Bool
        public var isDiving: Bool
        public var turboActive: Bool
        public var energy: Float
        public var turboFraction: Float
    }

    public var tick: UInt64 = 0
    public var players: [Player] = []
    /// Ball in field space (x, y) plus height.
    public var ball: SIMD3<Float> = .zero
    public var ballCarrier: EntityID?
    public var ballInAir = false

    public init() {}

    /// Overwrites this snapshot from `world` without reallocating.
    public mutating func capture(_ world: World) {
        tick = world.tick
        players.removeAll(keepingCapacity: true)
        for p in world.players {
            players.append(Player(id: p.id, position: p.position, number: p.number, location: p.location,
                                  velocity: p.velocity, facing: p.facing, isDown: p.isDown, isDiving: p.isDiving,
                                  turboActive: p.stamina.isTurboActive, energy: p.stamina.energy,
                                  turboFraction: p.stamina.turboFraction))
        }
        ballCarrier = world.ballCarrier
        ballInAir = world.ballFlight != nil
        let g = world.ballLocation
        let h: Float
        if let f = world.ballFlight {
            h = f.height
        } else if case .held = world.ball {
            h = World.carryHeight
        } else {
            h = 0.12
        }
        ball = SIMD3(g.x, g.y, h)
    }

    /// Writes `a` blended toward `b` by `t` into `out` (reusing its storage).
    public static func interpolate(_ a: WorldSnapshot, _ b: WorldSnapshot, _ t: Float, into out: inout WorldSnapshot) {
        out.tick = b.tick
        out.ballCarrier = b.ballCarrier
        out.ballInAir = b.ballInAir
        out.ball = a.ball + (b.ball - a.ball) * t
        out.players.removeAll(keepingCapacity: true)
        guard a.players.count == b.players.count else {
            out.players.append(contentsOf: b.players)
            return
        }
        for i in b.players.indices {
            var p = b.players[i]
            let pa = a.players[i]
            p.location = pa.location + (p.location - pa.location) * t
            p.velocity = pa.velocity + (p.velocity - pa.velocity) * t
            var df = p.facing - pa.facing
            if df > .pi { df -= 2 * .pi } else if df < -.pi { df += 2 * .pi }
            p.facing = pa.facing + df * t
            out.players.append(p)
        }
    }
}
