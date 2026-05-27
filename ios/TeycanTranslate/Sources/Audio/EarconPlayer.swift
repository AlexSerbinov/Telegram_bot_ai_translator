import AudioToolbox
import Foundation

/// Tiny "UI earcon" player for the Relay tab — plays a ~140ms two-tone cue
/// when the mic opens (`start`) and when end-of-speech is committed (`end`,
/// the moment the loader kicks in).
///
/// Uses `AudioServicesPlaySystemSound` (Core Audio Toolbox) instead of
/// `AVAudioPlayer` because:
///   - It bypasses `AVAudioSession` entirely. The Relay tab spends most of
///     its life in `.voiceChat` mode, which routes through Apple's Voice
///     Processing IO unit and attenuates output ~30%. Earcons through that
///     path come out distractingly quiet relative to TTS. AudioServices
///     uses iOS's dedicated system-sound path that ignores session mode.
///   - It naturally follows the user's ringer / media volume — exactly what
///     a UI cue should do.
///   - Tiny overhead (<1ms to fire) and no AVAudioPlayer lifecycle.
@MainActor
final class EarconPlayer {
    enum Cue: String {
        case start = "relay_start"
        case end   = "relay_end"
    }

    static let shared = EarconPlayer()

    private var soundIDs: [Cue: SystemSoundID] = [:]

    init() {
        register(.start)
        register(.end)
    }

    deinit {
        for id in soundIDs.values where id != 0 {
            AudioServicesDisposeSystemSoundID(id)
        }
    }

    func play(_ cue: Cue) {
        guard let id = soundIDs[cue], id != 0 else {
            DiagLogger.shared.log(.audio, "[earcon] \(cue.rawValue) not registered — skipped")
            return
        }
        AudioServicesPlaySystemSound(id)
    }

    private func register(_ cue: Cue) {
        guard let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "wav") else {
            DiagLogger.shared.log(.audio, "[earcon] missing resource: \(cue.rawValue).wav")
            return
        }
        var id: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &id)
        if status == noErr {
            soundIDs[cue] = id
        } else {
            DiagLogger.shared.log(.audio, "[earcon] register \(cue.rawValue) failed: status=\(status)")
        }
    }
}
