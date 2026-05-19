import Foundation
import WebRTC

/// Process-wide singleton — Google's libwebrtc strongly recommends a single
/// `RTCPeerConnectionFactory` per app. We initialize SSL once on first access.
enum PeerFactory {
    static let shared: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let encoder = RTCDefaultVideoEncoderFactory()
        let decoder = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
    }()
}
