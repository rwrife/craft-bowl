#if canImport(UIKit)
import CBCore
import UIKit

/// Hardware keyboard mapping (Simulator / iPad keyboards). Fed from `pressesBegan/Ended` on the game view.
///
/// WASD / arrows = move, Space = turbo (hold), J / K / L = pass left / center / right, H = handoff,
/// U = dive, Tab = switch player, Q = switch nearest, Return = snap, [ / ] = previous / next play,
/// 1–8 = pick play, P / Esc = pause, ` = dev overlay.
@MainActor
public final class KeyboardInput {
    private let queue: InputQueue
    private var held: Set<UIKeyboardHIDUsage> = []

    public init(queue: InputQueue) { self.queue = queue }

    /// Returns true if the key was consumed.
    @discardableResult
    public func handle(_ key: UIKeyboardHIDUsage, down: Bool) -> Bool {
        if down { held.insert(key) } else { held.remove(key) }
        switch key {
        case .keyboardW, .keyboardA, .keyboardS, .keyboardD,
             .keyboardUpArrow, .keyboardDownArrow, .keyboardLeftArrow, .keyboardRightArrow:
            queue.send(.move(moveVector), from: .keyboard)
            return true
        case .keyboardSpacebar:
            queue.send(.turbo(down), from: .keyboard)
            return true
        default:
            break
        }
        guard down, let action = Self.action(for: key) else { return Self.action(for: key) != nil }
        queue.send(action, from: .keyboard)
        return true
    }

    private var moveVector: Vec2 {
        var v = Vec2.zero
        if held.contains(.keyboardW) || held.contains(.keyboardUpArrow) { v.y += 1 }
        if held.contains(.keyboardS) || held.contains(.keyboardDownArrow) { v.y -= 1 }
        if held.contains(.keyboardD) || held.contains(.keyboardRightArrow) { v.x += 1 }
        if held.contains(.keyboardA) || held.contains(.keyboardLeftArrow) { v.x -= 1 }
        return v.normalized
    }

    private static func action(for key: UIKeyboardHIDUsage) -> GameAction? {
        switch key {
        case .keyboardJ: .passLeft
        case .keyboardK: .passCenter
        case .keyboardL: .passRight
        case .keyboardH: .handoff
        case .keyboardU: .dive
        case .keyboardTab: .switchPlayer
        case .keyboardQ: .switchNearest
        case .keyboardReturnOrEnter: .snap
        case .keyboardOpenBracket: .previousPlay
        case .keyboardCloseBracket: .nextPlay
        case .keyboardP, .keyboardEscape: .pause
        case .keyboardGraveAccentAndTilde: .toggleDevOverlay
        case .keyboard1: .playSelect(0)
        case .keyboard2: .playSelect(1)
        case .keyboard3: .playSelect(2)
        case .keyboard4: .playSelect(3)
        case .keyboard5: .playSelect(4)
        case .keyboard6: .playSelect(5)
        case .keyboard7: .playSelect(6)
        case .keyboard8: .playSelect(7)
        default: nil
        }
    }

    public func releaseAll() {
        held.removeAll()
        queue.send(.move(.zero), from: .keyboard)
        queue.send(.turbo(false), from: .keyboard)
    }
}
#endif
