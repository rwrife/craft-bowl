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

/// Box score for a simulated opposing-team possession, shown to the user once the drive is over.
public struct OpponentDrive: Sendable, Equatable {
    /// What handed the ball over to the opposing team.
    public enum Trigger: String, Sendable, Equatable {
        case touchdown, interception, downs, safety

        public var text: String {
            switch self {
            case .touchdown: "AFTER KICKOFF"
            case .interception: "AFTER INTERCEPTION"
            case .downs: "AFTER TURNOVER ON DOWNS"
            case .safety: "AFTER SAFETY"
            }
        }
    }

    /// How the possession finished.
    public enum Ending: String, Sendable, Equatable {
        case touchdown, fieldGoal, missedFieldGoal, punt, downs, turnover, clockExpired

        public var text: String {
            switch self {
            case .touchdown: "TOUCHDOWN"
            case .fieldGoal: "FIELD GOAL"
            case .missedFieldGoal: "MISSED FIELD GOAL"
            case .punt: "PUNT"
            case .downs: "TURNOVER ON DOWNS"
            case .turnover: "TURNOVER"
            case .clockExpired: "END OF QUARTER"
            }
        }
    }

    public let team: String
    public let trigger: Trigger
    public let ending: Ending
    public let plays: Int
    public let yards: Int
    public let points: Int
    public let seconds: Float
    /// Where the drive started and finished, as the opposing team's own yard line (0–100).
    public let startYard: Int
    public let endYard: Int

    public var headline: String { "\(team) DRIVE" }
    public var timeOfPossession: String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    public var resultText: String { points > 0 ? "\(ending.text)  (+\(points))" : ending.text }
    public var fieldPositionText: String {
        func spot(_ yard: Int) -> String {
            yard == 50 ? "MIDFIELD" : (yard < 50 ? "OWN \(yard)" : "OPP \(100 - yard)")
        }
        return "\(spot(startYard)) → \(spot(endYard))"
    }
}

/// Simplified game rules around one user offense vs a CPU defense (sandbox until issue #29 lands):
/// formation → snap → QB phase → runner phase → whistle → spot & downs.
public struct Match: Sendable {
    public static let ticksPerSecond = Int(GameClock.ticksPerSecond)
    public static let autoSnapTicks = 60 * 10
    public static let deadBallTicks = 150
    /// The opposing-possession recap stays up this long if the user never snaps the next play.
    public static let driveRecapTicks = 60 * 30
    public static let quarterSeconds: Float = 180

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
    /// Offense play-book indices offered this down (3 random, distinct). The user must pick one before the snap.
    public private(set) var playChoices: [Int] = []
    /// Which of `playChoices` is picked, or nil until the user chooses.
    public private(set) var chosenChoice: Int?
    /// Box score of the most recent simulated opposing possession, cleared at the next snap.
    public private(set) var opponentDrive: OpponentDrive?
    /// Name shown for the opposing team in drive recaps (set from the selected away team).
    public private(set) var opponentName = "OPPONENT"
    public static let choicesPerDown = 3

    private var opponentDriveTicks = 0

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

    /// Players the play is built around (pass targets, the runner, the QB on a keeper). They wear down while it's live.
    public func keyPlayers(for play: OffensivePlay) -> [EntityID] {
        var ids: [EntityID] = []
        for lane in Lane.allCases where play.slots[lane]?.role == .target {
            if let p = world.player(at: lane.slotPosition) { ids.append(p.id) }
        }
        if play.kind == .keeper, let qb = world.player(at: .qb) { ids.append(qb.id) }
        return ids
    }

    /// Who gets a stat bar overhead right now: the key players while picking a play (every skill player until a
    /// card is chosen), then only a runner (after a catch/handoff or a QB scramble) once the ball is snapped.
    public var statBarPlayers: [EntityID] {
        switch phase {
        case .preSnap:
            if chosenChoice != nil { return keyPlayers(for: offensePlay) }
            return [Position.laneLeft, .laneCenter, .laneRight, .rb].compactMap { world.player(at: $0)?.id }
        case .live:
            guard runnerPhase, let c = world.ballCarrier, world[c].side == .offense else { return [] }
            return [c]
        case .dead:
            return []
        }
    }

    public var playContext: PlayContext {
        PlayContext(
            offense: offensePlay, defense: defensePlay, lineOfScrimmage: lineOfScrimmage,
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

    public mutating func setOpponentName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        opponentName = trimmed.isEmpty ? "OPPONENT" : trimmed
    }

    public mutating func setRoster(
        offense: [Position: (ratings: Ratings, number: Int)],
        defense: [Position: (ratings: Ratings, number: Int)]
    ) {
        for index in world.players.indices {
            let position = world.players[index].position
            let roster = position.side == .offense ? offense : defense
            guard let player = roster[position] else { continue }
            world.players[index].ratings = player.ratings
            world.players[index].number = player.number
            world.players[index].stamina = Stamina(ratings: player.ratings, curves: world.curves)
        }
    }

    // MARK: Tick

    public mutating func step(input: TickInput, ai: [EntityID: PlayerIntent]) {
        phaseTicks += 1
        if opponentDrive != nil {
            opponentDriveTicks -= 1
            if opponentDriveTicks <= 0 { opponentDrive = nil }
        }
        switch phase {
        case .preSnap: stepPreSnap(input)
        case .live: stepLive(input, ai: ai)
        case .dead:
            world.step(intents: [:])
            if phaseTicks >= Match.deadBallTicks { resetFormation() }
        }
    }

    private mutating func stepPreSnap(_ input: TickInput) {
        world.step(intents: [:])
        let n = playChoices.count
        guard n > 0 else { snap(); return }
        // Before a pick, the lane buttons (J/K/L, X/A/B) choose a card; after it, any action button snaps.
        let wasChosen = chosenChoice != nil
        if input.playSelect >= 0 && Int(input.playSelect) < n { choose(Int(input.playSelect)) }
        if !wasChosen {
            if input.buttons.contains(.passLeft) {
                choose(0)
            } else if input.buttons.contains(.passCenter) {
                choose(min(1, n - 1))
            } else if input.buttons.contains(.passRight) {
                choose(min(2, n - 1))
            }
        }
        if input.buttons.contains(.nextPlay) { choose(((chosenChoice ?? -1) + 1) % n) }
        if input.buttons.contains(.previousPlay) { choose(((chosenChoice ?? 0) + n - 1) % n) }

        let snapButtons: TickInput.Buttons = [.snap, .passLeft, .passCenter, .passRight, .handoff]
        let wantsSnap = input.buttons.contains(.snap) || (wasChosen && !input.buttons.isDisjoint(with: snapButtons))
        if chosenChoice != nil && wantsSnap {
            snap()
        } else if phaseTicks >= Match.autoSnapTicks {
            // Play clock ran out: stuck with a random card.
            if chosenChoice == nil { choose(Int(world.rng.nextUInt32() % UInt32(n))) }
            snap()
        }
    }

    private mutating func choose(_ i: Int) {
        chosenChoice = i
        offenseIndex = playChoices[i]
    }

    private mutating func dealPlayChoices() {
        var pool = Array(playbook.offense.indices)
        var picks: [Int] = []
        while picks.count < Match.choicesPerDown && !pool.isEmpty {
            picks.append(pool.remove(at: Int(world.rng.nextUInt32() % UInt32(pool.count))))
        }
        playChoices = picks
        chosenChoice = nil
    }

    private mutating func snap() {
        defenseIndex = Int(world.rng.nextUInt32() % UInt32(playbook.defense.count))
        guard let qb = world.player(at: .qb) else { return }
        opponentDrive = nil
        opponentDriveTicks = 0
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
        updateExertion()
        world.step(intents: intents)
        for event in world.events { handle(event) }
        guard phase == .live else { return }
        checkCarrier()
    }

    /// Key players and the ball carrier (once they're running with it) drain health; everyone else recovers.
    private mutating func updateExertion() {
        let key = keyPlayers(for: offensePlay)
        let carrier = world.ballCarrier
        for i in world.players.indices {
            let p = world.players[i]
            let carrying = p.id == carrier && (runnerPhase || p.position != .qb)
            world.players[i].isExerting = key.contains(p.id) || carrying
        }
    }

    private mutating func handleQBButtons(_ buttons: TickInput.Buttons) {
        let actions = availableQBActions
        guard !actions.isEmpty, let qbID = world.ballCarrier else { return }
        if buttons.contains(.passLeft), actions.contains(.passLeft) {
            pass(to: .left, from: qbID)
        } else if buttons.contains(.passCenter), actions.contains(.passCenter) {
            pass(to: .center, from: qbID)
        } else if buttons.contains(.passRight), actions.contains(.passRight) {
            pass(to: .right, from: qbID)
        } else if buttons.contains(.handoff), actions.contains(.handoff) || actions.contains(.toss),
            let rb = world.player(at: .rb)
        {
            world.ball = .held(by: rb.id)
            controlled = rb.id
            runnerPhase = true
        }
    }

    private mutating func pass(to lane: Lane, from qbID: EntityID) {
        guard let r = world.player(at: lane.slotPosition) else { return }
        let qb = world[qbID]
        let armSpeed = world.curves.quarterbackPassSpeed(qb.ratings)
        var aim = r.location
        for _ in 0..<2 {
            let t = qb.location.distance(to: aim) / armSpeed
            aim = r.location + r.velocity * t
        }
        let pressured = world.players.contains {
            $0.side == .defense && !$0.isDown && $0.location.distance(to: qb.location) < 2.5
        }
        // Accuracy: a tired or low-ability QB sprays the ball, more so on long throws and under pressure.
        let spread =
            (1 - qb.ability(world.curves)) * (0.6 + qb.location.distance(to: aim) * 0.06)
            + (pressured ? 1.5 : 0)
        aim += Vec2(world.rng.unitFloat() * 2 - 1, world.rng.unitFloat() * 2 - 1) * spread
        aim.x = clamp(aim.x, -Field.halfWidth + 0.5, Field.halfWidth - 0.5)
        aim.y = clamp(aim.y, Field.wallMinY + 0.5, Field.wallMaxY - 0.5)
        let dist = qb.location.distance(to: aim)
        world.throwBall(to: aim, target: r.id, speed: armSpeed, peak: 0.6 + dist * 0.07)
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
            if world.rng.unitFloat() < 0.12 + 0.3 * d.ability(world.curves) {
                world.ball = .held(by: d.id)
                endPlay(.interception, at: d.location)
            } else {
                endPlay(.incomplete, at: spot, text: "BROKEN UP!")
            }
            return
        }
        if let target, !world[target].isDown {
            // Ability (after fatigue) widens the catch radius and makes the hands surer; a nearby defender hurts.
            let r = world[target]
            let ability = r.ability(world.curves)
            let reach: Float = (r.isDiving ? 0.6 : 0) + 1.2 + 0.9 * ability
            guard receiverDist < reach else { endPlay(.incomplete, at: spot); return }
            let contested = defender.map { $0.location.distance(to: spot) < 2.2 } ?? false
            let chance = clamp(0.62 + 0.38 * ability - (contested ? 0.18 : 0) - receiverDist * 0.08, 0.25, 0.98)
            guard world.rng.unitFloat() < chance else {
                endPlay(.incomplete, at: spot, text: "DROPPED!")
                return
            }
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
            let chance = clamp(
                0.72 + 0.35 * (d.ratings.p - c.ratings.p) - 0.25 * c.ratings.s * c.health
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
        for i in world.players.indices { world.players[i].isExerting = false }
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
            simulateOpponentDrive(after: .touchdown)
        case .safety:
            awayScore += 2
            message = "SAFETY!"
            restartDrive()
        case .interception:
            message = "INTERCEPTED!"
            restartDrive()
            simulateOpponentDrive(after: .interception)
        case .incomplete:
            message = text ?? "INCOMPLETE"
            advanceDown(to: lineOfScrimmage)
        case .tackled, .outOfBounds, .dive, .sack:
            let base =
                outcome == .sack
                ? "SACKED" : outcome == .outOfBounds ? "OUT OF BOUNDS" : outcome == .dive ? "DIVE!" : "TACKLED"
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
            simulateOpponentDrive(after: .downs)
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

    /// Temporary single-player possession simulation until defensive gameplay is available: plays out the
    /// opposing drive with the deterministic RNG and records a box score for the recap panel.
    private mutating func simulateOpponentDrive(after trigger: OpponentDrive.Trigger) {
        let startYard = 25
        var yard = Float(startYard)
        var driveDown = 1
        var toGo: Float = 10
        var plays = 0
        var seconds: Float = 0
        var points = 0
        var ending: OpponentDrive.Ending = .punt

        while plays < 24 {
            if clock <= 0 { ending = .clockExpired; break }
            plays += 1
            let elapsed = Float(8 + world.rng.nextUInt32() % 9)
            seconds += elapsed
            clock = max(0, clock - elapsed)

            let roll = world.rng.unitFloat()
            let gain: Float
            switch roll {
            case ..<0.22: gain = 0  // incompletion / stuff
            case ..<0.34: gain = -Float(world.rng.nextUInt32() % 8) - 1  // loss or sack
            case ..<0.80: gain = Float(world.rng.nextUInt32() % 9) + 1  // short gain
            case ..<0.97: gain = Float(9 + world.rng.nextUInt32() % 13)  // chunk play
            default: gain = Float(22 + world.rng.nextUInt32() % 30)  // big play
            }
            yard = clamp(yard + gain, 1, 100)

            if yard >= 100 {
                points = 7
                awayScore += 7
                ending = .touchdown
                break
            }
            if world.rng.unitFloat() < 0.022 {
                ending = .turnover
                break
            }
            if gain >= toGo {
                driveDown = 1
                toGo = min(10, 100 - yard)
            } else if driveDown >= 4 {
                // Fourth down: try a field goal in range, otherwise punt it away.
                if yard >= 62 {
                    if world.rng.unitFloat() < clamp(0.35 + (yard - 62) * 0.016, 0.3, 0.9) {
                        points = 3
                        awayScore += 3
                        ending = .fieldGoal
                    } else {
                        ending = .missedFieldGoal
                    }
                } else {
                    ending = world.rng.unitFloat() < 0.15 ? .downs : .punt
                }
                break
            } else {
                driveDown += 1
                toGo -= gain
            }
        }

        let endYard = ending == .touchdown ? 100 : Int(yard.rounded())
        opponentDriveTicks = Match.driveRecapTicks
        opponentDrive = OpponentDrive(
            team: opponentName, trigger: trigger, ending: ending,
            plays: plays, yards: endYard - startYard, points: points,
            seconds: seconds, startYard: startYard, endYard: endYard)
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
            p.location = Field.clampToWalls(Vec2(o.x, lineOfScrimmage + o.y), radius: World.playerRadius)
            p.velocity = .zero
            p.facing = p.side == .offense ? 0 : .pi
            p.isDown = false
            p.diveTicks = 0
            p.recoverTicks = 0
            p.engagedTicks = 0
            p.isExerting = false
            p.stamina.resetTurbo()
            world.players[i] = p
        }
        world.ball = .dead(at: Vec2(0, lineOfScrimmage))
        dealPlayChoices()
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
        // (power, speed, endurance, ability)
        let base: (Int, Int, Int, Int) =
            switch p {
            case .qb: (55, 68, 65, 80)
            case .rb: (72, 84, 70, 62)
            case .laneLeft: (48, 92, 58, 72)
            case .laneCenter: (58, 80, 78, 84)
            case .laneRight: (50, 86, 68, 66)
            case .lt, .lg, .rg, .rt: (90, 42, 75, 30)
            case .deL, .nt, .deR: (86, 52, 70, 40)
            case .mlb: (78, 72, 75, 55)
            case .olb: (70, 78, 70, 55)
            case .cbL, .cbR: (50, 88, 70, 62)
            case .fs, .ss: (62, 82, 70, 66)
            }
        func vary(_ v: Int) -> Int { v + Int(rng.nextUInt32() % 13) - 6 }
        return Ratings(power: vary(base.0), speed: vary(base.1), endurance: vary(base.2), ability: vary(base.3))
    }
}
