import Foundation
import Observation

/// Orchestrates the live Voice pipeline:
///   AVAudioEngine PCM 16kHz mono Int16
///     → Soniox WebSocket (stt-rt-v4)
///       → SlidingWindowMerger → accumulated transcript
///         → debounced translate (Groq via /api/translate-auto)
///   On stop: one-shot ElevenLabs TTS playback of the final translation.
///
/// Mirrors the proven Mini App `Live` tab pipeline — only TTS is one-shot
/// (instead of streaming via /ws/live) for simplicity. Streaming TTS can be
/// dropped in later behind the same `playTTS()` entry point.
@Observable
@MainActor
final class PhraseLiveSession {
    enum Phase: Equatable {
        case idle
        case starting
        case recording
        case translatingFinal
        case speaking
        case error(String)
    }

    private(set) var phase: Phase = .idle

    /// Originating-language text. Settable from outside (TextEditor binding) —
    /// when not recording, any change debounces a fresh translate. While
    /// recording the mic stream owns this and external writes are ignored.
    var sourceText: String = "" {
        didSet {
            guard !suppressDebouncer, oldValue != sourceText else { return }
            // Mic stream pipeline already calls debouncer.schedule explicitly,
            // so we only auto-debounce on user keyboard edits while idle.
            if !isRecording {
                debouncer?.schedule(text: sourceText)
            }
        }
    }

    /// Translation result. User may also override it directly (e.g. tweak a
    /// phrase before pressing Speak) — no re-translate kicks off when this
    /// is mutated externally.
    var translation: String = ""

    private(set) var detectedLanguage: String?

    /// When the mic pipeline writes `sourceText`, set this to true to avoid
    /// double-scheduling the debouncer (the pipeline already calls schedule
    /// itself).
    @ObservationIgnored
    private var suppressDebouncer = false

    @ObservationIgnored private let recorder = PCMStreamRecorder()
    @ObservationIgnored private var stt: SonioxLiveSTT?
    @ObservationIgnored private var merger = SlidingWindowMerger()
    @ObservationIgnored private var debouncer: LiveTranslationDebouncer!
    @ObservationIgnored private let player = MP3Player()

    @ObservationIgnored private var pumpTask: Task<Void, Never>?
    @ObservationIgnored private var primaryLang: String = "uk"
    @ObservationIgnored private var secondaryLang: String = "es"

    init() {
        player.onFinish = { [weak self] in
            guard let self else { return }
            if case .speaking = self.phase { self.phase = .idle }
        }
        debouncer = LiveTranslationDebouncer { [weak self] text in
            await self?.runTranslate(for: text)
        }
    }

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    func start(primaryLanguage: String, secondaryLanguage: String) async {
        guard case .idle = phase else { return }
        phase = .starting
        suppressDebouncer = true
        sourceText = ""
        translation = ""
        suppressDebouncer = false
        detectedLanguage = nil
        merger.reset()
        primaryLang = primaryLanguage
        secondaryLang = secondaryLanguage

        do {
            DiagLogger.shared.log(.stt, "fetching Soniox token")
            let token = try await APIClient.shared.sttToken()
            let stream = try await recorder.start()

            let stt = SonioxLiveSTT()
            self.stt = stt
            try await stt.connect(
                apiKey: token,
                languageHints: [primaryLanguage, secondaryLanguage]
            ) { [weak self] tokens, window in
                Task { @MainActor [weak self] in
                    self?.handleSttTokens(tokens, window: window)
                }
            } onError: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.fail("STT: \(error.localizedDescription)")
                }
            }

            phase = .recording
            startAudioPump(stream: stream)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func stop() async {
        guard isRecording else {
            // Already idle / errored; just reset.
            phase = .idle
            return
        }
        pumpTask?.cancel(); pumpTask = nil
        recorder.stop()
        await stt?.finishAndClose()
        stt = nil
        debouncer.cancel()

        // Final translate of the accumulated transcript.
        if !sourceText.isEmpty {
            phase = .translatingFinal
            await runTranslate(for: sourceText)
        } else {
            phase = .idle
        }
    }

    /// Force-translate the current `sourceText` immediately (bypass debouncer).
    /// Called from the "Translate" button — useful when user types and wants
    /// instant result instead of waiting 350ms.
    func translateNow(primaryLanguage: String? = nil, secondaryLanguage: String? = nil) async {
        if let primaryLanguage { primaryLang = primaryLanguage }
        if let secondaryLanguage { secondaryLang = secondaryLanguage }
        debouncer?.cancel()
        if !isRecording { phase = .translatingFinal }
        await runTranslate(for: sourceText)
    }

    func speakTranslation(provider: PhraseTtsProvider = .elevenlabs) async {
        guard !translation.isEmpty,
              case .idle = phase else { return }
        phase = .speaking
        do {
            // AVAudioPlayer handles both MP3 (ElevenLabs) and WAV (Soniox) from the
            // same Data buffer — no per-provider playback path needed.
            let audio = try await APIClient.shared.tts(
                text: translation,
                language: secondaryLang,
                provider: provider.rawValue
            )
            try player.play(data: audio)
        } catch {
            fail("TTS: \(error.localizedDescription)")
        }
    }

    // MARK: - Internal

    private func startAudioPump(stream: AsyncStream<Data>) {
        pumpTask = Task.detached { [weak self] in
            for await chunk in stream {
                if Task.isCancelled { break }
                await self?.stt?.sendAudio(chunk)
            }
        }
    }

    private func handleSttTokens(_ tokens: [SonioxLiveSTT.Token], window: String) {
        let merged = merger.merge(window)
        if merged != sourceText {
            // Suppress the didSet auto-debounce: we explicitly schedule below.
            suppressDebouncer = true
            sourceText = merged
            suppressDebouncer = false
            debouncer.schedule(text: merged)
        }
    }

    private func runTranslate(for text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let response = try await APIClient.shared.translateAuto(
                text: trimmed,
                primaryLanguage: primaryLang,
                secondaryLanguage: secondaryLang
            )
            translation = response.translation
            detectedLanguage = response.detectedLanguage
            secondaryLang = response.targetLanguage  // keep TTS in the right voice
            DiagLogger.shared.log(.net, "translate (\(response.detectedLanguage)→\(response.targetLanguage)): \(response.translation.prefix(60))")
            if case .translatingFinal = phase { phase = .idle }
        } catch {
            DiagLogger.shared.log(.net, "translate failed: \(error.localizedDescription)")
            // Don't fail the whole session for one missed translate — the
            // user can keep talking. But surface the last error.
            if case .translatingFinal = phase { phase = .idle }
        }
    }

    private func fail(_ message: String) {
        pumpTask?.cancel(); pumpTask = nil
        recorder.stop()
        Task { await self.stt?.finishAndClose() }
        stt = nil
        debouncer.cancel()
        phase = .error(message)
        DiagLogger.shared.log(.audio, "voice session error: \(message)")
    }
}
