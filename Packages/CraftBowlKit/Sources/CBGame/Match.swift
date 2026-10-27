import CBAI
import CBCore
import CBPlays
import CBSim
import Foundation

public enum PlayPhase: String, Sendable, Equatable {
    case preSnap, live, dead
}

public enum PlayOutcome: String, Sendable, Equatable {
    case tackled, outOfBounds, touchdown, incomplete, missedToss, interception, fumble, safety, dive, sack
}

/// Box score for a simulated opposing-team possession, shown to the user once the drive is over.
public struct OpponentDrive: Sendable, Equatable {
    /// What handed the ball over to the opposing team.
    public enum Trigger: String, Sendable, Equatable {
        case touchdown, interception, fumble, downs, safety

        public var text: String {
            switch self {
            case .touchdown: "AFTER KICKOFF"
            case .interception: "AFTER INTERCEPTION"
            case .fumble: "AFTER FUMBLE"
            case .downs: "AFTER TURNOVER ON DOWNS"
            case .safety: "AFTER SAFETY KICK"
            }
        }
    }

    /// How the possession finished.
    public enum Ending: String, Sendable, Equatable {
        case touchdown, fieldGoal, missedFieldGoal, punt, downs, interception, fumble, safety, endOfHalf, endOfGame

        public var text: String {
            switch self {
            case .touchdown: "TOUCHDOWN"
            case .fieldGoal: "FIELD GOAL"
            case .missedFieldGoal: "MISSED FIELD GOAL"
            case .punt: "PUNT"
            case .downs: "TURNOVER ON DOWNS"
            case .interception: "INTERCEPTED"
            case .fumble: "FUMBLE"
            case .safety: "SAFETY"
            case .endOfHalf: "END OF HALF"
            case .endOfGame: "END OF GAME"
            }
        }

        /// The defense (the user) got the ball back without the opponent scoring.
        public var isStop: Bool {
            switch self {
            case .punt, .downs, .interception, .fumble, .missedFieldGoal, .safety: true
            default: false
            }
        }
    }

    public let team: String
    public let trigger: Trigger
    public let ending: Ending
    public let plays: Int
    public let yards: Int
    /// Points the opposing team scored on the drive.
    public let points: Int
    public let seconds: Float
    /// Where the drive started and finished, as the opposing team's own yard line (0–100).
    public let startYard: Int
    public let endYard: Int
    /// Passing / rushing box score built from the simulated plays.
    public let stats: DriveStats
    /// One line per snap / kick, oldest first.
    public let playByPlay: [String]
    /// The user's own yard line (0–100) where their next possession starts.
    public let resumeYard: Int

    public init(
        team: String, trigger: Trigger, ending: Ending, plays: Int, yards: Int, points: Int, seconds: Float,
        startYard: Int, endYard: Int, stats: DriveStats = DriveStats(), playByPlay: [String] = [],
        resumeYard: Int = 25
    ) {
        self.team = team
        self.trigger = trigger
        self.ending = ending
        self.plays = plays
        self.yards = yards
        self.points = points
        self.seconds = seconds
        self.startYard = startYard
        self.endYard = endYard
        self.stats = stats
        self.playByPlay = playByPlay
        self.resumeYard = resumeYard
    }

    public var headline: String { "\(team) DRIVE" }
    public var timeOfPossession: String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    public var resultText: String { points > 0 ? "\(ending.text)  +\(points)" : ending.text }
    public var fieldPositionText: String {
        "\(OpponentDrive.spot(startYard)) → \(ending == .touchdown ? "END ZONE" : OpponentDrive.spot(endYard))"
    }
    public var resumeText: String {
        ending == .endOfGame ? "THAT'S THE GAME" : "YOUR BALL  \(OpponentDrive.spot(resumeYard))"
    }

    /// "OWN 25" / "MIDFIELD" / "OPP 30" from a 0–100 own-yard line.
    public static func spot(_ yard: Int) -> String {
        yard == 50 ? "MIDFIELD" : (yard < 50 ? "OWN \(yard)" : "OPP \(100 - yard)")
    }
}

/// Simplified game rules around one user offense vs a CPU defense (sandbox until issue #29 lands):
/// formation → snap → QB phase → runner phase → whistle → spot & downs.
public struct Match: Sendable {
    public static let ticksPerSecond = Int(GameClock.ticksPerSecond)
    public static let autoSnapTicks = 60 * 10
    public static let deadBallTicks = 150
    /// The opposing-possession recap stays up this long (pre-snap) if the user never dismisses it.
    public static let driveRecapTicks = 60 * 30
    /// The recap ignores buttons for this long so a late button mash doesn't skip it.
    public static let driveRecapMinTicks = 30
    /// Internal testing seam to apply a simulated drive outcome.
    mutating func recordOpponentDriveResultForTesting(_ result: OpponentDriveSimulator.Result) {
        applyOpponentDriveResult(result)
    }

    /// Opposing kickoffs/free kicks are fielded at the receiving team's own 25.
    public static let kickoffYardLine: Float = Field.ownGoalLine + 25
    public static let quarterSeconds: Float = 180
    /// The final-score screen ignores buttons this long so the last play's button mash doesn't start a rematch.
    public static let gameOverMinTicks = 90
    public static let halftimeMinTicks = 90

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
    /// Running box scores: the user's snaps, and every simulated opposing possession.
    public private(set) var homeGame = TeamGameStats()
    public private(set) var awayGame = TeamGameStats()
    /// The final gun has sounded: the sim holds on the final-score screen until a button starts a rematch.
    public private(set) var isGameOver = false
    /// Halftime screen is active between Q2 and Q3 until dismissed by the user.
    public private(set) var isHalftime = false
    public static let choicesPerDown = 3
    public typealias RosterEntry = (ratings: Ratings, number: Int)

    private var halftimeDue = false
    private var halftimeTicks = 0
    private var opponentDriveTicks = 0

    /// Rosters for the simulated opposing possession: their offense against the user's defense.
    private var opponentOffenseRoster: [Position: RosterEntry] = [:]
    private var homeDefenseRoster: [Position: RosterEntry] = [:]
    /// Set on the headless copy that plays out an opposing drive, so it never recurses into another one.
    var isNestedSimulation = false
    /// How the current snap is unfolding, for the user's box score.
    private var playThrown = false
    private var playCaught = false
    /// Receiver for a short backfield pitch; pass catches use the normal hands/contest rules.
    private var tossTarget: EntityID?
    private var looseFumbleTicks = 0

    private var nextLOS: Float = 35
    private var nextDown = 1
    private var nextFirstDown: Float = 45

    public var offensePlay: OffensivePlay { playbook.offense[offenseIndex] }
    public var defensePlay: DefensivePlay { playbook.defense[defenseIndex] }
    public var yardsToGo: Float { firstDownLine - lineOfScrimmage }
    /// Both teams' final (or, mid-game, running) numbers.
    public var gameSummary: GameSummary {
        GameSummary(homeScore: homeScore, awayScore: awayScore, home: homeGame, away: awayGame)
    }
    /// 4th quarter with no time left: the game ends as soon as the current play / recap is done.
    private var isFinalGun: Bool { quarter == 4 && clock <= 0 }

    /// The opposing-drive recap dialog is up: play selection waits until it's dismissed.
    public var isShowingDriveRecap: Bool { phase == .preSnap && opponentDrive != nil }
    /// Pre-snap ticks the current recap has been on screen.
    public var driveRecapElapsedTicks: Int { opponentDrive == nil ? 0 : Match.driveRecapTicks - opponentDriveTicks }

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

    /// - Parameters:
    ///   - offense/defense: the players on the field (user offense vs opposing defense).
    ///   - opponentOffense/homeDefense: who plays when the opposing possession is simulated.
    public mutating func setRoster(
        offense: [Position: RosterEntry],
        defense: [Position: RosterEntry],
        opponentOffense: [Position: RosterEntry] = [:],
        homeDefense: [Position: RosterEntry] = [:]
    ) {
        opponentOffenseRoster = opponentOffense
        homeDefenseRoster = homeDefense
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
        if isGameOver {
            stepGameOver(input)
            return
        }
        if isHalftime {
            halftimeTicks += 1
            let pressed = !input.buttons.isEmpty || input.playSelect >= 0
            if pressed && halftimeTicks >= Match.halftimeMinTicks { dismissHalftime() }
            return
        }
        if isShowingDriveRecap {
            opponentDriveTicks -= 1
            if opponentDriveTicks <= 0 { dismissDriveRecap() }
            if isGameOver || isHalftime { return }
        }
        switch phase {
        case .preSnap: stepPreSnap(input)
        case .live: stepLive(input, ai: ai)
        case .dead:
            world.step(intents: [:])
            guard phaseTicks >= Match.deadBallTicks else { break }
            // A drive recap (e.g. the opponent ran out the clock) still gets shown before the final screen.
            if isFinalGun && opponentDrive == nil {
                endGame()
            } else if halftimeDue && opponentDrive == nil {
                startHalftime()
            } else {
                resetFormation()
            }
        }
    }

    private mutating func stepGameOver(_ input: TickInput) {
        world.step(intents: [:])
        let pressed = !input.buttons.isEmpty || input.playSelect >= 0
        if pressed && phaseTicks >= Match.gameOverMinTicks { startNewGame() }
    }

    private mutating func startHalftime() {
        isHalftime = true
        halftimeDue = false
        halftimeTicks = 0
        message = "HALFTIME"
    }

    private mutating func dismissHalftime() {
        isHalftime = false
        halftimeTicks = 0
        // Second half starts with a fresh kickoff; no down, ball position or held input crosses halftime.
        restartDrive()
        nextLOS = Match.kickoffYardLine
        nextFirstDown = min(nextLOS + 10, Field.goalLine)
        message = "SELECT PLAY"
        resetFormation()
    }

    private mutating func endGame() {
        isGameOver = true
        phase = .dead
        phaseTicks = 0
        opponentDrive = nil
        opponentDriveTicks = 0
        controlled = nil
        runnerPhase = false
        message = "FINAL"
    }

    /// Rematch: same teams, fresh score, clock and box scores; the user receives the opening kickoff.
    public mutating func startNewGame() {
        isGameOver = false
        isHalftime = false
        halftimeDue = false
        halftimeTicks = 0
        homeScore = 0
        awayScore = 0
        quarter = 1
        clock = Match.quarterSeconds
        homeGame = TeamGameStats()
        awayGame = TeamGameStats()
        opponentDrive = nil
        opponentDriveTicks = 0
        lastOutcome = nil
        for i in world.players.indices {
            world.players[i].stamina = Stamina(ratings: world.players[i].ratings, curves: world.curves)
        }
        message = ""
        restartDrive()
        resetFormation()
    }

    private mutating func stepPreSnap(_ input: TickInput) {
        world.step(intents: [:])
        if opponentDrive != nil {
            // The recap is modal: the play clock waits and the first button press only closes it.
            phaseTicks = 0
            let pressed = !input.buttons.isEmpty || input.playSelect >= 0
            if pressed && driveRecapElapsedTicks >= Match.driveRecapMinTicks { dismissDriveRecap() }
            return
        }
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

    private mutating func dismissDriveRecap() {
        opponentDrive = nil
        opponentDriveTicks = 0
        phaseTicks = 0
        message = "SELECT PLAY"
        if isFinalGun {
            endGame()
        } else if halftimeDue {
            startHalftime()
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
        playThrown = false
        playCaught = false
        tossTarget = nil
        looseFumbleTicks = 0
        message = ""
        playNumber += 1
    }

    private mutating func stepLive(_ input: TickInput, ai: [EntityID: PlayerIntent]) {
        let used = min(clock, World.dt)
        clock -= used
        homeGame.seconds += used
        var intents = ai
        if looseFumbleTicks > 0 {
            let spot = world.ballLocation
            for player in world.players where !player.isDown {
                intents[player.id] = PlayerIntent(move: (spot - player.location).normalized)
            }
        } else if let c = controlled {
            intents[c] = PlayerIntent(move: input.move, turbo: input.turbo, dive: input.buttons.contains(.dive))
        }
        handleQBButtons(input.buttons)
        updateExertion()
        world.step(intents: intents)
        for event in world.events { handle(event) }
        guard phase == .live else { return }
        if looseFumbleTicks > 0 {
            resolveLooseFumble()
        } else {
            resolveCarrierContact()
        }
    }

    var completedPassThisPlay: Bool { playCaught }

    /// Internal testing seam to exercise receiver contact after a catch.
    mutating func markPlayCaughtForTesting() {
        playCaught = true
        runnerPhase = true
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
        } else if buttons.contains(.handoff), actions.contains(.handoff),
            let rb = world.player(at: .rb)
        {
            let qb = world[qbID]
            // Direct exchange window: the running back must be close enough for a hand-to-hand mesh.
            guard qb.location.distance(to: rb.location) <= 2.2 else { return }
            world.ball = .held(by: rb.id)
            controlled = rb.id
            runnerPhase = true
        } else if buttons.contains(.handoff), actions.contains(.toss),
            let rb = world.player(at: .rb)
        {
            // Pitch towards the running back's stride with a low arc.
            let tossSpeed: Float = 14
            let lead = rb.velocity * 0.25
            let targetSpot = rb.location + lead
            guard targetSpot.y <= world[qbID].location.y else { return }  // forward throw uses pass rules
            world.throwBall(to: targetSpot, target: rb.id, speed: tossSpeed, peak: 0.35)
            tossTarget = rb.id
            playThrown = false
            controlled = nil
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
        let accuracy =
            world.curves.quarterbackAccuracy(qb.ratings)
            * lerp(world.curves.exhaustedAbilityFactor, 1, qb.health)
        let spread =
            (1 - accuracy) * (0.6 + qb.location.distance(to: aim) * 0.06)
            + (pressured ? 1.5 : 0)
        aim += Vec2(world.rng.unitFloat() * 2 - 1, world.rng.unitFloat() * 2 - 1) * spread
        aim.x = clamp(aim.x, -Field.halfWidth + 0.5, Field.halfWidth - 0.5)
        aim.y = clamp(aim.y, Field.wallMinY + 0.5, Field.wallMaxY - 0.5)
        let dist = qb.location.distance(to: aim)
        world.throwBall(to: aim, target: r.id, speed: armSpeed, peak: 0.6 + dist * 0.07)
        playThrown = true
        // AI runs the receiver to the ball; the user takes over on the catch.
        controlled = nil
    }

    private mutating func handle(_ event: SimEvent) {
        switch event {
        case .ballArrived(let at, let target):
            if let toss = tossTarget {
                // A short pitch simply has to find the running back in the exchange radius; no hands roll.
                if target == toss, world[toss].location.distance(to: at) <= 1.2, !world[toss].isDown {
                    world.ball = .held(by: toss)
                    controlled = toss
                    runnerPhase = true
                    playCaught = false
                    tossTarget = nil
                    message = ""
                } else {
                    endPlay(.missedToss, at: at)
                }
                return
            }
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

    /// Test hook: place players / ball state for headless rule probes (issue #27 catch-rate fixtures).
    mutating func mutateWorld(_ body: (inout World) -> Void) { body(&world) }

    /// Internal (not private) so headless acceptance tests can resolve a catch at a controlled spot.
    mutating func resolveCatch(at spot: Vec2, target: EntityID?) {
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
            // Receiver hands (Ability curve, after fatigue) widen the catch radius and make the hands surer; a nearby defender hurts.
            let r = world[target]
            let ability = world.curves.receiverHands(r.ratings) * lerp(world.curves.exhaustedAbilityFactor, 1, r.health)
            let reach: Float = (r.isDiving ? 0.6 : 0) + 1.2 + 0.9 * ability
            guard receiverDist < reach else { endPlay(.incomplete, at: spot); return }
            let contested = defender.map { $0.location.distance(to: spot) < 2.2 } ?? false
            // Base, contest and distance terms are tuning (issue #27: open ≥ 90%, contested ≈ 50%).
            let chance = clamp(
                world.curves.catchBase() + 0.38 * ability
                    - (contested ? world.curves.contestedPenalty() : 0)
                    - receiverDist * world.curves.catchDistancePenalty(), 0.25, 0.98)
            guard world.rng.unitFloat() < chance else {
                endPlay(.incomplete, at: spot, text: "DROPPED!")
                return
            }
            world.ball = .held(by: target)
            controlled = target
            runnerPhase = true
            playCaught = true
            message = "CATCH!"
            return
        }
        endPlay(.incomplete, at: spot)
    }

    /// Internal test seam; the live tick calls the same contact resolver.
    mutating func resolveCarrierContact() {
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
            // Tunable Power-derived tackle edge vs the carrier's contact resistance;
            // the default 1...99 curve preserves the raw Power weighting.
            let edge = (world.curves.tackleStrength(d.ratings) - world.curves.tackleStrength(c.ratings)) / 98
            let chance = clamp(
                0.72 + 0.35 * edge - 0.25 * c.ratings.s * c.health
                    + (d.isDiving ? 0.1 : 0), 0.35, 0.95)
            if world.rng.unitFloat() < chance {
                if d.isDiving && edge >= 0.35 && world.rng.unitFloat() < world.curves.fumbleChance() {
                    // The hit dislodges the ball. Both teams get a brief live recovery window.
                    world.ball = .loose(at: c.location)
                    world[cid].isDown = true
                    world[cid].recoverTicks = 45
                    looseFumbleTicks = 90
                    controlled = nil
                    message = "FUMBLE!"
                    return
                }
                let sack = c.position == .qb && c.location.y < lineOfScrimmage && !playCaught && !runnerPhase
                endPlay(sack ? .sack : .tackled, at: c.location)
                return
            }
            world.players[i].recoverTicks = 40
            world.players[i].velocity *= 0.2
            world[cid].velocity *= 0.6
            message = "BROKEN TACKLE!"
        }
    }

    /// A stationary loose ball is claimed by the nearest upright player in reach; ties use roster order.
    /// ponytail: no bouncing ball trajectory; add one with a tuned ground-physics model.
    private mutating func resolveLooseFumble() {
        guard case .loose(at: let spot) = world.ball else { return }
        if let recoverer = world.players.filter({ !$0.isDown && $0.location.distance(to: spot) <= 1.2 })
            .min(by: {
                let a = $0.location.distance(to: spot), b = $1.location.distance(to: spot)
                return a == b ? $0.id.raw < $1.id.raw : a < b
            })
        {
            if recoverer.side == .offense {
                world.ball = .held(by: recoverer.id)
                controlled = recoverer.id
                runnerPhase = true
                message = "RECOVERED!"
            } else {
                endPlay(.fumble, at: spot)
            }
            looseFumbleTicks = 0
            return
        }
        looseFumbleTicks -= 1
        if looseFumbleTicks == 0 { endPlay(.fumble, at: spot) }
    }

    // MARK: Whistle

    private mutating func endPlay(_ outcome: PlayOutcome, at spot: Vec2, text: String? = nil) {
        recordHomePlay(outcome, at: spot)
        tossTarget = nil
        looseFumbleTicks = 0
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
            simulateOpponentDrive(after: .touchdown, from: Match.kickoffYardLine)
        case .safety:
            awayScore += 2
            message = "SAFETY!"
            restartDrive()
            simulateOpponentDrive(after: .safety, from: Match.kickoffYardLine)
        case .interception:
            message = "INTERCEPTED!"
            restartDrive()
            // Picked off in their own end zone is a touchback; otherwise they take over where the pick was made.
            let theirSpot = Match.mirrored(spot.y)
            simulateOpponentDrive(
                after: .interception,
                from: theirSpot <= Field.ownGoalLine ? Field.ownGoalLine + 20 : clamp(theirSpot.rounded(), 11, 109))
        case .fumble:
            message = "FUMBLE!"
            restartDrive()
            // Defense recovered the loose ball, or the recovery window expired.
            simulateOpponentDrive(after: .fumble, from: clamp(Match.mirrored(spot.y).rounded(), 11, 109))
        case .incomplete:
            message = text ?? "INCOMPLETE"
            advanceDown(to: lineOfScrimmage)
        case .missedToss:
            message = "TOSS MISSED  \(yards)"
            // ponytail: a missed backward pitch is a dead rush here;
            // add live loose-ball recovery with fumble rules.
            advanceDown(to: clamp(spot.y.rounded(), Field.ownGoalLine + 1, Field.goalLine - 1))
        case .tackled, .outOfBounds, .dive, .sack:
            let base =
                outcome == .sack
                ? "SACKED" : outcome == .outOfBounds ? "OUT OF BOUNDS" : outcome == .dive ? "DIVE!" : "TACKLED"
            message = "\(base)  \(yards)"
            advanceDown(to: clamp(spot.y.rounded(), Field.ownGoalLine + 1, Field.goalLine - 1))
        }
        if clock <= 0 {
            if quarter < 4 {
                if quarter == 2 { halftimeDue = true }
                quarter += 1
                clock = Match.quarterSeconds
            } else {
                message += "  —  FINAL"
            }
        }
    }

    private mutating func advanceDown(to spot: Float) {
        if spot >= firstDownLine {
            homeGame.stats.firstDowns += 1
            nextLOS = spot
            nextDown = 1
            nextFirstDown = min(spot + 10, Field.goalLine)
            message += "  FIRST DOWN!"
        } else if down >= 4 {
            message += "  TURNOVER ON DOWNS"
            homeGame.turnovers += 1
            restartDrive()
            simulateOpponentDrive(after: .downs, from: Match.mirrored(spot))
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

    /// Adds the snap that just ended to the user's box score (same buckets as the simulated opposing drives).
    private mutating func recordHomePlay(_ outcome: PlayOutcome, at spot: Vec2) {
        let gain =
            outcome == .touchdown
            ? Int((Field.goalLine - lineOfScrimmage).rounded()) : Int((spot.y - lineOfScrimmage).rounded())
        let qbBehindLine = world.ballCarrier.map { world[$0].position == .qb } == true && !runnerPhase
        var s = homeGame.stats
        switch outcome {
        case .interception:
            s.passAttempts += 1
            s.interceptions += 1
            homeGame.turnovers += 1
        case .incomplete:
            s.passAttempts += 1
        case .missedToss:
            s.rushAttempts += 1
            s.rushYards += gain
        case .fumble:
            if playCaught {
                s.passAttempts += 1
                s.completions += 1
                s.passYards += gain
            } else {
                s.rushAttempts += 1
                s.rushYards += gain
            }
            homeGame.turnovers += 1
        case .sack:
            s.sacks += 1
            s.sackYards += max(0, -gain)
        case .safety where !playCaught && qbBehindLine:
            s.sacks += 1
            s.sackYards += max(0, -gain)
        case .touchdown, .tackled, .outOfBounds, .dive, .safety:
            if playCaught {
                s.passAttempts += 1
                s.completions += 1
                s.passYards += gain
                if outcome == .touchdown { s.passTouchdowns += 1 }
            } else {
                s.rushAttempts += 1
                s.rushYards += gain
                if outcome == .touchdown { s.rushTouchdowns += 1 }
            }
            s.longestPlay = max(s.longestPlay, gain)
        }
        homeGame.stats = s
    }

    /// Converts a field y between the two teams' points of view (the engine's offense always drives toward +y).
    static func mirrored(_ y: Float) -> Float { Field.length - y }

    /// Plays the opposing possession out snap by snap on a headless copy of the engine (their offense vs the
    /// user's defense, both run by the CPU), then hands the ball back to the user wherever the drive ended.
    /// - Parameter start: the opponent's line of scrimmage, in their own field coordinates.
    private mutating func simulateOpponentDrive(after trigger: OpponentDrive.Trigger, from start: Float) {
        guard !isNestedSimulation, !isFinalGun else { return }
        let seed = UInt64(world.rng.nextUInt32()) << 32 | UInt64(world.rng.nextUInt32())
        var sim = OpponentDriveSimulator(
            seed: seed, playbook: playbook, format: format, curves: world.curves,
            offense: opponentOffenseRoster, defense: homeDefenseRoster)
        let result = sim.run(
            team: opponentName, trigger: trigger, startLine: start, quarter: quarter, clock: clock,
            scoreDelta: awayScore - homeScore)
        applyOpponentDriveResult(result)
    }

    private mutating func applyOpponentDriveResult(_ result: OpponentDriveSimulator.Result) {
        awayScore += result.opponentPoints
        homeScore += result.userPoints
        awayGame.stats.add(result.drive.stats)
        awayGame.seconds += result.drive.seconds
        if result.drive.ending == .interception || result.drive.ending == .fumble || result.drive.ending == .downs {
            awayGame.turnovers += 1
        }
        if quarter < 3 && result.quarter >= 3 { halftimeDue = true }
        quarter = result.quarter
        clock = result.clock
        nextLOS = result.userLineOfScrimmage
        nextDown = 1
        nextFirstDown = min(nextLOS + 10, Field.goalLine)
        opponentDriveTicks = Match.driveRecapTicks
        opponentDrive = result.drive
    }

    // MARK: Headless possession support

    /// Lines the (nested) match up for one snap at an arbitrary spot.
    mutating func setUpPlay(lineOfScrimmage los: Float, down: Int, firstDownLine: Float) {
        nextLOS = los
        nextDown = down
        nextFirstDown = firstDownLine
        clock = Match.quarterSeconds
        message = ""
        resetFormation()
    }

    /// Ends a stalled play where the ball is (safety net for the headless driver).
    mutating func forceWhistle() {
        guard phase == .live else { return }
        if looseFumbleTicks > 0 {
            endPlay(.fumble, at: world.ballLocation)
        } else {
            let spot = world.ballCarrier.map { world[$0].location } ?? Vec2(0, lineOfScrimmage)
            endPlay(.tackled, at: spot)
        }
    }

    /// Jumps the game clock (tests drive late-game situations without playing a whole game).
    mutating func setGameClock(quarter: Int, clock: Float) {
        self.quarter = quarter
        self.clock = clock
    }

    private mutating func resetFormation() {
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
