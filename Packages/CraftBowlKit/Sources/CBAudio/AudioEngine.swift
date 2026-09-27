#if canImport(AVFAudio)
import AVFAudio

/// Music / SFX / crowd buses (issue V2). Scaffold only.
@MainActor
public final class AudioSystem {
    public let engine = AVAudioEngine()
    public let music = AVAudioMixerNode()
    public let sfx = AVAudioMixerNode()
    public let crowd = AVAudioMixerNode()

    public init() {
        for bus in [music, sfx, crowd] {
            engine.attach(bus)
            engine.connect(bus, to: engine.mainMixerNode, format: nil)
        }
    }

    public func start() throws {
        #if os(iOS)
        try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        #endif
        try engine.start()
    }
}
#endif
