/// Field-space 2D vector (yards). x = sideline to sideline, y = downfield. Uses stdlib SIMD so it
/// works on every platform (the `simd` module is Apple-only).
public typealias Vec2 = SIMD2<Float>

extension SIMD2 where Scalar == Float {
    public var length: Float { (x * x + y * y).squareRoot() }
    public var normalized: Vec2 {
        let l = length
        return l > 1e-6 ? self / l : .zero
    }
    public func distance(to other: Vec2) -> Float { (other - self).length }
}

@inlinable public func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
@inlinable public func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

/// Linear RGB color, 0...1.
public struct RGB: Codable, Hashable, Sendable {
    public var r: Float, g: Float, b: Float
    public init(_ r: Float, _ g: Float, _ b: Float) { self.r = r; self.g = g; self.b = b }
    /// Create from a 0xRRGGBB hex literal (sRGB-ish authoring values).
    public init(hex: UInt32) {
        self.init(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255)
    }
}
