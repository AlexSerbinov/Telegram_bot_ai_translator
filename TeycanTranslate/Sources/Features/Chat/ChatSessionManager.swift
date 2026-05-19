import Foundation
import Observation
import WebRTC

/// Top-level session orchestrator for the Chat tab — uses `gpt-realtime`
/// (conversational, NOT translate) over WebRTC with NO system prompt.
/// The model talks to the user as a generic voice assistant.
///
/// Reuses the same backend endpoint as Bridge (`/api/realtime-chat/session`)
/// but with empty `instructions`. Server-side VAD (`server_vad`) handles
/// turn-taking automatically.
@Observable
@MainActor
final class ChatSessionManager {
    enum Phase: Equatable {
        case idle
        case starting
        case running
        case stopping
        case error(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var messages: [ChatMessage] = []
    private(set) var deadline: Date?
    private(set) var inWarnWindow: Bool = false

    private let client = RealtimeRTCClient()
    private let guard_ = CostGuard()
    private var deadlineMirrorTask: Task<Void, Never>?

    /// Per-turn counter so each new user utterance opens a fresh bubble id.
    /// Bumped at `input_audio_buffer.speech_started`.
    private var userTurnCounter = 0
    private var currentUserItemID: String { "chat-user-\(userTurnCounter)" }
    private var hasOpenUserBubble = false
    /// Wall-clock time of the most recent `speech_stopped` — used to log
    /// per-turn latency (speech_stopped → response.done).
    private var lastSpeechStoppedAt: Date?

    @ObservationIgnored
    private var tabObserver: NSObjectProtocol?

    init() {
        guard_.isLeakedNow = { [weak self] in self?.client.isLive ?? false }
        guard_.onWarn = { [weak self] in self?.inWarnWindow = true }
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
                if from == "chat", case .running = self.phase {
                    DiagLogger.shared.log(.guard_, "tab switch from chat — auto stop")
                    self.guard_.stop(reason: .tabSwitch)
                }
            }
        }
    }

    func start() async {
        guard case .idle = phase else { return }
        DiagLogger.shared.log(.app, "chat: mic tap → start requested")
        phase = .starting
        messages.removeAll()
        userTurnCounter = 0
        hasOpenUserBubble = false
        lastSpeechStoppedAt = nil

        AudioSessionConfigurator.configure(.voiceChat)
        let granted = await AudioSessionConfigurator.requestMicPermission()
        guard granted else {
            phase = .error("Microphone permission denied")
            DiagLogger.shared.log(.audio, "mic permission DENIED (chat)")
            return
        }

        // Empty instructions = no system prompt. Lets gpt-realtime behave as a
        // generic voice assistant. Voice/VAD defaults mirror Bridge.
        let request = RealtimeChatSessionRequest(
            voice: "marin",
            instructions: "",
            inputLanguage: "",
            roomMode: false,
            vadThreshold: 0.5,
            transcriptionModel: "gpt-4o-transcribe"
        )

        do {
            DiagLogger.shared.log(.net, "minting chat client_secret (no prompt)")
            let session = try await APIClient.shared.realtimeChatSession(request)
            DiagLogger.shared.log(.net, "chat client_secret OK (model=\(session.model))")

            let rtcConfig = RealtimeRTCConfig(
                sdpEndpoint: Endpoints.OpenAI.calls(model: session.model),
                clientSecret: session.client_secret,
                onEvent: { [weak self] event in self?.handle(event: event) },
                onRawEvent: { raw in DiagLogger.shared.log(.rtc, "evt: \(raw.prefix(300))") },
                onConnectionState: { [weak self] state in
                    if state == .failed || state == .closed {
                        Task { @MainActor [weak self] in
                            self?.guard_.stop(reason: state == .failed ? .pcFailed : .pcClosed)
                        }
                    }
                }
            )

            try await client.connect(config: rtcConfig)
            guard_.start()
            phase = .running
            startDeadlineMirror()
        } catch {
            DiagLogger.shared.log(.net, "chat session start failed: \(error.localizedDescription)")
            phase = .error(error.localizedDescription)
            await tearDown(reason: "start-failed")
        }
    }

    func stop() async {
        DiagLogger.shared.log(.app, "chat: mic tap → stop requested")
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
        case .inputAudioBufferSpeechStarted:
            userTurnCounter += 1
            hasOpenUserBubble = false
            DiagLogger.shared.log(.rtc, "chat: speech_started → turn #\(userTurnCounter)")
            openUserBubble()
        case .inputAudioBufferSpeechStopped:
            lastSpeechStoppedAt = Date()
            DiagLogger.shared.log(.rtc, "chat: speech_stopped (turn #\(userTurnCounter))")

        case .inputTranscriptDelta(_, let delta):
            DiagLogger.shared.log(.rtc, "[chat.in.delta] turn#\(userTurnCounter): \"\(short(delta))\"")
            openUserBubble()
            appendDelta(role: .user, itemID: currentUserItemID, delta: delta)
        case .inputTranscriptCompleted(_, let transcript):
            DiagLogger.shared.log(.rtc, "[chat.in.done] turn#\(userTurnCounter) (\(transcript.count) chars): \"\(transcript)\"")
            openUserBubble()
            replaceMessage(role: .user, itemID: currentUserItemID, text: transcript)

        case .outputTranscriptDelta(let id, let delta),
             .responseTextDelta(let id, let delta):
            DiagLogger.shared.log(.rtc, "[chat.out.delta] turn#\(userTurnCounter): \"\(short(delta))\"")
            appendDelta(role: .assistant, itemID: id ?? "chat-asst-stream", delta: delta)
        case .outputTranscriptDone(let id, let transcript):
            DiagLogger.shared.log(.rtc, "[chat.out.done] turn#\(userTurnCounter) (\(transcript.count) chars): \"\(transcript)\"")
            replaceMessage(role: .assistant, itemID: id ?? "chat-asst-stream", text: transcript)

        case .error(let msg):
            DiagLogger.shared.log(.rtc, "ERROR (chat): \(msg)")
            phase = .error(msg)

        case .responseDone(let status):
            if let stoppedAt = lastSpeechStoppedAt {
                let ms = Int(Date().timeIntervalSince(stoppedAt) * 1000)
                DiagLogger.shared.log(.rtc, "[chat.turn] #\(userTurnCounter) latency=\(ms)ms status=\(status)")
            } else {
                DiagLogger.shared.log(.rtc, "[chat.turn] #\(userTurnCounter) status=\(status)")
            }
            lastSpeechStoppedAt = nil
        case .outputAudioBufferStarted:
            if let stoppedAt = lastSpeechStoppedAt {
                let firstAudioMs = Int(Date().timeIntervalSince(stoppedAt) * 1000)
                DiagLogger.shared.log(.rtc, "[chat.audio] turn#\(userTurnCounter) first audio +\(firstAudioMs)ms after speech_stopped")
            }
        case .sessionCreated:
            DiagLogger.shared.log(.rtc, "chat: session.created")
        case .sessionUpdated:
            break

        case .other(let type, _):
            DiagLogger.shared.log(.rtc, "unhandled (chat): \(type)")
        }
    }

    /// Truncate a streaming text fragment so log lines stay readable.
    private func short(_ text: String, limit: Int = 60) -> String {
        let s = text.replacingOccurrences(of: "\n", with: " ")
        if s.count <= limit { return s }
        return String(s.prefix(limit)) + "…"
    }

    private func openUserBubble() {
        guard !hasOpenUserBubble else { return }
        messages.append(ChatMessage(id: currentUserItemID, role: .user, text: "", isFinalized: false))
        hasOpenUserBubble = true
    }

    private func appendDelta(role: ChatMessage.Role, itemID: String, delta: String) {
        if let idx = messages.lastIndex(where: { $0.id == itemID }) {
            messages[idx].text.append(delta)
            messages[idx].isFinalized = false
        } else {
            messages.append(ChatMessage(id: itemID, role: role, text: delta, isFinalized: false))
        }
    }

    private func replaceMessage(role: ChatMessage.Role, itemID: String, text: String) {
        if let idx = messages.lastIndex(where: { $0.id == itemID }) {
            messages[idx].text = text
            messages[idx].isFinalized = true
        } else {
            messages.append(ChatMessage(id: itemID, role: role, text: text, isFinalized: true))
        }
    }
}
