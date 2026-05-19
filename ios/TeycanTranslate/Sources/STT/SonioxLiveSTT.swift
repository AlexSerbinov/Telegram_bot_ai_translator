import Foundation

/// Real-time Soniox (`stt-rt-v4`) WebSocket client.
///
/// Soniox returns a *sliding window* of tokens — the latest message contains
/// the recent audio's transcription, NOT a cumulative diff. The caller is
/// responsible for merging consecutive windows into a single accumulating
/// transcript (see `SlidingWindowMerger` below — ported from Mini App).
///
/// Wire protocol (ws://stt-rt.soniox.com/transcribe-websocket):
///   1. Open WebSocket.
///   2. Send TEXT frame with the JSON config (api_key, model, audio_format, …).
///   3. Stream BINARY frames of raw `pcm_s16le` 16kHz mono audio.
///   4. Server sends back TEXT frames: { "tokens": [{ text, is_final, … }], … }
///   5. Send empty BINARY frame to flush; close socket to end.
actor SonioxLiveSTT {
    struct Token {
        let text: String
        let isFinal: Bool
        /// Speaker id Soniox assigns on-the-fly from voice characteristics
        /// when `enable_speaker_diarization` is on. Format is a short
        /// string like `"1"`, `"2"`. `nil` when diarization is disabled or
        /// the token isn't yet attributable to a speaker.
        let speaker: String?
        /// ISO 639-1 language code from Soniox language identification.
        /// `nil` when not yet identified.
        let language: String?
        /// Audio timestamp (ms from session start) where this token begins.
        /// Used downstream to dedupe — Soniox re-sends the same finalized
        /// token across multiple sliding-window batches; `(startMs, text)`
        /// is the unique-enough key to skip duplicates.
        let startMs: Int?
    }

    /// Streamed back to the orchestrator after each server message.
    typealias OnTokens = @Sendable ([Token], _ windowText: String) -> Void
    typealias OnError = @Sendable (any Error) -> Void

    static let endpoint = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket")!

    private var task: URLSessionWebSocketTask?
    private(set) var isOpen = false
    /// Set true the moment we initiate a graceful close. Distinguishes
    /// `task.receive()` failures caused by our own cancellation (expected,
    /// suppress) from real network errors (report).
    private var isClosing = false
    /// Diagnostics counters.
    private var sendCount = 0
    private var recvCount = 0

    func connect(
        apiKey: String,
        languageHints: [String],
        enableSpeakerDiarization: Bool = false,
        onTokens: @escaping OnTokens,
        onError: @escaping OnError
    ) async throws {
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: Self.endpoint)
        self.task = task
        task.resume()

        // Send the config message FIRST.
        var config_payload: [String: Any] = [
            "api_key":           apiKey,
            "model":             "stt-rt-v4",
            "audio_format":      "pcm_s16le",
            "sample_rate":       16_000,
            "num_channels":      1,
            "language_hints":    languageHints,
            "enable_language_identification": true,
        ]
        if enableSpeakerDiarization {
            config_payload["enable_speaker_diarization"] = true
        }
        let configData = try JSONSerialization.data(withJSONObject: config_payload)
        let configString = String(data: configData, encoding: .utf8) ?? "{}"
        try await task.send(.string(configString))
        isOpen = true
        DiagLogger.shared.log(.stt, "soniox WS connected (hints=\(languageHints.joined(separator: ",")), diarize=\(enableSpeakerDiarization))")

        // Receive loop — runs detached.
        Task.detached { [weak self] in
            await self?.receiveLoop(onTokens: onTokens, onError: onError)
        }
    }

    func sendAudio(_ data: Data) async {
        guard let task, isOpen else { return }
        // Empty frames have a specific meaning to Soniox (= flush + close).
        // Skip them so an upstream converter bug can't accidentally tell
        // Soniox to finalize the stream after every tap callback.
        guard !data.isEmpty else { return }
        do {
            try await task.send(.data(data))
            sendCount += 1
            if sendCount == 1 || sendCount % 100 == 0 {
                DiagLogger.shared.log(.stt, "soniox audio #\(sendCount): \(data.count)B sent")
            }
        } catch {
            DiagLogger.shared.log(.stt, "soniox send failed: \(error.localizedDescription)")
        }
    }

    func finishAndClose() async {
        guard let task else { return }
        // Mark as closing BEFORE cancelling, so the receive loop can swallow
        // the "operation cancelled" error that's about to appear.
        isClosing = true
        // Empty binary tells Soniox to flush + finalize.
        try? await task.send(.data(Data()))
        task.cancel(with: .normalClosure, reason: nil)
        self.task = nil
        isOpen = false
        DiagLogger.shared.log(.stt, "soniox WS closed")
    }

    // MARK: - Internal

    private func receiveLoop(onTokens: @escaping OnTokens, onError: @escaping OnError) async {
        guard let task = await self.task else { return }
        while await self.isOpen {
            do {
                let message = try await task.receive()
                let text: String?
                switch message {
                case .string(let s): text = s
                case .data(let d):   text = String(data: d, encoding: .utf8)
                @unknown default:    text = nil
                }
                recvCount += 1
                if let preview = text {
                    let snippet = String(preview.prefix(180))
                    DiagLogger.shared.log(.stt, "soniox recv #\(recvCount): \(snippet)")
                }
                guard let text, let data = text.data(using: .utf8) else { continue }
                if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let tokensRaw = parsed["tokens"] as? [[String: Any]] {
                        var tokens: [Token] = []
                        var window = ""
                        for t in tokensRaw {
                            let s = (t["text"] as? String) ?? ""
                            let isFinal = (t["is_final"] as? Bool) ?? false
                            // Soniox sends `speaker` as either a number or
                            // a string depending on payload version — accept
                            // both shapes.
                            let speaker: String?
                            if let sp = t["speaker"] as? String, !sp.isEmpty {
                                speaker = sp
                            } else if let spN = t["speaker"] as? Int {
                                speaker = String(spN)
                            } else {
                                speaker = nil
                            }
                            let language = (t["language"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                            let startMs = t["start_ms"] as? Int
                            tokens.append(Token(text: s, isFinal: isFinal, speaker: speaker, language: language, startMs: startMs))
                            window += s
                        }
                        onTokens(tokens, window)
                    }
                    // Soniox surfaces problems as { error_code, error_message }
                    // — not under "error". The previous code missed those and
                    // we'd just see silent dead air. Surface both shapes.
                    if let code = parsed["error_code"] {
                        let msg = parsed["error_message"] ?? "(no message)"
                        DiagLogger.shared.log(.stt, "soniox server error code=\(code) msg=\(msg)")
                    } else if let errAny = parsed["error"] {
                        DiagLogger.shared.log(.stt, "soniox server error: \(errAny)")
                    }
                }
            } catch {
                // If we initiated the close, swallow the inevitable
                // "operation cancelled" / "socket not connected" error.
                if await self.isClosing {
                    return
                }
                onError(error)
                break
            }
        }
    }
}

// MARK: - Sliding-window merge (port of Mini App `mergeWithWindow`)

/// Soniox real-time emits each token batch as a *window* — newer audio replaces
/// older audio inside the window. We keep an accumulated transcript and merge
/// each new window by finding the longest overlap with the tail of the
/// accumulated text.
struct SlidingWindowMerger {
    private(set) var accumulated: String = ""

    mutating func merge(_ window: String) -> String {
        guard !window.isEmpty else { return accumulated }
        if accumulated.isEmpty { accumulated = window; return accumulated }

        // Find longest suffix of `accumulated` that matches a prefix of `window`.
        let tailLimit = min(accumulated.count, window.count, 200)
        var bestOverlap = 0
        if tailLimit > 0 {
            let tail = String(accumulated.suffix(tailLimit))
            for k in stride(from: tailLimit, through: 1, by: -1) {
                let suffix = String(tail.suffix(k))
                if window.hasPrefix(suffix) {
                    bestOverlap = k
                    break
                }
            }
        }
        let appendPart = String(window.dropFirst(bestOverlap))
        accumulated += appendPart
        return accumulated
    }

    mutating func reset() { accumulated = "" }
}
