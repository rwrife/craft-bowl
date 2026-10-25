import CBAI
import CBCore
import CBPlays
import CBSim
import Foundation

/// Passing / rushing box score for one simulated possession.
public struct DriveStats: Sendable, Equatable {
    public var passAttempts = 0
    public var completions = 0
    public var passYards = 0
    public var passTouchdowns = 0
    public var interceptions = 0
    public var sacks = 0
    /// Yards lost to sacks (positive number).
    public var sackYards = 0
    public var rushAttempts = 0
    public var rushYards = 0
    public var rushTouchdowns = 0
    public var firstDowns = 0
    public var longestPlay = 0

    public init() {}

    public var netYards: Int { passYards + rushYards - sackYards }
    public var rushAverage: Float { rushAttempts > 0 ? Float(rushYards) / Float(rushAttempts) : 0 }
    /// Offensive snaps (kicks excluded).
    public var plays: Int { passAttempts + rushAttempts + sacks }

    /// Folds another possession's numbers into this running total.
    public mutating func add(_ other: DriveStats) {
        passAttempts += other.passAttempts
        completions += other.completions
        passYards += other.passYards
        passTouchdowns += other.passTouchdowns
        interceptions += other.interceptions
        sacks += other.sacks
        sackYards += other.sackYards
        rushAttempts += other.rushAttempts
        rushYards += other.rushYards
        rushTouchdowns += other.rushTouchdowns
        firstDowns += other.firstDowns
        longestPlay = max(longestPlay, other.longestPlay)
    }
}

/// Plays an opposing possession out on a private copy of the engine: the opponent's roster is the offense,
/// the user's defense is the defense, and both sides are driven by the CPU (a play-calling coach, a QB that
/// reads coverage, a runner that steers through traffic). Every snap is a real physics play — catches,
/// drops, interceptions, sacks and broken tackles all come from the same rules the user plays under.
struct OpponentDriveSimulator {
    struct Result {
        var drive: OpponentDrive
        /// Field y (user's point of view) where the user's next possession starts.
        var userLineOfScrimmage: Float
        var opponentPoints: Int
        var userPoints: Int
        var quarter: Int
        var clock: Float
    }

    private enum PlayAction: Equatable { case pass(EntityID), rush, scramble }

    private struct PlayResult {
        var outcome: PlayOutcome
        var spot: Vec2
        var gain: Int
        var seconds: Float
        var action: PlayAction?
        var carrierNumber: Int?
    }

    static let maxPlays = 40
    static let maxPlayTicks = 60 * 25

    private var match: Match
    private var brain = SandboxBrain()
    private var rng: PCG32

    init(
        seed: UInt64, playbook: Playbook, format: TeamFormat, curves: RatingCurves,
        offense: [Position: Match.RosterEntry], defense: [Position: Match.RosterEntry]
    ) {
        match = Match(seed: seed, playbook: playbook, format: format, curves: curves)
        match.isNestedSimulation = true
        match.setRoster(offense: offense, defense: defense)
        rng = PCG32(seed: seed, stream: 0x5EED_D21E)
    }

    // MARK: Drive

    mutating func run(
        team: String, trigger: OpponentDrive.Trigger, startLine: Float, quarter startQuarter: Int,
        clock startClock: Float, scoreDelta: Int
    ) -> Result {
        var quarter = startQuarter
        var clock = startClock
        var los = clamp(startLine.rounded(), Field.ownGoalLine + 1, Field.goalLine - 1)
        var down = 1
        var firstDown = min(los + 10, Field.goalLine)
        var plays = 0
        var seconds: Float = 0
        var stats = DriveStats()
        var log: [String] = []
        var points = 0
        var userPoints = 0
        var ending: OpponentDrive.Ending = .endOfGame
        var endLine = los
        // User's next line of scrimmage, in the user's coordinates.
        var userLOS = Match.kickoffYardLine

        func yardText(_ y: Float) -> String { OpponentDrive.spot(Int((y - Field.ownGoalLine).rounded())) }
        func situation() -> String {
            let ordinals = ["1ST", "2ND", "3RD", "4TH"]
            let togo = firstDown >= Field.goalLine ? "GOAL" : "\(max(1, Int((firstDown - los).rounded())))"
            return "\(ordinals[min(3, down - 1)])&\(togo) \(yardText(los))"
        }
        func useClock(_ s: Float) {
            seconds += s
            clock = max(0, clock - s)
        }

        driveLoop: while true {
            if clock <= 0 {
                // The possession carries over into Q2/Q4; halftime and the final gun end it.
                if quarter == 1 || quarter == 3 {
                    quarter += 1
                    clock = Match.quarterSeconds
                } else if quarter == 2 {
                    quarter = 3
                    clock = Match.quarterSeconds
                    ending = .endOfHalf
                    endLine = los
                    userLOS = Match.kickoffYardLine
                    break driveLoop
                } else {
                    ending = .endOfGame
                    endLine = los
                    userLOS = Match.kickoffYardLine
                    break driveLoop
                }
            }
            if plays >= Self.maxPlays {
                ending = .downs
                endLine = los
                userLOS = clamp(Match.mirrored(los), Field.ownGoalLine + 1, Field.goalLine - 1)
                break
            }

            let toGo = firstDown - los
            if down == 4 {
                let kickDistance = Int((Field.goalLine - los).rounded()) + 17
                let trailingLate = quarter == 4 && clock < 75 && scoreDelta + points < 0
                let shortYardage = toGo <= 1.5 && los >= 55
                let goForIt =
                    trailingLate && (scoreDelta + points < -3 || kickDistance > 52)
                    || (shortYardage && kickDistance > 45 && rng.unitFloat() < 0.6)
                if !goForIt && kickDistance <= 54 {
                    plays += 1
                    useClock(5)
                    let chance = clamp(1.02 - Float(kickDistance - 18) * 0.018, 0.35, 0.97)
                    endLine = los
                    if rng.unitFloat() < chance {
                        points += 3
                        ending = .fieldGoal
                        userLOS = Match.kickoffYardLine
                        log.append("\(situation())  \(kickDistance) YD FIELD GOAL IS GOOD")
                    } else {
                        ending = .missedFieldGoal
                        // Spot of the kick or the 20, whichever is better for the receiving team.
                        userLOS = max(Match.mirrored(los - 7), Field.ownGoalLine + 20)
                        log.append("\(situation())  \(kickDistance) YD FIELD GOAL NO GOOD")
                    }
                    break
                }
                if !goForIt {
                    plays += 1
                    useClock(6)
                    let distance = (36 + rng.unitFloat() * 16).rounded()
                    let landing = los + distance
                    endLine = los
                    ending = .punt
                    if landing >= Field.goalLine {
                        userLOS = Field.ownGoalLine + 20
                        log.append("\(situation())  PUNT \(Int(distance)) YDS  TOUCHBACK")
                    } else {
                        let returned = Float(Int(rng.nextUInt32() % 12))
                        userLOS = clamp(Match.mirrored(landing) + returned, Field.ownGoalLine + 1, Field.goalLine - 1)
                        log.append("\(situation())  PUNT \(Int(distance)) YDS  RETURN \(Int(returned))")
                    }
                    break
                }
            }

            let before = situation()
            let r = runPlay(los: los, down: down, toGo: toGo)
            plays += 1
            let runoff: Float =
                (r.outcome == .incomplete || r.outcome == .outOfBounds) ? 1 : 4 + rng.unitFloat() * 5
            useClock(r.seconds + runoff)
            stats.longestPlay = max(stats.longestPlay, r.gain)
            let who = r.carrierNumber.map { "#\($0)" } ?? ""
            let signed = "\(r.gain >= 0 ? "+" : "")\(r.gain)"

            switch r.outcome {
            case .interception:
                stats.passAttempts += 1
                stats.interceptions += 1
                log.append("\(before)  PASS INTERCEPTED")
                ending = .interception
                endLine = los
                let userSpot = Match.mirrored(r.spot.y)
                userLOS =
                    userSpot <= Field.ownGoalLine
                    ? Field.ownGoalLine + 20 : clamp(userSpot.rounded(), Field.ownGoalLine + 1, Field.goalLine - 1)
                break driveLoop
            case .incomplete:
                stats.passAttempts += 1
                log.append("\(before)  INCOMPLETE PASS")
            case .missedToss:
                stats.rushAttempts += 1
                stats.rushYards += r.gain
                log.append("\(before)  MISSED TOSS  \(signed)")
            case .safety:
                if case .pass = r.action { stats.passAttempts += 1 } else if r.action == nil { stats.sacks += 1 }
                log.append("\(before)  TACKLED IN END ZONE  SAFETY")
                userPoints += 2
                ending = .safety
                endLine = Field.ownGoalLine
                userLOS = Match.kickoffYardLine
                break driveLoop
            case .sack:
                stats.sacks += 1
                stats.sackYards += max(0, -r.gain)
                log.append("\(before)  SACKED  \(signed)")
            case .touchdown, .tackled, .outOfBounds, .dive:
                switch r.action {
                case .pass:
                    stats.passAttempts += 1
                    stats.completions += 1
                    stats.passYards += r.gain
                    if r.outcome == .touchdown { stats.passTouchdowns += 1 }
                    log.append("\(before)  PASS TO \(who)  \(signed)")
                case .scramble:
                    stats.rushAttempts += 1
                    stats.rushYards += r.gain
                    if r.outcome == .touchdown { stats.rushTouchdowns += 1 }
                    log.append("\(before)  QB RUN \(who)  \(signed)")
                case .rush, nil:
                    stats.rushAttempts += 1
                    stats.rushYards += r.gain
                    if r.outcome == .touchdown { stats.rushTouchdowns += 1 }
                    log.append("\(before)  RUN BY \(who)  \(signed)")
                }
            }

            if r.outcome == .touchdown {
                points += 7
                ending = .touchdown
                endLine = Field.goalLine
                userLOS = Match.kickoffYardLine
                log[log.count - 1] += "  TOUCHDOWN"
                break
            }

            let spot =
                r.outcome == .incomplete ? los : clamp(r.spot.y.rounded(), Field.ownGoalLine + 1, Field.goalLine - 1)
            if spot >= firstDown {
                stats.firstDowns += 1
                los = spot
                down = 1
                firstDown = min(los + 10, Field.goalLine)
            } else if down >= 4 {
                log[log.count - 1] += "  TURNOVER ON DOWNS"
                ending = .downs
                endLine = spot
                userLOS = Match.mirrored(spot)
                break
            } else {
                los = spot
                down += 1
            }
        }

        let startYard = Int((clamp(startLine.rounded(), Field.ownGoalLine + 1, Field.goalLine - 1) - Field.ownGoalLine))
        let endYard = Int((endLine - Field.ownGoalLine).rounded())
        let resume = clamp(userLOS.rounded(), Field.ownGoalLine + 1, Field.goalLine - 1)
        let drive = OpponentDrive(
            team: team, trigger: trigger, ending: ending, plays: plays, yards: endYard - startYard, points: points,
            seconds: seconds, startYard: startYard, endYard: endYard, stats: stats, playByPlay: log,
            resumeYard: Int(resume - Field.ownGoalLine))
        return Result(
            drive: drive, userLineOfScrimmage: resume, opponentPoints: points, userPoints: userPoints,
            quarter: quarter, clock: clock)
    }

    // MARK: One snap

    private mutating func runPlay(los: Float, down: Int, toGo: Float) -> PlayResult {
        match.setUpPlay(lineOfScrimmage: los, down: down, firstDownLine: min(los + max(toGo, 1), Field.goalLine))
        let card = callPlay(down: down, toGo: toGo, los: los)
        tick(TickInput(buttons: [.snap], playSelect: Int8(card)))

        let kind = match.offensePlay.kind
        var action: PlayAction?
        var ticks = 0
        var carrierNumber: Int?
        // QB clock: when he starts reading, and when he must get rid of it.
        let readTick: Int
        let deadline: Int
        switch kind {
        case .screen: readTick = 18 + Int(rng.nextUInt32() % 12); deadline = 60
        case .playAction: readTick = 55 + Int(rng.nextUInt32() % 20); deadline = 130
        default: readTick = 35 + Int(rng.nextUInt32() % 25); deadline = 115 + Int(rng.nextUInt32() % 25)
        }
        let handoffTick = 3 + Int(rng.nextUInt32() % 6)
        let openNeeded = 2.2 + rng.unitFloat() * 2.5
        // Sometimes the QB decides pre-snap and stares down one receiver instead of reading the coverage.
        let lockedOn: QBAction? = {
            let passes = match.availableQBActions.isEmpty ? match.offensePlay.qbActions : match.availableQBActions
            let lanes = passes.filter { $0 != .handoff && $0 != .toss }
            guard !lanes.isEmpty, rng.unitFloat() < 0.4 else { return nil }
            return lanes[Int(rng.nextUInt32() % UInt32(lanes.count))]
        }()

        while match.phase == .live {
            if let c = match.world.ballCarrier { carrierNumber = match.world[c].number }
            var input = TickInput()
            let world = match.world
            let qbActions = match.availableQBActions
            if !qbActions.isEmpty, let qbID = world.ballCarrier {
                let qb = world[qbID]
                if case .scramble = action {
                    input = runnerInput(qb)
                } else if kind == .keeper {
                    action = .scramble
                    input = runnerInput(qb)
                } else if kind == .run, qbActions.contains(.handoff) || qbActions.contains(.toss) {
                    if match.phaseTicks >= handoffTick {
                        input.buttons = [.handoff]
                        action = .rush
                    }
                } else {
                    let pressure = nearestDefender(to: qb.location, in: world)
                    let best = bestTarget(lockedOn.map { [$0] } ?? qbActions, los: los, in: world)
                    let ready = match.phaseTicks >= readTick
                    if ready, let best,
                        best.openness >= openNeeded || match.phaseTicks >= deadline || pressure < 2.0
                    {
                        if best.openness < 1.2 && pressure < 2.0 && rng.unitFloat() < 0.4 {
                            action = .scramble
                            input = runnerInput(qb)
                        } else {
                            input.buttons = Self.button(for: best.action)
                            action = .pass(best.receiver)
                        }
                    } else if best == nil && match.phaseTicks >= readTick {
                        action = .scramble
                        input = runnerInput(qb)
                    } else {
                        // Drop back into the pocket while the routes develop.
                        input.move = qb.location.y > los - 7 ? Vec2(0, -0.6) : .zero
                    }
                }
            } else if let c = world.ballCarrier, c == match.controlled {
                input = runnerInput(world[c])
            }
            tick(input)
            ticks += 1
            if ticks >= Self.maxPlayTicks { match.forceWhistle() }
        }

        let spot: Vec2
        if case .dead(let at) = match.world.ball { spot = at } else { spot = Vec2(0, los) }
        let outcome = match.lastOutcome ?? .tackled
        var gain = Int((spot.y - los).rounded())
        if outcome == .touchdown { gain = Int((Field.goalLine - los).rounded()) }
        if outcome == .incomplete || outcome == .interception { gain = 0 }
        if outcome == .safety { gain = Int((Field.ownGoalLine - los).rounded()) }
        if case .pass(let receiver) = action,
            outcome != .incomplete && outcome != .missedToss && outcome != .interception
        {
            carrierNumber = match.world[receiver].number
        }
        return PlayResult(
            outcome: outcome, spot: spot, gain: gain, seconds: Float(ticks) / Float(Match.ticksPerSecond),
            action: action, carrierNumber: carrierNumber)
    }

    private mutating func tick(_ input: TickInput) {
        let ai = brain.intents(world: match.world, context: match.playContext)
        match.step(input: input, ai: ai)
    }

    /// CPU coach: picks one of the three dealt cards, leaning pass on long yardage and run on short.
    private mutating func callPlay(down: Int, toGo: Float, los: Float) -> Int {
        var best = 0
        var bestScore = -Float.infinity
        for (slot, index) in match.playChoices.enumerated() {
            let kind = match.playbook.offense[index].kind
            let passing = kind == .pass || kind == .playAction || kind == .screen
            var score = rng.unitFloat()
            if toGo >= 7 && down >= 2 { score += passing ? 0.7 : 0 }
            if toGo <= 3 { score += passing ? 0 : 0.6 }
            if Field.goalLine - los <= 10 && kind == .run { score += 0.3 }
            if kind == .playAction && down == 1 { score += 0.25 }
            if score > bestScore { bestScore = score; best = slot }
        }
        return best
    }

    private struct Target {
        var action: QBAction
        var receiver: EntityID
        var openness: Float
    }

    /// The most open receiver, favoring depth a little so the QB doesn't always dump it off.
    private mutating func bestTarget(_ actions: [QBAction], los: Float, in world: World) -> Target? {
        var best: Target?
        var bestScore = -Float.infinity
        for action in actions {
            let lane: Lane
            switch action {
            case .passLeft: lane = .left
            case .passCenter: lane = .center
            case .passRight: lane = .right
            case .handoff, .toss: continue
            }
            guard let r = world.player(at: lane.slotPosition), !r.isDown else { continue }
            let lead = r.location + r.velocity * 0.4
            let openness = nearestDefender(to: lead, in: world)
            let depth = clamp(r.location.y - los, -3, 25)
            let score = min(openness, 6) + depth * 0.12 + rng.unitFloat() * 0.8
            if score > bestScore {
                bestScore = score
                best = Target(action: action, receiver: r.id, openness: openness)
            }
        }
        return best
    }

    private func nearestDefender(to point: Vec2, in world: World) -> Float {
        var best = Float.greatestFiniteMagnitude
        for d in world.players where d.side == .defense && !d.isDown {
            best = min(best, d.location.distance(to: point))
        }
        return best
    }

    /// Ball-carrier vision: scan a fan of headings, take the one with the most daylight (favoring upfield),
    /// and keep away from the sideline.
    private func runnerInput(_ carrier: PlayerState) -> TickInput {
        var bestDir = Vec2(0, 1)
        var bestScore = -Float.infinity
        for k in -5...5 {
            let angle = Float(k) * 0.26
            let dir = Vec2(sinf(angle), cosf(angle))
            var clearance: Float = 8
            for d in match.world.players where d.side == .defense && !d.isDown {
                let rel = d.location - carrier.location
                let along = (rel * dir).sum()
                guard along > -1, along < 10 else { continue }
                let perp = (rel - dir * along).length
                clearance = min(clearance, perp + max(0, along) * 0.3)
            }
            let endX = carrier.location.x + dir.x * 6
            if abs(endX) > Field.halfWidth - 1.5 { clearance -= 4 }
            let score = clearance + cosf(angle) * 2
            if score > bestScore {
                bestScore = score
                bestDir = dir
            }
        }
        return TickInput(move: bestDir, turbo: true)
    }

    private static func button(for action: QBAction) -> TickInput.Buttons {
        switch action {
        case .passLeft: .passLeft
        case .passCenter: .passCenter
        case .passRight: .passRight
        case .handoff, .toss: .handoff
        }
    }
}
