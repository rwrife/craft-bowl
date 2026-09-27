import CBCore
import Foundation

public struct EntityID: Hashable, Sendable, Codable {
    public let raw: UInt32
    public init(_ raw: UInt32) { self.raw = raw }
}

/// One player on the field. Simulation state only — appearance lives in CBAssets.
public struct PlayerState: Sendable {
    public let id: EntityID
    public var position: Position
    public var ratings: Ratings
    public var stamina: Stamina
    public var number: Int
    public var location: Vec2
    public var velocity: Vec2 = .zero
    /// Heading in radians, 0 = downfield (+y), positive turns toward +x.
    public var facing: Float = 0
    /// Ticks left in a dive lunge.
    public var diveTicks = 0
    /// On the ground (tackled / landed a dive). Down players don't move or collide.
    public var isDown = false
    /// Ticks until a player who whiffed (dive miss, broken tackle) can act again.
    public var recoverTicks = 0
    /// > 0 while in contact with an opponent (blocking / being blocked) — slows the player.
    public var engagedTicks = 0
    /// Part of the current play (key receiver/runner, ball carrier): health drains instead of regenerating.
    /// Set by the rules layer each live tick.
    public var isExerting = false

    public var side: Side { position.side }
    public var isDiving: Bool { diveTicks > 0 }
    public var health: Float { stamina.health }
    public func ability(_ curves: RatingCurves) -> Float { stamina.ability(ratings: ratings, curves: curves) }

    public init(id: EntityID, position: Position, ratings: Ratings, number: Int, location: Vec2,
                curves: RatingCurves = .default) {
        self.id = id
        self.position = position
        self.ratings = ratings
        self.number = number
        self.stamina = Stamina(ratings: ratings, curves: curves)
        self.location = location
        self.facing = position.side == .offense ? 0 : .pi
    }
}

/// A thrown or pitched ball.
public struct BallFlight: Sendable, Equatable {
    public var from: Vec2
    public var to: Vec2
    public var elapsed: Float
    public var duration: Float
    /// Apex height above the release/catch height, yards.
    public var peak: Float
    public var target: EntityID?

    public var progress: Float { duration > 0 ? min(1, elapsed / duration) : 1 }
    public var groundPosition: Vec2 { from + (to - from) * progress }
    public var height: Float {
        let t = progress
        return World.carryHeight + 4 * peak * t * (1 - t)
    }
}

public enum BallState: Sendable, Equatable {
    case held(by: EntityID)
    case inAir(BallFlight)
    case loose(at: Vec2)
    case dead(at: Vec2)
}

/// Things that happened during a tick that the rules layer (CBGame) must resolve.
public enum SimEvent: Sendable, Equatable {
    case ballArrived(at: Vec2, target: EntityID?)
    case diveLanded(EntityID)
    case contact(EntityID, EntityID)
}

/// Per-tick intent for one player (produced by CBInput for the user, CBAI for everyone else).
public struct PlayerIntent: Sendable, Equatable {
    public var move: Vec2 = .zero
    public var turbo = false
    public var dive = false
    public init(move: Vec2 = .zero, turbo: Bool = false, dive: Bool = false) {
        self.move = move; self.turbo = turbo; self.dive = dive
    }
}

/// Deterministic simulation world, stepped at a fixed 60 Hz (see `GameClock`).
///
/// ECS-lite: entities are dense indices into `players` (EntityID.raw == index), and the ball is a
/// singleton component. All randomness comes from `rng`, so a world copy + the same inputs replays
/// bit-identically (see `World.checksum`).
public struct World: Sendable {
    public static let dt = Float(1.0 / GameClock.ticksPerSecond)
    public static let playerRadius: Float = 0.42
    public static let carryHeight: Float = 1.15

    public var players: [PlayerState] = []
    public var ball: BallState = .dead(at: .zero)
    public var rng: PCG32
    public var curves: RatingCurves
    public private(set) var tick: UInt64 = 0
    /// Events raised by the last `step`. Cleared at the start of every step.
    public private(set) var events: [SimEvent] = []

    public init(seed: UInt64, curves: RatingCurves = .default) {
        rng = PCG32(seed: seed)
        self.curves = curves
    }

    @discardableResult
    public mutating func spawn(_ position: Position, ratings: Ratings, number: Int, at location: Vec2) -> EntityID {
        let id = EntityID(UInt32(players.count))
        players.append(PlayerState(id: id, position: position, ratings: ratings, number: number,
                                   location: location, curves: curves))
        return id
    }

    public subscript(id: EntityID) -> PlayerState {
        get { players[Int(id.raw)] }
        set { players[Int(id.raw)] = newValue }
    }

    public var ballCarrier: EntityID? {
        if case .held(by: let id) = ball { return id }
        return nil
    }

    public var ballFlight: BallFlight? {
        if case .inAir(let f) = ball { return f }
        return nil
    }

    /// Ball position on the ground plane.
    public var ballLocation: Vec2 {
        switch ball {
        case .held(by: let id): return self[id].location
        case .inAir(let f): return f.groundPosition
        case .loose(at: let p), .dead(at: let p): return p
        }
    }

    public func player(at position: Position) -> PlayerState? {
        players.first { $0.position == position }
    }

    // MARK: Actions

    /// Throws from the current carrier toward `to`; `speed` in yards/second.
    public mutating func throwBall(to: Vec2, target: EntityID?, speed: Float, peak: Float) {
        let from = ballLocation
        let duration = max(0.2, from.distance(to: to) / speed)
        ball = .inAir(BallFlight(from: from, to: to, elapsed: 0, duration: duration, peak: peak, target: target))
    }

    public mutating func startDive(_ id: EntityID) {
        var p = self[id]
        guard !p.isDown, !p.isDiving, p.recoverTicks == 0 else { return }
        let dir = Vec2(sin(p.facing), cos(p.facing))
        // Ability (after fatigue) sets how far and long the lunge carries.
        let ability = p.ability(curves)
        let speed = max(p.velocity.length, 4) * lerp(0.8, 1, p.health) + 1.5 + 2 * ability
        p.velocity = dir * speed
        p.diveTicks = 16 + Int(10 * ability)
        self[id] = p
    }

    // MARK: Tick

    /// Advance one fixed tick. `intents` maps players to their intent this tick.
    public mutating func step(intents: [EntityID: PlayerIntent]) {
        events.removeAll(keepingCapacity: true)
        let dt = World.dt
        let carrier = ballCarrier
        for i in players.indices {
            let intent = intents[players[i].id] ?? PlayerIntent()
            stepPlayer(i, intent: intent, carrying: players[i].id == carrier, dt: dt)
        }
        resolveCollisions()
        applyWalls()
        stepBall(dt: dt)
        tick &+= 1
    }

    /// Keeps every player inside the invisible walls, killing velocity into the wall so they slide along it.
    private mutating func applyWalls() {
        for i in players.indices {
            let p = players[i].location
            let c = Field.clampToWalls(p, radius: World.playerRadius)
            guard c != p else { continue }
            players[i].location = c
            if c.x != p.x { players[i].velocity.x = 0 }
            if c.y != p.y { players[i].velocity.y = 0 }
        }
    }

    private mutating func stepPlayer(_ i: Int, intent: PlayerIntent, carrying: Bool, dt: Float) {
        var p = players[i]
        defer { players[i] = p }
        if p.isDown || p.isDiving {
            p.stamina.stepHealth(dt: dt, ratings: p.ratings, curves: curves, exerting: p.isExerting)
        }
        if p.isDown {
            p.velocity = .zero
            if p.recoverTicks > 0 {
                p.recoverTicks -= 1
                if p.recoverTicks == 0 { p.isDown = false }
            }
            return
        }
        if p.isDiving {
            p.velocity *= 0.965
            p.location += p.velocity * dt
            p.diveTicks -= 1
            if p.diveTicks == 0 {
                p.isDown = true
                p.velocity = .zero
                events.append(.diveLanded(p.id))
            }
            return
        }
        if intent.dive && p.recoverTicks == 0 {
            players[i] = p
            startDive(p.id)
            p = players[i]
            return
        }

        let recovering = p.recoverTicks > 0
        if recovering { p.recoverTicks -= 1 }
        if p.engagedTicks > 0 { p.engagedTicks -= 1 }

        let desired = intent.move.length > 1 ? intent.move.normalized : intent.move
        let before = p.velocity.normalized
        let cutting = before != .zero && desired != .zero && (before * desired).sum() < 0.5
        p.stamina.step(dt: dt, ratings: p.ratings, curves: curves, exerting: p.isExerting, carrying: carrying,
                       cutting: cutting && p.velocity.length > 2, wantsTurbo: intent.turbo && !recovering)
        var vmax = p.stamina.maxSpeed(ratings: p.ratings, curves: curves)
        if p.engagedTicks > 0 { vmax *= carrying ? 0.7 : 0.45 }
        if recovering { vmax *= 0.35 }
        let target = desired * vmax
        let accel = curves.acceleration(p.ratings) * lerp(0.75, 1, p.health) * dt
        let delta = target - p.velocity
        p.velocity += delta.length > accel ? delta.normalized * accel : delta
        p.location += p.velocity * dt
        if p.velocity.length > 0.3 { p.facing = atan2(p.velocity.x, p.velocity.y) }
    }

    /// Circle separation between standing players. Opponents in contact become "engaged" (blocking).
    private mutating func resolveCollisions() {
        let minDist = World.playerRadius * 2
        let n = players.count
        for a in 0..<n where !players[a].isDown {
            for b in (a + 1)..<n where !players[b].isDown {
                let d = players[b].location - players[a].location
                let dist = d.length
                guard dist < minDist else { continue }
                let normal = dist > 1e-4 ? d / dist : Vec2(1, 0)
                let overlap = minDist - dist
                let pa = Float(players[a].ratings.power), pb = Float(players[b].ratings.power)
                let wa = pb / (pa + pb)
                if !players[a].isDiving { players[a].location -= normal * overlap * wa }
                if !players[b].isDiving { players[b].location += normal * overlap * (1 - wa) }
                if players[a].side != players[b].side {
                    players[a].engagedTicks = 8
                    players[b].engagedTicks = 8
                    events.append(.contact(players[a].id, players[b].id))
                }
            }
        }
    }

    private mutating func stepBall(dt: Float) {
        guard case .inAir(var f) = ball else { return }
        f.elapsed += dt
        if f.elapsed >= f.duration {
            ball = .loose(at: f.to)
            events.append(.ballArrived(at: f.to, target: f.target))
        } else {
            ball = .inAir(f)
        }
    }

    /// FNV-1a over every player position/velocity + ball + tick. Equal checksums ⇒ identical replays.
    public var checksum: UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ v: UInt32) { h = (h ^ UInt64(v)) &* 0x100_0000_01b3 }
        mix(UInt32(truncatingIfNeeded: tick))
        for p in players {
            mix(p.location.x.bitPattern); mix(p.location.y.bitPattern)
            mix(p.velocity.x.bitPattern); mix(p.velocity.y.bitPattern)
            mix(p.stamina.health.bitPattern)
        }
        mix(ballLocation.x.bitPattern); mix(ballLocation.y.bitPattern)
        return h
    }
}
