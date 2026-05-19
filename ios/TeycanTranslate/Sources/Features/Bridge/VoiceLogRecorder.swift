import Foundation

/// Captures a structured "voice log" for one Bridge session — the diarized
/// timeline of who said what, when. Human entries are sourced from the selected
/// Bridge transcription provider (Soniox or OpenAI Realtime input transcript);
/// model entries come from `outputTranscriptDone` events. Batches uploads to
/// `POST /api/voice-log` every `flushInterval` seconds so the History tab
/// can replay the conversation.
///
/// Coupled with the WAV capture in `BridgeSessionManager.stopSonioxParallel`
/// (uploaded with the same `sessionID`) so audio + transcript stay together.
actor VoiceLogRecorder {
    let sessionID: String
    private let deviceID: String
    /// Tab that owns this session (`"bridge"`, `"companion"`, `"chat"`, `"phrase"`).
    /// Sent on the first POST so the server can label sessions in History.
    private let mode: String
    private let flushInterval: TimeInterval = 2.5
    private let maxBatch: Int = 80

    private var pending: [VoiceLogEntryDTO] = []
    private var flushTask: Task<Void, Never>?
    private var ended = false
    private var modeAlreadySent = false

    init(deviceID: String, mode: String) {
        self.sessionID = "\(deviceID)-\(Int(Date().timeIntervalSince1970 * 1000))"
        self.deviceID = deviceID
        self.mode = mode
    }

    /// Append a finalized human utterance. Caller dedupes — we don't try to
    /// merge consecutive deltas. `speaker` is a provider-specific speaker id
    /// when available; `lang` is the ISO 639-1 code detected or inferred.
    func appendHuman(text: String, speaker: String?, lang: String?, ts: Date = Date()) {
        guard !ended, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pending.append(VoiceLogEntryDTO(
            ts: Int64(ts.timeIntervalSince1970 * 1000),
            role: .human, speaker: speaker, lang: lang, text: text
        ))
        scheduleOrFlush()
    }

    /// Append a finalized model utterance.
    func appendModel(text: String, lang: String?, ts: Date = Date()) {
        guard !ended, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pending.append(VoiceLogEntryDTO(
            ts: Int64(ts.timeIntervalSince1970 * 1000),
            role: .model, speaker: nil, lang: lang, text: text
        ))
        scheduleOrFlush()
    }

    /// Append a session marker (start, end, configuration snapshot, etc).
    func appendMeta(text: String, ts: Date = Date()) {
        guard !ended else { return }
        pending.append(VoiceLogEntryDTO(
            ts: Int64(ts.timeIntervalSince1970 * 1000),
            role: .meta, speaker: nil, lang: nil, text: text
        ))
        scheduleOrFlush()
    }

    /// Final flush — called from session teardown so the trailing entries
    /// land on the server even if there's a network blip.
    func finish() async {
        ended = true
        flushTask?.cancel()
        flushTask = nil
        await flushNow()
    }

    // MARK: - Internal

    private func scheduleOrFlush() {
        if pending.count >= maxBatch {
            Task { await self.flushNow() }
            return
        }
        guard flushTask == nil else { return }
        let interval = flushInterval
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            await self?.flushNow()
        }
    }

    private func flushNow() async {
        flushTask = nil
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        // Only send `mode` once per session — server captures the first
        // non-nil value, subsequent POSTs can leave it nil to save bytes.
        let modeForBatch: String? = modeAlreadySent ? nil : mode
        do {
            try await APIClient.shared.postVoiceLog(VoiceLogPostRequest(
                deviceID: deviceID, sessionID: sessionID, mode: modeForBatch, entries: batch
            ))
            modeAlreadySent = true
            DiagLogger.shared.log(.net, "voice-log: flushed \(batch.count) entries (session=\(sessionID), mode=\(mode))")
        } catch {
            DiagLogger.shared.log(.net, "voice-log: flush FAILED — \(batch.count) entries dropped — \(error.localizedDescription)")
        }
    }
}
