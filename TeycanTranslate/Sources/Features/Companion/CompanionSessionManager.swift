import Foundation
import Observation
import WebRTC

/// Top-level session orchestrator for the Companion tab. Owns the WebRTC
/// client and the cost guard; exposes a tiny `start/stop/extend` API to the
/// view model.
@Observable
@MainActor
final class CompanionSessionManager {
    enum Phase: Equatable {
        case idle
        case starting
        case running
        case stopping
        case error(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var sourceTranscript: String = ""
    private(set) var translatedTranscript: String = ""
    private(set) var deadline: Date?
    private(set) var inWarnWindow: Bool = false

    private let client = RealtimeRTCClient()
    private let guard_ = CostGuard()
    private var deadlineMirrorTask: Task<Void, Never>?

    @ObservationIgnored
    private var tabObserver: NSObjectProtocol?

    init() {
        guard_.isLeakedNow = { [weak self] in
            self?.client.isLive ?? false
        }
        guard_.onWarn = { [weak self] in
            self?.inWarnWindow = true
        }
        guard_.onStop = { [weak self] reason in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.tearDown(reason: reason.rawValue)
            }
        }
        tabObserver = NotificationCenter.default.addObserver(
            forName: .teycanTabChanged, object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let from = notification.userInfo?["from"] as? String
                if from == "companion", case .running = self.phase {
                    DiagLogger.shared.log(.guard_, "tab switch from realtime — auto stop")
                    self.guard_.stop(reason: .tabSwitch)
                }
            }
        }
    }

    // Block-based NotificationCenter observers retain only their block, which
    // captures `self` weakly — the small leak on deinit is acceptable. We
    // skip explicit removal here to avoid the nonisolated-deinit MainActor
    // dance under Swift 6 strict concurrency.

    func start(targetLanguage: String) async {
        guard case .idle = phase else { return }
        phase = .starting
        sourceTranscript = ""
        translatedTranscript = ""

        AudioSessionConfigurator.configure(.voiceChat)
        let granted = await AudioSessionConfigurator.requestMicPermission()
        guard granted else {
            phase = .error("Microphone permission denied")
            DiagLogger.shared.log(.audio, "mic permission DENIED")
            return
        }

        do {
            DiagLogger.shared.log(.net, "minting client_secret (target=\(targetLanguage))")
            let session = try await APIClient.shared.realtimeSession(targetLanguage: targetLanguage)
            DiagLogger.shared.log(.net, "client_secret OK (model=\(session.model))")

            let config = RealtimeRTCConfig(
                sdpEndpoint: Endpoints.OpenAI.translationsCalls,
                clientSecret: session.client_secret,
                onEvent: { [weak self] event in self?.handle(event: event) },
                onRawEvent: { raw in DiagLogger.shared.log(.rtc, "evt: \(raw.prefix(200))") },
                onConnectionState: { [weak self] state in
                    if state == .failed || state == .closed {
                        Task { @MainActor [weak self] in
                            self?.guard_.stop(reason: state == .failed ? .pcFailed : .pcClosed)
                        }
                    }
                }
            )

            try await client.connect(config: config)
            guard_.start()
            phase = .running
            startDeadlineMirror()
        } catch {
            DiagLogger.shared.log(.net, "session start failed: \(error.localizedDescription)")
            phase = .error(error.localizedDescription)
            await tearDown(reason: "start-failed")
        }
    }

    func stop() async {
        guard_.stop(reason: .manual)
    }

    func extend() {
        guard_.extend()
        inWarnWindow = false
    }

    // MARK: - Internal

    private func startDeadlineMirror() {
        deadlineMirrorTask?.cancel()
        deadlineMirrorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.deadline = self.guard_.deadline
                self.inWarnWindow = self.guard_.inWarnWindow
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func tearDown(reason: String) async {
        phase = .stopping
        deadlineMirrorTask?.cancel()
        deadlineMirrorTask = nil
        client.close()
        AudioSessionConfigurator.deactivate()
        deadline = nil
        inWarnWindow = false
        phase = .idle
    }

    private func handle(event: RealtimeEvent) {
        switch event {
        case .inputTranscriptDelta(_, let delta):
            sourceTranscript.append(delta)
        case .inputTranscriptCompleted(_, let transcript):
            sourceTranscript = transcript
        case .outputTranscriptDelta(_, let delta):
            translatedTranscript.append(delta)
        case .outputTranscriptDone(_, let transcript):
            translatedTranscript = transcript
        case .responseTextDelta(_, let delta):
            translatedTranscript.append(delta)
        case .error(let msg):
            DiagLogger.shared.log(.rtc, "ERROR from server: \(msg)")
            phase = .error(msg)
        case .sessionCreated, .sessionUpdated, .outputAudioBufferStarted, .responseDone,
             .inputAudioBufferSpeechStarted, .inputAudioBufferSpeechStopped:
            // Companion doesn't care about turn boundaries — translation flows
            // continuously and `response.done` status is informational here.
            break
        case .other(let type, _):
            DiagLogger.shared.log(.rtc, "unhandled event type: \(type)")
        }
    }
}
