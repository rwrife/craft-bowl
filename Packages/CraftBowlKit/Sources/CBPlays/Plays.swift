import CBCore
import CBSim
import Foundation

/// A lane slot's assignment in an offensive play.
public struct SlotAssignment: Codable, Hashable, Sendable {
    public var role: SlotRole
    public var route: RouteKind
    public init(role: SlotRole, route: RouteKind = .none) { self.role = role; self.route = route }
}

/// Data-driven offensive play: decides which of the 4 lane slots are live targets and which
/// convert to blockers (trading options for protection / lead blocking).
public struct OffensivePlay: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: Kind
    public var slots: [Lane: SlotAssignment]

    public enum Kind: String, Codable, Sendable { case pass, run, playAction, screen, keeper }

    /// Lanes that create a QB button.
    public var targetLanes: [Lane] {
        Lane.allCases.filter { slots[$0]?.role == .target }
    }

    /// Linemen + every slot converted to blocker/lead/fake.
    public func blockerCount(format: TeamFormat) -> Int {
        let converted = Lane.allCases.filter { lane in slots[lane]?.role != .target }.count
        return format.offensiveLinemen + converted
    }

    /// Contextual QB buttons for this play. Never more than 4 (docs/PLAN.md §5.4).
    public var qbActions: [QBAction] {
        var actions: [QBAction] = []
        if slots[.left]?.role == .target { actions.append(.passLeft) }
        if slots[.center]?.role == .target { actions.append(.passCenter) }
        if slots[.right]?.role == .target { actions.append(.passRight) }
        if let rb = slots[.backfield], rb.role == .target {
            switch rb.route {
            case .toss: actions.append(.toss)
            case .handoff: actions.append(.handoff)
            default: break  // RB is a pass target (flat/screen) — thrown via its lane, no handoff
            }
        }
        return actions
    }
}

/// What a defender does on a given call.
/// JSON form is a compact string: `"zone:left"`, `"deepZone:center"`, `"man:right"`, `"rush"`, `"spy"`, `"runFill"`.
public enum DefensiveAssignment: Codable, Hashable, Sendable {
    case zone(Lane)
    case deepZone(Lane)
    case man(Lane)
    case rush
    case spy
    case runFill

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let parts = raw.split(separator: ":").map(String.init)
        let lane = parts.count > 1 ? Lane(rawValue: parts[1]) : nil
        switch (parts.first, lane) {
        case ("zone"?, let l?): self = .zone(l)
        case ("deepZone"?, let l?): self = .deepZone(l)
        case ("man"?, let l?): self = .man(l)
        case ("rush"?, nil): self = .rush
        case ("spy"?, nil): self = .spy
        case ("runFill"?, nil): self = .runFill
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown assignment '\(raw)'"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .zone(let l): try c.encode("zone:\(l.rawValue)")
        case .deepZone(let l): try c.encode("deepZone:\(l.rawValue)")
        case .man(let l): try c.encode("man:\(l.rawValue)")
        case .rush: try c.encode("rush")
        case .spy: try c.encode("spy")
        case .runFill: try c.encode("runFill")
        }
    }
}

/// Data-driven defensive call. The key decision is what the MLB does (docs/PLAN.md §5.3).
public struct DefensivePlay: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var assignments: [Position: DefensiveAssignment]

    public var mlbAssignment: DefensiveAssignment? { assignments[.mlb] }

    public var rusherCount: Int {
        assignments.values.filter { $0 == .rush }.count
    }

    /// True when the MLB leaves coverage to attack the QB or the runner.
    public var mlbCommits: Bool {
        switch mlbAssignment {
        case .rush?, .runFill?, .spy?: true
        default: false
        }
    }
}

/// Players per side and composition (docs/PLAN.md §5.1). Shipped default: 9v9.
public struct TeamFormat: Codable, Hashable, Sendable {
    public var playersPerSide: Int
    public var offense: [Position]
    public var defense: [Position]

    public var offensiveLinemen: Int {
        offense.filter { [.lt, .lg, .rg, .rt].contains($0) }.count
    }

    public static let nineOnNine = TeamFormat(
        playersPerSide: 9,
        offense: [.qb, .rb, .laneLeft, .laneCenter, .laneRight, .lt, .lg, .rg, .rt],
        defense: [.deL, .nt, .deR, .mlb, .olb, .cbL, .cbR, .fs, .ss])
}

public struct Playbook: Codable, Sendable {
    public var offense: [OffensivePlay]
    public var defense: [DefensivePlay]

    /// Loads the bundled `format.json`, `offense.json` and `defense.json`.
    public static func loadBundled() throws -> (format: TeamFormat, playbook: Playbook) {
        let format = try Tuning.load(TeamFormat.self, named: "format", in: .module)
        let offense = try Tuning.load([OffensivePlay].self, named: "offense", in: .module)
        let defense = try Tuning.load([DefensivePlay].self, named: "defense", in: .module)
        return (format, Playbook(offense: offense, defense: defense))
    }
}
