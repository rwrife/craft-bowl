#if canImport(MetalKit)
import Metal
#if canImport(MetalFX)
import MetalFX
#endif
import simd

/// Cinematic night-game grade baked into a 32³ LUT (issue #10): mild S-curve contrast,
/// +12% saturation, teal shadows and warm highlights. Applied after tone mapping in display space.
enum ColorGrade {
    static let size = 32

    static func grade(_ c: SIMD3<Float>) -> SIMD3<Float> {
        var c = c
        c = c * c * (3 - 2 * c) * 0.18 + c * 0.82
        let luma = simd_dot(c, SIMD3(0.2126, 0.7152, 0.0722))
        c = simd_mix(SIMD3(repeating: luma), c, SIMD3(repeating: 1.12))
        c += SIMD3(-0.012, 0.012, 0.03) * (1 - luma) * (1 - luma)
        c += SIMD3(0.03, 0.012, -0.02) * luma * luma
        return simd_clamp(c, SIMD3(repeating: 0), SIMD3(repeating: 1))
    }

    static func makeLUT(device: MTLDevice) -> MTLTexture? {
        let d = MTLTextureDescriptor()
        d.textureType = .type3D
        d.pixelFormat = .rgba8Unorm
        d.width = size
        d.height = size
        d.depth = size
        d.usage = .shaderRead
        d.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: d) else { return nil }
        tex.label = "GradeLUT"
        var bytes = [UInt8](repeating: 255, count: size * size * size * 4)
        let s = Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let o = grade(SIMD3(Float(r) / s, Float(g) / s, Float(b) / s))
                    let i = ((b * size + g) * size + r) * 4
                    bytes[i] = UInt8(o.x * 255 + 0.5)
                    bytes[i + 1] = UInt8(o.y * 255 + 0.5)
                    bytes[i + 2] = UInt8(o.z * 255 + 0.5)
                }
            }
        }
        bytes.withUnsafeBytes { raw in
            tex.replace(region: MTLRegionMake3D(0, 0, 0, size, size, size), mipmapLevel: 0, slice: 0,
                        withBytes: raw.baseAddress!, bytesPerRow: size * 4, bytesPerImage: size * size * 4)
        }
        return tex
    }
}

#if canImport(MetalFX)
/// MetalFX spatial upscaler from the dynamic-resolution LDR image to drawable size.
/// Temporal upscaling + frame interpolation need motion vectors (follow-up on issue #10).
@MainActor
final class Upscaler {
    let scaler: MTLFXSpatialScaler
    let output: MTLTexture
    let inputUsage: MTLTextureUsage

    init?(device: MTLDevice, width: Int, height: Int) {
        guard MTLFXSpatialScalerDescriptor.supportsDevice(device) else { return nil }
        let d = MTLFXSpatialScalerDescriptor()
        d.colorTextureFormat = .rgba8Unorm
        d.outputTextureFormat = .rgba8Unorm
        d.inputWidth = width
        d.inputHeight = height
        d.outputWidth = width
        d.outputHeight = height
        d.colorProcessingMode = .perceptual
        guard let scaler = d.makeSpatialScaler(device: device) else { return nil }
        let od = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height,
                                                          mipmapped: false)
        od.usage = scaler.outputTextureUsage.union(.shaderRead)
        od.storageMode = .private
        guard let output = device.makeTexture(descriptor: od) else { return nil }
        output.label = "MetalFXOutput"
        self.scaler = scaler
        self.output = output
        self.inputUsage = scaler.colorTextureUsage
    }

    func encode(_ cmd: MTLCommandBuffer, input: MTLTexture, contentWidth: Int, contentHeight: Int) {
        scaler.colorTexture = input
        scaler.outputTexture = output
        scaler.inputContentWidth = contentWidth
        scaler.inputContentHeight = contentHeight
        scaler.encode(commandBuffer: cmd)
    }
}
#else
/// MetalFX isn't available (e.g. iOS Simulator SDK): the final blit does a bilinear upscale instead.
@MainActor
final class Upscaler {
    let output: MTLTexture
    let inputUsage: MTLTextureUsage = []

    init?(device: MTLDevice, width: Int, height: Int) { return nil }

    func encode(_ cmd: MTLCommandBuffer, input: MTLTexture, contentWidth: Int, contentHeight: Int) {}
}
#endif
#endif
