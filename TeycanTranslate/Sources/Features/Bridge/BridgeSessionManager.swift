import Foundation
import Observation
import WebRTC

/// Top-level orchestrator for the Bridge tab — uses `gpt-realtime` (conversational)
/// over WebRTC. Mirrors `CompanionSessionManager` but minted with the full session
/// config (voice, instructions, VAD threshold, etc.).
@Observable
@MainActor
final class BridgeSessionManager {
    enum Phase: Equatable {
        case idle
        case starting
        case running
        case stopping
        case error(String)
    }

    /// V9 conductor-stage cycle. Independent of connection `Phase`. Drives the
    /// per-turn UI animation: idle → source listening → source done →
    /// translating → target speaking → idle. Side is resolved from the
    /// detected language of the currently-streaming utterance vs `sessionLangA`.
    enum CyclePhase: Equatable {
        case idle
        case sourceListening(side: ConductorSide)
        case sourceFinished(side: ConductorSide)
        case translating(sourceSide: ConductorSide)
        case targetSpeaking(side: ConductorSide)
    }
    enum ConductorSide: Equatable { case a, b }

    private(set) var phase: Phase = .idle
    /// V9 conductor cycle phase. Logged on every transition (search DIAG LOG
    /// for `[phase]`) so we can trace exactly when each phrase ended and when
    /// the model started generating / speaking. Use `setCyclePhase(_:)` to
    /// mutate this — direct assignment bypasses the logging.
    private(set) var cyclePhase: CyclePhase = .idle
    /// Time the current session started running. `nil` while idle. Used by
    /// BridgeView to format MM:SS timestamps on the provenance trail of each
    /// archived turn card.
    private(set) var sessionStartedAt: Date?
    /// Timestamp of the most recent `speech_stopped` — used to compute the
    /// per-turn latency surfaced as `0.6s` on each provenance trail. Cleared
    /// at the end of each turn.
    @ObservationIgnored private var lastSpeechStoppedAt: Date?
    /// Latency captured for each finalized turn, keyed by user-bubble itemID.
    /// BridgeView reads this in the turn card to draw the provenance trail.
    private(set) var latencyByItemID: [String: Int] = [:]
    private(set) var messages: [BridgeMessage] = []
    private(set) var deadline: Date?
    private(set) var inWarnWindow: Bool = false
    /// Snapshot of the configured langA/langB at session start so the side
    /// detector and assistant-language inference both stay consistent even if
    /// the user swaps mid-session.
    private var sessionLangA: String = "uk"
    private var sessionLangB: String = "es"
    /// Last detected language for the user's current turn — assistant
    /// translations for the same turn are placed on the *other* side.
    private var lastUserLang: String?
    private var transcriptProvider: BridgeTranscriptProvider = .sonioxRealtime

    private let client = RealtimeRTCClient()
    private let guard_ = CostGuard()
    private var deadlineMirrorTask: Task<Void, Never>?
    /// Per-session voice-log recorder. Streams diarized human/model entries
    /// to `/api/voice-log` so the History tab can replay sessions.
    /// `nil` while idle.
    private var voiceLog: VoiceLogRecorder?

    // Parallel Soniox STT for user-side transcripts. Spun up only when
    // `BridgeSettings.transcriptProvider == .sonioxRealtime`. In that mode,
    // OpenAI input transcription is not requested, avoiding duplicate STT
    // billing and double bubbles.
    @ObservationIgnored private let sonioxRecorder = PCMStreamRecorder()
    @ObservationIgnored private var sonioxStt: SonioxLiveSTT?
    /// Per-turn accumulator of *finalized* Soniox token text — replaces the
    /// old SlidingWindowMerger which over-appended when consecutive windows
    /// didn't share a perfect prefix (caused "Hola, ¿quieres un té? Hola,
    /// ¿quieres un té?" duplication in the bubble). Tokens are deduped via
    /// `sonioxSeenFinalKeys` before being concatenated, so re-sends of the
    /// same finalized token across consecutive Soniox windows are no-ops.
    @ObservationIgnored private var sonioxFinalTextThisTurn: String = ""
    /// Set of `(startMs):(text)` keys for finalized tokens already absorbed
    /// into `sonioxFinalTextThisTurn`. Keeps the accumulator monotonic.
    @ObservationIgnored private var sonioxSeenFinalKeys: Set<String> = []
    /// Live "preview" tail rebuilt on every Soniox recv from the non-final
    /// tokens of the latest window. Lets the bubble stream as the speaker
    /// talks, without ever persisting unfinalized text.
    @ObservationIgnored private var sonioxLiveTailThisTurn: String = ""
    @ObservationIgnored private var sonioxPumpTask: Task<Void, Never>?
    @ObservationIgnored private var sonioxActive = false
    /// Per-turn id used for the user-side bubble the current turn's
    /// transcripts (Soniox tokens OR OpenAI input-transcription deltas) write
    /// into. Bumped at the start of each user utterance (`speech_started`)
    /// and reset on the assistant's `response.done`.
    private var sonioxTurnCounter = 0
    private var currentUserItemID: String { "user-turn-\(sonioxTurnCounter)" }
    private var hasOpenUserBubble = false
    /// Tracks the most recent Soniox token delivery so we can decide whether
    /// Soniox is actively producing or has gone silent. When Soniox is
    /// configured but quiet, we let OpenAI's gpt-4o-transcribe transcripts
    /// fill the user bubble as a fallback instead of leaving it empty.
    @ObservationIgnored private var sonioxLastTokenAt: Date?
    /// When Soniox parallel was armed. During the first few seconds we
    /// optimistically claim "actively transcribing" even before the first
    /// real token batch lands — this stops the brief window where OpenAI
    /// deltas would race in and flash a sentence into the bubble that
    /// Soniox then replaces with its own.
    @ObservationIgnored private var sonioxActivatedAt: Date?
    private static let sonioxWarmupGrace: TimeInterval = 6.0
    /// Set by `response.done(completed)`, cleared by the next
    /// `input_audio_buffer.speech_started`. While this is true, Soniox's
    /// late-finalizing tokens for the closing turn continue to fill the same
    /// user bubble instead of opening a phantom new one. This is the fix for
    /// the Soniox/gpt-realtime "phantom turn" bug.
    @ObservationIgnored private var sonioxAwaitingNewTurn = false

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
                if from == "bridge", case .running = self.phase {
                    DiagLogger.shared.log(.guard_, "tab switch from bridge — auto stop")
                    self.guard_.stop(reason: .tabSwitch)
                }
            }
        }
    }

    // See note in CompanionSessionManager — observer cleanup intentionally skipped.

    func start(settings: BridgeSettings) async {
        guard case .idle = phase else { return }
        DiagLogger.shared.log(.app, "bridge: mic tap → start requested")
        phase = .starting
        messages.removeAll()
        setCyclePhase(.idle)
        latencyByItemID.removeAll()
        lastSpeechStoppedAt = nil
        sessionLangA = settings.langA.code
        sessionLangB = settings.langB.code
        lastUserLang = nil
        transcriptProvider = settings.transcriptProvider

        // Spin up the voice-log recorder. Same sessionID gets attached to
        // the WAV upload on teardown so audio + transcript stay linked.
        let recorder = VoiceLogRecorder(deviceID: RemoteLogger.shared.publicDeviceID, mode: "bridge")
        self.voiceLog = recorder
        await recorder.appendMeta(text: "session.start langA=\(settings.langA.code) langB=\(settings.langB.code) voice=\(settings.voice.rawValue) transcriptProvider=\(settings.transcriptProvider.rawValue)")
        DiagLogger.shared.log(.app, "bridge: voice-log session = \(recorder.sessionID)")

        AudioSessionConfigurator.configure(.voiceChat)
        let granted = await AudioSessionConfigurator.requestMicPermission()
        guard granted else {
            phase = .error("Microphone permission denied")
            DiagLogger.shared.log(.audio, "mic permission DENIED (bridge)")
            return
        }

        // Always rebuild the system prompt against the *current* lang
        // selector. Without this, a user that picks UK ↔ EN still hits the
        // UK/ES default prompt baked into UserDefaults from earlier sessions.
        // We only override when settings.instructions is empty or still
        // equals the previous default — a user-edited prompt is preserved.
        let defaultPromptForPair = DefaultPrompt.make(
            langA: settings.langA.code,
            langB: settings.langB.code
        )
        let instructions: String
        if settings.instructions.isEmpty
            || settings.instructions == DefaultPrompt.uaToEs
            || settings.instructions.hasPrefix("You are a live voice translator")     // v6 / v7 / v8
            || settings.instructions.hasPrefix("You are a STRICT live voice translator") // v9
            || settings.instructions.hasPrefix("You are a STRICT live voice") {
            instructions = defaultPromptForPair
        } else {
            instructions = settings.instructions
        }
        DiagLogger.shared.log(.net, "bridge: prompt for pair \(settings.langA.code)↔\(settings.langB.code), \(instructions.count) chars")

        let request = RealtimeChatSessionRequest(
            voice: settings.voice.rawValue,
            instructions: instructions,
            inputLanguage: settings.inputLanguage.rawValue,
            roomMode: settings.roomMode,
            vadThreshold: settings.vadThreshold,
            transcriptionModel: settings.transcriptProvider == .gptRealtimeWhisper
                ? BridgeTranscriptionModel.gptRealtimeWhisper.rawValue
                : nil
        )

        do {
            DiagLogger.shared.log(.net, "minting bridge client_secret (voice=\(settings.voice.rawValue), transcriptProvider=\(settings.transcriptProvider.rawValue))")
            let session = try await APIClient.shared.realtimeChatSession(request)
            DiagLogger.shared.log(.net, "bridge client_secret OK (model=\(session.model))")

            let rtcConfig = RealtimeRTCConfig(
                sdpEndpoint: Endpoints.OpenAI.calls(model: session.model),
                clientSecret: session.client_secret,
                onEvent: { [weak self] event in self?.handle(event: event) },
                onRawEvent: { raw in
                    // Most events fit in 240 chars; transcript-completed
                    // events can be 600+. Bump the prefix so the actual text
                    // we care about (`transcript` field) lands in the logs.
                    DiagLogger.shared.log(.rtc, "evt: \(raw.prefix(800))")
                },
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
            sessionStartedAt = Date()
            startDeadlineMirror()

            if settings.transcriptProvider == .sonioxRealtime {
                await startSonioxParallel(langA: settings.langA.code, langB: settings.langB.code)
            } else {
                DiagLogger.shared.log(.stt, "bridge: using OpenAI \(BridgeTranscriptionModel.gptRealtimeWhisper.rawValue) for user transcripts and voice-log")
            }
        } catch {
            DiagLogger.shared.log(.net, "bridge session start failed: \(error.localizedDescription)")
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
        // Mark voice-log end + final flush BEFORE Soniox stops (so any
        // trailing finalized tokens still land in the right session).
        let sessionIDForRecording = voiceLog?.sessionID
        if let recorder = voiceLog {
            await recorder.appendMeta(text: "session.end reason=\(reason)")
            await recorder.finish()
        }
        await stopSonioxParallel(sessionID: sessionIDForRecording)
        voiceLog = nil
        client.close()
        AudioSessionConfigurator.deactivate()
        deadline = nil
        inWarnWindow = false
        setCyclePhase(.idle)
        lastSpeechStoppedAt = nil
        sessionStartedAt = nil
        phase = .idle
    }

    // MARK: - Soniox parallel STT

    private func startSonioxParallel(langA: String, langB: String) async {
        do {
            DiagLogger.shared.log(.stt, "bridge: fetching Soniox token")
            let token = try await APIClient.shared.sttToken()
            // Don't touch the AVAudioSession here — WebRTC already set it to
            // .voiceChat for echo cancellation. PCMStreamRecorder will tap the
            // (already voice-processed) input in parallel.
            let stream = try await sonioxRecorder.start(configureSession: false)

            let stt = SonioxLiveSTT()
            self.sonioxStt = stt
            sonioxFinalTextThisTurn = ""
            sonioxLiveTailThisTurn = ""
            sonioxSeenFinalKeys.removeAll()

            try await stt.connect(
                apiKey: token,
                languageHints: [langA, langB],
                enableSpeakerDiarization: true,
                onTokens: { [weak self] tokens, window in
                    Task { @MainActor [weak self] in
                        self?.handleSonioxTokens(tokens, window: window)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        DiagLogger.shared.log(.stt, "bridge soniox error: \(error.localizedDescription)")
                        self?.sonioxActive = false
                    }
                }
            )

            sonioxActive = true
            sonioxActivatedAt = Date()
            DiagLogger.shared.log(.stt, "bridge: soniox parallel STT armed (hints=\(langA),\(langB))")

            sonioxPumpTask = Task.detached { [weak self] in
                for await chunk in stream {
                    if Task.isCancelled { break }
                    await self?.sonioxStt?.sendAudio(chunk)
                }
            }

            // Watchdog: after 4s, check whether the mic actually produced any
            // PCM chunks. If not, AVAudioEngine is alive-but-starved — most
            // likely WebRTC has exclusive control of the input bus on this
            // device. We log it loudly so the agent reading server logs
            // knows OpenAI's gpt-4o-transcribe is what's actually serving
            // the user bubbles, not Soniox.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let self else { return }
                guard self.sonioxActive else { return }
                let chunks = self.sonioxRecorder.chunksProduced
                if chunks == 0 {
                    DiagLogger.shared.log(.stt, "bridge: WATCHDOG — Soniox armed but 0 PCM chunks after 4s. AVAudioEngine likely conflicting with WebRTC mic. Bubbles will be filled by OpenAI gpt-4o-transcribe, NOT Soniox.")
                } else {
                    DiagLogger.shared.log(.stt, "bridge: WATCHDOG ok — \(chunks) PCM chunks produced after 4s, Soniox path live.")
                }
            }
        } catch {
            DiagLogger.shared.log(.stt, "bridge: soniox parallel start FAILED — \(error.localizedDescription). Falling back to OpenAI transcription.")
            sonioxActive = false
            sonioxPumpTask?.cancel(); sonioxPumpTask = nil
            sonioxRecorder.stop()
            sonioxStt = nil
        }
    }

    private func stopSonioxParallel(sessionID: String? = nil) async {
        guard sonioxActive || sonioxStt != nil else { return }
        sonioxPumpTask?.cancel(); sonioxPumpTask = nil
        sonioxRecorder.stop()
        await sonioxStt?.finishAndClose()
        sonioxStt = nil
        sonioxActive = false

        // Flush captured PCM to a WAV file and ship it to the backend archive
        // for offline Gemini + Soniox-async transcription comparison. When a
        // voice-log session ID is supplied, the file is saved as
        // `{sessionID}.wav` on the server so the History tab can link it.
        let filenameBase = sessionID ?? "bridge-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-"))"
        if let wavURL = sonioxRecorder.writeCapturedWAV(filename: "\(filenameBase).wav") {
            let deviceID = RemoteLogger.shared.publicDeviceID
            let capturedSessionID = sessionID
            Task.detached(priority: .background) {
                do {
                    let body = try await APIClient.shared.uploadRecording(
                        wavURL: wavURL,
                        deviceID: deviceID,
                        label: "bridge",
                        sessionID: capturedSessionID
                    )
                    DiagLogger.shared.log(.net, "bridge WAV uploaded: \(body.prefix(160))")
                } catch {
                    DiagLogger.shared.log(.net, "bridge WAV upload failed: \(error.localizedDescription)")
                }
                try? FileManager.default.removeItem(at: wavURL)
            }
        }
        sonioxRecorder.clearCapture()

        sonioxFinalTextThisTurn = ""
        sonioxLiveTailThisTurn = ""
        sonioxSeenFinalKeys.removeAll()
        sonioxTurnCounter = 0
        sonioxLastTokenAt = nil
        sonioxActivatedAt = nil
        sonioxAwaitingNewTurn = false
    }

    private func handleSonioxTokens(_ tokens: [SonioxLiveSTT.Token], window: String) {
        // Two outputs from one Soniox batch:
        //   1. Finalized tokens → voice log (grouped by speaker, one entry
        //      per contiguous run) + appended to the per-turn final text.
        //   2. Non-final tokens → live "preview" tail concatenated fresh
        //      from THIS batch only (overwritten each recv).
        // Bubble text = finalized accumulator + live tail. No sliding-window
        // overlap detection, no chance of duplication.
        let wasSilent = sonioxLastTokenAt == nil
        sonioxLastTokenAt = Date()

        // --- 1. Absorb new finalized tokens (dedupe by start_ms + text) ---
        var newlyFinalForLog: [(speaker: String?, lang: String?, text: String)] = []
        for t in tokens where t.isFinal {
            let key = "\(t.startMs ?? -1):\(t.text)"
            guard !sonioxSeenFinalKeys.contains(key) else { continue }
            sonioxSeenFinalKeys.insert(key)
            sonioxFinalTextThisTurn += t.text
            // Group consecutive same-speaker/same-lang finals into one
            // voice-log entry so an utterance lands as one line.
            if var last = newlyFinalForLog.last,
               last.speaker == t.speaker,
               (last.lang == t.language || t.language == nil) {
                last.text += t.text
                newlyFinalForLog[newlyFinalForLog.count - 1] = last
            } else {
                newlyFinalForLog.append((t.speaker, t.language, t.text))
            }
        }
        if let recorder = voiceLog {
            for g in newlyFinalForLog {
                let trimmed = g.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let speakerLabel = g.speaker.map { "S\($0)" }
                let lang = g.lang
                DiagLogger.shared.log(.stt, "[voice-log] human \(speakerLabel ?? "?") lang=\(lang ?? "?"): \"\(short(trimmed, limit: 80))\"")
                Task { await recorder.appendHuman(text: trimmed, speaker: speakerLabel, lang: lang) }
            }
        }

        // --- 2. Live tail from non-final tokens in THIS batch only ---
        sonioxLiveTailThisTurn = tokens
            .filter { !$0.isFinal }
            .map { $0.text }
            .joined()

        let bubbleText = (sonioxFinalTextThisTurn + sonioxLiveTailThisTurn)
            .trimmingCharacters(in: .whitespaces)
        guard !bubbleText.isEmpty else { return }

        let finalsCount = tokens.filter { $0.isFinal }.count
        let prefix = wasSilent ? "[stt] FIRST batch" : "[stt] batch"
        DiagLogger.shared.log(.stt, "\(prefix) turn#\(sonioxTurnCounter): \(tokens.count) tokens (\(finalsCount) final) final=\(sonioxFinalTextThisTurn.count) live=\(sonioxLiveTailThisTurn.count) → \"\(short(bubbleText, limit: 60))\"")
        openUserBubble()
        replaceMessage(role: .user, itemID: currentUserItemID, text: bubbleText)
    }

    /// Resolve which conductor side (A/B) a language code maps to. Cyclephase
    /// uses this to know which endpoint pill to animate. Defaults to .a when
    /// the language is unknown so the UI never freezes between phases.
    private func side(forLang lang: String?) -> ConductorSide {
        guard let lang else { return .a }
        return lang == sessionLangA ? .a : .b
    }

    /// Tracks wall-clock time of the previous phase transition so we can log
    /// the elapsed delta — useful for spotting "model thinking" duration
    /// without doing math across log lines.
    @ObservationIgnored private var lastPhaseChangeAt: Date?

    /// All cyclePhase mutations go through here so we get a single DIAG LOG
    /// entry per transition. Skips logging if the new phase equals the old
    /// (idempotent re-set from a stream of identical events). Each entry
    /// includes the ms elapsed since the previous transition so the time
    /// budget of each phase is visible at-a-glance in the log.
    private func setCyclePhase(_ next: CyclePhase) {
        guard next != cyclePhase else { return }
        let now = Date()
        let deltaMs: Int
        if let prev = lastPhaseChangeAt {
            deltaMs = Int(now.timeIntervalSince(prev) * 1000)
        } else {
            deltaMs = 0
        }
        DiagLogger.shared.log(.rtc, "[phase] \(describe(cyclePhase)) → \(describe(next)) (+\(deltaMs)ms)")
        lastPhaseChangeAt = now
        cyclePhase = next
    }

    private func describe(_ p: CyclePhase) -> String {
        switch p {
        case .idle: return "idle"
        case .sourceListening(let s): return "sourceListening(\(s == .a ? "A" : "B"))"
        case .sourceFinished(let s):  return "sourceFinished(\(s == .a ? "A" : "B"))"
        case .translating(let s):     return "translating(src=\(s == .a ? "A" : "B"))"
        case .targetSpeaking(let s):  return "targetSpeaking(\(s == .a ? "A" : "B"))"
        }
    }

    /// Truncate a streaming text fragment so log lines stay readable. Used
    /// for per-delta `[in.delta]` / `[out.delta]` entries that would otherwise
    /// flood DIAG LOG with full sentences on each token batch.
    private func short(_ text: String, limit: Int = 40) -> String {
        let s = text.replacingOccurrences(of: "\n", with: " ")
        if s.count <= limit { return s }
        return String(s.prefix(limit)) + "…"
    }

    /// Emit a single human-readable summary line at the end of each completed
    /// turn: `[turn] #N UA→ES 1.2s "src…" → "tgt…"`. Designed so grepping the
    /// log for `[turn]` reproduces the entire conversation flow.
    private func logTurnSummary() {
        // Find the user + assistant messages of this turn. The user message is
        // identified by the current item ID; assistant is whichever assistant
        // bubble has matching language vs the user's detected lang.
        let userText = messages.last(where: { $0.id == currentUserItemID })?.text ?? ""
        let userLang = lastUserLang ?? sessionLangA
        let targetLang = (userLang == sessionLangA) ? sessionLangB : sessionLangA
        // Last finalized assistant message (since this is fired on response.done).
        let assistantText = messages.last(where: { $0.role == .assistant && $0.isFinalized })?.text ?? ""
        let latency = latencyByItemID[currentUserItemID] ?? 0
        let latencyStr = latency >= 1000 ? String(format: "%.1fs", Double(latency) / 1000.0) : "\(latency)ms"
        let line = "[turn] #\(sonioxTurnCounter) \(userLang.uppercased())→\(targetLang.uppercased()) \(latencyStr) \"\(short(userText))\" → \"\(short(assistantText))\""
        DiagLogger.shared.log(.rtc, line)
    }
    /// Current source side. While the user is mid-utterance we only know the
    /// language post-hoc (from Soniox/openai partials), so we fall back to the
    /// last detected user language. First-ever turn defaults to side A.
    private func currentSourceSide() -> ConductorSide { side(forLang: lastUserLang) }
    private func oppositeSide(_ side: ConductorSide) -> ConductorSide { side == .a ? .b : .a }

    /// B1 fix: after `lastUserLang` changes (e.g. Soniox/openai detects the
    /// actual user language), re-align the cyclePhase side if it disagrees.
    /// The first `speech_started` always opens with `.sourceListening(.a)`
    /// because `lastUserLang` is nil — without this reconciliation the pill
    /// would flash A then visibly flip to B once the first delta arrives.
    private func reconcileCyclePhaseWithLastUserLang() {
        let target = currentSourceSide()
        switch cyclePhase {
        case .sourceListening(let s) where s != target:
            setCyclePhase(.sourceListening(side: target))
        case .sourceFinished(let s) where s != target:
            setCyclePhase(.sourceFinished(side: target))
        case .translating(let s) where s != target:
            setCyclePhase(.translating(sourceSide: target))
        default:
            break
        }
    }

    private func handle(event: RealtimeEvent) {
        switch event {
        case .inputAudioBufferSpeechStarted:
            // If the previous turn's response just completed and we deferred
            // committing the turn boundary, commit it NOW. Late-finalizing
            // Soniox tokens for the closing turn keep flowing into its bubble
            // until this moment; once a new turn opens we reset the per-turn
            // accumulators so the new bubble starts empty.
            if sonioxAwaitingNewTurn {
                sonioxAwaitingNewTurn = false
                sonioxTurnCounter += 1
                // Reset per-turn Soniox accumulator state so a brand-new
                // bubble starts from empty — no carry-over from previous
                // turn's final tokens.
                sonioxFinalTextThisTurn = ""
                sonioxLiveTailThisTurn = ""
                sonioxSeenFinalKeys.removeAll()
                hasOpenUserBubble = false
                DiagLogger.shared.log(.stt, "bridge: turn boundary committed on speech_started — now in turn #\(sonioxTurnCounter)")
            }
            setCyclePhase(.sourceListening(side: currentSourceSide()))
            // Reserve the user bubble for the current turn before the
            // assistant starts streaming its translation.
            openUserBubble()

        case .inputAudioBufferSpeechStopped:
            lastSpeechStoppedAt = Date()
            setCyclePhase(.sourceFinished(side: currentSourceSide()))

        case .inputTranscriptDelta(_, let delta):
            // Suppress only while Soniox is genuinely producing tokens
            // (last 2s). If Soniox went silent — fall back to OpenAI's
            // gpt-4o-transcribe deltas filling the same bubble.
            if sonioxActivelyTranscribing {
                DiagLogger.shared.log(.rtc, "[in.delta] suppressed (soniox active): \"\(short(delta))\"")
                break
            }
            DiagLogger.shared.log(.rtc, "[in.delta] turn#\(sonioxTurnCounter) openai → bubble: \"\(short(delta))\"")
            openUserBubble()
            appendDelta(role: .user, itemID: currentUserItemID, delta: delta)
        case .inputTranscriptCompleted(_, let transcript):
            // Always log the FULL transcript text so we can read what
            // OpenAI's input transcription heard.
            DiagLogger.shared.log(.rtc, "bridge: openai INPUT TEXT (\(transcript.count) chars) → \"\(transcript)\"")
            if sonioxActivelyTranscribing {
                DiagLogger.shared.log(.rtc, "bridge: ignoring openai input completed — soniox active")
                break
            }
            openUserBubble()
            replaceMessage(role: .user, itemID: currentUserItemID, text: transcript)
            if transcriptProvider == .gptRealtimeWhisper,
               let recorder = voiceLog {
                let lang = BridgeLanguageGuesser.guess(text: transcript, langA: sessionLangA, langB: sessionLangB)
                DiagLogger.shared.log(.stt, "[voice-log] human OpenAI lang=\(lang): \"\(short(transcript, limit: 80))\"")
                Task { await recorder.appendHuman(text: transcript, speaker: "OpenAI", lang: lang) }
            }
        case .outputTranscriptDelta(let id, let delta), .responseTextDelta(let id, let delta):
            // First model delta after speech_stopped → transition to .translating.
            // We only flip if we were in .sourceFinished; any other state means
            // a streaming response that's already past the "thinking" phase.
            if case .sourceFinished(let src) = cyclePhase {
                if let stoppedAt = lastSpeechStoppedAt {
                    let firstTokenMs = Int(Date().timeIntervalSince(stoppedAt) * 1000)
                    DiagLogger.shared.log(.rtc, "[out.first] turn#\(sonioxTurnCounter) first model delta after speech_stopped: +\(firstTokenMs)ms")
                }
                setCyclePhase(.translating(sourceSide: src))
            }
            DiagLogger.shared.log(.rtc, "[out.delta] turn#\(sonioxTurnCounter): \"\(short(delta))\"")
            appendDelta(role: .assistant, itemID: id ?? "asst-stream", delta: delta)
        case .outputTranscriptDone(let id, let transcript):
            DiagLogger.shared.log(.rtc, "bridge: model OUTPUT TEXT (\(transcript.count) chars) → \"\(transcript)\"")
            replaceMessage(role: .assistant, itemID: id ?? "asst-stream", text: transcript)
            // Model side of the voice log — language is whatever the user
            // wasn't talking in (since we translate to the opposite side).
            let modelLang = (lastUserLang ?? sessionLangA) == sessionLangA ? sessionLangB : sessionLangA
            if let recorder = voiceLog {
                Task { await recorder.appendModel(text: transcript, lang: modelLang) }
            }
        case .error(let msg):
            DiagLogger.shared.log(.rtc, "ERROR (bridge): \(msg)")
            phase = .error(msg)
        case .responseDone(let status):
            // Only treat *completed* responses as turn-end signals. A
            // cancelled response means the user resumed speaking before the
            // assistant finished — keep the current bubble and don't even
            // mark the turn as closing.
            guard status == "completed" else {
                DiagLogger.shared.log(.stt, "bridge: response.done(\(status)) — keeping turn #\(sonioxTurnCounter)")
                // B2 fix: if cancel fires while we're mid-cycle (translating
                // or targetSpeaking), the conductor stage would otherwise
                // remain animating the target side until the next speech_started.
                // Reset to .idle so the UI visibly settles. The user's next
                // speech_started will reopen with .sourceListening.
                switch cyclePhase {
                case .translating, .targetSpeaking:
                    setCyclePhase(.idle)
                default:
                    break
                }
                break
            }
            // Compute per-turn latency: time from speech_stopped → response.done.
            // Stored under the user-bubble's item ID so BridgeView can render
            // it in the provenance trail of the matching turn pair.
            if let startedAt = lastSpeechStoppedAt {
                let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
                latencyByItemID[currentUserItemID] = ms
                DiagLogger.shared.log(.rtc, "bridge: turn #\(sonioxTurnCounter) latency=\(ms)ms")
            }
            // Per-turn summary line — single readable record of what happened
            // this turn: who spoke, in which direction, the latency, and the
            // first 40 chars of source + target text. Easy to grep for `[turn]`
            // to read the whole conversation flow at a glance.
            logTurnSummary()
            lastSpeechStoppedAt = nil
            setCyclePhase(.idle)
            // DEFER the turn boundary until the user actually speaks again.
            // Soniox's `is_final: true` tokens for this turn's audio can
            // arrive 1–5 s AFTER response.done. If we close the turn now,
            // those late finalizations open a phantom new bubble with the
            // trailing tail of the previous turn's text. Wait for the next
            // `input_audio_buffer.speech_started` instead.
            sonioxAwaitingNewTurn = true
            DiagLogger.shared.log(.stt, "bridge: response.done(completed) — turn #\(sonioxTurnCounter) closing, awaiting next speech_started before committing")
        case .outputAudioBufferStarted:
            // M's voice is now playing through the speaker — switch the conductor
            // stage to .targetSpeaking on the opposite side. This is the event
            // that was previously parsed but discarded (was `break` in the
            // composite case below). Per CyclePhase semantics: target side is
            // whichever side is NOT the source.
            if let stoppedAt = lastSpeechStoppedAt {
                let audioStartMs = Int(Date().timeIntervalSince(stoppedAt) * 1000)
                DiagLogger.shared.log(.rtc, "[out.audio] turn#\(sonioxTurnCounter) audio_buffer.started (speech_stopped → audio: +\(audioStartMs)ms)")
            }
            let src: ConductorSide = {
                switch cyclePhase {
                case .translating(let s): return s
                case .sourceFinished(let s): return s
                case .sourceListening(let s): return s
                case .targetSpeaking(let s): return oppositeSide(s)
                case .idle: return currentSourceSide()
                }
            }()
            setCyclePhase(.targetSpeaking(side: oppositeSide(src)))
        case .sessionCreated, .sessionUpdated:
            break
        case .other(let type, _):
            DiagLogger.shared.log(.rtc, "unhandled (bridge): \(type)")
        }
    }

    /// Soniox is "active" means the recorder + WS are armed; "actively
    /// transcribing" means either (a) we're in the warm-up grace window
    /// after arming, or (b) Soniox produced a real token in the last 4s.
    /// The warm-up grace stops OpenAI deltas from racing into the very first
    /// bubble before Soniox emits its first token (~300ms typical latency).
    /// After the grace expires, the lastTokenAt check ensures we fall back
    /// to OpenAI if AVAudioEngine starves silently.
    private var sonioxActivelyTranscribing: Bool {
        guard sonioxActive else { return false }
        if let armedAt = sonioxActivatedAt,
           Date().timeIntervalSince(armedAt) < Self.sonioxWarmupGrace {
            return true
        }
        guard let last = sonioxLastTokenAt else { return false }
        return Date().timeIntervalSince(last) < 4.0
    }

    private func openUserBubble() {
        guard !hasOpenUserBubble else { return }
        messages.append(BridgeMessage(id: currentUserItemID, role: .user, text: "", isFinalized: false, language: nil))
        hasOpenUserBubble = true
        DiagLogger.shared.log(.app, "UI: opened empty user bubble id=\(currentUserItemID) (turn #\(sonioxTurnCounter))")
    }

    private func appendDelta(role: BridgeMessage.Role, itemID: String, delta: String) {
        if let idx = messages.lastIndex(where: { $0.id == itemID }) {
            messages[idx].text.append(delta)
            messages[idx].isFinalized = false
            updateLanguage(messageIndex: idx)
        } else {
            var msg = BridgeMessage(id: itemID, role: role, text: delta, isFinalized: false, language: nil)
            // Detect language right away so the bubble lands on the right side
            // even before the first delta finalizes.
            if role == .user {
                msg.language = BridgeLanguageGuesser.guess(text: delta, langA: sessionLangA, langB: sessionLangB)
                if !delta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lastUserLang = msg.language
                    reconcileCyclePhaseWithLastUserLang()
                }
            } else {
                msg.language = assistantLanguage(for: delta)
            }
            messages.append(msg)
        }
    }

    /// Refresh the detected language on a streaming message — short prefixes
    /// can mis-guess (e.g. a single English-looking word that turns out to be
    /// part of a Ukrainian phrase). Re-running the guesser as more text
    /// arrives lets the bubble settle on the correct side.
    private func updateLanguage(messageIndex idx: Int) {
        let msg = messages[idx]
        let detected: String
        var userLangChanged = false
        if msg.role == .user {
            detected = BridgeLanguageGuesser.guess(text: msg.text, langA: sessionLangA, langB: sessionLangB)
            if !msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if lastUserLang != detected {
                    lastUserLang = detected
                    userLangChanged = true
                }
            }
        } else {
            detected = assistantLanguage(for: msg.text)
        }
        if messages[idx].language != detected {
            messages[idx].language = detected
        }
        if userLangChanged { reconcileCyclePhaseWithLastUserLang() }
    }

    /// Assistant's translation lives on the opposite side of the user's
    /// current turn. If we haven't seen the user's language yet, fall back to
    /// detecting from the assistant's own text — useful for the very first
    /// frame of audio where the assistant starts streaming before
    /// `input_audio_buffer.speech_started` resolves.
    private func assistantLanguage(for text: String) -> String {
        if let lang = lastUserLang {
            return (lang == sessionLangA) ? sessionLangB : sessionLangA
        }
        return BridgeLanguageGuesser.guess(text: text, langA: sessionLangA, langB: sessionLangB)
    }

    private func replaceMessage(role: BridgeMessage.Role, itemID: String, text: String) {
        if let idx = messages.lastIndex(where: { $0.id == itemID }) {
            messages[idx].text = text
            messages[idx].isFinalized = true
            updateLanguage(messageIndex: idx)
        } else {
            var msg = BridgeMessage(id: itemID, role: role, text: text, isFinalized: true, language: nil)
            if role == .user {
                msg.language = BridgeLanguageGuesser.guess(text: text, langA: sessionLangA, langB: sessionLangB)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lastUserLang = msg.language
                    reconcileCyclePhaseWithLastUserLang()
                }
            } else {
                msg.language = assistantLanguage(for: text)
            }
            messages.append(msg)
        }
    }
}
