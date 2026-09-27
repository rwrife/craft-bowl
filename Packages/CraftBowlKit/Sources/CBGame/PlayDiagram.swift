import CBAI
import CBCore
import CBPlays
import CBSim

/// Chalkboard X's-and-O's for a play card. Coordinates are yards relative to the ball:
/// x = field x (offense's left is negative), y = yards past the line of scrimmage.
public struct PlayDiagram: Equatable, Sendable {
    public enum Style: Sendable { case route, run, pitch, block }

    public struct Stroke: Equatable, Sendable {
        public var points: [Vec2]
        public var style: Style
    }

    public var name: String
    public var kindLabel: String
    public var offense: [Vec2]
    public var qb: Vec2
    public var defense: [Vec2]
    public var strokes: [Stroke]

    /// Visible window for drawing. Deep routes are trimmed to it so their arrowheads stay on the card.
    public static let minX: Float = -20, maxX: Float = 20, minY: Float = -9, maxY: Float = 15

    public init(play: OffensivePlay, format: TeamFormat = .nineOnNine) {
        name = play.name
        kindLabel = switch play.kind {
        case .pass: "PASS"
        case .run: "RUN"
        case .playAction: "PLAY ACTION"
        case .screen: "SCREEN"
        case .keeper: "QB KEEPER"
        }
        let spot = { (p: Position) in Match.formationOffset(p) }
        qb = spot(.qb)
        offense = format.offense.filter { $0 != .qb }.map(spot)
        defense = format.defense.map(spot)

        var s: [Stroke] = []
        for p in format.offense where [.lt, .lg, .rg, .rt].contains(p) {
            let o = spot(p)
            s.append(Stroke(points: [o, o + Vec2(0, 0.9)], style: .block))
        }
        for lane in Lane.allCases {
            guard let slot = play.slots[lane] else { continue }
            let start = spot(lane.slotPosition)
            switch slot.role {
            case .target:
                switch slot.route {
                case .handoff:
                    s.append(Stroke(points: [start, Vec2(0.4, -5.8), Vec2(1.2, -1.5), Vec2(1.6, 6)], style: .run))
                case .toss:
                    let catchSpot = Vec2(-3, -6.5)
                    s.append(Stroke(points: [qb, catchSpot], style: .pitch))
                    s.append(Stroke(points: [start, catchSpot, Vec2(-12, -2.5), Vec2(-14.5, 5)], style: .run))
                default:
                    let wps = SandboxBrain.routeWaypoints(lane: lane, route: slot.route)
                    if !wps.isEmpty { s.append(Stroke(points: [start] + wps, style: .route)) }
                }
            case .lead:
                s.append(Stroke(points: [start, Vec2(lane.centerX * 0.3, 1.5)], style: .block))
            case .blocker:
                s.append(Stroke(points: [start, start + Vec2(0, -1)], style: .block))
            case .fake:
                s.append(Stroke(points: [start, start + Vec2(1.2, 2)], style: .block))
            }
        }
        if play.kind == .keeper {
            s.append(Stroke(points: [qb, Vec2(1.5, -1.5), Vec2(2.5, 7)], style: .run))
        }
        strokes = s.map { PlayDiagram.trimmed($0) }
    }

    /// Cuts a stroke where it first leaves the top of the window.
    private static func trimmed(_ stroke: Stroke) -> Stroke {
        var out = stroke
        for i in 1..<stroke.points.count {
            let a = stroke.points[i - 1], b = stroke.points[i]
            guard b.y > maxY else { continue }
            let t = (maxY - a.y) / (b.y - a.y)
            out.points = Array(stroke.points[..<i]) + [a + (b - a) * t]
            break
        }
        return out
    }
}

extension Match {
    /// Diagrams for this down's offered plays, in card order.
    public var playChoiceDiagrams: [PlayDiagram] {
        playChoices.map { PlayDiagram(play: playbook.offense[$0], format: format) }
    }
}
