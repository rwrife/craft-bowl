import CBAnimation
import CBCore
import simd

/// CPU-side mesh assembly out of cuboids — the whole game is blocks (docs/PLAN.md §4).
/// Placeholder for the Blockbench/glTF `cbasset` pipeline (issue #16); same vertex layout.
struct MeshBuilder {
    var vertices: [GPUVertex] = []
    var indices: [UInt32] = []

    /// Adds an axis-aligned box. `groundAO` darkens the lower edge of side faces (contact shadow feel).
    mutating func box(_ lo: SIMD3<Float>, _ hi: SIMD3<Float>, color: SIMD3<Float> = SIMD3(1, 1, 1),
                      material: Material, bone: Bone? = nil, groundAO: Float = 1, skip: Set<Int> = []) {
        let (lo, hi) = (simd_min(lo, hi), simd_max(lo, hi))
        let c = (lo + hi) * 0.5
        let h = (hi - lo) * 0.5
        let faces: [(n: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>, ao: Float)] = [
            (SIMD3(1, 0, 0), SIMD3(0, 0, -1), SIMD3(0, 1, 0), 0.86),
            (SIMD3(-1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 1, 0), 0.86),
            (SIMD3(0, 1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, -1), 1.0),
            (SIMD3(0, -1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1), 0.6),
            (SIMD3(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0, 1, 0), 0.9),
            (SIMD3(0, 0, -1), SIMD3(-1, 0, 0), SIMD3(0, 1, 0), 0.9),
        ]
        let boneIndex = Float(bone?.rawValue ?? 0)
        for (i, f) in faces.enumerated() where !skip.contains(i) {
            let fc = c + f.n * abs(simd_dot(h, f.n))
            let du = f.u * abs(simd_dot(h, f.u))
            let dv = f.v * abs(simd_dot(h, f.v))
            let base = UInt32(vertices.count)
            for corner in [(-1, -1), (1, -1), (1, 1), (-1, 1)] as [(Float, Float)] {
                let p = fc + du * corner.0 + dv * corner.1
                var ao = f.ao
                if f.n.y == 0 && corner.1 < 0 { ao *= groundAO }
                vertices.append(GPUVertex(position: SIMD4(p, boneIndex), normal: SIMD4(f.n, ao),
                                          color: SIMD4(color, material.rawValue)))
            }
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
    }

    /// Mirrors a box across x = 0 onto the matching bone on the other side.
    mutating func mirroredBox(_ lo: SIMD3<Float>, _ hi: SIMD3<Float>, color: SIMD3<Float> = SIMD3(1, 1, 1),
                              material: Material, left: Bone, right: Bone, groundAO: Float = 1) {
        box(lo, hi, color: color, material: material, bone: left, groundAO: groundAO)
        box(SIMD3(-hi.x, lo.y, lo.z), SIMD3(-lo.x, hi.y, hi.z), color: color, material: material, bone: right,
            groundAO: groundAO)
    }

    var boundingSphere: SIMD4<Float> {
        guard let first = vertices.first else { return .zero }
        var lo = SIMD3(first.position.x, first.position.y, first.position.z), hi = lo
        for v in vertices {
            let p = SIMD3(v.position.x, v.position.y, v.position.z)
            lo = simd_min(lo, p); hi = simd_max(hi, p)
        }
        let c = (lo + hi) * 0.5
        return SIMD4(c, simd_length(hi - c))
    }
}

enum Meshes {
    /// Bone pivots in model space (feet at y = 0, facing -Z, player's left = -X).
    enum Pivot {
        static let pelvis = SIMD3<Float>(0, 0.98, 0)
        static let chest = SIMD3<Float>(0, 1.08, 0)
        static let head = SIMD3<Float>(0, 1.7, 0)
        static let shoulderL = SIMD3<Float>(-0.47, 1.56, 0)
        static let elbowL = SIMD3<Float>(-0.47, 1.23, 0)
        static let hipL = SIMD3<Float>(-0.165, 0.95, 0)
        static let kneeL = SIMD3<Float>(-0.165, 0.51, 0)
        static func mirrored(_ p: SIMD3<Float>) -> SIMD3<Float> { SIMD3(-p.x, p.y, p.z) }
    }

    /// The single player model. Colors come from the team palette via material IDs.
    static func player() -> MeshBuilder {
        var m = MeshBuilder()
        let black = SIMD3<Float>(0.03, 0.03, 0.035)
        let white = SIMD3<Float>(0.85, 0.85, 0.85)
        // legs
        m.mirroredBox(SIMD3(-0.31, 0, -0.25), SIMD3(-0.03, 0.13, 0.13), color: black, material: .plain,
                      left: .shinL, right: .shinR, groundAO: 0.7)
        m.mirroredBox(SIMD3(-0.28, 0.13, -0.12), SIMD3(-0.05, 0.53, 0.12), material: .secondary, left: .shinL, right: .shinR)
        m.mirroredBox(SIMD3(-0.285, 0.44, -0.125), SIMD3(-0.045, 0.5, 0.125), color: white, material: .plain,
                      left: .shinL, right: .shinR)
        m.mirroredBox(SIMD3(-0.3, 0.5, -0.145), SIMD3(-0.03, 0.96, 0.145), material: .pants, left: .thighL, right: .thighR)
        // hips + belt
        m.box(SIMD3(-0.33, 0.88, -0.19), SIMD3(0.33, 1.08, 0.19), material: .pants, bone: .pelvis)
        m.box(SIMD3(-0.34, 1.03, -0.2), SIMD3(0.34, 1.1, 0.2), material: .trim, bone: .pelvis)
        // torso + shoulder pads
        m.box(SIMD3(-0.36, 1.08, -0.22), SIMD3(0.36, 1.5, 0.22), material: .primary, bone: .chest)
        m.box(SIMD3(-0.5, 1.46, -0.27), SIMD3(0.5, 1.7, 0.27), material: .primary, bone: .chest)
        m.box(SIMD3(-0.51, 1.54, -0.275), SIMD3(-0.34, 1.6, 0.275), material: .secondary, bone: .chest)
        m.box(SIMD3(0.34, 1.54, -0.275), SIMD3(0.51, 1.6, 0.275), material: .secondary, bone: .chest)
        m.box(SIMD3(-0.37, 1.24, -0.225), SIMD3(0.37, 1.3, 0.225), material: .secondary, bone: .chest)
        // head: neck, helmet, stripe, face, facemask
        m.box(SIMD3(-0.1, 1.66, -0.1), SIMD3(0.1, 1.76, 0.1), material: .skin, bone: .head)
        m.box(SIMD3(-0.24, 1.73, -0.25), SIMD3(0.24, 2.18, 0.24), material: .helmet, bone: .head)
        m.box(SIMD3(-0.05, 2.18, -0.26), SIMD3(0.05, 2.21, 0.25), material: .stripe, bone: .head)
        m.box(SIMD3(-0.17, 1.78, -0.27), SIMD3(0.17, 2.02, -0.25), material: .skin, bone: .head)
        m.box(SIMD3(-0.03, 1.94, -0.28), SIMD3(0.03, 1.97, -0.27), color: black, material: .plain, bone: .head)
        m.box(SIMD3(-0.19, 1.76, -0.34), SIMD3(0.19, 1.81, -0.27), material: .facemask, bone: .head)
        m.box(SIMD3(-0.19, 1.87, -0.34), SIMD3(0.19, 1.9, -0.27), material: .facemask, bone: .head)
        m.box(SIMD3(-0.025, 1.76, -0.34), SIMD3(0.025, 1.9, -0.27), material: .facemask, bone: .head)
        // arms
        m.mirroredBox(SIMD3(-0.58, 1.22, -0.12), SIMD3(-0.37, 1.6, 0.12), material: .primary,
                      left: .upperArmL, right: .upperArmR)
        m.mirroredBox(SIMD3(-0.57, 0.95, -0.1), SIMD3(-0.38, 1.24, 0.1), material: .skin, left: .foreArmL, right: .foreArmR)
        m.mirroredBox(SIMD3(-0.575, 0.95, -0.105), SIMD3(-0.375, 1.01, 0.105), color: white, material: .plain,
                      left: .foreArmL, right: .foreArmR)
        m.mirroredBox(SIMD3(-0.58, 0.8, -0.11), SIMD3(-0.37, 0.96, 0.11), material: .skin, left: .handL, right: .handR)
        return m
    }

    /// Seated voxel fan: shirt block + head. Instanced thousands of times.
    static func crowdPerson() -> MeshBuilder {
        var m = MeshBuilder()
        m.box(SIMD3(-0.2, 0, -0.14), SIMD3(0.2, 0.5, 0.14), material: .crowd, groundAO: 0.55, skip: [3])
        m.box(SIMD3(-0.24, 0.3, -0.1), SIMD3(-0.18, 0.62, 0.06), material: .crowd, skip: [3])
        m.box(SIMD3(0.18, 0.3, -0.1), SIMD3(0.24, 0.62, 0.06), material: .crowd, skip: [3])
        m.box(SIMD3(-0.13, 0.5, -0.12), SIMD3(0.13, 0.78, 0.12), material: .skin, skip: [3])
        return m
    }

    static func ball() -> MeshBuilder {
        var m = MeshBuilder()
        let brown = SIMD3<Float>(0.36, 0.16, 0.06)
        m.box(SIMD3(-0.09, -0.09, -0.15), SIMD3(0.09, 0.09, 0.15), color: brown, material: .plain)
        m.box(SIMD3(-0.055, -0.055, -0.2), SIMD3(0.055, 0.055, 0.2), color: brown, material: .plain)
        m.box(SIMD3(-0.02, 0.09, -0.07), SIMD3(0.02, 0.105, 0.07), color: SIMD3(0.95, 0.95, 0.95), material: .plain)
        return m
    }

    struct Stadium {
        var mesh: MeshBuilder
        /// Crowd seat transforms: world position, yaw, side (-1 left stand, 1 right stand, 0 far stand).
        var seats: [(position: SIMD3<Float>, yaw: Float, side: Int)]
        var floodlights: [SIMD3<Float>]
        var lamps: [SIMD3<Float>]
    }

    /// Field, bleachers, sideline wall + ad boards, floodlight towers and goalposts (world space).
    static func stadium() -> Stadium {
        var m = MeshBuilder()
        var seats: [(SIMD3<Float>, Float, Int)] = []
        var floodlights: [SIMD3<Float>] = []
        var lamps: [SIMD3<Float>] = []

        // Turf covers everything inside the stands.
        m.box(SIMD3(-60, -0.1, -150), SIMD3(60, 0, 25), material: .turf, skip: [0, 1, 3, 4, 5])

        let concrete = SIMD3<Float>(0.24, 0.25, 0.3)
        let rows = 18
        let rowDepth: Float = 0.9, rowRise: Float = 0.55, standStart: Float = 30.5
        let seatSpacing: Float = 0.55
        // side stands (along the field, z = -(-4)...-(124))
        for side in [-1, 1] as [Float] {
            for r in 0..<rows {
                let x0 = standStart + Float(r) * rowDepth, x1 = x0 + rowDepth
                let top = 0.9 + Float(r) * rowRise
                let shade: Float = r % 2 == 0 ? 1 : 0.86
                let lo = side > 0 ? SIMD3(x0, 0, -124) : SIMD3(-x1, 0, -124)
                let hi = side > 0 ? SIMD3(x1, top, 4) : SIMD3(-x0, top, 4)
                m.box(lo, hi, color: concrete * shade, material: .plain, groundAO: 0.7)
                var z: Float = 3
                while z > -123 {
                    let x = side * (x0 + rowDepth * 0.45)
                    seats.append((SIMD3(x, top, z), side > 0 ? .pi / 2 : -.pi / 2, Int(side)))
                    z -= seatSpacing
                }
            }
            // sideline wall + ad boards
            let wx0: Float = 28.6, wx1: Float = 29.3
            let wlo = side > 0 ? SIMD3(wx0, 0, -124) : SIMD3(-wx1, 0, -124)
            let whi = side > 0 ? SIMD3(wx1, 1.2, 4) : SIMD3(-wx0, 1.2, 4)
            m.box(wlo, whi, color: SIMD3(0.08, 0.09, 0.14), material: .plain, groundAO: 0.6)
            let adColors: [SIMD3<Float>] = [SIMD3(0.9, 0.62, 0.1), SIMD3(0.12, 0.3, 0.8), SIMD3(0.75, 0.12, 0.12),
                                            SIMD3(0.85, 0.85, 0.85), SIMD3(0.1, 0.55, 0.3)]
            for i in 0..<16 {
                let z1 = -Float(i) * 8 + 2, z0 = z1 - 7.2
                let ax = side > 0 ? wx0 - 0.02 : -wx0 + 0.02
                let lo = SIMD3(side > 0 ? ax - 0.02 : ax, 0.25, z0)
                let hi = SIMD3(side > 0 ? ax : ax + 0.02, 1.0, z1)
                m.box(lo, hi, color: adColors[i % adColors.count] * 0.25, material: .emissive)
            }
            // floodlight towers behind the stands
            for fz in [-8, -60, -112] as [Float] {
                let x = side * 50
                m.box(SIMD3(x - 0.5, 0, fz - 0.5), SIMD3(x + 0.5, 34, fz + 0.5), color: SIMD3(0.18, 0.19, 0.22),
                      material: .plain)
                let head = SIMD3<Float>(x - side * 0.6, 35.5, fz)
                m.box(SIMD3(head.x - 0.5, head.y - 2.2, fz - 4.2), SIMD3(head.x + 0.5, head.y + 2.2, fz + 4.2),
                      color: SIMD3(0.12, 0.12, 0.14), material: .plain)
                for ly in 0..<3 {
                    for lz in 0..<5 {
                        let p = SIMD3(head.x - side * 0.55, head.y - 1.4 + Float(ly) * 1.4, fz - 3.2 + Float(lz) * 1.6)
                        m.box(p - SIMD3(0.12, 0.5, 0.6), p + SIMD3(0.12, 0.5, 0.6), color: SIMD3(1, 0.95, 0.82),
                              material: .emissive)
                        lamps.append(p - SIMD3(side * 0.2, 0, 0))
                    }
                }
                floodlights.append(head - SIMD3(side * 3, 1, 0))
            }
        }
        // far end-zone stand (behind z = -122)
        for r in 0..<14 {
            let z0 = -125 - Float(r) * rowDepth, z1 = z0 - rowDepth
            let top = 0.9 + Float(r) * rowRise
            m.box(SIMD3(-30, 0, z1), SIMD3(30, top, z0), color: concrete * (r % 2 == 0 ? 1 : 0.86), material: .plain,
                  groundAO: 0.7)
            var x: Float = -29.4
            while x < 29.4 {
                seats.append((SIMD3(x, top, z0 - rowDepth * 0.45), .pi, 0))
                x += seatSpacing
            }
        }
        m.box(SIMD3(-30, 0, -124.4), SIMD3(30, 1.2, -123.7), color: SIMD3(0.08, 0.09, 0.14), material: .plain)

        // goalposts on both end lines
        let yellow = SIMD3<Float>(1, 0.78, 0.08)
        for (z, dir) in [(-121.0, Float(-1)), (1.0, Float(1))] as [(Float, Float)] {
            m.box(SIMD3(-0.18, 0, z - 0.18), SIMD3(0.18, 3.0, z + 0.18), color: yellow, material: .plain, groundAO: 0.7)
            m.box(SIMD3(-0.12, 2.9, z), SIMD3(0.12, 3.1, z - dir), color: yellow, material: .plain)
            let cz = z - dir * 1.0
            m.box(SIMD3(-3.1, 3.0, cz - 0.1), SIMD3(3.1, 3.2, cz + 0.1), color: yellow, material: .plain)
            for x in [-3.08, 3.08] as [Float] {
                m.box(SIMD3(x - 0.08, 3.0, cz - 0.08), SIMD3(x + 0.08, 10.0, cz + 0.08), color: yellow, material: .plain)
            }
        }
        return Stadium(mesh: m, seats: seats, floodlights: floodlights, lamps: lamps)
    }
}
