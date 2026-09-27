import CBCore

/// Everything one local player asked for during a single 60 Hz sim tick.
/// This is the unit that gets recorded and replayed (issue #3), so it must stay a plain value.
public struct TickInput: Sendable, Equatable, Codable {
    public struct Buttons: OptionSet, Sendable, Equatable, Codable, Hashable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) { self.rawValue = rawValue }
        public static let passLeft = Buttons(rawValue: 1 << 0)
        public static let passCenter = Buttons(rawValue: 1 << 1)
        public static let passRight = Buttons(rawValue: 1 << 2)
        public static let handoff = Buttons(rawValue: 1 << 3)
        public static let dive = Buttons(rawValue: 1 << 4)
        public static let switchPlayer = Buttons(rawValue: 1 << 5)
        public static let switchNearest = Buttons(rawValue: 1 << 6)
        public static let swat = Buttons(rawValue: 1 << 7)
        public static let snap = Buttons(rawValue: 1 << 8)
        public static let nextPlay = Buttons(rawValue: 1 << 9)
        public static let previousPlay = Buttons(rawValue: 1 << 10)

        public static let anyPass: Buttons = [.passLeft, .passCenter, .passRight]
    }

    public var move: Vec2
    public var turbo: Bool
    public var buttons: Buttons
    /// Direct pick from the play-select grid (0-based), or -1.
    public var playSelect: Int8

    public init(move: Vec2 = .zero, turbo: Bool = false, buttons: Buttons = [], playSelect: Int8 = -1) {
        self.move = move
        self.turbo = turbo
        self.buttons = buttons
        self.playSelect = playSelect
    }

    public static let none = TickInput()
}
