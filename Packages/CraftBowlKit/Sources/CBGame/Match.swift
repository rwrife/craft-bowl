import CBAI
import CBCore
import CBPlays
import CBSim
import Foundation

public enum PlayPhase: String, Sendable, Equatable {
    case preSnap, live, dead
}

public enum PlayOutcome: String, Sendable, Equatable {
    case tackled, outOfBounds, touchdown, incomplete, interception, safety, dive, sack
}

/// Simplified game rules around one user offense vs a CPU defense (sandbox until issue #29 lands):
/// formation → snap → QB phase → runner phase → whistle → spot & downs.
public struct Match: Sendable {
    public static let ticksPerSecond = Int(GameClock.ticksPerSecond)
    public static let autoSnapTicks = 60 * 6
    public static let deadBallTicks = 150
    public static let quarterSeconds: Float = 300
    public static let passSpeed: Float = 22

    public private(set) var world: World
    public let playbook: Playbook
    public let format: TeamFormat

    public private(set) var phase: PlayPhase = .preSnap
    public private(set) var phaseTicks = 0
    public private(set) var lineOfScrimmage: Float = 35
    public private(set) var firstDownLine: Float = 45
    public private(set) var down = 1
    public private(set) var homeScore = 0
    public private(set) var awayScore = 0
    public private(set) var quarter = 1
    public private(set) var clock: Float = Match.quarterSeconds
    public private(set) var offenseIndex = 1
    public private(set) var defenseIndex = 0
    public private(set) var controlled: EntityID?
    public private(set) var runnerPhase = false
    public private(set) var message = "SELECT PLAY"
    public private(set) var lastOutcome: PlayOutcome?
    public private(set) var playNumber = 0

    private var nextLOS: Float = 35
    private var nextDown = 1
    private var nextFirstDown: Float = 45

    public var offensePlay: OffensivePlay { playbook.offense[offenseIndex] }
    public var defensePlay: DefensivePlay { playbook.defense[defenseIndex] }
    public var yardsToGo: Float { firstDownLine - lineOfScrimmage }

    /// QB buttons available right now (empty when the QB no longer has the ball behind the line).
    public var availableQBActions: [QBAction] {
        guard phase == .live, !runnerPhase, let c = world.ballCarrier, world[c].position == .qb,
              world[c].location.y < lineOfScrimmage
        else { return [] }
        return offensePlay.qbActions
    }

    public var playContext: PlayContext {
        PlayContext(offense: offensePlay, defense: defensePlay, lineOfScrimmage: lineOfScrimmage,
                    isLive: phase == .live, liveTicks: phase == .live ? phaseTicks : 0,
                    controlled: controlled, runnerPhase: runnerPhase)
    }

    public init(seed: UInt64, playbook: Playbook, format: TeamFormat = .nineOnNine, curves: RatingCurves = .default) {
        self.playbook = playbook
        self.format = format
        world = World(seed: seed, curves: curves)
        if let i = playbook.offense.firstIndex(where: { $0.id == "spread_pass" }) { offenseIndex = i }
        for position in format.offense + format.defense {
            let r = Match.ratings(for: position, rng: &world.rng)
            world.spawn(position, ratings: r, number: Match.number(for: position), at: .zero)
        }
        resetFormation()
    }

    public mutating func setCurves(_ curves: RatingCurves) { world.curves = curves }

    // MARK: Tick

    public mutating func step(input: TickInput, ai: [EntityID: PlayerIntent]) {
        phaseTicks += 1
        switch phase {
        case .preSnap: stepPreSnap(input)
        case .live: stepLive(input, ai: ai)
        case .dead:
            world.step(intents: [:])
            if phaseTicks >= Match.deadBallTicks { resetFormation() }
        }
    }

    private mutating func stepPreSnap(_ input: TickInput) {
        let count = playbook.offense.count
        if input.buttons.contains(.nextPlay) { offenseIndex = (offenseIndex + 1) % count }
        if input.buttons.contains(.previousPlay) { offenseIndex = (offenseIndex + count - 1) % count }
        if input.playSelect >= 0 && Int(input.playSelect) < count { offenseIndex = Int(input.playSelect) }
        world.step(intents: [:])
        let snapButtons: TickInput.Buttons = [.snap, .passLeft, .passCenter, .passRight, .handoff]
        if !input.buttons.isDisjoint(with: snapButtons) || phaseTicks >= Match.autoSnapTicks { snap() }
    }

    private mutating func snap() {
        defenseIndex = Int(world.rng.nextUInt32() % UInt32(playbook.defense.count))
        guard let qb = world.player(at: .qb) else { return }
        world.ball = .held(by: qb.id)
        controlled = qb.id
        phase = .live
        phaseTicks = 0
        runnerPhase = false
        message = ""
        playNumber += 1
    }

    private mutating func stepLive(_ input: TickInput, ai: [EntityID: PlayerIntent]) {
        clock = max(0, clock - World.dt)
        var intents = ai
        if let c = controlled {
            intents[c] = PlayerIntent(move: input.move, turbo: input.turbo, dive: input.buttons.contains(.dive))
        }
        handleQBButtons(input.buttons)
        world.step(intents: intents)
        for event in world.events { handle(event) }
        guard phase == .live else { return }
        checkCarrier()
    }

    private mutating func handleQBButtons(_ buttons: TickInput.Buttons) {
        let actions = availableQBActions
        guard !actions.isEmpty, let qbID = world.ballCarrier else { return }
        if buttons.contains(.passLeft), actions.contains(.passLeft) { pass(to: .left, from: qbID) }
        else if buttons.contains(.passCenter), actions.contains(.passCenter) { pass(to: .center, from: qbID) }
        else if buttons.contains(.passRight), actions.contains(.passRight) { pass(to: .right, from: qbID) }
        else if buttons.contains(.handoff), actions.contains(.handoff) || actions.contains(.toss),
                let rb = world.player(at: .rb) {
            world.ball = .held(by: rb.id)
            controlled = rb.id
            runnerPhase = true
        }
    }

    private mutating func pass(to lane: Lane, from qbID: EntityID) {
        guard let r = world.player(at: lane.slotPosition) else { return }
        let qb = world[qbID]
        var aim = r.location
        for _ in 0..<2 {
            let t = qb.location.distance(to: aim) / Match.passSpeed
            aim = r.location + r.velocity * t
        }
        let pressured = world.players.contains { $0.side == .defense && !$0.isDown && $0.location.distance(to: qb.location) < 2.5 }
        if pressured {
            aim += Vec2(world.rng.unitFloat() * 3 - 1.5, world.rng.unitFloat() * 3 - 1.5)
        }
        aim.x = clamp(aim.x, -Field.halfWidth + 0.5, Field.halfWidth - 0.5)
        let dist = qb.location.distance(to: aim)
        world.throwBall(to: aim, target: r.id, speed: Match.passSpeed, peak: 0.6 + dist * 0.07)
        // AI runs the receiver to the ball; the user takes over on the catch.
        controlled = nil
    }

    private mutating func handle(_ event: SimEvent) {
        switch event {
        case .ballArrived(let at, let target):
            resolveCatch(at: at, target: target)
        case .diveLanded(let id):
            if id == world.ballCarrier {
                endPlay(.dive, at: world[id].location)
            } else {
                world[id].recoverTicks = 45
            }
        case .contact:
            break
        }
    }

    private mutating func resolveCatch(at spot: Vec2, target: EntityID?) {
        let defender = world.players
            .filter { $0.side == .defense && !$0.isDown }
            .min { $0.location.distance(to: spot) < $1.location.distance(to: spot) }
        let receiverDist = target.map { world[$0].location.distance(to: spot) } ?? .infinity
        if let d = defender, d.location.distance(to: spot) < 1.2, d.location.distance(to: spot) < receiverDist {
            if world.rng.unitFloat() < 0.3 {
                world.ball = .held(by: d.id)
                endPlay(.interception, at: d.location)
            } else {
                endPlay(.incomplete, at: spot, text: "BROKEN UP!")
            }
            return
        }
        if let target, receiverDist < 1.8, !world[target].isDown {
            world.ball = .held(by: target)
            controlled = target
            runnerPhase = true
            message = "CATCH!"
            return
        }
        endPlay(.incomplete, at: spot)
    }

    private mutating func checkCarrier() {
        guard let cid = world.ballCarrier else { return }
        let c = world[cid]
        if c.location.y >= Field.goalLine { endPlay(.touchdown, at: c.location); return }
        if abs(c.location.x) > Field.halfWidth { endPlay(.outOfBounds, at: c.location); return }
        if c.location.y <= Field.ownGoalLine { endPlay(.safety, at: c.location); return }
        if c.location.y > lineOfScrimmage { runnerPhase = true }
        if phaseTicks > 30 && message == "CATCH!" { message = "" }

        for i in world.players.indices {
            let d = world.players[i]
            guard d.side == .defense, !d.isDown, d.recoverTicks == 0 else { continue }
            let reach: Float = d.isDiving ? 1.5 : 0.95
            guard d.location.distance(to: c.location) < reach else { continue }
            let chance = clamp(0.72 + 0.35 * (d.ratings.p - c.ratings.p) - 0.25 * c.ratings.s * c.stamina.energy
                               + (d.isDiving ? 0.1 : 0), 0.35, 0.95)
            if world.rng.unitFloat() < chance {
                let sack = c.position == .qb && c.location.y < lineOfScrimmage
                endPlay(sack ? .sack : .tackled, at: c.location)
                return
            }
            world.players[i].recoverTicks = 40
            world.players[i].velocity *= 0.2
            world[cid].velocity *= 0.6
            message = "BROKEN TACKLE!"
        }
    }

    // MARK: Whistle

    private mutating func endPlay(_ outcome: PlayOutcome, at spot: Vec2, text: String? = nil) {
        lastOutcome = outcome
        phase = .dead
        phaseTicks = 0
        if let c = world.ballCarrier { world[c].isDown = outcome != .touchdown && outcome != .outOfBounds }
        world.ball = .dead(at: spot)
        let gain = (spot.y - lineOfScrimmage).rounded()
        let yards = "\(gain >= 0 ? "+" : "")\(Int(gain)) YDS"
        switch outcome {
        case .touchdown:
            homeScore += 7
            message = "TOUCHDOWN!"
            restartDrive()
        case .safety:
            awayScore += 2
            message = "SAFETY!"
            restartDrive()
        case .interception:
            message = "INTERCEPTED!"
            restartDrive()
        case .incomplete:
            message = text ?? "INCOMPLETE"
            advanceDown(to: lineOfScrimmage)
        case .tackled, .outOfBounds, .dive, .sack:
            let base = outcome == .sack ? "SACKED" : outcome == .outOfBounds ? "OUT OF BOUNDS" : outcome == .dive ? "DIVE!" : "TACKLED"
            message = "\(base)  \(yards)"
            advanceDown(to: clamp(spot.y.rounded(), Field.ownGoalLine + 1, Field.goalLine - 1))
        }
        if clock <= 0 {
            if quarter < 4 { quarter += 1; clock = Match.quarterSeconds } else { message += "  —  FINAL" }
        }
    }

    private mutating func advanceDown(to spot: Float) {
        if spot >= firstDownLine {
            nextLOS = spot
            nextDown = 1
            nextFirstDown = min(spot + 10, Field.goalLine)
            message += "  FIRST DOWN!"
        } else if down >= 4 {
            message += "  TURNOVER ON DOWNS"
            restartDrive()
        } else {
            nextLOS = spot
            nextDown = down + 1
            nextFirstDown = firstDownLine
        }
    }

    private mutating func restartDrive() {
        nextLOS = 35
        nextDown = 1
        nextFirstDown = 45
    }

    private mutating func resetFormation() {
        if quarter == 4 && clock <= 0 {
            homeScore = 0; awayScore = 0; quarter = 1; clock = Match.quarterSeconds
        }
        lineOfScrimmage = nextLOS
        down = nextDown
        firstDownLine = nextFirstDown
        phase = .preSnap
        phaseTicks = 0
        controlled = world.player(at: .qb)?.id
        runnerPhase = false
        for i in world.players.indices {
            var p = world.players[i]
            let o = Match.formationOffset(p.position)
            p.location = Vec2(o.x, lineOfScrimmage + o.y)
            p.velocity = .zero
            p.facing = p.side == .offense ? 0 : .pi
            p.isDown = false
            p.diveTicks = 0
            p.recoverTicks = 0
            p.engagedTicks = 0
            p.stamina.recover()
            world.players[i] = p
        }
        world.ball = .dead(at: Vec2(0, lineOfScrimmage))
        if message.isEmpty || message == "CATCH!" { message = "SELECT PLAY" }
    }

    // MARK: Data

    static func formationOffset(_ p: Position) -> Vec2 {
        switch p {
        case .qb: Vec2(0, -4.5)
        case .rb: Vec2(0, -7)
        case .laneLeft: Vec2(-17, -1)
        case .laneCenter: Vec2(7, -1.5)
        case .laneRight: Vec2(17, -1)
        case .lt: Vec2(-3.1, -1)
        case .lg: Vec2(-1.05, -1)
        case .rg: Vec2(1.05, -1)
        case .rt: Vec2(3.1, -1)
        case .deL: Vec2(-2.6, 1.1)
        case .nt: Vec2(0, 1.1)
        case .deR: Vec2(2.6, 1.1)
        case .mlb: Vec2(0, 5)
        case .olb: Vec2(7.5, 4.5)
        case .cbL: Vec2(-17, 6)
        case .cbR: Vec2(17, 6)
        case .fs: Vec2(-6, 14)
        case .ss: Vec2(6, 12)
        }
    }

    static func number(for p: Position) -> Int {
        switch p {
        case .qb: 12
        case .rb: 28
        case .laneLeft: 81
        case .laneCenter: 88
        case .laneRight: 11
        case .lt: 72
        case .lg: 65
        case .rg: 61
        case .rt: 77
        case .deL: 94
        case .nt: 99
        case .deR: 91
        case .mlb: 55
        case .olb: 52
        case .cbL: 24
        case .cbR: 21
        case .fs: 31
        case .ss: 38
        }
    }

    static func ratings(for p: Position, rng: inout PCG32) -> Ratings {
        let base: (Int, Int, Int) = switch p {
        case .qb: (55, 68, 65)
        case .rb: (72, 84, 70)
        case .laneLeft, .laneCenter, .laneRight: (50, 88, 66)
        case .lt, .lg, .rg, .rt: (90, 42, 75)
        case .deL, .nt, .deR: (86, 52, 70)
        case .mlb: (78, 72, 75)
        case .olb: (70, 78, 70)
        case .cbL, .cbR: (50, 88, 70)
        case .fs, .ss: (62, 82, 70)
        }
        func vary(_ v: Int) -> Int { v + Int(rng.nextUInt32() % 13) - 6 }
        return Ratings(power: vary(base.0), speed: vary(base.1), endurance: vary(base.2))
    }
}
