#if canImport(GameController)
import CBCore
import GameController

/// Bridges MFi / Xbox / PlayStation controllers into per-player `InputQueue`s.
///
/// Mapping: left stick / d-pad up-down = move, RT = turbo (hold), A = pass center, X = pass left,
/// B = pass right, Y = handoff/toss, RB = dive, LB = switch player, LT = switch to nearest,
/// d-pad left/right = previous/next play, Menu = pause, Options (or L3+R3) = dev overlay.
@MainActor
public final class ControllerInput {
    private let queues: [InputQueue]
    private var observers: [NSObjectProtocol] = []
    /// Connected controllers in assignment order; index = local player slot.
    public private(set) var assigned: [GCController] = []
    public var onChange: (() -> Void)?

    public init(queues: [InputQueue]) {
        self.queues = queues
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebindAll() }
            })
        }
        GCController.startWirelessControllerDiscovery {}
        rebindAll()
    }

    public var connectedNames: [String] {
        assigned.map { $0.vendorName ?? "Controller" }
    }

    /// Re-assigns every connected extended gamepad to a player slot (P1, P2) in connection order.
    private func rebindAll() {
        let pads = GCController.controllers().filter { $0.extendedGamepad != nil }
        assigned = Array(pads.prefix(queues.count))
        for (slot, controller) in assigned.enumerated() {
            controller.playerIndex = GCControllerPlayerIndex(rawValue: slot) ?? .indexUnset
            bind(controller, to: queues[slot])
        }
        for q in queues.dropFirst(assigned.count) { q.send(.move(.zero), from: .controller) }
        onChange?()
    }

    private func bind(_ controller: GCController, to q: InputQueue) {
        guard let pad = controller.extendedGamepad else { return }
        pad.leftThumbstick.valueChangedHandler = { _, x, y in
            MainActor.assumeIsolated { q.send(.move(Vec2(x, y)), from: .controller) }
        }
        pad.dpad.valueChangedHandler = { _, _, y in
            guard y != 0 else { return }
            MainActor.assumeIsolated { q.send(.move(Vec2(0, y)), from: .controller) }
        }
        pad.rightTrigger.pressedChangedHandler = { _, _, pressed in
            MainActor.assumeIsolated { q.send(.turbo(pressed), from: .controller) }
        }
        func tap(_ button: GCControllerButtonInput?, _ action: GameAction) {
            button?.pressedChangedHandler = { _, _, pressed in
                guard pressed else { return }
                MainActor.assumeIsolated { q.send(action, from: .controller) }
            }
        }
        tap(pad.buttonA, .passCenter)
        tap(pad.buttonX, .passLeft)
        tap(pad.buttonB, .passRight)
        tap(pad.buttonY, .handoff)
        tap(pad.rightShoulder, .dive)
        tap(pad.leftShoulder, .switchPlayer)
        tap(pad.leftTrigger, .switchNearest)
        tap(pad.dpad.left, .previousPlay)
        tap(pad.dpad.right, .nextPlay)
        tap(pad.buttonMenu, .pause)
        tap(pad.buttonOptions, .toggleDevOverlay)
        let l3 = pad.leftThumbstickButton, r3 = pad.rightThumbstickButton
        r3?.pressedChangedHandler = { _, _, pressed in
            guard pressed, l3?.isPressed == true else { return }
            MainActor.assumeIsolated { q.send(.toggleDevOverlay, from: .controller) }
        }
    }
}
#endif
