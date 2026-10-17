import AVFAudio
import CBAudio
import XCTest

@testable import CraftBowl

final class WhistleAudioTests: XCTestCase {
    @MainActor
    func testBundledWhistleUsesQuietSFXPlayerAndStopsOnTitleScreen() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Whistle", withExtension: "mp3"))
        let audio = AudioSystem()
        try audio.loadWhistle(from: url)

        let players = audio.engine.attachedNodes.compactMap { $0 as? AVAudioPlayerNode }
        let whistle = try XCTUnwrap(
            players.first {
                audio.engine.outputConnectionPoints(for: $0, outputBus: 0).contains { $0.node === audio.sfx }
            })
        XCTAssertEqual(whistle.volume, 0.2, accuracy: 0.001)

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        try audio.engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        try audio.engine.start()
        defer { audio.engine.stop() }

        audio.playWhistle()
        XCTAssertTrue(whistle.isPlaying)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        var hasSound = false
        for _ in 0..<10 {
            let status = try audio.engine.renderOffline(1024, to: buffer)
            XCTAssertEqual(status, .success)
            let samples = try XCTUnwrap(buffer.floatChannelData)
            hasSound = hasSound || (0..<Int(buffer.frameLength)).contains { abs(samples[0][$0]) > 0.0001 }
        }
        XCTAssertTrue(hasSound, "The bundled whistle should render audible samples through the SFX bus.")

        audio.playTitleMusic()
        XCTAssertFalse(whistle.isPlaying)
    }
}
