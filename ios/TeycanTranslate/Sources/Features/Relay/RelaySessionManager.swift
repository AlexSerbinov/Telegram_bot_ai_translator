import Foundation
import Observation

/// Orchestrates the full Relay pipeline:
///   mic → Soniox STT WS → `RelayDirectionResolver`
///        → (on idle timer or user stop) commit per-turn
///        → `/api/translate-fast` (Groq, dynamic from/to)
///        → `/api/tts?provider=soniox` (WAV bytes)
///        → `MP3Player` (handles WAV via AVAudioPlayer)
///
/// Continuous listening like Bridge, but with no OpenAI in the loop. Direction
/// is auto-detected per turn from Soniox's per-token `language` field; no
/// system prompt, no WebRTC. Voice-log + recording flow mirror Bridge so the
/// session shows up in History with a `relay` mode badge.
@Observable
@MainActor
final class RelaySessionManager {
    enum Phase: Equatable {
        case idle
        case starting
        case listening
        case translating
        case speaking
        case error(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var messages: [RelayMessage] = []
    private(set) var deadline: Date?
    private(set) var inWarnWindow = false
    /// Live detected language during the current turn — drives the
    /// "(detected: UK)" eyebrow that updates as the user talks.
    private(set) var detectedLang: String?
    /// Non-nil when either TTS provider is unhealthy — populated at
    /// session start via `/api/tts-quota` AND from any 4xx error parsed
    /// out of a live TTS call. RelayView renders this as a dismissable
    /// banner above the chat.
    private(set) var quotaWarning: String?

    @ObservationIgnored private let recorder = PCMStreamRecorder()
    @ObservationIgnored private let player = MP3Player()
    @ObservationIgnored private let guard_ = CostGuard()
    @ObservationIgnored private var stt: SonioxLiveSTT?
    @ObservationIgnored private var resolver: RelayDirectionResolver?
    @ObservationIgnored private var voiceLog: VoiceLogRecorder?

    @ObservationIgnored private var pumpTask: Task<Void, Never>?
    @ObservationIgnored private var idleTimerTask: Task<Void, Never>?
    @ObservationIgnored private var deadlineMirrorTask: Task<Void, Never>?

    @ObservationIgnored private var sessionLangA: String = "uk"
    @ObservationIgnored private var sessionLangB: String = "es"
    @ObservationIgnored private var turnID: Int = 0
    @ObservationIgnored private var hasFinalForCurrentTurn = false
    @ObservationIgnored private var finalTextThisTurn: String = ""
    @ObservationIgnored private var liveTail: String = ""
    @ObservationIgnored private var seenFinalKeys: Set<String> = []
    /// Set while a translate/TTS round-trip is in flight. Stops the idle
    /// timer from queuing a second commit for tokens that arrive during
    /// playback.
    @ObservationIgnored private var commitInFlight = false
    /// Resumed once the current in-flight turn fully finishes (including TTS
    /// playback). `stop()` `await`s this so the last utterance doesn't get
    /// cut off mid-word when the user taps the mic again.
    @ObservationIgnored private var pendingStopContinuation: CheckedContinuation<Void, Never>?

    @ObservationIgnored private var tabObserver: NSObjectProtocol?

    /// Soniox sends heartbeat batches with empty `tokens` arrays every ~1s
    /// during silence (just to surface `final_audio_proc_ms`). If we let
    /// those reset the idle-commit timer, it would never fire — the user
    /// could pause forever and we'd just keep heartbeating. So we only
    /// schedule the idle timer on batches that contain real tokens.
    ///
    /// Default idle-commit window when no completeness score has come back
    /// yet for this turn. 1.0s + Soniox's own ~1-1.5s finalization lag
    /// ≈ 2-2.5s perceived end-of-utterance latency — the trade-off the
    /// user picked: snappier commits, accept a small bump in occasional
    /// mid-sentence cuts (the "Done speaking" button is the manual override
    /// when adaptive timing gets it wrong).
    private static let idleCommitSeconds: Double = 1.0

    /// TTS provider — read fresh from UserDefaults at each commit, so the
    /// user can toggle ElevenLabs ↔ Soniox in `RelaySettingsSheet` and
    /// the next turn picks it up without restarting the session.
    /// ElevenLabs is significantly snappier (~75ms first byte for Flash v2.5
    /// vs ~5s round-trip for Soniox), so it's the default.
    private var ttsProvider: String {
        UserDefaults.standard.string(forKey: Preferences.K.relayTtsProvider) ?? "elevenlabs"
    }
    /// Model param scoped to the active provider. Soniox uses its built-in
    /// `tts-rt-v1` server-side, so we don't pin a model from the client.
    private var ttsModel: String? {
        switch ttsProvider {
        case "elevenlabs": return "eleven_flash_v2_5"
        default:           return nil
        }
    }
    /// Streaming pipe is available server-side but disabled for now —
    /// AVAudioPlayer needs the full MP3 anyway, so the only win would be
    /// server-side latency. Toggle to `true` later if we move to AVPlayer
    /// streaming on the client.
    private static let ttsStream: Bool = false

    /// Number of mic chunks dropped while STT was closed for TTS — useful
    /// for spotting echo-loop avoidance in logs ("dropped 47 chunks during
    /// playback"). We deliberately drop them rather than buffer + replay,
    /// because buffered chunks captured ALSO contain TTS playback bleeding
    /// into the mic, which Soniox happily transcribes back as a fresh user
    /// turn — and that's the classic translator-on-speaker feedback loop.
    @ObservationIgnored private var droppedDuringPlayback: Int = 0

    /// Latest Groq oss-20b "is this utterance complete" score 0.0–1.0,
    /// updated asynchronously after each batch of new final tokens.
    /// Drives `idleTimeoutForCurrentScore()` — high score → short wait,
    /// low → long wait. Resets to 0 at the start of each new turn.
    @ObservationIgnored private var lastCompletenessScore: Double = 0
    /// In-flight completeness query — at most one outstanding per turn.
    /// New token batches that arrive while a query is in flight wait for
    /// it to settle before kicking off a new one (debounce).
    @ObservationIgnored private var completenessTask: Task<Void, Never>?

    /// Mid-turn split tracking — used to break a single Soniox stream
    /// into multiple Relay turns when:
    ///   (A) Speaker diarization reports a different `speaker_id` for
    ///       ≥3 consecutive finalized tokens (different person started
    ///       talking), OR
    ///   (D) A different language streak runs for ≥3 consecutive finals
    ///       within {langA, langB} (single speaker code-switched, OR
    ///       diarization didn't disambiguate two close-timbre speakers).
    ///
    /// When a split fires we roll back the trailing N "wrong-side"
    /// tokens off the resolver + finalTextThisTurn, stash them in
    /// `pendingFinalsForNextTurn`, then call `commitNow()` so the OLD
    /// portion translates as its own turn. After `commitTurn()` finishes
    /// (resetTurnState already ran), we re-feed the stashed tokens via
    /// `handleSttTokens` so they form the start of the NEXT turn cleanly.
    @ObservationIgnored private var turnSpeakerID: String?
    @ObservationIgnored private var otherSpeakerStreak: Int = 0
    @ObservationIgnored private var turnDominantLang: String?
    @ObservationIgnored private var otherLangStreak: Int = 0
    @ObservationIgnored private var pendingFinalsForNextTurn: [SonioxLiveSTT.Token] = []
    /// Mirror of every finalized token absorbed this turn, in order. Kept
    /// alongside `RelayDirectionResolver.finalTokens` because the resolver
    /// only stores `(text, lang)` while we need the full `Token` for re-
    /// feed on split (it carries `speaker`, `startMs`, `isFinal`).
    @ObservationIgnored private var turnFinalTokens: [SonioxLiveSTT.Token] = []
    /// Threshold used by both (A) speaker and (D) language split. Matches
    /// `RelayDirectionResolver.minConfidence` so the split fires at the
    /// same confidence level the resolver itself trusts a streak at.
    private static let splitTokenThreshold: Int = 3

    init() {
        guard_.isLeakedNow = { [weak self] in self?.stt != nil }
        guard_.onWarn = { [weak self] in self?.inWarnWindow = true }
        guard_.onStop = { [weak self] reason in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.tearDown(reason: reason.rawValue)
            }
        }
        tabObserver = NotificationCenter.default.addObserver(
            forName: .teycanTabChanged, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let from = note.userInfo?["from"] as? String
                if from == "relay", self.isLiveLike {
                    DiagLogger.shared.log(.guard_, "tab switch from relay — auto stop")
                    self.guard_.stop(reason: .tabSwitch)
                }
            }
        }
        player.onFinish = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                DiagLogger.shared.log(.tts, "[relay.tts] playback finished")
                // Only kick back to .listening if we're still on the speaking
                // phase — guard against late callbacks after teardown.
                if case .speaking = self.phase {
                    self.phase = .listening
                }
                self.commitInFlight = false
                // Wake up any `stop()` waiter that was holding off teardown
                // so the last utterance could finish speaking out.
                if let cont = self.pendingStopContinuation {
                    self.pendingStopContinuation = nil
                    cont.resume()
                    // stop() will handle the teardown — don't re-open STT.
                    return
                }
                // Otherwise resume listening for the next user turn.
                await self.resumeListening()
            }
        }
    }

    var isRunning: Bool { isLiveLike }

    private var isLiveLike: Bool {
        switch phase {
        case .starting, .listening, .translating, .speaking: return true
        case .idle, .error: return false
        }
    }

    func start(langA: String, langB: String) async {
        guard case .idle = phase else { return }
        DiagLogger.shared.log(.app, "relay: mic tap → start (\(langA)↔\(langB))")
        phase = .starting
        sessionLangA = langA
        sessionLangB = langB
        messages.removeAll()
        turnID = 0
        pendingFinalsForNextTurn.removeAll()
        resetTurnState()
        detectedLang = nil
        quotaWarning = nil
        // Fire-and-forget the TTS quota probe. We don't await because
        // letting it block session start would add ~100-200ms of dead
        // air right when the user just tapped Start. The banner appears
        // as soon as the response lands.
        Task { @MainActor [weak self] in await self?.refreshTtsQuota() }
        resolver = RelayDirectionResolver(langA: langA, langB: langB)

        AudioSessionConfigurator.configure(.voiceChat)
        let granted = await AudioSessionConfigurator.requestMicPermission()
        guard granted else {
            phase = .error("Microphone permission denied")
            DiagLogger.shared.log(.audio, "mic permission DENIED (relay)")
            return
        }

        let rec = VoiceLogRecorder(deviceID: RemoteLogger.shared.publicDeviceID, mode: "relay")
        self.voiceLog = rec
        await rec.appendMeta(text: "session.start langA=\(langA) langB=\(langB)")
        DiagLogger.shared.log(.app, "relay: voice-log session = \(rec.sessionID)")

        do {
            DiagLogger.shared.log(.stt, "relay: fetching Soniox token")
            let token = try await APIClient.shared.sttToken()
            let stream = try await recorder.start()

            let sttClient = SonioxLiveSTT()
            self.stt = sttClient
            try await sttClient.connect(
                apiKey: token,
                languageHints: [langA, langB],
                enableSpeakerDiarization: true,
                onTokens: { [weak self] tokens, _ in
                    Task { @MainActor [weak self] in
                        self?.handleSttTokens(tokens)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        DiagLogger.shared.log(.stt, "relay soniox error: \(error.localizedDescription)")
                        self?.phase = .error("STT: \(error.localizedDescription)")
                    }
                }
            )

            guard_.start()
            phase = .listening
            startDeadlineMirror()
            startAudioPump(stream: stream)
            EarconPlayer.shared.play(.start)
        } catch {
            DiagLogger.shared.log(.net, "relay session start failed: \(error.localizedDescription)")
            phase = .error(error.localizedDescription)
            await tearDown(reason: "start-failed")
        }
    }

    func stop() async {
        DiagLogger.shared.log(.app, "relay: mic tap → stop")
        // Stop the mic + Soniox WS immediately so the user knows we heard
        // the stop, but keep the output side alive — let the pending turn
        // finish translating + speaking before teardown. Otherwise tearDown
        // would close the AVAudioPlayer mid-word ("обірвалось" complaint).
        pumpTask?.cancel(); pumpTask = nil
        recorder.stop()
        await stt?.finishAndClose()
        stt = nil
        idleTimerTask?.cancel(); idleTimerTask = nil

        // If we have un-committed finals, run them through translate + TTS.
        if hasFinalForCurrentTurn, !commitInFlight {
            await commitTurn()
        }

        // Wait for any in-flight turn (translate + TTS playback) to fully
        // finish. player.onFinish / error paths resume the continuation.
        if commitInFlight || phase == .speaking || phase == .translating {
            DiagLogger.shared.log(.app, "[relay] stop: awaiting in-flight playback…")
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                if !commitInFlight && phase != .speaking && phase != .translating {
                    cont.resume()
                    return
                }
                self.pendingStopContinuation = cont
            }
        }

        guard_.stop(reason: .manual)
    }

    func continueSession() {
        guard_.extend()
        inWarnWindow = false
    }

    /// Manually clear the TTS quota banner (e.g., user tapped "X" on it).
    func dismissQuotaWarning() {
        quotaWarning = nil
    }

    /// Probe `/api/tts-quota` and populate `quotaWarning` if either
    /// provider reports a problem. Called at session start; backend
    /// caches results for 60s so multiple calls in a short window are
    /// cheap.
    private func refreshTtsQuota() async {
        do {
            guard let quota = try await APIClient.shared.ttsQuota() else {
                // 404 — endpoint not deployed yet on this backend. Skip
                // the banner; runtime TTS errors will still surface.
                return
            }
            // Active TTS provider drives which side's warning we surface
            // first. ElevenLabs unhealthy while user is on Soniox isn't
            // immediately actionable, and vice versa.
            let active = UserDefaults.standard.string(forKey: Preferences.K.relayTtsProvider) ?? "elevenlabs"
            var warnings: [String] = []
            if active == "elevenlabs", !quota.elevenlabs.ok {
                warnings.append(quota.elevenlabs.message ?? "ElevenLabs unavailable")
            }
            if active == "soniox", !quota.soniox.ok {
                warnings.append(quota.soniox.message ?? "Soniox unavailable")
            }
            // Soft warning when ok==true but < 10% credits remain — gives
            // the user a chance to top up before mid-conversation failure.
            if active == "elevenlabs", quota.elevenlabs.ok,
               let pct = quota.elevenlabs.remainingPct, pct < 0.10,
               let used = quota.elevenlabs.used, let limit = quota.elevenlabs.limit {
                warnings.append("ElevenLabs low: \(limit - used)/\(limit) chars left (\(Int(pct * 100))%)")
            }
            quotaWarning = warnings.isEmpty ? nil : warnings.joined(separator: " · ")
            if let w = quotaWarning {
                DiagLogger.shared.log(.net, "[relay.quota] WARN: \(w)")
            }
        } catch {
            DiagLogger.shared.log(.net, "[relay.quota] check failed: \(error.localizedDescription)")
            // Quota check is best-effort — swallow errors.
        }
    }

    /// Extract a user-friendly quota/availability message from a TTS
    /// failure. Returns nil for non-quota errors (network blips,
    /// translation timeouts) so the banner doesn't blink on every flake.
    private func quotaErrorMessage(from error: any Error) -> String? {
        if let apiErr = error as? APIError, case .httpStatus(let code, let body) = apiErr {
            switch code {
            case 401, 403: return "TTS auth failed (\(code)) — check API key"
            case 402:      return "TTS payment required — top up credits"
            case 429:      return "TTS rate-limited — wait a moment"
            case 400..<500:
                let b = body.lowercased()
                if b.contains("quota") || b.contains("limit") || b.contains("credit") {
                    return "TTS quota exceeded — top up to continue"
                }
                return nil
            default: return nil
            }
        }
        return nil
    }

    /// True when there's *anything* the user has said this turn that we
    /// could commit right now — either finalized tokens or live partials.
    /// We include the live tail because Soniox has a ~1–1.5s finalization
    /// lag; waiting for `isFinal` before showing the Done button creates
    /// a noticeable "button is late" UX gap. When the user taps Done
    /// with only live tokens, `commitNow()` will force-finalize them.
    var canCommitNow: Bool {
        guard case .listening = phase else { return false }
        guard !commitInFlight else { return false }
        if hasFinalForCurrentTurn { return true }
        let liveTrimmed = liveTail.trimmingCharacters(in: .whitespacesAndNewlines)
        return !liveTrimmed.isEmpty
    }

    /// User pressed the "Done speaking" button — skip the idle timer and
    /// commit the current turn right away. If we only have non-final
    /// (live) tokens, treat them as final before committing, so the user
    /// doesn't have to wait for Soniox's finalization lag.
    func commitNow() async {
        guard canCommitNow else { return }
        idleTimerTask?.cancel()
        idleTimerTask = nil
        // Promote the live tail to "final" so commitTurn() has something
        // to translate even before Soniox has caught up with isFinal.
        if !hasFinalForCurrentTurn {
            let liveTrimmed = liveTail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !liveTrimmed.isEmpty, var resolver = self.resolver {
                resolver.absorb(text: liveTrimmed, language: detectedLang, isFinal: true)
                self.resolver = resolver
                finalTextThisTurn = liveTrimmed
                hasFinalForCurrentTurn = true
                DiagLogger.shared.log(.app, "[relay] Done tapped before final — promoted live tail (\(liveTrimmed.count) chars)")
            }
        }
        DiagLogger.shared.log(.app, "[relay] user tapped Done → commit immediately")
        await commitTurn()
    }

    /// Manual "Speak" button on a model bubble — replays the TTS for an
    /// already-translated line. Useful when the auto-playback got cut off
    /// or when the user wants to hear it again.
    func replay(message: RelayMessage) async {
        guard message.role == .model, let lang = message.language else { return }
        guard !message.text.isEmpty else { return }
        // Stop any current playback so we don't overlap.
        player.stop()
        DiagLogger.shared.log(.tts, "[relay.replay] text=\"\(short(message.text, limit: 60))\" lang=\(lang)")
        do {
            let wav = try await APIClient.shared.tts(
                text: message.text, language: lang,
                provider: self.ttsProvider,
                model: self.ttsModel,
                stream: Self.ttsStream
            )
            // If a session is active, the audio session is already configured;
            // reconfiguring it now would break the live input tap. Only
            // configure when called from .idle (replay from History-style UI).
            let needConfig = !isLiveLike
            if !needConfig {
                AudioSessionConfigurator.forceSpeakerOutput()
            }
            try player.play(data: wav, configureSession: needConfig)
        } catch {
            DiagLogger.shared.log(.tts, "[relay.replay] FAILED: \(error.localizedDescription)")
        }
    }

    // MARK: - STT pipeline

    private func startAudioPump(stream: AsyncStream<Data>) {
        pumpTask = Task.detached { [weak self] in
            for await chunk in stream {
                if Task.isCancelled { break }
                await self?.handlePumpedChunk(chunk)
            }
        }
    }

    /// Forwards a captured PCM chunk to Soniox when STT is open. Drops
    /// the chunk when STT is closed (TTS playback / reopen) — half-duplex
    /// design. Buffering + replay isn't safe because mic chunks during
    /// playback contain the TTS bleeding through the speaker, which
    /// Soniox transcribes as a fresh "user" turn and we get a feedback
    /// loop. Standard voice-translator UX: user waits for the model to
    /// finish speaking, then speaks.
    private func handlePumpedChunk(_ chunk: Data) async {
        if let stt = self.stt {
            await stt.sendAudio(chunk)
        } else {
            droppedDuringPlayback += 1
        }
    }

    private func handleSttTokens(_ tokens: [SonioxLiveSTT.Token]) {
        guard var resolver = self.resolver else { return }

        // Soniox sends heartbeat batches `{tokens: [], final_audio_proc_ms: …}`
        // every ~1s during silence. Treat them as "still alive, nothing new"
        // — must NOT reset the idle-commit timer or we'd never commit.
        let hasTokens = !tokens.isEmpty

        var hasNewFinal = false
        // Newly absorbed finals from THIS batch, in arrival order. Used by
        // the speaker/language split detector below after the absorb loop.
        var newFinalsThisBatch: [SonioxLiveSTT.Token] = []
        for t in tokens {
            if t.isFinal {
                let key = "\(t.startMs ?? -1):\(t.text)"
                if seenFinalKeys.contains(key) { continue }
                seenFinalKeys.insert(key)
                resolver.absorb(text: t.text, language: t.language, isFinal: true)
                finalTextThisTurn += t.text
                turnFinalTokens.append(t)
                newFinalsThisBatch.append(t)
                hasNewFinal = true
            }
        }
        // Live tail rebuilt from THIS batch's non-finals only — no accumulation.
        liveTail = tokens
            .filter { !$0.isFinal }
            .map(\.text)
            .joined()
        self.resolver = resolver

        if hasNewFinal { hasFinalForCurrentTurn = true }

        detectedLang = resolver.currentGuess()
        if hasTokens {
            renderLiveUserBubble()
        }

        // (A) Speaker diarization split + (D) language split — detect a
        // strong "different side started talking" signal and force-commit
        // the previous side's content as its own turn. The detector returns
        // the kind of split that fired (if any) so we can stash + commit.
        if hasNewFinal, !commitInFlight,
           let split = detectMidTurnSplit(newFinals: newFinalsThisBatch) {
            stashSplitTokens(count: split.count, kind: split.kind)
            Task { await self.commitNow() }
            return
        }

        // Fire a background completeness query whenever we've got new
        // finalized text. The score returned is used at next
        // `scheduleIdleTimer()` to pick a shorter/longer wait.
        if hasNewFinal {
            scheduleCompletenessCheck()
        }

        // Only reset idle timer when there were real tokens in the batch.
        // Heartbeats don't count. The previous timer keeps running so the
        // 2.5s of silence after the last real token actually fires commit.
        guard !commitInFlight, hasTokens else { return }
        scheduleIdleTimer()
    }

    // MARK: - Mid-turn split detection (speaker + language)

    private enum SplitKind: String { case speaker, language }
    private struct SplitTrigger {
        let kind: SplitKind
        /// How many trailing finals to peel off the current turn.
        let count: Int
    }

    /// Walks the newly-absorbed finals to update the per-turn dominant
    /// speaker and language. Returns a `SplitTrigger` if either streak
    /// of a NEW speaker or NEW {langA, langB} language hits the
    /// `splitTokenThreshold`. Otherwise returns nil.
    ///
    /// Important: this mutates the streak counters — when no split fires
    /// the counters carry across batches so a slow streak (one token per
    /// batch) eventually trips the threshold.
    private func detectMidTurnSplit(newFinals: [SonioxLiveSTT.Token]) -> SplitTrigger? {
        for t in newFinals {
            // -- Speaker tracking
            if let sp = t.speaker {
                if turnSpeakerID == nil {
                    turnSpeakerID = sp
                    otherSpeakerStreak = 0
                } else if sp == turnSpeakerID {
                    otherSpeakerStreak = 0
                } else {
                    otherSpeakerStreak += 1
                    if otherSpeakerStreak >= Self.splitTokenThreshold {
                        DiagLogger.shared.log(.stt, "[relay.split] kind=speaker old=\(turnSpeakerID ?? "?") new=\(sp) (streak=\(otherSpeakerStreak))")
                        return SplitTrigger(kind: .speaker, count: otherSpeakerStreak)
                    }
                }
            }

            // -- Language tracking (only within the session pair)
            if let lang = t.language, lang == sessionLangA || lang == sessionLangB {
                if turnDominantLang == nil {
                    turnDominantLang = lang
                    otherLangStreak = 0
                } else if lang == turnDominantLang {
                    otherLangStreak = 0
                } else {
                    otherLangStreak += 1
                    if otherLangStreak >= Self.splitTokenThreshold {
                        DiagLogger.shared.log(.stt, "[relay.split] kind=language old=\(turnDominantLang ?? "?") new=\(lang) (streak=\(otherLangStreak))")
                        return SplitTrigger(kind: .language, count: otherLangStreak)
                    }
                }
            }
        }
        return nil
    }

    /// Roll back the last `count` finals from the current turn so they
    /// belong to the NEXT turn instead. We pop them off the resolver,
    /// pop the matching `Token` mirrors off `turnFinalTokens`, trim
    /// `finalTextThisTurn` by their joined text, and stash the raw
    /// tokens in `pendingFinalsForNextTurn` for re-feed after commit.
    ///
    /// `seenFinalKeys` is left alone — `resetTurnState()` (called from
    /// `commitTurn()` shortly after this) clears it wholesale, so by the
    /// time the drain re-feeds these tokens via `handleSttTokens`, the
    /// dedupe path will accept them as fresh.
    private func stashSplitTokens(count: Int, kind: SplitKind) {
        guard var resolver = self.resolver, count > 0 else { return }
        let n = min(count, turnFinalTokens.count)
        guard n > 0 else { return }
        _ = resolver.popLastFinals(n)
        self.resolver = resolver
        let poppedTokens = Array(turnFinalTokens.suffix(n))
        turnFinalTokens.removeLast(n)
        let poppedText = poppedTokens.map(\.text).joined()
        if finalTextThisTurn.hasSuffix(poppedText) {
            finalTextThisTurn.removeLast(poppedText.count)
        }
        pendingFinalsForNextTurn.append(contentsOf: poppedTokens)
        DiagLogger.shared.log(.stt, "[relay.split] popped \(n) tokens (\(poppedText.count) chars) kind=\(kind.rawValue) text=\"\(short(poppedText, limit: 60))\" → stashed for next turn")
    }

    /// Debounce + fire one completeness query at a time. If already
    /// in-flight, skip (the next batch will retrigger). The query runs
    /// in the background — its result feeds `lastCompletenessScore`,
    /// which the next `scheduleIdleTimer()` picks up. Passes the last
    /// few finalized turns as conversation context so the LLM can score
    /// short answers correctly (e.g. "Coffee" answering "Tea or coffee?").
    private func scheduleCompletenessCheck() {
        guard completenessTask == nil else { return }
        let textSnapshot = finalTextThisTurn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard textSnapshot.count >= 3 else { return }
        let langSnapshot = detectedLang ?? sessionLangA
        let context = recentTurnsForCompletenessContext()
        completenessTask = Task { [weak self] in
            do {
                let score = try await APIClient.shared.completenessScore(
                    text: textSnapshot,
                    language: langSnapshot,
                    recentTurns: context
                )
                await MainActor.run {
                    guard let self else { return }
                    self.lastCompletenessScore = score
                    self.completenessTask = nil
                    let pct = Int((score * 100).rounded())
                    let pause = self.idleTimeoutForCurrentScore()
                    // Confidence + pause first, then everything else — so
                    // the values stay visible even when the LogPanel row
                    // truncates the tail.
                    DiagLogger.shared.log(.net, "[relay.complete] \(pct)% wait=\(String(format: "%.1f", pause))s | ctx=\(context.count) | \"\(self.short(textSnapshot, limit: 40))\"")
                    // If a timer is already counting down with a LONGER
                    // wait than the new score warrants, reschedule with
                    // the shorter one — keeps the UX snappy when user
                    // finishes a clearly-complete sentence.
                    if let task = self.idleTimerTask, !task.isCancelled {
                        self.scheduleIdleTimer()
                    }
                }
            } catch {
                await MainActor.run {
                    self?.completenessTask = nil
                }
            }
        }
    }

    /// Snapshot of the last few finalized turns to give the LLM enough
    /// context to score short replies correctly. Caps at 6 turns and
    /// only includes finalized bubbles (in-progress ones would mislead).
    private func recentTurnsForCompletenessContext() -> [CompletenessTurn] {
        let finalized = messages.filter { $0.isFinalized }
        let recent = finalized.suffix(6)
        return recent.compactMap { msg in
            let trimmed = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return CompletenessTurn(
                role: msg.role == .user ? .user : .model,
                lang: msg.language,
                text: trimmed
            )
        }
    }

    /// Map latest completeness score → idle wait. Score is "how likely
    /// is this a complete utterance, 0–1". Halved from the original
    /// (0.6/1.2/1.8s) per user preference for snappier commits — the
    /// "Done speaking" shortcut button covers the rare cases where the
    /// adaptive timing cuts off mid-sentence.
    /// - ≥ 0.85 → 0.3s (confident sentence end)
    /// - ≥ 0.55 → 0.6s (probably done)
    /// - <  0.55 → 1.0s (might be mid-sentence, fallback to default)
    private func idleTimeoutForCurrentScore() -> Double {
        let s = lastCompletenessScore
        if s >= 0.85 { return 0.3 }
        if s >= 0.55 { return 0.6 }
        return Self.idleCommitSeconds
    }

    private func scheduleIdleTimer() {
        idleTimerTask?.cancel()
        let secs = idleTimeoutForCurrentScore()
        let pct = Int((lastCompletenessScore * 100).rounded())
        idleTimerTask = Task { [weak self] in
            let ns = UInt64(secs * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            // Same leading format as [relay.complete] so confidence+pause
            // stay visible after row truncation in the in-app LogPanel.
            DiagLogger.shared.log(.stt, "[relay.idle] \(pct)% wait=\(String(format: "%.1f", secs))s → commit")
            await self?.commitTurn()
        }
    }

    private func renderLiveUserBubble() {
        let preview = (finalTextThisTurn + liveTail).trimmingCharacters(in: .whitespaces)
        guard !preview.isEmpty else { return }
        let id = "relay-user-\(turnID)"
        if let idx = messages.lastIndex(where: { $0.id == id }) {
            messages[idx].text = preview
            messages[idx].language = detectedLang
        } else {
            messages.append(RelayMessage(
                id: id, role: .user, text: preview,
                language: detectedLang, isFinalized: false,
                wasFallback: false, createdAt: Date()
            ))
        }
    }

    // MARK: - Turn commit

    private func commitTurn() async {
        guard hasFinalForCurrentTurn, !commitInFlight else { return }
        guard var resolver = self.resolver, let commit = resolver.commit() else {
            // No translatable text — but pending split-stash might still
            // have tokens to recover into the next turn.
            resetTurnState()
            drainPendingFinalsIfAny()
            return
        }
        resolver.reset()
        self.resolver = resolver
        commitInFlight = true

        // 1. Finalize user bubble.
        let userID = "relay-user-\(turnID)"
        if let idx = messages.lastIndex(where: { $0.id == userID }) {
            messages[idx].text = commit.finalText
            messages[idx].language = commit.sourceLang
            messages[idx].isFinalized = true
            messages[idx].wasFallback = commit.wasFallback
        }
        DiagLogger.shared.log(.rtc, "[relay.turn] #\(turnID) \(commit.sourceLang)→\(commit.targetLang) fallback=\(commit.wasFallback) text=\"\(short(commit.finalText, limit: 80))\"")
        if let rec = voiceLog {
            Task { await rec.appendHuman(text: commit.finalText, speaker: nil, lang: commit.sourceLang) }
        }

        // 2. Translate (streaming Groq via /api/translate-fast-stream).
        //    Render the model bubble word-by-word as deltas arrive so the
        //    user sees the translation forming BEFORE TTS catches up.
        //    Earcon "end" plays here — exactly when the loader ring kicks
        //    in around the mic, signalling "I heard you, now translating".
        EarconPlayer.shared.play(.end)
        phase = .translating
        let t0 = Date()
        let modelID = "relay-model-\(turnID)"
        messages.append(RelayMessage(
            id: modelID, role: .model, text: "",
            language: commit.targetLang, isFinalized: false,
            wasFallback: false, createdAt: Date()
        ))

        let translation: String
        var firstByteAt: Date?
        do {
            var assembled = ""
            let stream = APIClient.shared.translateFastStream(
                text: commit.finalText,
                from: commit.sourceLang,
                to: commit.targetLang
            )
            for try await delta in stream {
                if firstByteAt == nil { firstByteAt = Date() }
                assembled += delta
                if let idx = messages.lastIndex(where: { $0.id == modelID }) {
                    messages[idx].text = assembled
                }
            }
            translation = assembled.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translation.isEmpty else { throw APIError.invalidResponse }
            let totalMs = Int(Date().timeIntervalSince(t0) * 1000)
            let ttfbMs = firstByteAt.map { Int($0.timeIntervalSince(t0) * 1000) } ?? -1
            DiagLogger.shared.log(.net, "[relay.translate] #\(turnID) ttfb=\(ttfbMs)ms total=\(totalMs)ms: \"\(short(translation, limit: 80))\"")
        } catch {
            DiagLogger.shared.log(.net, "[relay.translate] FAILED: \(error.localizedDescription)")
            // Remove the placeholder bubble we appended above.
            messages.removeAll(where: { $0.id == modelID })
            phase = .listening
            commitInFlight = false
            pendingStopContinuation?.resume()
            pendingStopContinuation = nil
            resetTurnState()
            turnID += 1
            drainPendingFinalsIfAny()
            return
        }

        // 3. Finalize model bubble.
        if let idx = messages.lastIndex(where: { $0.id == modelID }) {
            messages[idx].text = translation
            messages[idx].isFinalized = true
        }
        if let rec = voiceLog {
            Task { await rec.appendModel(text: translation, lang: commit.targetLang) }
        }

        // 4. Pause mic + STT BEFORE TTS playback. We close the WS, stop the
        //    AVAudioEngine input tap, then switch the audio session from
        //    `.voiceChat` (which routes through Apple's Voice Processing IO
        //    unit and attenuates output ~30%) to `.playback`/`.spokenAudio` —
        //    the loud, non-VPIO path. After playback we restart recorder +
        //    STT in `resumeListening()`. Half-duplex: user can't talk
        //    during TTS anyway, so dropping the engine here is free.
        await pauseAudioForPlayback()

        // 5. TTS via Soniox (server-proxied) → WAV bytes → MP3Player.
        phase = .speaking
        do {
            let wav = try await APIClient.shared.tts(
                text: translation,
                language: commit.targetLang,
                provider: self.ttsProvider,
                model: self.ttsModel,
                stream: Self.ttsStream
            )
            // Session is already in `.playback`/`.spokenAudio` from
            // pauseAudioForPlayback() — that's the loud route. Belt &
            // braces: re-assert speaker routing right before play(), in
            // case anything mid-flight (incoming call, interruption) shifted
            // the output back to earpiece or BT.
            AudioSessionConfigurator.forceSpeakerOutput()
            try player.play(data: wav, configureSession: false)
            DiagLogger.shared.log(.tts, "[relay.tts] #\(turnID) playing \(wav.count)B (\(commit.targetLang))")
        } catch {
            DiagLogger.shared.log(.tts, "[relay.tts] FAILED: \(error.localizedDescription)")
            // Surface quota / auth failures to the user via the banner so
            // they understand WHY playback went silent. Non-quota errors
            // (timeout, network blip) don't flip the banner — they're
            // transient and would just produce noise.
            if let msg = quotaErrorMessage(from: error) {
                quotaWarning = msg
            }
            phase = .listening
            commitInFlight = false
            pendingStopContinuation?.resume()
            pendingStopContinuation = nil
            // No playback happening, restart audio + STT so the user can
            // keep talking despite the TTS failure. Session is currently in
            // `.playback` mode (we switched in pauseAudioForPlayback) — must
            // switch back before recorder can capture again.
            await resumeListening()
        }

        resetTurnState()
        turnID += 1
        drainPendingFinalsIfAny()
        // player.onFinish bumps phase back to .listening (and clears
        // commitInFlight) AND re-opens the STT for the next turn.
    }

    /// If a mid-turn split fired (speaker/language change), drain the
    /// stashed tokens back through `handleSttTokens` so they form the
    /// start of the freshly-reset turn cleanly. Called after every
    /// `resetTurnState()` exit path in `commitTurn()` — including the
    /// nil-commit early return — so popped tokens never leak.
    private func drainPendingFinalsIfAny() {
        guard !pendingFinalsForNextTurn.isEmpty else { return }
        let drained = pendingFinalsForNextTurn
        pendingFinalsForNextTurn = []
        DiagLogger.shared.log(.stt, "[relay.split] draining \(drained.count) stashed tokens into next turn")
        if self.resolver == nil {
            self.resolver = RelayDirectionResolver(langA: sessionLangA, langB: sessionLangB)
        }
        handleSttTokens(drained)
    }

    /// Tear down the listening side before TTS playback: close Soniox WS,
    /// stop the AVAudioEngine input tap, cancel the audio pump, and switch
    /// the audio session to `.playback`/`.spokenAudio` so TTS plays at full
    /// loudness (bypassing `.voiceChat`'s VPIO attenuation).
    ///
    /// We deliberately stop the recorder rather than leaving the engine
    /// running and dropping chunks: a live input tap forces the session to
    /// stay in `.playAndRecord` with the voice-processed output path. The
    /// AVAudioPlayer would then play through that quieter route no matter
    /// what we do at the player level.
    private func pauseAudioForPlayback() async {
        if let stt = self.stt {
            DiagLogger.shared.log(.stt, "[relay] closing STT before TTS playback")
            await stt.finishAndClose()
            self.stt = nil
        }
        pumpTask?.cancel(); pumpTask = nil
        recorder.stop()
        AudioSessionConfigurator.switchToPlaybackMode()
    }

    /// Inverse of `pauseAudioForPlayback()` — restore the listening session
    /// after TTS finishes (or after a TTS error path). Switches the audio
    /// session back to `.voiceChat`, restarts the AVAudioEngine + pump, and
    /// re-opens the Soniox WS for the next user turn.
    private func resumeListening() async {
        guard isLiveLike else { return }
        let dropped = droppedDuringPlayback
        droppedDuringPlayback = 0
        DiagLogger.shared.log(.audio, "[relay] resuming listening (dropped \(dropped) chunks during playback)")

        AudioSessionConfigurator.configure(.voiceChat)

        // (C) Post-TTS warmup. Open the Soniox WS BEFORE the recorder
        // restart so the handshake (~100-200ms) completes against silence
        // instead of racing the first real mic chunk. Then send 200ms of
        // zeroed PCM as a lead-in — Soniox's per-token language model
        // benefits from clean prefix audio to settle before the user's
        // first word lands. Without this warmup we routinely lose the
        // first 200-500ms of speech ("café" → "afé") after every
        // commit cycle.
        do {
            let token = try await APIClient.shared.sttToken()
            let sttClient = SonioxLiveSTT()
            try await sttClient.connect(
                apiKey: token,
                languageHints: [sessionLangA, sessionLangB],
                enableSpeakerDiarization: true,
                onTokens: { [weak self] tokens, _ in
                    Task { @MainActor [weak self] in
                        self?.handleSttTokens(tokens)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        DiagLogger.shared.log(.stt, "[relay] soniox error post-reopen: \(error.localizedDescription)")
                    }
                }
            )
            // 200ms × 16kHz × 2 bytes/sample = 6400 bytes of zeros.
            let silenceLeadIn = Data(count: 200 * 16 * 2)
            await sttClient.sendAudio(silenceLeadIn)
            self.stt = sttClient
            // Fresh resolver — last turn's tokens are gone, new turn starts clean.
            self.resolver = RelayDirectionResolver(langA: sessionLangA, langB: sessionLangB)
            DiagLogger.shared.log(.stt, "[relay] STT re-opened OK + 200ms silence lead-in sent")
        } catch {
            DiagLogger.shared.log(.stt, "[relay] STT re-open FAILED: \(error.localizedDescription)")
            phase = .error("STT reopen: \(error.localizedDescription)")
            return
        }

        // Now bring the recorder back up. By the time the first real PCM
        // chunk reaches Soniox, the WS is hot and the lang model has
        // settled. Mic chunks captured during the warmup don't exist
        // (engine wasn't running), so there's no echo-loop risk.
        do {
            let stream = try await recorder.start(configureSession: false)
            startAudioPump(stream: stream)
        } catch {
            DiagLogger.shared.log(.audio, "[relay] recorder restart FAILED: \(error.localizedDescription)")
            phase = .error("Recorder restart: \(error.localizedDescription)")
            return
        }

        // "Start" earcon — the user's "I'm listening again" cue. Lands
        // AFTER the warmup, so from user POV: TTS ends → 200ms silent
        // gap → chime → mic live.
        EarconPlayer.shared.play(.start)
    }

    private func resetTurnState() {
        finalTextThisTurn = ""
        liveTail = ""
        seenFinalKeys.removeAll()
        turnFinalTokens.removeAll(keepingCapacity: true)
        hasFinalForCurrentTurn = false
        detectedLang = nil
        idleTimerTask?.cancel()
        idleTimerTask = nil
        // Reset adaptive idle — next turn starts with default (low) score
        // until the first completeness check returns a fresher one.
        lastCompletenessScore = 0
        completenessTask?.cancel()
        completenessTask = nil
        // Mid-turn split trackers — fresh per turn. Note that
        // `pendingFinalsForNextTurn` is NOT cleared here: it's drained
        // explicitly by `commitTurn()` after this reset so the popped
        // tokens land in the new turn that this reset just initialized.
        turnSpeakerID = nil
        otherSpeakerStreak = 0
        turnDominantLang = nil
        otherLangStreak = 0
    }

    // MARK: - Teardown

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
        idleTimerTask?.cancel(); idleTimerTask = nil
        deadlineMirrorTask?.cancel(); deadlineMirrorTask = nil
        pumpTask?.cancel(); pumpTask = nil
        droppedDuringPlayback = 0
        recorder.stop()

        let sessionIDForRecording = voiceLog?.sessionID
        if let rec = voiceLog {
            await rec.appendMeta(text: "session.end reason=\(reason)")
            await rec.finish()
        }
        voiceLog = nil

        await stt?.finishAndClose()
        stt = nil
        player.stop()

        if let sessionID = sessionIDForRecording,
           let wavURL = recorder.writeCapturedWAV(filename: "\(sessionID).wav") {
            let deviceID = RemoteLogger.shared.publicDeviceID
            Task.detached(priority: .background) {
                do {
                    _ = try await APIClient.shared.uploadRecording(
                        wavURL: wavURL, deviceID: deviceID, label: "relay", sessionID: sessionID
                    )
                    DiagLogger.shared.log(.net, "relay WAV uploaded")
                } catch {
                    DiagLogger.shared.log(.net, "relay WAV upload failed: \(error.localizedDescription)")
                }
                try? FileManager.default.removeItem(at: wavURL)
            }
        }
        recorder.clearCapture()

        AudioSessionConfigurator.deactivate()
        deadline = nil
        inWarnWindow = false
        commitInFlight = false
        resolver = nil
        detectedLang = nil
        pendingFinalsForNextTurn.removeAll()
        turnFinalTokens.removeAll()
        phase = .idle
    }

    // MARK: - Helpers

    private func short(_ text: String, limit: Int = 60) -> String {
        let s = text.replacingOccurrences(of: "\n", with: " ")
        if s.count <= limit { return s }
        return String(s.prefix(limit)) + "…"
    }
}
