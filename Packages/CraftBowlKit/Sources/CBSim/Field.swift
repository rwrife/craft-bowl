import CBCore

/// Field geometry in yards. x runs sideline to sideline (0 = middle), y runs downfield.
/// y = 0 is the back of the offense's end zone, 10 its goal line, 110 the far goal line, 120 the far end line.
public enum Field {
    public static let halfWidth: Float = 53.333 / 2
    public static let length: Float = 120
    public static let ownGoalLine: Float = 10
    public static let goalLine: Float = 110
    /// Width of each of the three passing lanes (docs/PLAN.md §5.2).
    public static let laneWidth: Float = 53.333 / 3

    /// Center x of a passing lane: -1 = left, 0 = center, 1 = right (offense's point of view).
    public static func laneCenterX(_ index: Int) -> Float { Float(index) * laneWidth }

    public static func isOutOfBounds(_ p: Vec2) -> Bool {
        abs(p.x) > halfWidth || p.y < 0 || p.y > length
    }
}
