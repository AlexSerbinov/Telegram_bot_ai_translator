import AVFoundation
import Foundation
import WebRTC

/// Process-wide singleton — Google's libwebrtc strongly recommends a single
/// `RTCPeerConnectionFactory` per app. We initialize SSL once on first access.
///
/// First access also installs our custom `RTCAudioSessionConfiguration` —
/// libwebrtc's default config uses `AVAudioSession.Mode.voiceChat`, which
/// routes through Apple's Voice Processing IO at the conservative VoIP gain
/// stage and ends up noticeably quieter than `.videoChat`. Both modes have
/// the same echo cancellation (essential for Bridge/Companion so the model
/// doesn't hear itself), but `.videoChat` is the FaceTime-tuned variant with
/// louder output — exactly what we want for half-duplex live translation
/// where the user needs to clearly hear the model from arm's length.
enum PeerFactory {
    static let shared: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        installLoudAudioSessionDefault()
        let encoder = RTCDefaultVideoEncoderFactory()
        let decoder = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
    }()

    private static func installLoudAudioSessionDefault() {
        let config = RTCAudioSessionConfiguration.webRTC()
        config.category = AVAudioSession.Category.playAndRecord.rawValue
        config.mode = AVAudioSession.Mode.videoChat.rawValue
        config.categoryOptions = [
            .defaultToSpeaker,
            .allowBluetoothHFP,
            .allowBluetoothA2DP,
            .duckOthers
        ]
        RTCAudioSessionConfiguration.setWebRTC(config)
        DiagLogger.shared.log(.rtc, "RTCAudioSessionConfiguration installed: mode=videoChat (was voiceChat) for louder output")
    }
}
