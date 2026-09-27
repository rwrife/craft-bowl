import CBCore
import CBPlays
import CBSim
import Foundation

/// What the AI needs to know about the current play beyond raw world state.
public struct PlayContext: Sendable {
    public var offense: OffensivePlay
    public var defense: DefensivePlay
    public var lineOfScrimmage: Float
    public var isLive: Bool
    /// Ticks since the snap.
    public var liveTicks: Int
    /// The user-controlled player (never given an AI intent).
    public var controlled: EntityID?
    /// True once the ball has been handed off / caught / carried past the line: everyone pursues or blocks.
    public var runnerPhase: Bool

    public init(offense: OffensivePlay, defense: DefensivePlay, lineOfScrimmage: Float, isLive: Bool,
                liveTicks: Int, controlled: EntityID?, runnerPhase: Bool) {
        self.offense = offense
        self.defense = defense
        self.lineOfScrimmage = lineOfScrimmage
        self.isLive = isLive
        self.liveTicks = liveTicks
        self.controlled = controlled
        self.runnerPhase = runnerPhase
    }
}

/// Produces intents for every non-user-controlled player each tick.
public protocol PlayerBrain: Sendable {
    mutating func intents(world: World, context: PlayContext) -> [EntityID: PlayerIntent]
}

/// Picks play calls for the CPU side (issue #44).
public protocol CoachBrain: Sendable {
    mutating func callOffense(from book: [OffensivePlay], situation: Situation) -> OffensivePlay
    mutating func callDefense(from book: [DefensivePlay], situation: Situation) -> DefensivePlay
}

public struct Situation: Sendable, Equatable {
    public var down: Int
    public var yardsToGo: Float
    public var yardLine: Float
    public var scoreDelta: Int
    public var secondsLeft: Double
    public init(down: Int, yardsToGo: Float, yardLine: Float, scoreDelta: Int, secondsLeft: Double) {
        self.down = down; self.yardsToGo = yardsToGo; self.yardLine = yardLine
        self.scoreDelta = scoreDelta; self.secondsLeft = secondsLeft
    }
}

/// Placeholder brain: everyone stands still.
public struct IdleBrain: PlayerBrain {
    public init() {}
    public mutating func intents(world: World, context: PlayContext) -> [EntityID: PlayerIntent] { [:] }
}

extension Position {
    /// The lane slot this offensive position fills, if any.
    public var lane: Lane? {
        switch self {
        case .laneLeft: .left
        case .laneCenter: .center
        case .laneRight: .right
        case .rb: .backfield
        default: nil
        }
    }
}

extension Lane {
    /// Field x at the middle of the lane (backfield = middle of the field).
    public var centerX: Float {
        switch self {
        case .left: Field.laneCenterX(-1)
        case .center, .backfield: 0
        case .right: Field.laneCenterX(1)
        }
    }
}

/// First-pass teammate + defensive AI (placeholder for issues #42/#43): lane routes, pass pro and
/// lead blocking on offense; zone drops, man trail, blitz, spy, run-fill and pursuit on defense.
public struct SandboxBrain: PlayerBrain {
    /// Where each AI player was heading last tick (debug draw: routes / pursuit targets).
    public private(set) var aimPoints: [EntityID: Vec2] = [:]
    private var out: [EntityID: PlayerIntent] = [:]

    public init() {}

    public mutating func intents(world: World, context: PlayContext) -> [EntityID: PlayerIntent] {
        out.removeAll(keepingCapacity: true)
        aimPoints.removeAll(keepingCapacity: true)
        guard context.isLive else { return out }
        let carrier = world.ballCarrier.map { world[$0] }
        let flight = world.ballFlight
        let qb = world.player(at: .qb)

        for p in world.players where p.id != context.controlled && !p.isDown && !p.isDiving {
            let intent: PlayerIntent
            if p.side == .offense {
                intent = offenseIntent(p, world: world, context: context, carrier: carrier, flight: flight, qb: qb)
            } else {
                intent = defenseIntent(p, world: world, context: context, carrier: carrier, flight: flight, qb: qb)
            }
            out[p.id] = intent
        }
        return out
    }

    // MARK: Offense

    private mutating func offenseIntent(_ p: PlayerState, world: World, context: PlayContext,
                                        carrier: PlayerState?, flight: BallFlight?, qb: PlayerState?) -> PlayerIntent {
        let los = context.lineOfScrimmage
        if let flight, flight.target == p.id {
            return go(p, to: flight.to, arrive: 0.5)
        }
        if p.id == carrier?.id { return PlayerIntent() }

        if let lane = p.position.lane, let slot = context.offense.slots[lane], !context.runnerPhase {
            switch slot.role {
            case .target:
                if lane == .backfield && (slot.route == .handoff || slot.route == .toss) {
                    return go(p, to: Vec2(slot.route == .toss ? -3 : 0, los - 6.5), arrive: 1)
                }
                return go(p, to: routePoint(lane: lane, route: slot.route, start: p, los: los,
                                            ticks: context.liveTicks), arrive: 1.5)
            case .lead:
                return go(p, to: Vec2(lane.centerX * 0.3, los + 1.5), arrive: 1)
            case .blocker, .fake:
                break
            }
        }
        if p.position == .qb { return PlayerIntent() }
        guard let carrier else { return PlayerIntent() }
        return block(p, for: carrier, world: world)
    }

    private func routePoint(lane: Lane, route: RouteKind, start: PlayerState, los: Float, ticks: Int) -> Vec2 {
        let t = Float(ticks) / 60
        let x = lane == .center ? Float(4) : lane.centerX
        switch route {
        case .deep: return Vec2(x * 0.9, los + 32)
        case .mid: return t < 1.4 ? Vec2(x, los + 10) : Vec2(x * 0.45, los + 15)
        case .short: return Vec2(x, los + 5.5)
        case .flat: return Vec2(lane == .backfield ? 14 : x * 1.2, los + 1.5)
        case .screen: return Vec2(x * 0.8, los - 2.5)
        case .handoff, .toss, .none: return start.location
        }
    }

    /// Get between the most dangerous nearby defender and the ball carrier.
    private mutating func block(_ p: PlayerState, for carrier: PlayerState, world: World) -> PlayerIntent {
        var best: PlayerState?
        var bestScore = Float.greatestFiniteMagnitude
        for d in world.players where d.side == .defense && !d.isDown {
            let toCarrier = d.location.distance(to: carrier.location)
            let toMe = d.location.distance(to: p.location)
            guard toMe < 9 else { continue }
            let score = toCarrier + toMe * 0.8
            if score < bestScore { bestScore = score; best = d }
        }
        guard let threat = best else { return go(p, to: carrier.location + Vec2(0, 4), arrive: 2) }
        let spot = threat.location + (carrier.location - threat.location).normalized * 0.7
        return go(p, to: spot, arrive: 0.4)
    }

    // MARK: Defense

    private mutating func defenseIntent(_ p: PlayerState, world: World, context: PlayContext,
                                        carrier: PlayerState?, flight: BallFlight?, qb: PlayerState?) -> PlayerIntent {
        let los = context.lineOfScrimmage
        if let flight {
            if p.location.distance(to: flight.to) < 12 { return go(p, to: flight.to, arrive: 0.3, turbo: true) }
            if let t = flight.target { return pursue(p, world[t]) }
        }
        guard let carrier else { return PlayerIntent() }
        let qbHasBall = carrier.position == .qb && carrier.location.y < los + 0.5
        if context.runnerPhase || !qbHasBall { return pursue(p, carrier) }

        switch context.defense.assignments[p.position] ?? .rush {
        case .rush:
            return pursue(p, carrier)
        case .spy:
            return go(p, to: Vec2(carrier.location.x, los + 4.5), arrive: 1)
        case .runFill:
            if let rb = world.player(at: .rb) { return pursue(p, rb) }
            return pursue(p, carrier)
        case .man(let lane):
            guard let r = world.player(at: lane.slotPosition),
                  context.offense.slots[lane]?.role == .target
            else { return zoneDrop(p, lane: lane, depth: 7, world: world, los: los) }
            return go(p, to: r.location + r.velocity * 0.25 + Vec2(0, 1.2), arrive: 0.5)
        case .zone(let lane):
            return zoneDrop(p, lane: lane, depth: 7, world: world, los: los)
        case .deepZone(let lane):
            return zoneDrop(p, lane: lane, depth: 16, world: world, los: los)
        }
    }

    private mutating func zoneDrop(_ p: PlayerState, lane: Lane, depth: Float, world: World, los: Float) -> PlayerIntent {
        let home = Vec2(lane.centerX, los + depth)
        var threat: PlayerState?
        for r in world.players where r.side == .offense && r.position.lane != nil {
            let inLane = abs(r.location.x - lane.centerX) < Field.laneWidth * 0.6
            let inDepth = r.location.y > los && abs(r.location.y - home.y) < 9
            if inLane && inDepth && (threat == nil || r.location.y > (threat?.location.y ?? 0)) { threat = r }
        }
        if let threat {
            return go(p, to: threat.location + Vec2(0, 1.5), arrive: 1, scale: 0.9)
        }
        return go(p, to: home, arrive: 1.5, scale: 0.85)
    }

    private mutating func pursue(_ p: PlayerState, _ target: PlayerState) -> PlayerIntent {
        let dist = p.location.distance(to: target.location)
        let lead = clamp(dist / 8, 0, 1)
        let aim = target.location + target.velocity * lead
        var intent = go(p, to: aim, arrive: 0.2, turbo: dist < 7)
        let away = (target.location - p.location).normalized
        let fleeing = (target.velocity.normalized * away).sum() > 0.5 && target.velocity.length > 3
        if dist > 1.1 && dist < 2.1 && fleeing && p.recoverTicks == 0 { intent.dive = true }
        return intent
    }

    private mutating func go(_ p: PlayerState, to target: Vec2, arrive: Float, turbo: Bool = false,
                             scale: Float = 1) -> PlayerIntent {
        aimPoints[p.id] = target
        let d = target - p.location
        let len = d.length
        guard len > 0.25 else { return PlayerIntent() }
        return PlayerIntent(move: d / len * min(1, len / arrive) * scale, turbo: turbo)
    }
}
