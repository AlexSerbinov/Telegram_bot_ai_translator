import AVFoundation
import Foundation

/// Plays an in-memory MP3 blob. Used for `/api/tts` playback in the Phrase tab.
/// Single-instance — calling `play()` cancels any in-flight playback.
@MainActor
final class MP3Player: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private(set) var isPlaying = false

    var onFinish: (() -> Void)?

    func play(data: Data) throws {
        // For TTS playback we want speaker output, no measurement mode.
        AudioSessionConfigurator.configure(.voiceChat)
        player?.stop()
        let p = try AVAudioPlayer(data: data)
        p.delegate = self
        p.prepareToPlay()
        guard p.play() else {
            throw NSError(domain: "MP3Player", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "AVAudioPlayer.play() returned false"])
        }
        self.player = p
        self.isPlaying = true
        DiagLogger.shared.log(.tts, "playing MP3 (\(data.count) bytes, \(String(format: "%.1f", p.duration))s)")
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isPlaying = false
            self?.onFinish?()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let msg = error?.localizedDescription ?? "unknown"
        DiagLogger.shared.log(.tts, "decode error: \(msg)")
        Task { @MainActor [weak self] in
            self?.isPlaying = false
            self?.onFinish?()
        }
    }
}
