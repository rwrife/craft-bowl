import CBSim

/// The 3+1 lane system (docs/PLAN.md §5.2): three passing lanes plus the backfield/run lane.
public enum Lane: String, Codable, CaseIterable, Sendable {
    case left, center, right
    /// The "+1" lane owned by the running back.
    case backfield

    public static let passingLanes: [Lane] = [.left, .center, .right]

    /// The offensive position that owns this lane slot.
    public var slotPosition: Position {
        switch self {
        case .left: .laneLeft
        case .center: .laneCenter
        case .right: .laneRight
        case .backfield: .rb
        }
    }
}

/// What a lane-slot player does on a given play.
public enum SlotRole: String, Codable, Sendable {
    /// Runs a route / is a handoff or toss target — creates a QB button.
    case target
    /// Stays in to pass-protect.
    case blocker
    /// Lead-blocks for the runner.
    case lead
    /// Play-action / fake: sells a run, then blocks or releases late.
    case fake
}

/// Route shapes available to a lane target.
public enum RouteKind: String, Codable, Sendable {
    case short, mid, deep, flat, screen, handoff, toss, none
}

/// Buttons the QB sees behind the line (docs/PLAN.md §5.4).
public enum QBAction: String, Codable, Hashable, Sendable {
    case passLeft, passCenter, passRight, handoff, toss
}

// Encode `[Lane: …]` dictionaries as JSON objects keyed by raw value.
extension Lane: CodingKeyRepresentable {}
