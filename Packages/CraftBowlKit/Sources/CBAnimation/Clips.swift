/// Animation clip identifiers for the single player rig (docs/PLAN.md §4, issue P5).
public enum ClipID: String, CaseIterable, Codable, Sendable {
    case idle, stanceThreePoint, stanceTwoPoint, stanceQB
    case run, sprint, backpedal, shuffle
    case throwPass, handoff, toss
    case catchHigh, catchLow, catchDive
    case blockEngage, blockDrive
    case tackle, dive, stumble, fall, getUp
    case juke, stiffArm
    case celebrate1, celebrate2, celebrate3
}

/// Bones of the rigid rig. Every vertex binds to exactly one bone.
public enum Bone: Int, CaseIterable, Codable, Sendable {
    case pelvis, spine, chest, head
    case upperArmL, foreArmL, handL, upperArmR, foreArmR, handR
    case thighL, shinL, thighR, shinR
}
