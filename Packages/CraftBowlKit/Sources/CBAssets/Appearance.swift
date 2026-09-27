import CBCore

/// Helmet variants built into the single player mesh.
public enum HelmetStyle: UInt8, Codable, Sendable {
    case none, classic, knight
}

/// Optional mesh parts toggled per instance (bitmask), docs/PLAN.md §4.
public struct PartMask: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let helmetClassic = PartMask(rawValue: 1 << 0)
    public static let helmetKnight = PartMask(rawValue: 1 << 1)
    public static let facemask = PartMask(rawValue: 1 << 2)
    public static let shoulderArmor = PartMask(rawValue: 1 << 3)
    public static let hairShort = PartMask(rawValue: 1 << 4)
    public static let hairTall = PartMask(rawValue: 1 << 5)
    public static let belt = PartMask(rawValue: 1 << 6)
    public static let wristTape = PartMask(rawValue: 1 << 7)
}

/// Everything that makes one player look unique — same model for everyone.
public struct PlayerAppearance: Codable, Hashable, Sendable {
    public var skinTone: UInt8
    public var faceID: UInt8
    public var hairID: UInt8
    public var helmetStyle: HelmetStyle
    public var parts: PartMask
    public var number: UInt8
    /// Clamped per-axis body scale (x = width, y = height, z = depth).
    public var bodyScale: SIMD3<Float>

    public init(skinTone: UInt8, faceID: UInt8 = 0, hairID: UInt8 = 0, helmetStyle: HelmetStyle = .classic,
                parts: PartMask = [.helmetClassic, .facemask], number: UInt8,
                bodyScale: SIMD3<Float> = SIMD3(1, 1, 1)) {
        self.skinTone = skinTone
        self.faceID = faceID
        self.hairID = hairID
        self.helmetStyle = helmetStyle
        self.parts = parts
        self.number = min(number, 99)
        self.bodyScale = SIMD3(clamp(bodyScale.x, 0.85, 1.3), clamp(bodyScale.y, 0.9, 1.1), clamp(bodyScale.z, 0.85, 1.3))
    }
}

/// Team palette consumed by the recolor shader (mask R = skin, G = primary, B = secondary, A = trim).
public struct TeamUniform: Codable, Hashable, Sendable {
    public var primary: RGB
    public var secondary: RGB
    public var trim: RGB
    public var helmet: RGB
    public var helmetStripe: RGB
    public var pants: RGB
    public var numberFill: RGB
    public var numberOutline: RGB

    /// Reference image home team: royal blue with gold.
    public static let blue = TeamUniform(
        primary: RGB(hex: 0x2A5BD7), secondary: RGB(hex: 0xF2B230), trim: RGB(hex: 0x1B2A55),
        helmet: RGB(hex: 0x2A5BD7), helmetStripe: RGB(hex: 0xF2B230), pants: RGB(hex: 0xE0A93A),
        numberFill: RGB(hex: 0xF2B230), numberOutline: RGB(hex: 0x1B2A55))

    /// Reference image away team: crimson with charcoal armor.
    public static let red = TeamUniform(
        primary: RGB(hex: 0xB3262B), secondary: RGB(hex: 0x2B2B30), trim: RGB(hex: 0xF0D24A),
        helmet: RGB(hex: 0x3A3A40), helmetStripe: RGB(hex: 0xC8312F), pants: RGB(hex: 0x2B2B30),
        numberFill: RGB(hex: 0xF0D24A), numberOutline: RGB(hex: 0x5A1214))
}

/// Natural skin tone palette indexed by `PlayerAppearance.skinTone`.
public enum SkinPalette {
    public static let tones: [RGB] = [
        RGB(hex: 0xF6D7C3), RGB(hex: 0xEDC4A6), RGB(hex: 0xE2B08C), RGB(hex: 0xD49E76),
        RGB(hex: 0xC68A62), RGB(hex: 0xB07650), RGB(hex: 0x9A6242), RGB(hex: 0x855236),
        RGB(hex: 0x70432C), RGB(hex: 0x5C3623), RGB(hex: 0x4A2B1C), RGB(hex: 0x3A2217),
    ]
}
