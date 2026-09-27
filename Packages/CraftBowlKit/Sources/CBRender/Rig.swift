import CBAnimation
import simd

/// High-level pose for a player this frame. The procedural rig turns it into rigid bone matrices.
/// Stand-in for the clip/blend-tree animation system (issue #17).
public enum PlayerPose: UInt8, Sendable {
    case stance, threePoint, idle, run, dive, down, celebrate
}

enum Rig {
    static let boneCount = Bone.allCases.count

    /// Writes `boneCount` model-space matrices into `out` starting at `offset`.
    static func pose(_ pose: PlayerPose, phase: Float, speed01 amt: Float, turbo: Bool,
                     into out: UnsafeMutablePointer<simd_float4x4>) {
        typealias M = RenderMath
        typealias P = Meshes.Pivot
        var bodyPitch: Float = 0, drop: Float = 0, lean: Float = 0
        var legL: Float = 0, legR: Float = 0, kneeL: Float = 0, kneeR: Float = 0
        var armL: Float = 0, armR: Float = 0, elbowL: Float = 0.2, elbowR: Float = 0.2, armOut: Float = 0.08
        var headPitch: Float = 0

        switch pose {
        case .idle:
            let breathe = sinf(phase * 0.5) * 0.02
            lean = -0.05 + breathe
            armL = 0.1; armR = 0.1
        case .stance:
            drop = 0.2; lean = -0.55; headPitch = 0.45
            legL = 0.75; legR = 0.55; kneeL = 1.1; kneeR = 0.9
            armL = 0.55; armR = 0.55; elbowL = 0.6; elbowR = 0.6
        case .threePoint:
            drop = 0.38; lean = -1.05; headPitch = 0.9
            legL = 1.1; legR = 0.8; kneeL = 1.7; kneeR = 1.3
            armL = 0.3; armR = 1.25; elbowL = 0.4; elbowR = 0.1
        case .run:
            let s = sinf(phase), c = cosf(phase)
            legL = s * 0.9 * amt; legR = -s * 0.9 * amt
            kneeL = amt * (0.25 + 1.1 * max(0, -sinf(phase - 0.7)))
            kneeR = amt * (0.25 + 1.1 * max(0, sinf(phase - 0.7)))
            armL = -s * 0.85 * amt; armR = s * 0.85 * amt
            elbowL = 0.4 + 0.9 * amt; elbowR = elbowL
            lean = -(0.08 + 0.3 * amt + (turbo ? 0.18 : 0))
            headPitch = -lean * 0.6
            drop = -abs(c) * 0.07 * amt
        case .dive:
            bodyPitch = -1.25; drop = 0.45
            armL = 2.9; armR = 2.9; elbowL = 0; elbowR = 0
            legL = -0.3; legR = -0.1; kneeL = 0.3; kneeR = 0.5
            headPitch = 0.9
        case .down:
            bodyPitch = -1.52; drop = 0.72
            armL = 2.4; armR = 1.2; elbowL = 0.4; elbowR = 0.9; armOut = 0.5
            legL = 0.1; legR = -0.2; kneeL = 0.3; kneeR = 0.6
            headPitch = 1.2
        case .celebrate:
            let bounce = abs(sinf(phase * 1.6))
            drop = -bounce * 0.25
            armL = 2.9 + sinf(phase * 3) * 0.15; armR = 2.9 - sinf(phase * 3) * 0.15; armOut = 0.35
            elbowL = 0.1; elbowR = 0.1
            kneeL = 0.3 * (1 - bounce); kneeR = kneeL; legL = kneeL * 0.5; legR = legL
        }

        let root = M.translation(SIMD3(0, -drop, 0)) * M.about(P.pelvis, M.rotationX(bodyPitch))
        let chest = root * M.about(P.chest, M.rotationX(lean))
        let head = chest * M.about(P.head, M.rotationX(headPitch))
        let shoulderR = P.mirrored(P.shoulderL), elbowPR = P.mirrored(P.elbowL)
        let upperL = chest * M.about(P.shoulderL, M.rotationX(armL) * M.rotationZ(-armOut))
        let upperR = chest * M.about(shoulderR, M.rotationX(armR) * M.rotationZ(armOut))
        let foreL = upperL * M.about(P.elbowL, M.rotationX(elbowL))
        let foreR = upperR * M.about(elbowPR, M.rotationX(elbowR))
        let thighL = root * M.about(P.hipL, M.rotationX(legL))
        let thighR = root * M.about(P.mirrored(P.hipL), M.rotationX(legR))
        let shinL = thighL * M.about(P.kneeL, M.rotationX(-kneeL))
        let shinR = thighR * M.about(P.mirrored(P.kneeL), M.rotationX(-kneeR))

        out[Bone.pelvis.rawValue] = root
        out[Bone.spine.rawValue] = root
        out[Bone.chest.rawValue] = chest
        out[Bone.head.rawValue] = head
        out[Bone.upperArmL.rawValue] = upperL
        out[Bone.foreArmL.rawValue] = foreL
        out[Bone.handL.rawValue] = foreL
        out[Bone.upperArmR.rawValue] = upperR
        out[Bone.foreArmR.rawValue] = foreR
        out[Bone.handR.rawValue] = foreR
        out[Bone.thighL.rawValue] = thighL
        out[Bone.shinL.rawValue] = shinL
        out[Bone.thighR.rawValue] = thighR
        out[Bone.shinR.rawValue] = shinR
    }
}
