import Foundation
import WebRTC

/// Configuration for a single Realtime session connection.
struct RealtimeRTCConfig {
    /// OpenAI SDP endpoint — translations or conversational.
    let sdpEndpoint: URL
    /// Ephemeral client_secret minted by our server.
    let clientSecret: String

    /// Fired for every parsed event on the data channel.
    let onEvent: @MainActor (RealtimeEvent) -> Void
    /// Fired for every raw event line — used by `LogPanel` for diagnostics.
    let onRawEvent: @MainActor (String) -> Void
    /// Connection state changes (connected, failed, closed, etc.).
    let onConnectionState: @MainActor (RTCPeerConnectionState) -> Void
}

/// Owns one WebRTC peer connection + data channel for the lifetime of one
/// Realtime session. Reused for both `gpt-realtime-translate` (Companion tab)
/// and `gpt-realtime` conversational (Bridge tab) — only the SDP endpoint and
/// the server-side session config differ.
@MainActor
final class RealtimeRTCClient: NSObject {
    private var peer: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var localAudioTrack: RTCAudioTrack?
    private var config: RealtimeRTCConfig?
    /// Resolved exactly once when peer state first hits `.connected`. Lets
    /// callers `await` until the audio path is actually flowing, instead of
    /// returning from `connect()` as soon as SDP exchange completes (which is
    /// ~1s before ICE finishes negotiating). Without this, the user thinks
    /// the mic is hot but the first few seconds of speech land in the void.
    private var connectedContinuation: CheckedContinuation<Void, Never>?
    private var didResolveConnected = false

    /// True while WebRTC owns mic + peer resources. Read by CostGuard's
    /// `isLeakedNow` predicate.
    var isLive: Bool { peer != nil || dataChannel != nil }

    func connect(config: RealtimeRTCConfig) async throws {
        self.config = config
        didResolveConnected = false
        DiagLogger.shared.log(.rtc, "connect: \(config.sdpEndpoint.absoluteString)")

        let factory = PeerFactory.shared
        let rtcConfig = RTCConfiguration()
        rtcConfig.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peer = factory.peerConnection(with: rtcConfig, constraints: constraints, delegate: self) else {
            throw NSError(domain: "RealtimeRTC", code: -1, userInfo: [NSLocalizedDescriptionKey: "PeerConnection init failed"])
        }
        self.peer = peer

        // Mic capture — WebRTC framework owns AVAudioEngine internally.
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = factory.audioSource(with: audioConstraints)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "mic0")
        peer.add(audioTrack, streamIds: ["stream0"])
        self.localAudioTrack = audioTrack

        // Data channel for OpenAI events.
        let dcConfig = RTCDataChannelConfiguration()
        dcConfig.isOrdered = true
        if let dc = peer.dataChannel(forLabel: "oai-events", configuration: dcConfig) {
            dc.delegate = self
            self.dataChannel = dc
        }

        // Build SDP offer.
        let mediaConstraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true"],
            optionalConstraints: nil
        )
        let offer = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<RTCSessionDescription, Error>) in
            peer.offer(for: mediaConstraints) { sdp, error in
                if let sdp { cont.resume(returning: sdp) }
                else { cont.resume(throwing: error ?? NSError(domain: "RealtimeRTC", code: -2)) }
            }
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            peer.setLocalDescription(offer) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
        DiagLogger.shared.log(.rtc, "local SDP set")

        // Hand offer SDP to OpenAI via our APIClient helper, get answer SDP back.
        let answerSDP = try await APIClient.shared.openaiSDPExchange(
            url: config.sdpEndpoint,
            clientSecret: config.clientSecret,
            offerSDP: offer.sdp
        )
        DiagLogger.shared.log(.rtc, "got OpenAI answer SDP (\(answerSDP.count) bytes)")

        let answer = RTCSessionDescription(type: .answer, sdp: answerSDP)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            peer.setRemoteDescription(answer) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
        DiagLogger.shared.log(.rtc, "remote SDP set — handshake complete, waiting for peer to connect…")

        // Wait for the peer state to actually transition to `.connected`
        // before returning. Time-bounded at 8s: above that we give up and
        // return anyway (caller will see the existing failure callback if
        // the peer eventually transitions to .failed).
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                if self.didResolveConnected { return }
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    self.connectedContinuation = cont
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 8 * 1_000_000_000)
            }
            await group.next()
            group.cancelAll()
        }
        if !didResolveConnected {
            DiagLogger.shared.log(.rtc, "WARN: peer state did not reach .connected within 8s — proceeding anyway")
        }
    }

    private func resolveConnected() {
        guard !didResolveConnected else { return }
        didResolveConnected = true
        connectedContinuation?.resume()
        connectedContinuation = nil
    }

    func close() {
        DiagLogger.shared.log(.rtc, "close()")
        connectedContinuation?.resume()
        connectedContinuation = nil
        didResolveConnected = false
        dataChannel?.close()
        peer?.close()
        dataChannel = nil
        peer = nil
        localAudioTrack = nil
        config = nil
    }
}

// MARK: - RTCPeerConnectionDelegate

extension RealtimeRTCClient: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        Task { @MainActor [weak self] in
            DiagLogger.shared.log(.rtc, "peer state → \(newState.label)")
            if newState == .connected {
                self?.resolveConnected()
            }
            self?.config?.onConnectionState(newState)
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

// MARK: - RTCDataChannelDelegate

extension RealtimeRTCClient: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        Task { @MainActor in
            DiagLogger.shared.log(.rtc, "data channel state → \(dataChannel.readyState.label)")
        }
    }

    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let raw = String(data: buffer.data, encoding: .utf8) ?? ""
        Task { @MainActor [weak self] in
            self?.config?.onRawEvent(raw)
            do {
                let event = try JSONDecoder().decode(RealtimeEvent.self, from: buffer.data)
                self?.config?.onEvent(event)
            } catch {
                DiagLogger.shared.log(.rtc, "event decode failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Pretty labels for logs

private extension RTCPeerConnectionState {
    var label: String {
        switch self {
        case .new: return "new"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .disconnected: return "disconnected"
        case .failed: return "failed"
        case .closed: return "closed"
        @unknown default: return "unknown"
        }
    }
}

private extension RTCDataChannelState {
    var label: String {
        switch self {
        case .connecting: return "connecting"
        case .open: return "open"
        case .closing: return "closing"
        case .closed: return "closed"
        @unknown default: return "unknown"
        }
    }
}
