import AVFoundation
import Foundation

/// Plays an in-memory MP3 blob. Used for `/api/tts` playback in the Phrase tab.
/// Single-instance — calling `play()` cancels any in-flight playback.
@MainActor
final class MP3Player: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private(set) var isPlaying = false

    var onFinish: (() -> Void)?

    func play(data: Data, configureSession: Bool = true) throws {
        // For one-shot TTS (Phrase tab) we configure the session so the
        // play-back routes correctly. For continuously-listening tabs (Relay)
        // the session is already set up + a live AVAudioEngine input tap is
        // running — calling configure() here would force `setPreferredInput`
        // mid-playback and silently break the input tap (frames stop flowing,
        // Soniox then 408-times-out after 20s of "client sent no audio").
        // Callers in that situation pass `configureSession: false`.
        if configureSession {
            AudioSessionConfigurator.configure(.voiceChat)
        }
        player?.stop()
        let p = try AVAudioPlayer(data: data)
        p.delegate = self
        // Explicit max volume — AVAudioPlayer's default IS 1.0 but pinning
        // it removes any chance of inheriting a stale value from a previous
        // player instance.
        p.volume = 1.0
        p.prepareToPlay()
        guard p.play() else {
            throw NSError(domain: "MP3Player", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "AVAudioPlayer.play() returned false"])
        }
        self.player = p
        self.isPlaying = true
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute.outputs.map { "\($0.portType.rawValue)/\($0.portName)" }.joined(separator: ",")
        DiagLogger.shared.log(.tts, "playing MP3 \(data.count)B \(String(format: "%.1f", p.duration))s | cat=\(session.category.rawValue) mode=\(session.mode.rawValue) vol=\(String(format: "%.2f", session.outputVolume)) route=\(route)")
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
