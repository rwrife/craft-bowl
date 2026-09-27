import CBInput
import CBRender
import MetalKit
import SwiftUI

/// MTKView that takes hardware keyboard presses (Simulator / iPad keyboards) and a three-finger tap
/// for the dev overlay.
final class GameMTKView: MTKView {
    var keyboard: KeyboardInput?
    var onThreeFingerTap: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        becomeFirstResponder()
        if gestureRecognizers?.isEmpty ?? true {
            let tap = UITapGestureRecognizer(target: self, action: #selector(threeFingerTap))
            tap.numberOfTouchesRequired = 3
            addGestureRecognizer(tap)
        }
    }

    @objc private func threeFingerTap() { onThreeFingerTap?() }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !handle(presses, down: true) { super.pressesBegan(presses, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !handle(presses, down: false) { super.pressesEnded(presses, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !handle(presses, down: false) { super.pressesCancelled(presses, with: event) }
    }

    private func handle(_ presses: Set<UIPress>, down: Bool) -> Bool {
        guard let keyboard else { return false }
        var handled = false
        for press in presses {
            if let key = press.key, keyboard.handle(key.keyCode, down: down) { handled = true }
        }
        return handled
    }
}

/// Hosts the Metal game view inside SwiftUI and wires the renderer to the game session.
struct GameView: UIViewRepresentable {
    let session: GameSession

    final class Coordinator {
        var renderer: Renderer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GameMTKView {
        let view = GameMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isMultipleTouchEnabled = true
        view.keyboard = session.keyboard
        view.onThreeFingerTap = { [weak session] in session?.showDevOverlay.toggle() }
        let renderer = Renderer(view: view)
        renderer?.source = session
        session.renderer = renderer
        context.coordinator.renderer = renderer
        return view
    }

    func updateUIView(_ uiView: GameMTKView, context: Context) {}
}
