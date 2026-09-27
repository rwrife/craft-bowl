import CBRender
import MetalKit
import SwiftUI

/// Hosts the Metal game view inside SwiftUI.
struct GameView: UIViewRepresentable {
    final class Coordinator {
        var renderer: Renderer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isMultipleTouchEnabled = true
        context.coordinator.renderer = Renderer(view: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
