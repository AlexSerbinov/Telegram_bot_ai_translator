import AVFoundation
import Foundation

/// Records mic audio to an AAC-encoded .m4a file in the temp directory.
/// One-shot pattern: `start()` → user speaks → `stop()` returns the file URL.
/// The file is small (~24KB/sec) and ElevenLabs Scribe v2 accepts it directly.
@MainActor
final class AudioRecorder {
    enum RecorderError: LocalizedError {
        case permissionDenied
        case alreadyRecording
        case recorderInitFailed(any Error)
        case noRecordingInProgress
        var errorDescription: String? {
            switch self {
            case .permissionDenied:        return "Microphone permission denied"
            case .alreadyRecording:        return "Already recording"
            case .recorderInitFailed(let e): return "Recorder init failed: \(e.localizedDescription)"
            case .noRecordingInProgress:   return "No recording in progress"
            }
        }
    }

    private var recorder: AVAudioRecorder?
    private(set) var fileURL: URL?
    private(set) var isRecording = false

    func start() async throws {
        guard !isRecording else { throw RecorderError.alreadyRecording }
        guard await AudioSessionConfigurator.requestMicPermission() else {
            throw RecorderError.permissionDenied
        }
        AudioSessionConfigurator.configure(.measurement)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey:            kAudioFormatMPEG4AAC,
            AVSampleRateKey:          16_000,                // ElevenLabs Scribe v2 happy with 16k
            AVNumberOfChannelsKey:    1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            guard r.record() else {
                throw RecorderError.recorderInitFailed(NSError(domain: "AudioRecorder", code: -1))
            }
            self.recorder = r
            self.fileURL = url
            self.isRecording = true
            DiagLogger.shared.log(.audio, "recording started → \(url.lastPathComponent)")
        } catch {
            throw RecorderError.recorderInitFailed(error)
        }
    }

    func stop() throws -> URL {
        guard let recorder, let url = fileURL else { throw RecorderError.noRecordingInProgress }
        recorder.stop()
        self.recorder = nil
        self.isRecording = false
        DiagLogger.shared.log(.audio, "recording stopped (\(fileSize(of: url)) bytes)")
        return url
    }

    func currentLevel() -> Float {
        recorder?.updateMeters()
        return recorder?.averagePower(forChannel: 0) ?? -160
    }

    private func fileSize(of url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }
}
