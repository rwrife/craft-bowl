#if canImport(MetalKit)
import CBAnimation
import CBAssets
import CBCore
import Metal
import MetalKit
import QuartzCore
import Synchronization
import simd

/// GPU pass timings written from Metal's completion threads, read on the main thread.
final class GPUTimings: Sendable {
    private let values = Mutex<SIMD3<Float>>(.zero)
    func set(_ pass: Int, _ ms: Float) { values.withLock { $0[pass] = ms } }
    var current: SIMD3<Float> { values.withLock { $0 } }
}

/// Forward renderer for the blocky stadium (issues #6–#10).
///
/// Frame = 3 command buffers on one queue: [GPU cull + shadow map] → [HDR scene] → [bloom, tone map +
/// LUT, MetalFX upscale, present]. Per-frame data lives in a triple-buffered shared arena so the CPU never
/// waits on the GPU mid-frame. Players and the ~10k crowd are instanced and culled on the GPU into
/// indirect draw arguments.
@MainActor
public final class Renderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    public weak var source: RenderFrameSource?
    public var settings = RenderSettings()
    public private(set) var stats = RenderStats()

    static let framesInFlight = 3
    static let maxPlayers = 32
    static let maxGlows = 160
    static let maxDebugVertices = 24_000
    static let maxOverlayVertices = 2048
    static let maxLights = 16
    static let shadowSize = 2048
    static let bloomLevels = 5

    private let queue: MTLCommandQueue
    private let inFlight = DispatchSemaphore(value: Renderer.framesInFlight)
    private let timings = GPUTimings()
    private let captureScope: MTLCaptureScope
    private var residency: MTLResidencySet?
    /// GPU culling + indirect draws. The Simulator's Metal device has no indirect-draw support, so it draws everything directly.
    private let gpuDriven: Bool

    // Pipelines
    private let scenePSO, shadowPSO, skyPSO, glowPSO, debugPSO: MTLRenderPipelineState
    private let prefilterPSO, downPSO, upPSO, compositePSO, blitPSO, overlayPSO: MTLRenderPipelineState
    private let cullPSO: MTLComputePipelineState
    private let depthWrite, depthSky, depthRead: MTLDepthStencilState

    // Geometry
    private struct Mesh {
        let vertices: MTLBuffer
        let indices: MTLBuffer
        let indexCount: Int
        let bounds: SIMD4<Float>
    }
    private let stadium, player, crowdPerson, ball: Mesh
    private let crowdInstances: MTLBuffer
    private let crowdCount: Int
    private var glowTemplate: [GPUGlow] = []
    private var floodLights: [GPUPointLight] = []

    // Per-frame arena
    private struct Layout {
        var uniforms = 0, lights = 0, teams = 0, cull = 0, cullCrowd = 0, args = 0, instances = 0, bones = 0, glows = 0, debug = 0, overlay = 0
        var size = 0
    }
    private let layout: Layout
    private let arenas: [MTLBuffer]
    private let visibleLists: [MTLBuffer]
    private var frameIndex = 0

    // Targets
    private var targetSize = SIMD2<Int>(0, 0)
    private var hdr: MTLTexture?
    private var depth: MTLTexture?
    private var bloom: MTLTexture?
    private var bloomViews: [MTLTexture] = []
    private var ldr: MTLTexture?
    private var upscaler: Upscaler?
    private let shadowMap: MTLTexture
    private let lut: MTLTexture

    private var frame = RenderFrame()
    private var renderScale: Float = 0.85
    private let start = CACurrentMediaTime()
    private var lastTime = CACurrentMediaTime()
    private var smoothedCPU: Float = 0

    private static func supportsResidencySets(_ device: MTLDevice) -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return device.supportsFamily(.apple6) || device.supportsFamily(.mac2)
        #endif
    }

    /// Needs an A14 (Apple GPU family 7) or newer. The Simulator's Metal device reports a lower family
    /// but supports every feature used here, so it's allowed for development.
    public static func isSupported(_ device: MTLDevice?) -> Bool {
        guard let device else { return false }
        #if targetEnvironment(simulator)
        return true
        #else
        return device.supportsFamily(.apple7)
        #endif
    }

    public init?(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(), Renderer.isSupported(device),
              let queue = device.makeCommandQueue(), let library = device.makeDefaultLibrary()
        else { return nil }
        self.device = device
        #if targetEnvironment(simulator)
        gpuDriven = false
        #else
        gpuDriven = true
        #endif
        self.queue = queue
        queue.label = "CraftBowl.Main"

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .invalid
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        do {
            func render(_ label: String, _ v: String, _ f: String?, color: MTLPixelFormat?,
                        depth: MTLPixelFormat = .invalid, additive: Bool = false,
                        alpha: Bool = false) throws -> MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor()
                d.label = label
                d.vertexFunction = library.makeFunction(name: v)
                d.fragmentFunction = f.flatMap { library.makeFunction(name: $0) }
                if let color {
                    let a = d.colorAttachments[0]!
                    a.pixelFormat = color
                    if additive || alpha {
                        a.isBlendingEnabled = true
                        a.rgbBlendOperation = .add
                        a.alphaBlendOperation = .add
                        a.sourceRGBBlendFactor = additive ? .one : .sourceAlpha
                        a.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
                        a.sourceAlphaBlendFactor = .zero
                        a.destinationAlphaBlendFactor = .one
                    }
                }
                d.depthAttachmentPixelFormat = depth
                return try device.makeRenderPipelineState(descriptor: d)
            }
            let hdrFormat = MTLPixelFormat.rgba16Float
            scenePSO = try render("Scene", "scene_vertex", "scene_fragment", color: hdrFormat, depth: .depth32Float)
            shadowPSO = try render("Shadow", "shadow_vertex", nil, color: nil, depth: .depth32Float)
            skyPSO = try render("Sky", "sky_vertex", "sky_fragment", color: hdrFormat, depth: .depth32Float)
            glowPSO = try render("Glow", "glow_vertex", "glow_fragment", color: hdrFormat, depth: .depth32Float,
                                 additive: true)
            debugPSO = try render("Debug", "debug_vertex", "debug_fragment", color: hdrFormat, depth: .depth32Float,
                                  alpha: true)
            prefilterPSO = try render("BloomPrefilter", "post_vertex", "bloom_prefilter", color: hdrFormat)
            downPSO = try render("BloomDown", "post_vertex", "bloom_down", color: hdrFormat)
            upPSO = try render("BloomUp", "post_vertex", "bloom_up", color: hdrFormat, additive: true)
            compositePSO = try render("Composite", "post_vertex", "composite", color: .rgba8Unorm)
            blitPSO = try render("FinalBlit", "post_vertex", "final_blit", color: view.colorPixelFormat)
            overlayPSO = try render("Overlay", "overlay_vertex", "debug_fragment", color: view.colorPixelFormat,
                                    alpha: true)
            guard let cullFn = library.makeFunction(name: "cull_instances") else { return nil }
            cullPSO = try device.makeComputePipelineState(function: cullFn)
        } catch {
            print("CraftBowl renderer: pipeline creation failed: \(error)")
            return nil
        }

        func depthState(_ compare: MTLCompareFunction, write: Bool) -> MTLDepthStencilState? {
            let d = MTLDepthStencilDescriptor()
            d.depthCompareFunction = compare
            d.isDepthWriteEnabled = write
            return device.makeDepthStencilState(descriptor: d)
        }
        guard let dw = depthState(.less, write: true), let ds = depthState(.lessEqual, write: false),
              let dr = depthState(.lessEqual, write: false)
        else { return nil }
        depthWrite = dw
        depthSky = ds
        depthRead = dr

        func upload(_ m: MeshBuilder, _ label: String) -> Mesh? {
            guard let vb = device.makeBuffer(bytes: m.vertices, length: m.vertices.count * MemoryLayout<GPUVertex>.stride),
                  let ib = device.makeBuffer(bytes: m.indices, length: m.indices.count * 4)
            else { return nil }
            vb.label = "\(label).vertices"
            ib.label = "\(label).indices"
            return Mesh(vertices: vb, indices: ib, indexCount: m.indices.count, bounds: m.boundingSphere)
        }
        let stadiumData = Meshes.stadium()
        guard let stadium = upload(stadiumData.mesh, "Stadium"), let player = upload(Meshes.player(), "Player"),
              let crowdPerson = upload(Meshes.crowdPerson(), "CrowdPerson"), let ball = upload(Meshes.ball(), "Ball")
        else { return nil }
        self.stadium = stadium
        self.player = player
        self.crowdPerson = crowdPerson
        self.ball = ball

        // Crowd instances are static; only the bob animation (shader) and excitement uniform change.
        var rng = PCG32(seed: 0xC0FFEE)
        let home = TeamUniform.blue, away = TeamUniform.red
        let neutrals: [RGB] = [RGB(hex: 0xE8E8E8), RGB(hex: 0x2B2B2B), RGB(hex: 0x5A6B7C), RGB(hex: 0x8C6A4A),
                               RGB(hex: 0x3F7F4F), RGB(hex: 0xC9B37E)]
        var crowd: [GPUInstance] = []
        crowd.reserveCapacity(stadiumData.seats.count)
        for seat in stadiumData.seats {
            if rng.unitFloat() < 0.04 { continue }
            let homeBias: Float = seat.side < 0 ? 0.62 : (seat.side > 0 ? 0.25 : 0.45)
            let roll = rng.unitFloat()
            let color: RGB
            if roll < homeBias * 0.8 {
                color = rng.unitFloat() < 0.75 ? home.primary : home.secondary
            } else if roll < 0.8 {
                color = rng.unitFloat() < 0.75 ? away.primary : away.secondary
            } else {
                color = neutrals[Int(rng.nextUInt32() % UInt32(neutrals.count))]
            }
            let s = 0.92 + rng.unitFloat() * 0.16
            let jitter = SIMD3<Float>((rng.unitFloat() - 0.5) * 0.08, 0, (rng.unitFloat() - 0.5) * 0.08)
            let model = RenderMath.translation(seat.position + jitter) * RenderMath.rotationY(seat.yaw)
                * RenderMath.scale(SIMD3(s, s, s))
            let shade = 0.85 + rng.unitFloat() * 0.3
            let skin = rng.nextUInt32() % 12
            let seed = rng.nextUInt32() & 0xFFFF
            crowd.append(GPUInstance(model: model, tint: SIMD4(color.linear.xyz * shade, 0),
                                     params: SIMD4(2, noBones, InstanceFlags.crowd, skin | (seed << 16)),
                                     bounds: crowdPerson.bounds))
        }
        crowdCount = crowd.count
        guard let crowdBuf = device.makeBuffer(bytes: crowd, length: crowd.count * MemoryLayout<GPUInstance>.stride)
        else { return nil }
        crowdBuf.label = "Crowd.instances"
        crowdInstances = crowdBuf

        for p in stadiumData.lamps {
            glowTemplate.append(GPUGlow(positionSize: SIMD4(p, 2.2), color: SIMD4(3.6, 3.4, 3.0, 0)))
        }
        for p in stadiumData.floodlights {
            glowTemplate.append(GPUGlow(positionSize: SIMD4(p + SIMD3(0, 1, 0), 18), color: SIMD4(0.5, 0.48, 0.42, 0)))
            floodLights.append(GPUPointLight(positionRadius: SIMD4(p, 180), colorIntensity: SIMD4(0.92, 0.95, 1.0, 0.7)))
        }

        // Arena layout (256-byte aligned sub-allocations).
        var l = Layout()
        var cursor = 0
        func take(_ bytes: Int) -> Int {
            let o = cursor
            cursor = (cursor + bytes + 255) & ~255
            return o
        }
        l.uniforms = take(MemoryLayout<FrameUniforms>.stride)
        l.lights = take(MemoryLayout<GPUPointLight>.stride * Renderer.maxLights)
        l.teams = take(MemoryLayout<GPUTeamColors>.stride * 2)
        // Each constant-buffer binding needs its own 256-byte-aligned slot.
        l.cull = take(MemoryLayout<CullUniforms>.stride)
        l.cullCrowd = take(MemoryLayout<CullUniforms>.stride)
        l.args = take(MemoryLayout<IndexedIndirectArgs>.stride * 2)
        l.instances = take(MemoryLayout<GPUInstance>.stride * (Renderer.maxPlayers + 2))
        l.bones = take(MemoryLayout<simd_float4x4>.stride * Rig.boneCount * Renderer.maxPlayers)
        l.glows = take(MemoryLayout<GPUGlow>.stride * Renderer.maxGlows)
        l.debug = take(MemoryLayout<GPUDebugVertex>.stride * Renderer.maxDebugVertices)
        l.overlay = take(MemoryLayout<GPUDebugVertex>.stride * Renderer.maxOverlayVertices)
        l.size = cursor
        layout = l

        var arenas: [MTLBuffer] = [], visible: [MTLBuffer] = []
        for i in 0..<Renderer.framesInFlight {
            guard let a = device.makeBuffer(length: l.size, options: .storageModeShared),
                  let v = device.makeBuffer(length: (Renderer.maxPlayers + crowd.count) * 4, options: .storageModePrivate)
            else { return nil }
            a.label = "FrameArena\(i)"
            v.label = "VisibleList\(i)"
            arenas.append(a)
            visible.append(v)
        }
        self.arenas = arenas
        self.visibleLists = visible

        let sd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: Renderer.shadowSize,
                                                          height: Renderer.shadowSize, mipmapped: false)
        sd.usage = [.renderTarget, .shaderRead]
        sd.storageMode = .private
        guard let shadowMap = device.makeTexture(descriptor: sd), let lut = ColorGrade.makeLUT(device: device)
        else { return nil }
        shadowMap.label = "ShadowMap"
        self.shadowMap = shadowMap
        self.lut = lut

        captureScope = MTLCaptureManager.shared().makeCaptureScope(commandQueue: queue)
        captureScope.label = "CraftBowl Frame"
        super.init()
        MTLCaptureManager.shared().defaultCaptureScope = captureScope

        var allocations: [any MTLAllocation] = [stadium.vertices, stadium.indices, player.vertices, player.indices,
                                                crowdPerson.vertices, crowdPerson.indices, ball.vertices, ball.indices,
                                                crowdInstances, shadowMap, lut]
        allocations += arenas as [any MTLAllocation]
        allocations += visible as [any MTLAllocation]
        // The Simulator's Metal device doesn't support residency sets; creating one trips an API-validation assertion.
        if Self.supportsResidencySets(device),
           let set = try? device.makeResidencySet(descriptor: MTLResidencySetDescriptor()) {
            set.addAllocations(allocations)
            set.commit()
            queue.addResidencySet(set)
            residency = set
        }
        stats.crowdTotal = crowdCount
        stats.residencySetActive = residency != nil
        view.delegate = self
    }

    // MARK: - Targets

    private func ensureTargets(width: Int, height: Int) {
        guard width > 0, height > 0, SIMD2(width, height) != targetSize else { return }
        let old: [any MTLAllocation] = [hdr, bloom, ldr, upscaler?.output].compactMap { $0 }
        targetSize = SIMD2(width, height)
        upscaler = Upscaler(device: device, width: width, height: height)

        let hd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height,
                                                          mipmapped: false)
        hd.usage = [.renderTarget, .shaderRead]
        hd.storageMode = .private
        hdr = device.makeTexture(descriptor: hd)
        hdr?.label = "HDR"

        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: width, height: height,
                                                          mipmapped: false)
        dd.usage = .renderTarget
        #if targetEnvironment(simulator)
        dd.storageMode = .private
        #else
        dd.storageMode = .memoryless
        #endif
        depth = device.makeTexture(descriptor: dd)
        depth?.label = "SceneDepth"

        let bd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: max(1, width / 2),
                                                          height: max(1, height / 2), mipmapped: true)
        bd.mipmapLevelCount = Renderer.bloomLevels
        bd.usage = [.renderTarget, .shaderRead]
        bd.storageMode = .private
        bloom = device.makeTexture(descriptor: bd)
        bloom?.label = "Bloom"
        bloomViews = (0..<Renderer.bloomLevels).compactMap { level in
            bloom?.makeTextureView(pixelFormat: .rgba16Float, textureType: .type2D, levels: level..<(level + 1),
                                   slices: 0..<1)
        }

        let ld = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height,
                                                          mipmapped: false)
        ld.usage = MTLTextureUsage([.renderTarget, .shaderRead]).union(upscaler?.inputUsage ?? [])
        ld.storageMode = .private
        ldr = device.makeTexture(descriptor: ld)
        ldr?.label = "LDR"

        if let residency {
            // Memoryless depth has no backing allocation, so it's never added to the residency set.
            old.forEach { residency.removeAllocation($0) }
            residency.addAllocations([hdr, bloom, ldr, upscaler?.output].compactMap { $0 })
            residency.commit()
        }
        stats.metalFXActive = upscaler != nil
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        ensureTargets(width: Int(size.width), height: Int(size.height))
    }

    // MARK: - Frame

    nonisolated private static func timingHandler(_ timings: GPUTimings, pass: Int,
                                                  signal: DispatchSemaphore?) -> MTLCommandBufferHandler {
        { cb in
            let ms = Float((cb.gpuEndTime - cb.gpuStartTime) * 1000)
            timings.set(pass, ms.isFinite ? max(0, ms) : 0)
            signal?.signal()
        }
    }

    public func draw(in view: MTKView) {
        let cpuStart = CACurrentMediaTime()
        inFlight.wait()
        captureScope.begin()
        defer { captureScope.end() }

        frameIndex = (frameIndex + 1) % Renderer.framesInFlight
        let arena = arenas[frameIndex]
        let base = arena.contents()
        let args = (base + layout.args).bindMemory(to: IndexedIndirectArgs.self, capacity: 2)
        // This slot's previous GPU work is complete (semaphore), so its culling results are readable.
        stats.playersVisible = gpuDriven ? Int(args[0].instanceCount) : stats.playersVisible
        stats.crowdVisible = gpuDriven ? Int(args[1].instanceCount) : (settings.crowd ? crowdCount : 0)

        let now = CACurrentMediaTime()
        let dt = min(0.1, now - lastTime)
        lastTime = now
        source?.update(deltaTime: dt, frame: &frame)

        let W = Int(view.drawableSize.width), H = Int(view.drawableSize.height)
        ensureTargets(width: W, height: H)
        guard let hdr, let depth, let ldr, bloomViews.count == Renderer.bloomLevels,
              let cmd0 = queue.makeCommandBuffer(), let cmd1 = queue.makeCommandBuffer(),
              let cmd2 = queue.makeCommandBuffer()
        else { inFlight.signal(); return }

        updateRenderScale()
        let rw = max(64, Int(Float(W) * renderScale) & ~1), rh = max(64, Int(Float(H) * renderScale) & ~1)
        stats.renderScale = renderScale
        stats.renderSize = SIMD2(rw, rh)
        stats.drawableSize = SIMD2(W, H)
        var drawCalls = 0

        let playerCount = min(frame.players.count, Renderer.maxPlayers)
        if !gpuDriven { stats.playersVisible = playerCount }
        let glowCount = settings.glows ? min(glowTemplate.count, Renderer.maxGlows) : 0
        let fu = writeFrameData(base: base, aspect: Float(W) / Float(H), renderSize: SIMD2(Float(rw), Float(rh)),
                                full: SIMD2(Float(W), Float(H)), playerCount: playerCount, glowCount: glowCount)
        let debugCount = writeDebug(base: base, eye: frame.camera.eye)
        let overlayCount = writeStatBars(base: base, viewProj: fu.viewProj, size: SIMD2(Float(W), Float(H)))

        // Pass 1: GPU culling + shadow map
        cmd0.label = "Cull+Shadow"
        if gpuDriven, let ce = cmd0.makeComputeCommandEncoder() {
            ce.label = "GPU Cull"
            ce.setComputePipelineState(cullPSO)
            let tg = MTLSize(width: 64, height: 1, depth: 1)
            ce.setBuffer(arena, offset: layout.instances, index: 0)
            ce.setBuffer(arena, offset: layout.cull, index: 1)
            ce.setBuffer(visibleLists[frameIndex], offset: 0, index: 2)
            ce.setBuffer(arena, offset: layout.args, index: 3)
            if playerCount > 0 {
                ce.dispatchThreadgroups(MTLSize(width: (playerCount + 63) / 64, height: 1, depth: 1),
                                        threadsPerThreadgroup: tg)
            }
            if settings.crowd {
                ce.setBuffer(crowdInstances, offset: 0, index: 0)
                ce.setBuffer(arena, offset: layout.cullCrowd, index: 1)
                ce.dispatchThreadgroups(MTLSize(width: (crowdCount + 63) / 64, height: 1, depth: 1),
                                        threadsPerThreadgroup: tg)
            }
            ce.endEncoding()
        }
        if settings.shadows {
            let sp = MTLRenderPassDescriptor()
            sp.depthAttachment.texture = shadowMap
            sp.depthAttachment.loadAction = .clear
            sp.depthAttachment.storeAction = .store
            sp.depthAttachment.clearDepth = 1
            if let se = cmd0.makeRenderCommandEncoder(descriptor: sp) {
                se.label = "Shadow Map"
                se.setRenderPipelineState(shadowPSO)
                se.setDepthStencilState(depthWrite)
                se.setCullMode(.none)
                se.setDepthBias(0.5, slopeScale: 1.5, clamp: 0.01)
                se.setVertexBuffer(arena, offset: layout.uniforms, index: 4)
                se.setVertexBuffer(arena, offset: layout.bones, index: 5)
                se.setVertexBuffer(visibleLists[frameIndex], offset: 0, index: 2)
                drawCalls += encodeOpaque(se, arena: arena, playerCount: playerCount, shadow: true)
                se.endEncoding()
            }
        }
        cmd0.addCompletedHandler(Renderer.timingHandler(timings, pass: 0, signal: nil))
        cmd0.commit()

        // Pass 2: HDR scene
        cmd1.label = "Scene"
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = hdr
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].storeAction = .store
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rp.depthAttachment.texture = depth
        rp.depthAttachment.loadAction = .clear
        rp.depthAttachment.storeAction = .dontCare
        rp.depthAttachment.clearDepth = 1
        if let e = cmd1.makeRenderCommandEncoder(descriptor: rp) {
            e.label = "Forward"
            e.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(rw), height: Double(rh), znear: 0, zfar: 1))
            e.setScissorRect(MTLScissorRect(x: 0, y: 0, width: rw, height: rh))
            e.setFrontFacing(.counterClockwise)
            e.setCullMode(.back)
            e.setRenderPipelineState(scenePSO)
            e.setDepthStencilState(depthWrite)
            e.setVertexBuffer(arena, offset: layout.uniforms, index: 4)
            e.setVertexBuffer(arena, offset: layout.bones, index: 5)
            e.setVertexBuffer(arena, offset: layout.teams, index: 6)
            e.setFragmentBuffer(arena, offset: layout.uniforms, index: 0)
            e.setFragmentBuffer(arena, offset: layout.lights, index: 1)
            e.setFragmentTexture(shadowMap, index: 0)
            e.setVertexBuffer(visibleLists[frameIndex], offset: 0, index: 2)
            drawCalls += encodeOpaque(e, arena: arena, playerCount: playerCount, shadow: false)
            if settings.crowd {
                e.pushDebugGroup("Crowd")
                var dp = DrawParams(visibleOffset: UInt32(Renderer.maxPlayers), useVisible: gpuDriven ? 1 : 0)
                e.setVertexBytes(&dp, length: MemoryLayout<DrawParams>.stride, index: 3)
                e.setVertexBuffer(crowdPerson.vertices, offset: 0, index: 0)
                e.setVertexBuffer(crowdInstances, offset: 0, index: 1)
                if gpuDriven {
                    e.drawIndexedPrimitives(type: .triangle, indexType: .uint32, indexBuffer: crowdPerson.indices,
                                            indexBufferOffset: 0, indirectBuffer: arena,
                                            indirectBufferOffset: layout.args + MemoryLayout<IndexedIndirectArgs>.stride)
                } else {
                    e.drawIndexedPrimitives(type: .triangle, indexCount: crowdPerson.indexCount, indexType: .uint32,
                                            indexBuffer: crowdPerson.indices, indexBufferOffset: 0,
                                            instanceCount: crowdCount)
                }
                drawCalls += 1
                e.popDebugGroup()
            }
            e.setCullMode(.none)
            e.setRenderPipelineState(skyPSO)
            e.setDepthStencilState(depthSky)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            drawCalls += 1
            e.setDepthStencilState(depthRead)
            if glowCount > 0 {
                e.setRenderPipelineState(glowPSO)
                e.setVertexBuffer(arena, offset: layout.glows, index: 0)
                e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: glowCount)
                drawCalls += 1
            }
            if debugCount > 0 {
                e.setRenderPipelineState(debugPSO)
                e.setVertexBuffer(arena, offset: layout.debug, index: 0)
                e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: debugCount)
                drawCalls += 1
            }
            e.endEncoding()
        }
        cmd1.addCompletedHandler(Renderer.timingHandler(timings, pass: 1, signal: nil))
        cmd1.commit()

        // Pass 3: post + present
        cmd2.label = "Post"
        let scaleUV = SIMD2(Float(rw) / Float(W), Float(rh) / Float(H))
        if settings.bloom {
            drawCalls += encodeBloom(cmd2, hdr: hdr, scaleUV: scaleUV, full: SIMD2(W, H))
        }
        var pu = PostUniforms(source: SIMD4(scaleUV.x, scaleUV.y, 1 / Float(W), 1 / Float(H)),
                              bloom: SIMD4(1.1, 0.6, 0.55, settings.bloom ? 1 : 0),
                              grade: SIMD4(settings.exposure * fu.skyTop.w, settings.colorGrade ? 1 : 0,
                                           settings.vignette, Float(ColorGrade.size)),
                              misc: SIMD4(fu.cameraPos.w, settings.chromaticAberration, 0, 0))
        drawCalls += fullscreen(cmd2, target: ldr, pso: compositePSO, label: "Composite",
                                viewport: SIMD2(rw, rh), textures: [hdr, bloomViews[0], lut], uniforms: &pu)
        var finalSource = ldr
        var finalUV = scaleUV
        if settings.metalFX, let upscaler {
            upscaler.encode(cmd2, input: ldr, contentWidth: rw, contentHeight: rh)
            finalSource = upscaler.output
            finalUV = SIMD2(1, 1)
        }
        if let drawable = view.currentDrawable {
            var bu = PostUniforms(source: SIMD4(finalUV.x, finalUV.y, 0, 0))
            drawCalls += fullscreen(cmd2, target: drawable.texture, pso: blitPSO, label: "Final",
                                    viewport: SIMD2(W, H), textures: [finalSource], uniforms: &bu)
            if overlayCount > 0 {
                let p = MTLRenderPassDescriptor()
                p.colorAttachments[0].texture = drawable.texture
                p.colorAttachments[0].loadAction = .load
                p.colorAttachments[0].storeAction = .store
                if let e = cmd2.makeRenderCommandEncoder(descriptor: p) {
                    e.label = "Stat Bars"
                    e.setRenderPipelineState(overlayPSO)
                    e.setVertexBuffer(arena, offset: layout.overlay, index: 0)
                    e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: overlayCount)
                    e.endEncoding()
                    drawCalls += 1
                }
            }
            cmd2.present(drawable)
        }
        cmd2.addCompletedHandler(Renderer.timingHandler(timings, pass: 2, signal: inFlight))
        cmd2.commit()

        let gpu = timings.current
        stats.gpuCullShadowMs = gpu.x
        stats.gpuSceneMs = gpu.y
        stats.gpuPostMs = gpu.z
        stats.drawCalls = drawCalls
        stats.metalFXActive = settings.metalFX && upscaler != nil
        let cpu = Float((CACurrentMediaTime() - cpuStart) * 1000)
        smoothedCPU = smoothedCPU * 0.9 + cpu * 0.1
        stats.cpuFrameMs = smoothedCPU
    }

    private func updateRenderScale() {
        guard settings.dynamicResolution else {
            renderScale = clamp(settings.fixedScale, 0.5, 1)
            return
        }
        let gpu = timings.current
        let total = gpu.x + gpu.y + gpu.z
        guard total > 0 else { return }
        if total > settings.targetFrameMs * 0.85 {
            renderScale -= 0.03
        } else if total < settings.targetFrameMs * 0.6 {
            renderScale += 0.005
        }
        renderScale = clamp(renderScale, 0.5, 1)
    }

    /// Stadium (direct), players (GPU-culled indirect, or all for shadows), ball (direct).
    private func encodeOpaque(_ e: MTLRenderCommandEncoder, arena: MTLBuffer, playerCount: Int, shadow: Bool) -> Int {
        let stride = MemoryLayout<GPUInstance>.stride
        var calls = 0
        var dp = DrawParams()
        e.setVertexBytes(&dp, length: MemoryLayout<DrawParams>.stride, index: 3)
        e.setVertexBuffer(stadium.vertices, offset: 0, index: 0)
        e.setVertexBuffer(arena, offset: layout.instances + stride * Renderer.maxPlayers, index: 1)
        e.drawIndexedPrimitives(type: .triangle, indexCount: stadium.indexCount, indexType: .uint32,
                                indexBuffer: stadium.indices, indexBufferOffset: 0)
        calls += 1
        if frame.ballVisible {
            e.setVertexBuffer(ball.vertices, offset: 0, index: 0)
            e.setVertexBuffer(arena, offset: layout.instances + stride * (Renderer.maxPlayers + 1), index: 1)
            e.drawIndexedPrimitives(type: .triangle, indexCount: ball.indexCount, indexType: .uint32,
                                    indexBuffer: ball.indices, indexBufferOffset: 0)
            calls += 1
        }
        if playerCount > 0 {
            e.setVertexBuffer(player.vertices, offset: 0, index: 0)
            e.setVertexBuffer(arena, offset: layout.instances, index: 1)
            if shadow || !gpuDriven {
                e.drawIndexedPrimitives(type: .triangle, indexCount: player.indexCount, indexType: .uint32,
                                        indexBuffer: player.indices, indexBufferOffset: 0, instanceCount: playerCount)
            } else {
                dp.useVisible = 1
                e.setVertexBytes(&dp, length: MemoryLayout<DrawParams>.stride, index: 3)
                e.drawIndexedPrimitives(type: .triangle, indexType: .uint32, indexBuffer: player.indices,
                                        indexBufferOffset: 0, indirectBuffer: arena, indirectBufferOffset: layout.args)
            }
            calls += 1
        }
        return calls
    }

    private func encodeBloom(_ cmd: MTLCommandBuffer, hdr: MTLTexture, scaleUV: SIMD2<Float>, full: SIMD2<Int>) -> Int {
        var calls = 0
        var pu = PostUniforms(source: SIMD4(scaleUV.x, scaleUV.y, 1 / Float(full.x), 1 / Float(full.y)),
                              bloom: SIMD4(1.1, 0.6, 0, 1))
        calls += fullscreen(cmd, target: bloomViews[0], pso: prefilterPSO, label: "Bloom Prefilter",
                            viewport: nil, textures: [hdr], uniforms: &pu)
        for level in 1..<Renderer.bloomLevels {
            let src = bloomViews[level - 1]
            pu.source = SIMD4(1, 1, 1 / Float(src.width), 1 / Float(src.height))
            calls += fullscreen(cmd, target: bloomViews[level], pso: downPSO, label: "Bloom Down \(level)",
                                viewport: nil, textures: [src], uniforms: &pu)
        }
        for level in stride(from: Renderer.bloomLevels - 2, through: 0, by: -1) {
            let src = bloomViews[level + 1]
            pu.source = SIMD4(1, 1, 1 / Float(src.width), 1 / Float(src.height))
            calls += fullscreen(cmd, target: bloomViews[level], pso: upPSO, label: "Bloom Up \(level)",
                                viewport: nil, textures: [src], uniforms: &pu, load: true)
        }
        return calls
    }

    private func fullscreen(_ cmd: MTLCommandBuffer, target: MTLTexture, pso: MTLRenderPipelineState, label: String,
                            viewport: SIMD2<Int>?, textures: [MTLTexture], uniforms: inout PostUniforms,
                            load: Bool = false) -> Int {
        let p = MTLRenderPassDescriptor()
        p.colorAttachments[0].texture = target
        p.colorAttachments[0].loadAction = load ? .load : .dontCare
        p.colorAttachments[0].storeAction = .store
        guard let e = cmd.makeRenderCommandEncoder(descriptor: p) else { return 0 }
        e.label = label
        if let viewport {
            e.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(viewport.x), height: Double(viewport.y),
                                      znear: 0, zfar: 1))
        }
        e.setRenderPipelineState(pso)
        for (i, t) in textures.enumerated() { e.setFragmentTexture(t, index: i) }
        e.setFragmentBytes(&uniforms, length: MemoryLayout<PostUniforms>.stride, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        e.endEncoding()
        return 1
    }

    // MARK: - Frame data

    private func writeFrameData(base: UnsafeMutableRawPointer, aspect: Float, renderSize: SIMD2<Float>,
                                full: SIMD2<Float>, playerCount: Int, glowCount: Int) -> FrameUniforms {
        let cam = frame.camera
        let view = RenderMath.lookAt(eye: cam.eye, target: cam.target, up: SIMD3(0, 1, 0))
        let proj = RenderMath.perspective(fovY: cam.fovY, aspect: aspect, near: cam.near, far: cam.far)
        let viewProj = proj * view
        let forward = simd_normalize(cam.target - cam.eye)
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let up = simd_cross(right, forward)

        // Shadow frustum: ortho box around the camera focus, snapped to shadow texels to avoid shimmer.
        let lightDir = simd_normalize(SIMD3<Float>(0.3, -1, 0.4))
        let lightView = RenderMath.lookAt(eye: -lightDir * 100, target: .zero, up: SIMD3(0, 0, -1))
        let focus = cam.target + SIMD3(0, 0, 4)
        var fl = lightView * SIMD4(focus, 1)
        let extent: Float = 42
        let texel = extent * 2 / Float(Renderer.shadowSize)
        fl.x = (fl.x / texel).rounded() * texel
        fl.y = (fl.y / texel).rounded() * texel
        let lightProj = RenderMath.orthographic(left: fl.x - extent, right: fl.x + extent, bottom: fl.y - extent,
                                                top: fl.y + extent, near: -fl.z - 140, far: -fl.z + 140)

        var flags: UInt32 = FrameFlags.fieldLines
        if settings.shadows { flags |= FrameFlags.shadows }
        if settings.pixelNoise { flags |= FrameFlags.pixelNoise }
        let lightCount = min(floodLights.count, Renderer.maxLights)
        let time = Float(CACurrentMediaTime() - start)

        var fu = FrameUniforms()
        fu.viewProj = viewProj
        fu.invViewProj = viewProj.inverse
        fu.lightViewProj = lightProj * lightView
        fu.cameraPos = SIMD4(cam.eye, time)
        fu.cameraRight = SIMD4(right, 0)
        fu.cameraUp = SIMD4(up, 0)
        fu.lightDir = SIMD4(lightDir, 1.15)
        // Night game: a cool floodlight key over the field, faint navy ambient, dark navy fog.
        fu.lightColor = SIMD4(0.96, 0.97, 1.0, 0.6)
        fu.skyTop = SIMD4(0.002, 0.004, 0.016, 1.0)
        fu.skyHorizon = SIMD4(0.02, 0.03, 0.075, 0.0045)
        fu.ambient = SIMD4(0.07, 0.085, 0.16, 0.35)
        fu.groundAmbient = SIMD4(0.03, 0.045, 0.03, 0)
        fu.params = SIMD4(frame.crowdExcitement, renderSize.x / full.x, Float(lightCount), Float(bitPattern: flags))
        fu.field = SIMD4(frame.lineOfScrimmage, frame.firstDownLine, frame.showLines ? 1 : 0, 0)
        fu.viewport = SIMD4(renderSize.x, renderSize.y, 1 / full.x, 1 / full.y)
        (base + layout.uniforms).storeBytes(of: fu, as: FrameUniforms.self)

        let lights = (base + layout.lights).bindMemory(to: GPUPointLight.self, capacity: Renderer.maxLights)
        for i in 0..<lightCount { lights[i] = floodLights[i] }

        let teams = (base + layout.teams).bindMemory(to: GPUTeamColors.self, capacity: 2)
        for (i, t) in [frame.home, frame.away].enumerated() {
            teams[i] = GPUTeamColors(primary: t.primary.linear, secondary: t.secondary.linear, trim: t.trim.linear,
                                     helmet: t.helmet.linear, stripe: t.helmetStripe.linear, pants: t.pants.linear,
                                     numberFill: t.numberFill.linear, numberOutline: t.numberOutline.linear)
        }

        let instances = (base + layout.instances).bindMemory(to: GPUInstance.self, capacity: Renderer.maxPlayers + 2)
        let bones = (base + layout.bones).bindMemory(to: simd_float4x4.self,
                                                     capacity: Rig.boneCount * Renderer.maxPlayers)
        let playerBounds = SIMD4(player.bounds.x, player.bounds.y, player.bounds.z, player.bounds.w * 1.4)
        for i in 0..<playerCount {
            let p = frame.players[i]
            Rig.pose(p.pose, phase: p.phase, speed01: p.speed01, turbo: p.turbo, into: bones + i * Rig.boneCount)
            var f: UInt32 = 0
            if p.controlled { f |= InstanceFlags.controlled }
            if p.turbo { f |= InstanceFlags.turbo }
            let model = RenderMath.translation(p.position) * RenderMath.rotationY(p.yaw) * RenderMath.scale(p.scale)
            instances[i] = GPUInstance(model: model, tint: SIMD4(1, 1, 1, 0),
                                       params: SIMD4(UInt32(p.team), UInt32(i * Rig.boneCount), f,
                                                     UInt32(p.skinTone) | UInt32(p.number) << 8 | UInt32(i) << 16),
                                       bounds: playerBounds)
        }
        instances[Renderer.maxPlayers] = GPUInstance(model: matrix_identity_float4x4, tint: SIMD4(1, 1, 1, 0),
                                                     params: SIMD4(2, noBones, 0, 0), bounds: stadium.bounds)
        instances[Renderer.maxPlayers + 1] = GPUInstance(
            model: RenderMath.translation(frame.ballPosition) * RenderMath.rotationY(frame.ballYaw)
                * RenderMath.rotationX(frame.ballPitch),
            tint: SIMD4(1, 1, 1, 0), params: SIMD4(2, noBones, 0, 0), bounds: ball.bounds)

        let planes = RenderMath.frustumPlanes(viewProj)
        let cullPlayers = (base + layout.cull).bindMemory(to: CullUniforms.self, capacity: 1)
        let enabled: UInt32 = settings.gpuCulling ? 1 : 0
        var c = CullUniforms(p0: planes[0], p1: planes[1], p2: planes[2], p3: planes[3], p4: planes[4], p5: planes[5],
                             lod: SIMD4(cam.eye, 0), instanceCount: UInt32(playerCount), visibleOffset: 0,
                             argsIndex: 0, enabled: enabled)
        cullPlayers.pointee = c
        c.lod = SIMD4(cam.eye, settings.crowdDistance)
        c.instanceCount = UInt32(crowdCount)
        c.visibleOffset = UInt32(Renderer.maxPlayers)
        c.argsIndex = 1
        (base + layout.cullCrowd).bindMemory(to: CullUniforms.self, capacity: 1).pointee = c

        let args = (base + layout.args).bindMemory(to: IndexedIndirectArgs.self, capacity: 2)
        args[0] = IndexedIndirectArgs(indexCount: UInt32(player.indexCount), instanceCount: 0, indexStart: 0,
                                      baseVertex: 0, baseInstance: 0)
        args[1] = IndexedIndirectArgs(indexCount: UInt32(crowdPerson.indexCount), instanceCount: 0, indexStart: 0,
                                      baseVertex: 0, baseInstance: 0)

        let glows = (base + layout.glows).bindMemory(to: GPUGlow.self, capacity: Renderer.maxGlows)
        for i in 0..<glowCount { glows[i] = glowTemplate[i] }
        return fu
    }

    /// Screen-space stat bars (NDC quads), pixel-snapped so the chunky frame stays crisp.
    private func writeStatBars(base: UnsafeMutableRawPointer, viewProj: simd_float4x4, size: SIMD2<Float>) -> Int {
        let out = (base + layout.overlay).bindMemory(to: GPUDebugVertex.self, capacity: Renderer.maxOverlayVertices)
        var n = 0
        func quad(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ c: SIMD4<Float>) {
            guard n + 6 <= Renderer.maxOverlayVertices, x1 > x0, y1 > y0 else { return }
            let a = SIMD2(x0 / size.x * 2 - 1, 1 - y0 / size.y * 2), b = SIMD2(x1 / size.x * 2 - 1, 1 - y1 / size.y * 2)
            for p in [SIMD2(a.x, a.y), SIMD2(b.x, a.y), SIMD2(b.x, b.y), SIMD2(a.x, a.y), SIMD2(b.x, b.y), SIMD2(a.x, b.y)] {
                out[n] = GPUDebugVertex(position: SIMD4(p.x, p.y, 0, 1), color: c)
                n += 1
            }
        }
        let unit = max(1, (size.y / 360).rounded())            // ~1 pt
        let w = (unit * 30).rounded(), h = unit * 5, border = unit
        let colors = [StatBar.speedColor, StatBar.enduranceColor, StatBar.abilityColor]
        for bar in frame.statBars {
            let clip = viewProj * SIMD4(bar.anchor, 1)
            guard clip.w > 0.1 else { continue }
            let ndc = SIMD2(clip.x, clip.y) / clip.w
            let cx = ((ndc.x * 0.5 + 0.5) * size.x).rounded(), bottom = ((0.5 - ndc.y * 0.5) * size.y).rounded()
            let x0 = cx - (w / 2).rounded(), y1 = bottom, y0 = y1 - h
            let low = bar.health < 0.35
            let frameColor: SIMD4<Float> = low ? SIMD4(0.95, 0.2, 0.15, 1) : SIMD4(0.02, 0.03, 0.06, 0.95)
            quad(x0 - border * 2, y0 - border * 2, x0 + w + border * 2, y1 + border * 2, frameColor)
            quad(x0 - border, y0 - border, x0 + w + border, y1 + border, SIMD4(0.85, 0.88, 0.95, 0.9))
            quad(x0, y0, x0 + w, y1, SIMD4(0.08, 0.09, 0.14, 1))
            var x = x0
            let third = w / 3
            for i in 0..<3 {
                let len = (third * clamp(bar.segments[i], 0, 1)).rounded()
                quad(x, y0, x + len, y1, SIMD4(colors[i], 1))
                quad(x, y0, x + len, y0 + unit, SIMD4(colors[i] * 0.5 + 0.5, 1))   // top highlight
                x += len
            }
            // faint notches at each third so the empty (fatigued) portion reads as lost stats
            for i in 1..<3 {
                let nx = (x0 + third * Float(i)).rounded()
                if nx > x { quad(nx, y0, nx + unit, y1, SIMD4(0.3, 0.32, 0.4, 1)) }
            }
        }
        return n
    }

    /// Expands lines into camera-facing ribbons (hardware lines are 1px on Retina).
    private func writeDebug(base: UnsafeMutableRawPointer, eye: SIMD3<Float>) -> Int {
        let out = (base + layout.debug).bindMemory(to: GPUDebugVertex.self, capacity: Renderer.maxDebugVertices)
        var n = 0
        func emit(_ lines: [DebugLine], width: Float) {
            for l in lines {
                guard n + 6 <= Renderer.maxDebugVertices else { return }
                let dir = l.b - l.a
                let mid = (l.a + l.b) * 0.5
                var side = simd_cross(dir, eye - mid)
                let len = simd_length(side)
                guard len > 1e-5 else { continue }
                side *= width * 0.5 / len
                let quad = [l.a - side, l.a + side, l.b + side, l.a - side, l.b + side, l.b - side]
                for p in quad {
                    out[n] = GPUDebugVertex(position: SIMD4(p, 1), color: l.color)
                    n += 1
                }
            }
        }
        emit(frame.markers, width: 0.16)
        if settings.debugDraw { emit(frame.debugLines, width: 0.07) }
        return n
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
#endif
