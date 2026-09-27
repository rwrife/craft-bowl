import CBAssets
import CBCore
import simd

/// Broadcast-style camera in world space (x right, y up, z = -downfield).
public struct Camera: Sendable {
    public var eye: SIMD3<Float>
    public var target: SIMD3<Float>
    public var fovY: Float
    public var near: Float = 0.5
    public var far: Float = 400

    public init(eye: SIMD3<Float>, target: SIMD3<Float>, fovY: Float = 0.62) {
        self.eye = eye
        self.target = target
        self.fovY = fovY
    }

    /// Camera presets. `reference` matches the concept art: high behind the offense, looking downfield.
    public enum Preset: String, CaseIterable, Sendable {
        case reference, broadcast, low, overhead, sideline

        /// Offset of the eye from the focus point, in field space (x across, y downfield) plus height.
        public var offset: (across: Float, back: Float, height: Float, fov: Float, lookAhead: Float) {
            switch self {
            case .reference: (0, 17, 11.5, 0.78, 9)
            case .broadcast: (0, 24, 16, 0.6, 7)
            case .low: (0, 9, 3.2, 0.9, 10)
            case .overhead: (0, 6, 42, 0.8, 4)
            case .sideline: (-42, 0, 14, 0.62, 0)
            }
        }
    }
}

public struct PlayerDraw: Sendable {
    public var position: SIMD3<Float>
    /// World-space yaw; 0 faces -Z (downfield).
    public var yaw: Float
    public var team: UInt8
    public var pose: PlayerPose
    public var phase: Float
    public var speed01: Float
    public var controlled: Bool
    public var turbo: Bool
    public var skinTone: UInt8
    public var number: UInt8
    public var scale: SIMD3<Float>

    public init(position: SIMD3<Float>, yaw: Float, team: UInt8, pose: PlayerPose, phase: Float = 0,
                speed01: Float = 0, controlled: Bool = false, turbo: Bool = false, skinTone: UInt8 = 4,
                number: UInt8 = 0, scale: SIMD3<Float> = SIMD3(1, 1, 1)) {
        self.position = position
        self.yaw = yaw
        self.team = team
        self.pose = pose
        self.phase = phase
        self.speed01 = speed01
        self.controlled = controlled
        self.turbo = turbo
        self.skinTone = skinTone
        self.number = number
        self.scale = scale
    }
}

public struct DebugLine: Sendable {
    public var a: SIMD3<Float>
    public var b: SIMD3<Float>
    public var color: SIMD4<Float>
    public init(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ color: SIMD4<Float>) {
        self.a = a
        self.b = b
        self.color = color
    }
}

/// Everything the renderer needs for one frame. Filled by the game each frame (no allocation once warmed).
public struct RenderFrame: Sendable {
    public var camera = Camera(eye: SIMD3(0, 12, -18), target: SIMD3(0, 0, -44))
    public var players: [PlayerDraw] = []
    public var ballVisible = false
    public var ballPosition = SIMD3<Float>()
    public var ballYaw: Float = 0
    public var ballPitch: Float = 0
    public var lineOfScrimmage: Float = 35
    public var firstDownLine: Float = 45
    public var showLines = true
    public var crowdExcitement: Float = 0.2
    public var home = TeamUniform.blue
    public var away = TeamUniform.red
    /// Always drawn (gameplay markers: controlled-player ring, pass target cones).
    public var markers: [DebugLine] = []
    /// Drawn only when `RenderSettings.debugDraw` is on.
    public var debugLines: [DebugLine] = []

    public init() {}
}

public struct RenderSettings: Sendable {
    public var shadows = true
    public var bloom = true
    public var colorGrade = true
    public var metalFX = true
    public var pixelNoise = true
    public var crowd = true
    public var glows = true
    public var gpuCulling = true
    public var debugDraw = false
    public var dynamicResolution = true
    /// Used when dynamic resolution is off.
    public var fixedScale: Float = 0.85
    public var exposure: Float = 1.0
    public var vignette: Float = 0.35
    public var chromaticAberration: Float = 0
    /// Crowd LOD cutoff in yards (0 = unlimited).
    public var crowdDistance: Float = 150
    public var targetFrameMs: Float = 1000 / 60

    public init() {}
}

public struct RenderStats: Sendable {
    public var cpuFrameMs: Float = 0
    public var gpuCullShadowMs: Float = 0
    public var gpuSceneMs: Float = 0
    public var gpuPostMs: Float = 0
    public var gpuTotalMs: Float { gpuCullShadowMs + gpuSceneMs + gpuPostMs }
    public var renderScale: Float = 1
    public var renderSize = SIMD2<Int>()
    public var drawableSize = SIMD2<Int>()
    public var crowdTotal = 0
    public var crowdVisible = 0
    public var playersVisible = 0
    public var drawCalls = 0
    public var metalFXActive = false
    public var residencySetActive = false
    public init() {}
}

/// Provides the frame contents. Called on the main thread once per display frame, before encoding.
@MainActor
public protocol RenderFrameSource: AnyObject {
    func update(deltaTime: Double, frame: inout RenderFrame)
}
