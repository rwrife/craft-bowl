import CBCore
import Foundation
import CBSim

/// Every input source (touch, controller, keyboard) maps into this one stream (issue #5).
public enum GameAction: Sendable, Equatable {
    case move(Vec2)
    case passLeft, passCenter, passRight, handoff
    case turbo(Bool)
    case dive
    case switchPlayer, switchNearest
    case swat
    case pause
    case snap
    case nextPlay, previousPlay
    case playSelect(Int)
    case toggleDevOverlay

    public var label: String {
        switch self {
        case .move(let v): String(format: "move(%.2f, %.2f)", v.x, v.y)
        case .passLeft: "passLeft"
        case .passCenter: "passCenter"
        case .passRight: "passRight"
        case .handoff: "handoff"
        case .turbo(let on): "turbo(\(on))"
        case .dive: "dive"
        case .switchPlayer: "switchPlayer"
        case .switchNearest: "switchNearest"
        case .swat: "swat"
        case .pause: "pause"
        case .snap: "snap"
        case .nextPlay: "nextPlay"
        case .previousPlay: "previousPlay"
        case .playSelect(let n): "playSelect(\(n))"
        case .toggleDevOverlay: "toggleDevOverlay"
        }
    }
}

public enum InputSource: String, Sendable, CaseIterable {
    case touch, controller, keyboard
}

/// One logged action for the dev overlay.
public struct LoggedAction: Sendable, Identifiable {
    public let id: Int
    public let source: InputSource
    public let action: GameAction
}

/// Collects actions between sim ticks for one local player. Owned by the main actor; the game loop
/// calls `makeTickInput()` once per sim tick.
@MainActor
public final class InputQueue {
    private var moves: [InputSource: Vec2] = [:]
    private var turbo: Set<InputSource> = []
    private var pending: TickInput.Buttons = []
    private var pendingPlaySelect: Int8 = -1
    private var counter = 0

    /// Most recent discrete actions (newest last), capped for the dev overlay.
    public private(set) var log: [LoggedAction] = []
    /// Called for app-level actions that aren't sim input (pause, dev overlay).
    public var onAppAction: ((GameAction, InputSource) -> Void)?

    public init() {}

    public var move: Vec2 {
        moves.values.max { $0.length < $1.length } ?? .zero
    }

    public var turboHeld: Bool { !turbo.isEmpty }

    public func send(_ action: GameAction, from source: InputSource) {
        switch action {
        case .move(let v):
            moves[source] = v.length > 1 ? v.normalized : v
            return
        case .turbo(let held):
            let was = turbo.contains(source)
            if held { turbo.insert(source) } else { turbo.remove(source) }
            if was == held { return }
        case .passLeft: pending.insert(.passLeft)
        case .passCenter: pending.insert(.passCenter)
        case .passRight: pending.insert(.passRight)
        case .handoff: pending.insert(.handoff)
        case .dive: pending.insert(.dive)
        case .switchPlayer: pending.insert(.switchPlayer)
        case .switchNearest: pending.insert(.switchNearest)
        case .swat: pending.insert(.swat)
        case .snap: pending.insert(.snap)
        case .nextPlay: pending.insert(.nextPlay)
        case .previousPlay: pending.insert(.previousPlay)
        case .playSelect(let n): pendingPlaySelect = Int8(clamping: n)
        case .pause, .toggleDevOverlay: onAppAction?(action, source)
        }
        counter += 1
        log.append(LoggedAction(id: counter, source: source, action: action))
        if log.count > 10 { log.removeFirst(log.count - 10) }
    }

    /// Builds this tick's input and clears one-shot buttons.
    public func makeTickInput() -> TickInput {
        defer {
            pending = []
            pendingPlaySelect = -1
        }
        return TickInput(move: move, turbo: turboHeld, buttons: pending, playSelect: pendingPlaySelect)
    }

    /// Clears all held state (e.g. when the app backgrounds).
    public func reset() {
        moves.removeAll()
        turbo.removeAll()
        pending = []
    }
}
