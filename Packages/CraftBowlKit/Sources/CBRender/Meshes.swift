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
        m.box(SIMD3(-72, -0.1, -160), SIMD3(72, 0, 25), material: .turf, skip: [0, 1, 3, 4, 5])

        let concrete = SIMD3<Float>(0.15, 0.16, 0.2)
        let fascia = SIMD3<Float>(0.05, 0.06, 0.09)
        let rowDepth: Float = 0.9, standStart: Float = 30.5
        // Two-tier bowl: steep upper decks behind the lower bowl so the crowd towers over the field.
        let lowerRows = 18, lowerRise: Float = 0.55
        let upperRows = 22, upperRise: Float = 0.8
        let lowerOuter = standStart + Float(lowerRows) * rowDepth            // 46.7
        let lowerTop = 0.9 + Float(lowerRows - 1) * lowerRise                  // 10.25
        let upperStart = lowerOuter + 0.6, upperBase = lowerTop + 2.1
        let upperOuter = upperStart + Float(upperRows) * rowDepth             // 67.1
        let upperTop = upperBase + 0.9 + Float(upperRows - 1) * upperRise
        let farStart: Float = 125, farLowerRows = 16
        let farLowerOuter = farStart + Float(farLowerRows) * rowDepth
        let farLowerTop = 0.9 + Float(farLowerRows - 1) * lowerRise
        let farUpperStart = farLowerOuter + 0.6, farUpperBase = farLowerTop + 2.1
        let farUpperRows = 18
        let farUpperOuter = farUpperStart + Float(farUpperRows) * rowDepth
        let ribbon: [SIMD3<Float>] = [SIMD3(0.1, 0.25, 0.8), SIMD3(0.9, 0.62, 0.1), SIMD3(0.75, 0.1, 0.1)]

        /// A bank of stadium lights facing the field; `inward` is the unit axis pointing at the field.
        func lightBank(_ c: SIMD3<Float>, inward: SIMD3<Float>) {
            let across = SIMD3<Float>(abs(inward.z), 0, abs(inward.x))
            let thick = SIMD3<Float>(abs(inward.x), 0, abs(inward.z))
            m.box(c - SIMD3(0, c.y - 1, 0) - thick * 0.4 - across * 0.4, c - SIMD3(0, 2.2, 0) + thick * 0.4 + across * 0.4,
                  color: SIMD3(0.1, 0.1, 0.12), material: .plain)
            m.box(c - across * 4.4 - SIMD3(0, 2.3, 0) - thick * 0.5, c + across * 4.4 + SIMD3(0, 2.3, 0) + thick * 0.5,
                  color: SIMD3(0.08, 0.08, 0.1), material: .plain)
            for ly in 0..<2 {
                for lx in 0..<5 {
                    let p = c + inward * 0.55 + across * (Float(lx) - 2) * 1.7 + SIMD3(0, Float(ly) * 2 - 1, 0)
                    m.box(p - across * 0.7 - SIMD3(0, 0.75, 0) - thick * 0.1,
                          p + across * 0.7 + SIMD3(0, 0.75, 0) + thick * 0.1,
                          color: SIMD3(1, 0.96, 0.86), material: .emissive)
                    lamps.append(p + inward * 0.25)
                }
            }
            floodlights.append(c + inward * 3 - SIMD3(0, 1, 0))
        }

        for side in [-1, 1] as [Float] {
            func xs(_ a: Float, _ b: Float) -> (Float, Float) { side > 0 ? (a, b) : (-b, -a) }
            // lower bowl
            for r in 0..<lowerRows {
                let x0 = standStart + Float(r) * rowDepth
                let top = 0.9 + Float(r) * lowerRise
                let (lx, hx) = xs(x0, x0 + rowDepth)
                m.box(SIMD3(lx, 0, -124), SIMD3(hx, top, 4), color: concrete * (r % 2 == 0 ? 1 : 0.86),
                      material: .plain, groundAO: 0.7)
                var z: Float = 3
                while z > -123 {
                    seats.append((SIMD3(side * (x0 + rowDepth * 0.45), top, z), side > 0 ? .pi / 2 : -.pi / 2, Int(side)))
                    z -= 0.55
                }
            }
            // club-level fascia with an LED ribbon board between the tiers
            let (fx0, fx1) = xs(lowerOuter, upperStart)
            m.box(SIMD3(fx0, 0, -140), SIMD3(fx1, upperBase, 4), color: fascia, material: .plain)
            for i in 0..<18 {
                let z1 = -Float(i) * 8 + 4, z0 = z1 - 7.6
                let ax = side * (lowerOuter - 0.03)
                m.box(SIMD3(min(ax, ax + side * 0.02), lowerTop + 0.9, z0), SIMD3(max(ax, ax + side * 0.02), upperBase - 0.35, z1),
                      color: ribbon[i % ribbon.count] * 0.22, material: .emissive)
            }
            // upper deck (runs past the far corner to meet the far upper deck)
            for r in 0..<upperRows {
                let x0 = upperStart + Float(r) * rowDepth
                let top = upperBase + 0.9 + Float(r) * upperRise
                let (lx, hx) = xs(x0, x0 + rowDepth)
                m.box(SIMD3(lx, upperBase - 1, -farUpperStart), SIMD3(hx, top, 4),
                      color: concrete * (r % 2 == 0 ? 0.9 : 0.78), material: .plain)
                var z: Float = 3
                while z > -farUpperStart + 0.5 {
                    seats.append((SIMD3(side * (x0 + rowDepth * 0.45), top, z), side > 0 ? .pi / 2 : -.pi / 2, Int(side)))
                    z -= 0.62
                }
            }
            let (bx0, bx1) = xs(upperOuter, upperOuter + 1)
            m.box(SIMD3(bx0, 0, -farUpperOuter - 1), SIMD3(bx1, upperTop + 2.5, 4), color: fascia, material: .plain)

            // sideline wall + ad boards
            let wx0: Float = 28.6, wx1: Float = 29.3
            let (wl, wh) = xs(wx0, wx1)
            m.box(SIMD3(wl, 0, -124), SIMD3(wh, 1.2, 4), color: SIMD3(0.08, 0.09, 0.14), material: .plain, groundAO: 0.6)
            let adColors: [SIMD3<Float>] = [SIMD3(0.9, 0.62, 0.1), SIMD3(0.12, 0.3, 0.8), SIMD3(0.75, 0.12, 0.12),
                                            SIMD3(0.85, 0.85, 0.85), SIMD3(0.1, 0.55, 0.3)]
            for i in 0..<16 {
                let z1 = -Float(i) * 8 + 2, z0 = z1 - 7.2
                let ax = side > 0 ? wx0 - 0.02 : -wx0 + 0.02
                let lo = SIMD3(side > 0 ? ax - 0.02 : ax, 0.25, z0)
                let hi = SIMD3(side > 0 ? ax : ax + 0.02, 1.0, z1)
                m.box(lo, hi, color: adColors[i % adColors.count] * 0.25, material: .emissive)
            }
            // light banks along the rim of the upper deck
            for fz in [2, -28, -60, -92, -124] as [Float] {
                lightBank(SIMD3(side * (upperOuter + 0.5), upperTop + 6.5, fz), inward: SIMD3(-side, 0, 0))
            }
        }

        // far end-zone bowl (behind z = -122)
        for r in 0..<farLowerRows {
            let z0 = -farStart - Float(r) * rowDepth, z1 = z0 - rowDepth
            let top = 0.9 + Float(r) * lowerRise
            m.box(SIMD3(-lowerOuter, 0, z1), SIMD3(lowerOuter, top, z0), color: concrete * (r % 2 == 0 ? 1 : 0.86),
                  material: .plain, groundAO: 0.7)
            var x: Float = -lowerOuter + 0.4
            while x < lowerOuter - 0.4 {
                seats.append((SIMD3(x, top, z0 - rowDepth * 0.45), .pi, 0))
                x += 0.55
            }
        }
        m.box(SIMD3(-upperStart, 0, -farUpperStart), SIMD3(upperStart, farUpperBase, -farLowerOuter), color: fascia,
              material: .plain)
        for i in 0..<12 {
            let x0 = -46 + Float(i) * 7.7
            m.box(SIMD3(x0, farLowerTop + 0.9, -farLowerOuter + 0.01), SIMD3(x0 + 7.3, farUpperBase - 0.35, -farLowerOuter + 0.03),
                  color: ribbon[i % ribbon.count] * 0.22, material: .emissive)
        }
        for r in 0..<farUpperRows {
            let z0 = -farUpperStart - Float(r) * rowDepth, z1 = z0 - rowDepth
            let top = farUpperBase + 0.9 + Float(r) * upperRise
            m.box(SIMD3(-upperOuter, farUpperBase - 1, z1), SIMD3(upperOuter, top, z0),
                  color: concrete * (r % 2 == 0 ? 0.9 : 0.78), material: .plain)
            var x: Float = -upperOuter + 0.4
            while x < upperOuter - 0.4 {
                seats.append((SIMD3(x, top, z0 - rowDepth * 0.45), .pi, 0))
                x += 0.62
            }
        }
        let farTop = farUpperBase + 0.9 + Float(farUpperRows - 1) * upperRise
        m.box(SIMD3(-upperOuter - 1, 0, -farUpperOuter - 1), SIMD3(upperOuter + 1, farTop + 2.5, -farUpperOuter),
              color: fascia, material: .plain)
        for fx in [-40, 0, 40] as [Float] {
            lightBank(SIMD3(fx, farTop + 6.5, -farUpperOuter - 0.5), inward: SIMD3(0, 0, 1))
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
