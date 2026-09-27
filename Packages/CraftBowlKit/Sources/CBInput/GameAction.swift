import CBCore

/// Every input source (touch, controller, keyboard) maps into this one stream (issue F5).
public enum GameAction: Sendable, Equatable {
    case move(Vec2)
    case passLeft, passCenter, passRight, handoff
    case turbo(Bool)
    case dive
    case switchPlayer, switchNearest
    case swat
    case pause
    case playSelect(Int)
}

/// Collects actions between sim ticks. Owned by the main actor; drained by the game loop.
@MainActor
public final class InputQueue {
    public private(set) var move: Vec2 = .zero
    public private(set) var turboHeld = false
    private var pending: [GameAction] = []

    public init() {}

    public func send(_ action: GameAction) {
        switch action {
        case .move(let v): move = v
        case .turbo(let held): turboHeld = held
        default: pending.append(action)
        }
    }

    /// Returns and clears discrete actions since the last tick.
    public func drain() -> [GameAction] {
        defer { pending.removeAll(keepingCapacity: true) }
        return pending
    }
}
