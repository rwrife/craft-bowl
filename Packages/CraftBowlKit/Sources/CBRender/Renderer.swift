#if canImport(MetalKit)
import CBCore
import Metal
import MetalKit
import QuartzCore

/// Renderer bootstrap (issue R1). Draws the procedural night-sky/turf backdrop from
/// `App/Shaders/Backdrop.metal` so the pipeline is proven end to end. The frame graph,
/// Metal 4 command allocators/argument tables and real scene passes land in R1/R2.
@MainActor
public final class Renderer: NSObject, @preconcurrency MTKViewDelegate {
    public let device: MTLDevice
    private let queue: MTLCommandQueue
    private let backdrop: MTLRenderPipelineState
    private let inFlight = DispatchSemaphore(value: 3)
    private let start = CACurrentMediaTime()

    /// Metal 4 needs an A14 (Apple GPU family 7) or newer. Checked before creating a Renderer.
    public static func isSupported(_ device: MTLDevice?) -> Bool {
        device?.supportsFamily(.apple7) ?? false
    }

    public init?(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              Renderer.isSupported(device),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vfn = library.makeFunction(name: "backdrop_vertex"),
              let ffn = library.makeFunction(name: "backdrop_fragment")
        else { return nil }

        view.device = device
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0.02, green: 0.04, blue: 0.10, alpha: 1)

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "Backdrop"
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        guard let pso = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }

        self.device = device
        self.queue = queue
        self.backdrop = pso
        super.init()
        view.delegate = self
    }

    nonisolated private static func signalOnCompletion(_ semaphore: DispatchSemaphore) -> MTLCommandBufferHandler {
        { _ in semaphore.signal() }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        inFlight.wait()
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass)
        else { inFlight.signal(); return }

        var uniforms = SIMD4<Float>(Float(CACurrentMediaTime() - start),
                                    Float(view.drawableSize.width), Float(view.drawableSize.height), 0)
        enc.label = "Frame"
        enc.setRenderPipelineState(backdrop)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()

        // Built in a nonisolated context: Metal calls this on a background thread.
        cmd.addCompletedHandler(Renderer.signalOnCompletion(inFlight))
        cmd.present(drawable)
        cmd.commit()
    }
}
#endif
