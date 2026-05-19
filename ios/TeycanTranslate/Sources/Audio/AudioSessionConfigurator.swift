import AVFoundation

enum AudioMode {
    /// Realtime / Chat — voice chat semantics (echo cancellation, optimized for speech).
    case voiceChat
    /// Phrase tab record path — clean PCM for ElevenLabs / Soniox.
    case measurement
}

enum AudioSessionConfigurator {
    /// Configures `AVAudioSession` for the current tab's needs. Idempotent —
    /// safe to call on every tab activation.
    ///
    /// Output: always main loudspeaker (not the earpiece). `.voiceChat` mode
    /// alone routes to the earpiece on iPhone, so we both pass
    /// `.defaultToSpeaker` and explicitly call `overrideOutputAudioPort(.speaker)`
    /// after activation. Echo cancellation stays on for `.voiceChat`.
    ///
    /// Input: prefer the iPhone built-in mic over any paired Bluetooth headset
    /// mic. AirPods etc. can still play audio (we don't block A2DP / HFP for
    /// playback) — we just don't pick them up as the recording source.
    static func configure(_ mode: AudioMode) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: mode == .voiceChat ? .voiceChat : .measurement,
                                    options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP, .duckOthers])
            try session.setActive(true)

            // Output routing only matters for the modes that actually play
            // audio back (Bridge / Companion = `.voiceChat`). Phrase recording
            // (`.measurement`) doesn't play anything during capture, so we
            // leave its routing alone — touching `overrideOutputAudioPort` or
            // `setPreferredInput` in measurement mode has historically
            // destabilised AVAudioEngine capture on some devices.
            if mode == .voiceChat {
                let outs = session.currentRoute.outputs.map { $0.portType }
                let headphonesConnected = outs.contains { port in
                    port == .headphones || port == .bluetoothA2DP || port == .bluetoothLE ||
                    port == .bluetoothHFP || port == .usbAudio || port == .carAudio
                }
                if !headphonesConnected {
                    try session.overrideOutputAudioPort(.speaker)
                    DiagLogger.shared.log(.audio, "output forced to main speaker")
                } else {
                    try session.overrideOutputAudioPort(.none)
                    DiagLogger.shared.log(.audio, "output kept on headphones (\(outs.map { $0.rawValue }.joined(separator: ",")))")
                }

                if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                    try? session.setPreferredInput(builtIn)
                    DiagLogger.shared.log(.audio, "mic input forced to built-in (\(builtIn.portName))")
                } else {
                    DiagLogger.shared.log(.audio, "built-in mic not in availableInputs — leaving system default")
                }
            }

            DiagLogger.shared.log(.audio, "session configured (\(mode))")
        } catch {
            DiagLogger.shared.log(.audio, "session configure failed: \(error.localizedDescription)")
        }
    }

    static func deactivate() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            DiagLogger.shared.log(.audio, "session deactivated")
        } catch {
            DiagLogger.shared.log(.audio, "session deactivate failed: \(error.localizedDescription)")
        }
    }

    static func requestMicPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
