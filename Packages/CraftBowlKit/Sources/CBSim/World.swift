import CBCore

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
    public var location: Vec2
    public var velocity: Vec2 = .zero
    public var facing: Float = 0

    public init(id: EntityID, position: Position, ratings: Ratings, location: Vec2,
                curves: RatingCurves = .default) {
        self.id = id
        self.position = position
        self.ratings = ratings
        self.stamina = Stamina(ratings: ratings, curves: curves)
        self.location = location
    }
}

public enum BallState: Sendable, Equatable {
    case held(by: EntityID)
    case inAir(from: Vec2, to: Vec2, elapsed: Float, duration: Float)
    case loose(at: Vec2)
    case dead(at: Vec2)
}

/// Per-tick intent for the controlled player (produced by CBInput or CBAI).
public struct PlayerIntent: Sendable, Equatable {
    public var move: Vec2 = .zero
    public var turbo = false
    public var dive = false
    public init(move: Vec2 = .zero, turbo: Bool = false, dive: Bool = false) {
        self.move = move; self.turbo = turbo; self.dive = dive
    }
}

/// Deterministic simulation world, stepped at a fixed 60 Hz (see `GameClock`).
/// This is the seed of ECS-lite world from issue F3; systems will be split out as they grow.
public struct World: Sendable {
    public var players: [PlayerState] = []
    public var ball: BallState = .dead(at: .zero)
    public var rng: PCG32
    public var curves: RatingCurves
    public private(set) var tick: UInt64 = 0

    public init(seed: UInt64, curves: RatingCurves = .default) {
        rng = PCG32(seed: seed)
        self.curves = curves
    }

    @discardableResult
    public mutating func spawn(_ position: Position, ratings: Ratings, at location: Vec2) -> EntityID {
        let id = EntityID(UInt32(players.count))
        players.append(PlayerState(id: id, position: position, ratings: ratings, location: location, curves: curves))
        return id
    }

    public var ballCarrier: EntityID? {
        if case let .held(by: id) = ball { return id }
        return nil
    }

    /// Advance one fixed tick. `intents` maps controlled/AI players to their intent this tick.
    public mutating func step(intents: [EntityID: PlayerIntent]) {
        let dt = Float(1.0 / GameClock.ticksPerSecond)
        let carrier = ballCarrier
        for i in players.indices {
            let intent = intents[players[i].id] ?? PlayerIntent()
            let desired = intent.move.length > 1 ? intent.move.normalized : intent.move
            let before = players[i].velocity.normalized
            let cutting = before != .zero && desired != .zero && (before * desired).sum() < 0.5
            players[i].stamina.step(dt: dt, ratings: players[i].ratings, curves: curves,
                                    carrying: players[i].id == carrier, cutting: cutting,
                                    wantsTurbo: intent.turbo)
            let vmax = players[i].stamina.maxSpeed(ratings: players[i].ratings, curves: curves)
            let target = desired * vmax
            let accel = curves.acceleration(players[i].ratings) * dt
            let delta = target - players[i].velocity
            let step = delta.length > accel ? delta.normalized * accel : delta
            players[i].velocity += step
            players[i].location += players[i].velocity * dt
        }
        tick &+= 1
    }
}
