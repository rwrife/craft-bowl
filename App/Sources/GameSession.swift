import CBAssets
import CBAudio
import CBCore
import CBGame
import CBInput
import CBPlays
import CBRender
import CBSim
import Foundation
import Observation
import QuartzCore

/// Scoreboard / prompt state for the SwiftUI HUD. Only reassigned when it actually changes.
struct HUDState: Equatable {
    var homeScore = 0
    var awayScore = 0
    var quarter = 1
    var clock = "5:00"
    var downDistance = "1ST & 10"
    var ballOn = "OWN 25"
    var message = ""
    var phase: PlayPhase = .preSnap
    var playName = ""
    var defenseName = ""
    var qbActions: [QBAction] = []
    var runner = false
    var turbo: Float = 1
    var health: Float = 1
    /// The 3 plays offered this down and which one (if any) is picked.
    var playCards: [PlayDiagram] = []
    var chosenCard: Int?
}

/// Dev overlay numbers, refreshed ~4×/s.
struct DevStats: Equatable {
    var fps: Double = 0
    var cpuMs: Float = 0
    var simMs: Float = 0
    var gpuCullShadow: Float = 0
    var gpuScene: Float = 0
    var gpuPost: Float = 0
    var renderScale: Float = 1
    var renderSize = ""
    var crowd = ""
    var players = ""
    var drawCalls = 0
    var metalFX = false
    var residency = false
    var inspector: [String] = []
    var inputLog: [String] = []
    var controllers: [String] = []
    var tick: UInt64 = 0
    var checksum = ""
}

enum ReplayState: Equatable {
    case idle
    case recording(ticks: Int)
    case recorded(ticks: Int)
    case playing(tick: Int, of: Int)
    case verified(matches: Bool, ticks: Int)
}

private enum SessionPresentation: Equatable {
    case attract, intro, gameplay
}

/// Owns the deterministic simulation, input, camera and render-frame assembly (the game loop).
/// The renderer calls `update` once per display frame; the sim advances in fixed 60 Hz ticks.
@MainActor
@Observable
final class GameSession: RenderFrameSource {
    private(set) var hud = HUDState()
    private(set) var dev = DevStats()
    private(set) var replay: ReplayState = .idle
    var showDevOverlay = UserDefaults.standard.bool(forKey: "CBDevOverlay")
    var paused = false
    var slowMotion = false
    var autopilot = true
    var cameraPreset: Camera.Preset = .reference
    var settings = RenderSettings()
    private(set) var introSpotlightHome = true
    private(set) var audioError = ""

    @ObservationIgnored let input = InputQueue()
    @ObservationIgnored private(set) var keyboard: KeyboardInput!
    @ObservationIgnored private var controllers: ControllerInput!
    @ObservationIgnored weak var renderer: Renderer?

    @ObservationIgnored private let playbook: Playbook
    @ObservationIgnored private let format: TeamFormat
    @ObservationIgnored private var curves: RatingCurves
    @ObservationIgnored private var sim: GameSimulation
    @ObservationIgnored private var clock = GameClock()
    @ObservationIgnored private var prev = WorldSnapshot()
    @ObservationIgnored private var cur = WorldSnapshot()
    @ObservationIgnored private var interp = WorldSnapshot()
    @ObservationIgnored private var recording: InputRecording?
    @ObservationIgnored private var playback: (recording: InputRecording, cursor: Int)?
    @ObservationIgnored private var animPhase: [Float] = []
    @ObservationIgnored private var focus = Vec2(0, 30)
    @ObservationIgnored private var excitement: Float = 0.2
    @ObservationIgnored private var autoRNG = PCG32(seed: 7)
    @ObservationIgnored private var autoThrowTick = 70
    @ObservationIgnored private var frameCount = 0
    @ObservationIgnored private var statsWindowStart = CACurrentMediaTime()
    @ObservationIgnored private var lastSimMs: Float = 0
    @ObservationIgnored private var hudTimer: Double = 0
    @ObservationIgnored private let tuning = TuningWatcher()
    @ObservationIgnored private let audio = AudioSystem()
    @ObservationIgnored private var presentation: SessionPresentation = .attract
    @ObservationIgnored private var introElapsed: Double = 0
    @ObservationIgnored private var crowdVolume: Float = 0.8
    @ObservationIgnored private var appliedCrowdVolume: Float = -1
    private(set) var homeTeam: TeamDefinition?
    private(set) var awayTeam: TeamDefinition?

    init() {
        guard let loaded = try? Playbook.loadBundled() else { fatalError("Bundled playbook JSON failed to load") }
        format = loaded.format
        playbook = loaded.playbook
        curves = RatingCurves.loadBundled()
        sim = GameSimulation(seed: 1, playbook: playbook, format: format, curves: curves)
        keyboard = KeyboardInput(queue: input)
        controllers = ControllerInput(queues: [input])
        input.onAppAction = { [weak self] action, _ in
            switch action {
            case .pause: self?.paused.toggle()
            case .toggleDevOverlay: self?.showDevOverlay.toggle()
            default: break
            }
        }
        resetSnapshots()
        if UserDefaults.standard.object(forKey: "CBAutopilot") != nil {
            autopilot = UserDefaults.standard.bool(forKey: "CBAutopilot")
        }
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "CBShadows") != nil { settings.shadows = defaults.bool(forKey: "CBShadows") }
        if defaults.object(forKey: "CBBloom") != nil { settings.bloom = defaults.bool(forKey: "CBBloom") }
        if defaults.object(forKey: "CBDynamicResolution") != nil {
            settings.dynamicResolution = defaults.bool(forKey: "CBDynamicResolution")
        }
        do {
            guard let crowdURL = Bundle.main.url(forResource: "Crowd", withExtension: "mp3") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let cheerURLs = ["Cheer", "Cheer2", "Cheer3"].compactMap {
                Bundle.main.url(forResource: $0, withExtension: "mp3")
            }
            guard cheerURLs.count == 3 else {
                throw CocoaError(.fileNoSuchFile)
            }
            try audio.loadCrowdLoop(from: crowdURL)
            try audio.loadCheers(from: cheerURLs)
            try audio.start()
            func volume(_ key: String, fallback: Float) -> Float {
                defaults.object(forKey: key) == nil ? fallback : defaults.float(forKey: key)
            }
            setAudio(
                master: volume("CBMasterVolume", fallback: 0.85),
                music: volume("CBMusicVolume", fallback: 0.7),
                sfx: volume("CBSFXVolume", fallback: 0.9),
                crowd: volume("CBCrowdVolume", fallback: 0.8))
        } catch {
            audioError = error.localizedDescription
        }
    }

    func startGame(home: TeamDefinition, away: TeamDefinition,
                   seed: UInt64 = UInt64(Date().timeIntervalSince1970), showIntro: Bool = true) {
        homeTeam = home
        awayTeam = away
        sim = GameSimulation(seed: seed, playbook: playbook, format: format, curves: curves)
        sim.setRoster(offense: home.gameRoster(for: .offense), defense: away.gameRoster(for: .defense))
        clock = GameClock()
        input.reset()
        autopilot = UserDefaults.standard.bool(forKey: "CBAutopilot")
        recording = nil
        playback = nil
        replay = .idle
        introElapsed = 0
        introSpotlightHome = true
        presentation = showIntro ? .intro : .gameplay
        audio.playCrowdLoop()
        refreshCrowdVolume()
        resetSnapshots()
    }

    func beginGameplay() {
        presentation = .gameplay
        refreshCrowdVolume()
        introElapsed = 0
        introSpotlightHome = true
        focus = Vec2(0, sim.match.lineOfScrimmage)
    }

    func enterAttractMode() {
        presentation = .attract
        audio.stopCrowdLoop()
        autopilot = true
        homeTeam = nil
        awayTeam = nil
        sim = GameSimulation(seed: UInt64(Date().timeIntervalSince1970), playbook: playbook, format: format, curves: curves)
        clock = GameClock()
        resetSnapshots()
    }

    func setAudio(master: Float, music: Float, sfx: Float, crowd: Float) {
        audio.engine.mainMixerNode.outputVolume = clamp(master, 0, 1)
        audio.music.outputVolume = clamp(music, 0, 1)
        audio.sfx.outputVolume = clamp(sfx, 0, 1)
        crowdVolume = clamp(crowd, 0, 1)
        refreshCrowdVolume()
    }

    private func refreshCrowdVolume() {
        let playSelection = presentation == .gameplay && sim.match.phase == .preSnap
        let output = crowdVolume * (playSelection ? 0.75 : 1)
        guard output != appliedCrowdVolume else { return }
        audio.crowd.outputVolume = output
        appliedCrowdVolume = output
    }

    private func resetSnapshots() {
        prev.capture(sim.world)
        cur.capture(sim.world)
        interp.capture(sim.world)
        animPhase = Array(repeating: 0, count: sim.world.players.count)
        focus = Vec2(0, sim.match.lineOfScrimmage)
    }

    // MARK: Record / replay (issue #3)

    func startRecording() {
        playback = nil
        recording = InputRecording(start: sim)
        replay = .recording(ticks: 0)
    }

    func stopRecording() {
        guard let r = recording else { return }
        replay = .recorded(ticks: r.tickCount)
    }

    /// Rewinds to the recording's start and re-feeds its inputs live, then checks the checksum.
    func playRecording() {
        guard let r = recording else { return }
        if case .recording = replay { stopRecording() }
        sim = r.start
        playback = (r, 0)
        clock = GameClock()
        resetSnapshots()
        replay = .playing(tick: 0, of: r.tickCount)
    }

    /// Headless re-simulation of the whole recording.
    func verifyRecording() {
        guard let r = recording else { return }
        if case .recording = replay { stopRecording() }
        replay = .verified(matches: r.replay().matches, ticks: r.tickCount)
    }

    // MARK: Frame

    func update(deltaTime: Double, frame: inout RenderFrame) {
        renderer?.settings = settings
        refreshCrowdVolume()
        if presentation == .intro {
            introElapsed += deltaTime
            let showHome = introElapsed < 2.5
            if introSpotlightHome != showHome { introSpotlightHome = showHome }
            WorldSnapshot.interpolate(prev, cur, 0, into: &interp)
            buildFrame(&frame, dt: Float(deltaTime), realDt: Float(deltaTime))
            buildIntroFrame(&frame)
            return
        }
        clock.timeScale = paused ? 0 : (slowMotion ? 0.25 : 1)
        let steps = clock.advance(by: deltaTime)
        let t0 = CACurrentMediaTime()
        for _ in 0..<steps { tick() }
        if steps > 0 { lastSimMs = Float((CACurrentMediaTime() - t0) * 1000) / Float(steps) }
        #if DEBUG
        if let newCurves = tuning.poll() {
            curves = newCurves
            sim.setCurves(newCurves)
        }
        #endif

        WorldSnapshot.interpolate(prev, cur, Float(clock.interpolationAlpha), into: &interp)
        let dt = Float(deltaTime) * Float(clock.timeScale)
        buildFrame(&frame, dt: dt, realDt: Float(deltaTime))

        hudTimer += deltaTime
        if hudTimer >= 0.1 {
            hudTimer = 0
            refreshHUD()
        }
        frameCount += 1
        let now = CACurrentMediaTime()
        if now - statsWindowStart >= 0.25 {
            refreshDev(fps: Double(frameCount) / (now - statsWindowStart))
            frameCount = 0
            statsWindowStart = now
        }
    }

    private func tick() {
        let phaseBeforeTick = sim.match.phase
        var ti: TickInput
        if var pb = playback {
            guard pb.cursor < pb.recording.inputs.count else {
                replay = .verified(matches: sim.world.checksum == pb.recording.finalChecksum,
                                   ticks: pb.recording.tickCount)
                playback = nil
                return
            }
            ti = pb.recording.inputs[pb.cursor]
            pb.cursor += 1
            playback = pb
            if pb.cursor % 30 == 0 { replay = .playing(tick: pb.cursor, of: pb.recording.tickCount) }
            _ = input.makeTickInput()
        } else {
            ti = input.makeTickInput()
            if autopilot { ti = autopilotInput(ti) }
        }
        sim.tick(ti)
        let majorOutcomes: Set<PlayOutcome> = [.touchdown, .interception, .safety, .sack]
        if presentation == .gameplay, phaseBeforeTick == .live, sim.match.phase == .dead,
           sim.match.lastOutcome.map(majorOutcomes.contains) == true ||
           sim.match.message.contains("FIRST DOWN") ||
           sim.match.message.contains("TURNOVER ON DOWNS") {
            audio.playCheer()
        }
        if case .recording = replay, recording != nil {
            recording!.append(ti, resultingChecksum: sim.world.checksum)
            if recording!.tickCount % 30 == 0 { replay = .recording(ticks: recording!.tickCount) }
        }
        swap(&prev, &cur)
        cur.capture(sim.world)
    }

    /// Attract-mode / smoke-test driver: picks plays, snaps, throws and runs through the same input path.
    private func autopilotInput(_ user: TickInput) -> TickInput {
        var t = user
        let m = sim.match
        switch m.phase {
        case .preSnap:
            if m.phaseTicks == 40 { t.playSelect = Int8(autoRNG.nextUInt32() % UInt32(max(1, m.playChoices.count))) }
            if m.phaseTicks == 110 {
                t.buttons.insert(.snap)
                autoThrowTick = 30 + Int(autoRNG.nextUInt32() % 30)
            }
        case .live:
            let actions = m.availableQBActions
            if !actions.isEmpty {
                if m.phaseTicks >= autoThrowTick {
                    switch actions[Int(autoRNG.nextUInt32() % UInt32(actions.count))] {
                    case .passLeft: t.buttons.insert(.passLeft)
                    case .passCenter: t.buttons.insert(.passCenter)
                    case .passRight: t.buttons.insert(.passRight)
                    case .handoff, .toss: t.buttons.insert(.handoff)
                    }
                } else {
                    t.move = Vec2(0, -0.35)
                }
            } else if m.runnerPhase || m.world.ballCarrier == m.controlled {
                let weave = sinf(Float(m.phaseTicks) * 0.05) * 0.45
                t.move = Vec2(weave, 1).normalized
                t.turbo = true
            }
        case .dead:
            break
        }
        return t
    }

    private func buildFrame(_ frame: inout RenderFrame, dt: Float, realDt: Float) {
        let m = sim.match
        frame.home = homeTeam?.uniform ?? .blue
        frame.away = awayTeam?.uniform ?? .red
        frame.players.removeAll(keepingCapacity: true)
        if animPhase.count != interp.players.count { animPhase = Array(repeating: 0, count: interp.players.count) }
        let celebrating = m.phase == .dead && m.lastOutcome == .touchdown
        for (i, p) in interp.players.enumerated() {
            let speed = p.velocity.length
            let offense = p.position.side == .offense
            let lineman: Bool = switch p.position {
            case .lt, .lg, .rg, .rt, .deL, .nt, .deR: true
            default: false
            }
            let pose: PlayerPose
            if p.isDown {
                pose = .down
            } else if p.isDiving {
                pose = .dive
            } else if m.phase == .preSnap {
                pose = lineman ? .threePoint : (p.position == .qb ? .idle : .stance)
            } else if celebrating && offense {
                pose = .celebrate
            } else if speed > 0.35 {
                pose = .run
            } else {
                pose = .idle
            }
            animPhase[i] += pose == .run ? dt * speed * 2.7 : dt * 3
            if animPhase[i] > 1000 { animPhase[i] -= 200 * .pi }
            let scale: SIMD3<Float> = lineman ? SIMD3(1.14, 1.0, 1.1) : SIMD3(1, 1, 1)
            frame.players.append(PlayerDraw(
                position: fieldToWorld(p.location), yaw: -p.facing, team: offense ? 0 : 1, pose: pose,
                phase: animPhase[i], speed01: clamp(speed / 7, 0, 1), controlled: p.id == m.controlled,
                turbo: p.turboActive && speed > 1, skinTone: UInt8((p.id.raw &* 7 &+ 3) % 12),
                number: UInt8(clamping: p.number), scale: scale))
        }

        // Ball: carried in the right hand, or on its flight arc.
        frame.ballVisible = true
        var ballPos = fieldToWorld(Vec2(interp.ball.x, interp.ball.y), height: interp.ball.z)
        if let carrier = interp.ballCarrier, let p = interp.players.first(where: { $0.id == carrier }) {
            let fwd = SIMD3<Float>(sinf(p.facing), 0, -cosf(p.facing))
            let right = SIMD3<Float>(cosf(p.facing), 0, sinf(p.facing))
            ballPos = fieldToWorld(p.location, height: p.isDown ? 0.25 : 1.05) + fwd * 0.28 + right * 0.32
            frame.ballYaw = -p.facing
            frame.ballPitch = 0.35
        } else if interp.ballInAir {
            let d = cur.ball - prev.ball
            let ground = (d.x * d.x + d.y * d.y).squareRoot()
            frame.ballYaw = -atan2f(d.x, d.y)
            frame.ballPitch = ground > 1e-4 ? atan2f(d.z, ground) : 0
        } else {
            frame.ballPitch = 0
            frame.ballYaw = 0
        }
        frame.ballPosition = ballPos

        frame.lineOfScrimmage = m.lineOfScrimmage
        frame.firstDownLine = m.firstDownLine
        frame.showLines = m.phase != .live || m.phaseTicks < 30

        // Crowd reacts to big moments.
        var target: Float = m.phase == .live ? 0.35 : 0.15
        if m.phase == .live, let c = m.world.ballCarrier, m.world[c].side == .offense {
            let gain = m.world[c].location.y - m.lineOfScrimmage
            target = clamp(0.35 + gain / 30, 0.35, 0.9)
        }
        if celebrating { target = 1 }
        excitement += (target - excitement) * min(1, realDt * 2)
        frame.crowdExcitement = excitement

        updateCamera(&frame.camera, dt: realDt)
        buildMarkers(&frame.markers)
        buildStatBars(&frame.statBars)
        frame.debugLines.removeAll(keepingCapacity: true)
        if settings.debugDraw { buildDebug(&frame.debugLines) }
    }

    private func buildIntroFrame(_ frame: inout RenderFrame) {
        let homeY: Float = 38
        let awayY: Float = 68
        for index in frame.players.indices {
            let home = frame.players[index].team == 0
            let teamIndex = home ? index : index - format.offense.count
            let row = Float(teamIndex / 5)
            let column = Float(teamIndex % 5) - 2
            let y = (home ? homeY : awayY) + row * (home ? -2.2 : 2.2)
            frame.players[index].position = fieldToWorld(Vec2(column * 2.4, y))
            frame.players[index].yaw = home ? 0 : .pi
            frame.players[index].pose = teamIndex.isMultiple(of: 3) ? .stance : .run
            frame.players[index].speed01 = 0.35
            frame.players[index].controlled = false
        }

        let home = introElapsed < 2.5
        let localTime = Float(home ? introElapsed : introElapsed - 2.5)
        let pan = lerp(-11, 11, clamp(localTime / 2.5, 0, 1))
        let teamY = home ? homeY : awayY
        let cameraY = teamY + (home ? 10 : -10)
        frame.camera.eye = fieldToWorld(Vec2(pan, cameraY), height: 3.4)
        frame.camera.target = fieldToWorld(Vec2(pan * 0.25, teamY), height: 1.2)
        frame.camera.fovY = 0.72
        frame.ballVisible = false
        frame.showLines = false
        frame.markers.removeAll(keepingCapacity: true)
        frame.statBars.removeAll(keepingCapacity: true)
        frame.debugLines.removeAll(keepingCapacity: true)
        frame.crowdExcitement = 0.72
    }

    private func updateCamera(_ cam: inout Camera, dt: Float) {
        let m = sim.match
        var desired: Vec2
        switch m.phase {
        // Pre-snap the camera sits further back so the formation (and its stat bars) clears the play cards.
        case .preSnap: desired = Vec2(0, m.lineOfScrimmage - 11)
        case .live, .dead: desired = Vec2(interp.ball.x * 0.7, interp.ball.y)
        }
        desired.x = clamp(desired.x, -12, 12)
        let rate: Float = m.phase == .live ? 3.5 : 2
        focus += (desired - focus) * min(1, dt * rate)
        let o = cameraPreset.offset
        cam.eye = fieldToWorld(focus + Vec2(o.across, -o.back), height: o.height)
        cam.target = fieldToWorld(focus + Vec2(0, o.lookAhead), height: 0.8)
        cam.fovY = o.fov
    }

    private func circle(_ lines: inout [DebugLine], _ c: Vec2, radius: Float, height: Float, _ color: SIMD4<Float>,
                        segments: Int = 16) {
        for s in 0..<segments {
            let a0 = Float(s) / Float(segments) * 2 * .pi, a1 = Float(s + 1) / Float(segments) * 2 * .pi
            lines.append(DebugLine(fieldToWorld(c + Vec2(cosf(a0), sinf(a0)) * radius, height: height),
                                   fieldToWorld(c + Vec2(cosf(a1), sinf(a1)) * radius, height: height), color))
        }
    }

    private func buildMarkers(_ lines: inout [DebugLine]) {
        lines.removeAll(keepingCapacity: true)
        let m = sim.match
        if let c = m.controlled, let p = interp.players.first(where: { $0.id == c }) {
            circle(&lines, p.location, radius: 0.8, height: 0.04, SIMD4(1, 0.85, 0.15, 0.9), segments: 20)
        }
        // Receiver markers above the three pass targets while the QB can throw.
        let actions = m.availableQBActions
        guard !actions.isEmpty else { return }
        let targets: [(QBAction, Position, SIMD4<Float>)] = [
            (.passLeft, .laneLeft, SIMD4(0.2, 0.8, 1, 0.95)),
            (.passCenter, .laneCenter, SIMD4(1, 0.9, 0.2, 0.95)),
            (.passRight, .laneRight, SIMD4(1, 0.35, 0.8, 0.95)),
        ]
        for (action, position, color) in targets where actions.contains(action) {
            guard let p = interp.players.first(where: { $0.position == position }) else { continue }
            let top = fieldToWorld(p.location, height: 2.75)
            let s: Float = 0.3
            let pts = [top + SIMD3(0, s * 1.4, 0), top + SIMD3(s, 0, 0), top - SIMD3(0, s * 1.4, 0), top - SIMD3(s, 0, 0)]
            for k in 0..<4 { lines.append(DebugLine(pts[k], pts[(k + 1) % 4], color)) }
        }
    }

    /// Speed / endurance / ability bars over the play's key players before the snap, then over the runner only.
    /// Each segment is that rating scaled by current health, so a tiring player's bar visibly shrinks.
    private func buildStatBars(_ bars: inout [StatBar]) {
        bars.removeAll(keepingCapacity: true)
        for id in sim.match.statBarPlayers {
            guard let p = interp.players.first(where: { $0.id == id }), !p.isDown else { continue }
            let r = p.ratings
            let seg = SIMD3(Float(r.speed), Float(r.endurance), Float(r.ability)) / 99 * p.health
            bars.append(StatBar(anchor: fieldToWorld(p.location, height: 2.45), segments: seg, health: p.health))
        }
    }

    private func buildDebug(_ lines: inout [DebugLine]) {
        let m = sim.match
        let los = m.lineOfScrimmage
        // Passing lanes
        let laneColor = SIMD4<Float>(0.2, 1, 1, 0.5)
        for x in [-Field.halfWidth, -Field.laneWidth / 2, Field.laneWidth / 2, Field.halfWidth] {
            lines.append(DebugLine(fieldToWorld(Vec2(x, los - 10), height: 0.05),
                                   fieldToWorld(Vec2(x, min(120, los + 45)), height: 0.05), laneColor))
        }
        // Collision circles + velocity
        for p in interp.players {
            let color: SIMD4<Float> = p.position.side == .offense ? SIMD4(0.3, 0.5, 1, 0.8) : SIMD4(1, 0.3, 0.3, 0.8)
            circle(&lines, p.location, radius: World.playerRadius, height: 0.06, color, segments: 12)
            if p.velocity.length > 0.1 {
                lines.append(DebugLine(fieldToWorld(p.location, height: 0.1),
                                       fieldToWorld(p.location + p.velocity * 0.5, height: 0.1), SIMD4(1, 1, 1, 0.7)))
            }
        }
        // AI aim points (routes, pursuit leads)
        for (id, aim) in sim.brain.aimPoints {
            guard let p = interp.players.first(where: { $0.id == id }) else { continue }
            lines.append(DebugLine(fieldToWorld(p.location, height: 0.15), fieldToWorld(aim, height: 0.15),
                                   SIMD4(1, 0.6, 0.1, 0.6)))
        }
        if let flight = m.world.ballFlight {
            lines.append(DebugLine(fieldToWorld(flight.from, height: 0.1), fieldToWorld(flight.to, height: 0.1),
                                   SIMD4(1, 1, 1, 0.9)))
            circle(&lines, flight.to, radius: 1, height: 0.08, SIMD4(1, 1, 1, 0.9))
        }
    }

    // MARK: HUD

    private func refreshHUD() {
        let m = sim.match
        var h = HUDState()
        h.homeScore = m.homeScore
        h.awayScore = m.awayScore
        h.quarter = m.quarter
        let secs = Int(m.clock.rounded(.up))
        h.clock = String(format: "%d:%02d", secs / 60, secs % 60)
        let ordinals = ["1ST", "2ND", "3RD", "4TH"]
        let togo = m.firstDownLine >= Field.goalLine ? "GOAL" : "\(max(1, Int(m.yardsToGo.rounded())))"
        h.downDistance = "\(ordinals[min(3, max(0, m.down - 1))]) & \(togo)"
        let yard = Int((m.lineOfScrimmage - Field.ownGoalLine).rounded())
        h.ballOn = yard == 50 ? "MIDFIELD" : (yard < 50 ? "OWN \(yard)" : "OPP \(100 - yard)")
        h.message = m.message
        h.phase = m.phase
        h.playName = m.offensePlay.name.uppercased()
        h.defenseName = m.defensePlay.name.uppercased()
        h.qbActions = m.availableQBActions
        h.runner = m.phase == .live && h.qbActions.isEmpty
        if m.phase == .preSnap {
            h.playCards = m.playChoiceDiagrams
            h.chosenCard = m.chosenChoice
        }
        if let c = m.controlled {
            let p = m.world[c]
            h.turbo = (p.stamina.turboFraction * 20).rounded() / 20
            h.health = (p.stamina.health * 20).rounded() / 20
        }
        if h != hud { hud = h }
    }

    private func refreshDev(fps: Double) {
        guard showDevOverlay else { return }
        var d = DevStats()
        d.fps = fps
        d.simMs = lastSimMs
        if let r = renderer {
            let s = r.stats
            d.cpuMs = s.cpuFrameMs
            d.gpuCullShadow = s.gpuCullShadowMs
            d.gpuScene = s.gpuSceneMs
            d.gpuPost = s.gpuPostMs
            d.renderScale = s.renderScale
            d.renderSize = "\(s.renderSize.x)×\(s.renderSize.y) → \(s.drawableSize.x)×\(s.drawableSize.y)"
            d.crowd = "\(s.crowdVisible)/\(s.crowdTotal)"
            d.players = "\(s.playersVisible)/\(interp.players.count)"
            d.drawCalls = s.drawCalls
            d.metalFX = s.metalFXActive
            d.residency = s.residencySetActive
        }
        let m = sim.match
        d.tick = m.world.tick
        d.checksum = String(m.world.checksum, radix: 16)
        if let c = m.controlled {
            let p = m.world[c]
            d.inspector = [
                "#\(p.number) \(p.position.rawValue.uppercased())  P\(p.ratings.power) S\(p.ratings.speed) E\(p.ratings.endurance) A\(p.ratings.ability)",
                String(format: "pos %.1f, %.1f  spd %.2f", p.location.x, p.location.y, p.velocity.length),
                String(format: "health %.2f  turbo %.2f%@", p.stamina.health, p.stamina.turboFraction,
                       p.stamina.isTurboActive ? " ON" : ""),
            ]
        }
        d.inspector.append("phase \(m.phase.rawValue)  ticks \(m.phaseTicks)  ball \(ballDescription(m.world.ball))")
        d.inputLog = input.log.suffix(6).reversed().map { "[\($0.source.rawValue)] \($0.action.label)" }
        d.controllers = controllers.connectedNames
        if d != dev { dev = d }
    }

    private func ballDescription(_ b: BallState) -> String {
        switch b {
        case .held: "held"
        case .inAir: "air"
        case .loose: "loose"
        case .dead: "dead"
        }
    }
}

/// DEBUG-only hot reload of `ratings.json` (issue #4): edit the file in the repo while the Simulator
/// runs and movement curves update within a second. A copy in the app's Documents folder wins on device.
@MainActor
final class TuningWatcher {
    private let urls: [URL]
    private var lastModified: Date?
    private var lastCheck: CFTimeInterval = 0

    init(sourceFile: String = #filePath) {
        let repo = URL(fileURLWithPath: sourceFile).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        var urls: [URL] = []
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(docs.appendingPathComponent("ratings.json"))
        }
        urls.append(repo.appendingPathComponent("Packages/CraftBowlKit/Sources/CBSim/Resources/ratings.json"))
        self.urls = urls
        lastModified = currentFile?.date
    }

    private var currentFile: (url: URL, date: Date)? {
        for url in urls {
            if let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date {
                return (url, date)
            }
        }
        return nil
    }

    /// Returns new curves when the file changed since the last successful load.
    func poll() -> RatingCurves? {
        let now = CACurrentMediaTime()
        guard now - lastCheck > 1 else { return nil }
        lastCheck = now
        guard let file = currentFile, file.date != lastModified else { return nil }
        lastModified = file.date
        guard let data = try? Data(contentsOf: file.url),
              let curves = try? JSONDecoder().decode(RatingCurves.self, from: data)
        else {
            print("CraftBowl tuning: failed to decode \(file.url.lastPathComponent)")
            return nil
        }
        print("CraftBowl tuning: reloaded \(file.url.path)")
        return curves
    }
}
