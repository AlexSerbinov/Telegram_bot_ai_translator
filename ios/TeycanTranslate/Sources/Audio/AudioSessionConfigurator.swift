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
    /// Output: always main loudspeaker (not the earpiece). Voice modes alone
    /// route to the earpiece on iPhone, so we both pass `.defaultToSpeaker`
    /// and explicitly call `overrideOutputAudioPort(.speaker)` after
    /// activation. Echo cancellation stays on for `.voiceChat` → AVAudioSession
    /// `.videoChat` mode (yes, video chat — same VPIO with AEC, but Apple
    /// tuned it for louder output than `.voiceChat`, which routes through
    /// the conservative VoIP gain stage and ends up ~30% quieter at the
    /// speaker. The mic-side echo cancellation is identical, so for Bridge
    /// and Companion — both WebRTC bidirectional — this is a free volume
    /// boost without losing AEC).
    ///
    /// Input: prefer the iPhone built-in mic over any paired Bluetooth headset
    /// mic. AirPods etc. can still play audio (we don't block A2DP / HFP for
    /// playback) — we just don't pick them up as the recording source.
    static func configure(_ mode: AudioMode) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: mode == .voiceChat ? .videoChat : .measurement,
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

            DiagLogger.shared.log(.audio, "session configured (\(mode) → AVMode.\(session.mode.rawValue))")
        } catch {
            DiagLogger.shared.log(.audio, "session configure failed: \(error.localizedDescription)")
        }
    }

    /// Re-assert main-loudspeaker output without touching category / mode /
    /// preferred input. Use this before TTS playback in tabs that have a
    /// long-lived `.voiceChat` session — `configure()` would otherwise need
    /// to be called, but that path also re-runs `setPreferredInput()` which
    /// silently breaks the live AVAudioEngine input tap (Relay's mic
    /// stream). This is the surgical alternative.
    ///
    /// Skips the override when headphones / AirPods / car audio are
    /// connected — those should keep playing through the user's chosen
    /// route, not the phone speaker.
    static func forceSpeakerOutput() {
        let session = AVAudioSession.sharedInstance()
        let outs = session.currentRoute.outputs.map { $0.portType }
        let headphonesConnected = outs.contains { port in
            port == .headphones || port == .bluetoothA2DP || port == .bluetoothLE ||
            port == .bluetoothHFP || port == .usbAudio || port == .carAudio
        }
        do {
            if headphonesConnected {
                try session.overrideOutputAudioPort(.none)
                DiagLogger.shared.log(.audio, "output kept on headphones (\(outs.map { $0.rawValue }.joined(separator: ",")))")
            } else {
                try session.overrideOutputAudioPort(.speaker)
                DiagLogger.shared.log(.audio, "output forced to main speaker (no session reconfigure)")
            }
        } catch {
            DiagLogger.shared.log(.audio, "speaker override failed: \(error.localizedDescription)")
        }
    }

    /// Switch the live session into pure-playback mode for loud TTS output.
    /// `.voiceChat` routes through Apple's Voice Processing IO unit which
    /// applies AEC/AGC and attenuates output ~30%. For Relay's TTS playback we
    /// want maximum loudness, so we temporarily downgrade to `.playback` with
    /// `.spokenAudio` mode (the mode Apple recommends for voice readers).
    ///
    /// Caller MUST stop any active AVAudioEngine input tap before calling —
    /// `.playback` is output-only and the input tap will silently die.
    static func switchToPlaybackMode() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            let outs = session.currentRoute.outputs.map { $0.portType }
            let headphonesConnected = outs.contains { port in
                port == .headphones || port == .bluetoothA2DP || port == .bluetoothLE ||
                port == .bluetoothHFP || port == .usbAudio || port == .carAudio
            }
            if !headphonesConnected {
                try session.overrideOutputAudioPort(.speaker)
            }
            DiagLogger.shared.log(.audio, "session switched to .playback/.spokenAudio (max loudness)")
        } catch {
            DiagLogger.shared.log(.audio, "switch to playback mode failed: \(error.localizedDescription)")
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
