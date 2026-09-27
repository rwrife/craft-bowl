import CBCore

/// Normalized (0...1, origin top-left) HUD anchor rects matching the reference layout (issue I5).
public struct HUDRect: Sendable, Equatable {
    public var x: Float, y: Float, w: Float, h: Float
    public init(x: Float, y: Float, w: Float, h: Float) { self.x = x; self.y = y; self.w = w; self.h = h }
}

public enum HUDLayout {
    /// Center-top scorebug: home banner | score | away banner.
    public static let scorebug = HUDRect(x: 0.24, y: 0.035, w: 0.54, h: 0.075)
    /// Top-right down & distance + quarter/clock stack.
    public static let downDistance = HUDRect(x: 0.83, y: 0.035, w: 0.145, h: 0.07)
    public static let clock = HUDRect(x: 0.83, y: 0.11, w: 0.145, h: 0.065)
    /// Bottom-left minimap.
    public static let minimap = HUDRect(x: 0.02, y: 0.73, w: 0.145, h: 0.245)
    /// Bottom-right 2x2 action cluster + PLAYS button.
    public static let actionCluster = HUDRect(x: 0.845, y: 0.73, w: 0.135, h: 0.245)
}
