import CBCore
import simd

/// Right-handed matrix helpers with Metal's 0...1 clip depth.
public enum RenderMath {
    public static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let ys = 1 / tanf(fovY * 0.5)
        let xs = ys / aspect
        let zs = far / (near - far)
        return simd_float4x4(columns: (SIMD4(xs, 0, 0, 0), SIMD4(0, ys, 0, 0),
                                       SIMD4(0, 0, zs, -1), SIMD4(0, 0, zs * near, 0)))
    }

    public static func orthographic(left l: Float, right r: Float, bottom b: Float, top t: Float,
                                    near n: Float, far f: Float) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(2 / (r - l), 0, 0, 0), SIMD4(0, 2 / (t - b), 0, 0),
                                SIMD4(0, 0, 1 / (n - f), 0),
                                SIMD4((l + r) / (l - r), (t + b) / (b - t), n / (n - f), 1)))
    }

    public static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye - target)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)
        return simd_float4x4(columns: (SIMD4(x.x, y.x, z.x, 0), SIMD4(x.y, y.y, z.y, 0), SIMD4(x.z, y.z, z.z, 0),
                                       SIMD4(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)))
    }

    public static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(t, 1)
        return m
    }

    public static func scale(_ s: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4(s, 1))
    }

    public static func rotationX(_ a: Float) -> simd_float4x4 {
        let c = cosf(a), s = sinf(a)
        return simd_float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, c, s, 0), SIMD4(0, -s, c, 0), SIMD4(0, 0, 0, 1)))
    }

    public static func rotationY(_ a: Float) -> simd_float4x4 {
        let c = cosf(a), s = sinf(a)
        return simd_float4x4(columns: (SIMD4(c, 0, -s, 0), SIMD4(0, 1, 0, 0), SIMD4(s, 0, c, 0), SIMD4(0, 0, 0, 1)))
    }

    public static func rotationZ(_ a: Float) -> simd_float4x4 {
        let c = cosf(a), s = sinf(a)
        return simd_float4x4(columns: (SIMD4(c, s, 0, 0), SIMD4(-s, c, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)))
    }

    /// Rotation `r` applied about `pivot`.
    static func about(_ pivot: SIMD3<Float>, _ r: simd_float4x4) -> simd_float4x4 {
        translation(pivot) * r * translation(-pivot)
    }

    /// Six normalized frustum planes (xyz normal, w distance; inside ⇔ dot(n,p)+w ≥ 0).
    static func frustumPlanes(_ m: simd_float4x4) -> [SIMD4<Float>] {
        let r0 = SIMD4(m.columns.0.x, m.columns.1.x, m.columns.2.x, m.columns.3.x)
        let r1 = SIMD4(m.columns.0.y, m.columns.1.y, m.columns.2.y, m.columns.3.y)
        let r2 = SIMD4(m.columns.0.z, m.columns.1.z, m.columns.2.z, m.columns.3.z)
        let r3 = SIMD4(m.columns.0.w, m.columns.1.w, m.columns.2.w, m.columns.3.w)
        return [r3 + r0, r3 - r0, r3 + r1, r3 - r1, r2, r3 - r2].map { p in
            p / simd_length(SIMD3(p.x, p.y, p.z))
        }
    }
}

/// Field space (x across, y downfield, yards) → world space (x right, y up, z = -downfield).
@inlinable public func fieldToWorld(_ p: Vec2, height: Float = 0) -> SIMD3<Float> {
    SIMD3(p.x, height, -p.y)
}

extension RGB {
    /// Authoring colors are sRGB; shaders light in linear space.
    var linear: SIMD4<Float> { SIMD4(powf(r, 2.2), powf(g, 2.2), powf(b, 2.2), 1) }
}
