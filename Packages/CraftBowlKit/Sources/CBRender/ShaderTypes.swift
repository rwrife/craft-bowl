import simd

// Swift mirrors of App/Shaders/ShaderTypes.h. Keep field order and sizes identical.

enum Material: Float {
    case plain = 0, skin, primary, secondary, helmet, pants, trim, emissive, turf, crowd, stripe, facemask
}

enum InstanceFlags {
    static let crowd: UInt32 = 1
    static let controlled: UInt32 = 2
    static let turbo: UInt32 = 4
}

enum FrameFlags {
    static let shadows: UInt32 = 1
    static let pixelNoise: UInt32 = 2
    static let fieldLines: UInt32 = 4
}

let noBones: UInt32 = 0xFFFF_FFFF

struct GPUVertex {
    var position: SIMD4<Float>
    var normal: SIMD4<Float>
    var color: SIMD4<Float>
}

struct GPUInstance {
    var model: simd_float4x4
    var tint: SIMD4<Float>
    var params: SIMD4<UInt32>
    var bounds: SIMD4<Float>
}

struct FrameUniforms {
    var viewProj = matrix_identity_float4x4
    var invViewProj = matrix_identity_float4x4
    var lightViewProj = matrix_identity_float4x4
    var cameraPos = SIMD4<Float>()
    var cameraRight = SIMD4<Float>()
    var cameraUp = SIMD4<Float>()
    var lightDir = SIMD4<Float>()
    var lightColor = SIMD4<Float>()
    var skyTop = SIMD4<Float>()
    var skyHorizon = SIMD4<Float>()
    var ambient = SIMD4<Float>()
    var groundAmbient = SIMD4<Float>()
    var params = SIMD4<Float>()
    var field = SIMD4<Float>()
    var viewport = SIMD4<Float>()
}

struct GPUPointLight {
    var positionRadius: SIMD4<Float>
    var colorIntensity: SIMD4<Float>
}

struct GPUTeamColors {
    var primary, secondary, trim, helmet, stripe, pants, numberFill, numberOutline: SIMD4<Float>
}

struct DrawParams {
    var visibleOffset: UInt32 = 0
    var useVisible: UInt32 = 0
    var instanceBase: UInt32 = 0
    var pad: UInt32 = 0
}

struct CullUniforms {
    var p0, p1, p2, p3, p4, p5: SIMD4<Float>
    var lod: SIMD4<Float>
    var instanceCount: UInt32
    var visibleOffset: UInt32
    var argsIndex: UInt32
    var enabled: UInt32
}

struct GPUGlow {
    var positionSize: SIMD4<Float>
    var color: SIMD4<Float>
}

struct GPUDebugVertex {
    var position: SIMD4<Float>
    var color: SIMD4<Float>
}

struct PostUniforms {
    var source = SIMD4<Float>()
    var bloom = SIMD4<Float>()
    var grade = SIMD4<Float>()
    var misc = SIMD4<Float>()
}

/// Mirrors MTLDrawIndexedPrimitivesIndirectArguments (20 bytes).
struct IndexedIndirectArgs {
    var indexCount: UInt32
    var instanceCount: UInt32
    var indexStart: UInt32
    var baseVertex: Int32
    var baseInstance: UInt32
}
