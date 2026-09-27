#if canImport(GameController)
import CBCore
import GameController

/// Bridges MFi / Xbox / PlayStation controllers into an `InputQueue`.
/// Mapping: left stick = move, A = pass center / dive, X = pass left, B = pass right,
/// Y = handoff / switch nearest, RT = turbo, LB = switch player, Menu = pause.
@MainActor
public final class ControllerInput {
    private let queue: InputQueue
    private var observers: [NSObjectProtocol] = []

    public init(queue: InputQueue) {
        self.queue = queue
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) {
            [weak self] note in
            guard let controller = note.object as? GCController else { return }
            MainActor.assumeIsolated { self?.bind(controller) }
        })
        GCController.controllers().forEach(bind)
    }

    private func bind(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        let q = queue
        pad.leftThumbstick.valueChangedHandler = { _, x, y in
            MainActor.assumeIsolated { q.send(.move(Vec2(x, y))) }
        }
        pad.rightTrigger.pressedChangedHandler = { _, _, pressed in
            MainActor.assumeIsolated { q.send(.turbo(pressed)) }
        }
        let tap: (GCControllerButtonInput, GameAction) -> Void = { button, action in
            button.pressedChangedHandler = { _, _, pressed in
                guard pressed else { return }
                MainActor.assumeIsolated { q.send(action) }
            }
        }
        tap(pad.buttonA, .passCenter)
        tap(pad.buttonX, .passLeft)
        tap(pad.buttonB, .passRight)
        tap(pad.buttonY, .handoff)
        tap(pad.leftShoulder, .switchPlayer)
        tap(pad.rightShoulder, .switchNearest)
        tap(pad.buttonMenu, .pause)
    }
}
#endif
