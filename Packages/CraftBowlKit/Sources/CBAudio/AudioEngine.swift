#if canImport(AVFAudio)
import AVFAudio

/// Music / SFX / crowd buses (issue V2). Scaffold only.
@MainActor
public final class AudioSystem {
    public let engine = AVAudioEngine()
    public let music = AVAudioMixerNode()
    public let sfx = AVAudioMixerNode()
    public let crowd = AVAudioMixerNode()
    private let crowdPlayer = AVAudioPlayerNode()
    private let cheerPlayer = AVAudioPlayerNode()
    private var crowdBuffer: AVAudioPCMBuffer?
    private var cheerBuffers: [AVAudioPCMBuffer] = []
    private var lastCheerIndex: Int?

    public init() {
        for bus in [music, sfx, crowd] {
            engine.attach(bus)
            engine.connect(bus, to: engine.mainMixerNode, format: nil)
        }
        engine.attach(crowdPlayer)
        engine.attach(cheerPlayer)
    }

    public func start() async throws {
        #if os(iOS)
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
        }.value
        #endif
        try engine.start()
    }

    public func loadCrowdLoop(from url: URL) throws {
        crowdBuffer = try loadBuffer(from: url)
        if let crowdBuffer {
            engine.connect(crowdPlayer, to: crowd, format: crowdBuffer.format)
        }
    }

    public func loadCheers(from urls: [URL]) throws {
        cheerBuffers = try urls.map(loadBuffer)
        guard let format = cheerBuffers.first?.format else { throw CocoaError(.fileReadCorruptFile) }
        guard cheerBuffers.allSatisfy({
            $0.format.sampleRate == format.sampleRate && $0.format.channelCount == format.channelCount
        }) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        engine.connect(cheerPlayer, to: sfx, format: format)
    }

    public func playCrowdLoop() {
        guard !crowdPlayer.isPlaying, let crowdBuffer else { return }
        crowdPlayer.scheduleBuffer(crowdBuffer, at: nil, options: .loops)
        crowdPlayer.play()
    }

    public func stopCrowdLoop() {
        crowdPlayer.stop()
    }

    public func playCheer() {
        guard !cheerBuffers.isEmpty else { return }
        var index = Int.random(in: cheerBuffers.indices)
        if cheerBuffers.count > 1, index == lastCheerIndex {
            index = (index + 1) % cheerBuffers.count
        }
        lastCheerIndex = index
        cheerPlayer.stop()
        cheerPlayer.scheduleBuffer(cheerBuffers[index])
        cheerPlayer.play()
    }

    private func loadBuffer(from url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length))
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: buffer)
        return buffer
    }
}
#endif
