import Foundation
import Observation

enum BridgeVoice: String, CaseIterable, Identifiable {
    case marin, cedar, alloy, ash, ballad, coral, echo, sage, shimmer, verse
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum BridgeTranscriptionModel: String, CaseIterable, Identifiable {
    case gpt4oTranscribe = "gpt-4o-transcribe"
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    case gptRealtimeWhisper = "gpt-realtime-whisper"
    case whisper1 = "whisper-1"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .gpt4oTranscribe:     return "GPT-4o (accurate)"
        case .gpt4oMiniTranscribe: return "GPT-4o mini (fast)"
        case .gptRealtimeWhisper:  return "GPT Realtime Whisper"
        case .whisper1:            return "Whisper v1"
        }
    }
}

enum BridgeTranscriptProvider: String, CaseIterable, Identifiable {
    case sonioxRealtime = "soniox-realtime"
    case gptRealtimeWhisper = "gpt-realtime-whisper"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sonioxRealtime: return "Soniox Real Time"
        case .gptRealtimeWhisper: return "GPT Realtime Whisper"
        }
    }

    var detail: String {
        switch self {
        case .sonioxRealtime:
            return "Parallel Soniox STT drives user bubbles and voice logs."
        case .gptRealtimeWhisper:
            return "OpenAI Realtime input transcript drives user bubbles and voice logs."
        }
    }
}

enum BridgeInputLanguage: String, CaseIterable, Identifiable {
    case auto = ""
    case uk, es, en, ru, de, fr, it, pt
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .uk:   return "🇺🇦 Українська"
        case .es:   return "🇪🇸 Español"
        case .en:   return "🇺🇸 English"
        case .ru:   return "🇷🇺 Русский"
        case .de:   return "🇩🇪 Deutsch"
        case .fr:   return "🇫🇷 Français"
        case .it:   return "🇮🇹 Italiano"
        case .pt:   return "🇵🇹 Português"
        }
    }
}

/// Persisted, observable bag of Chat-tab user preferences. UI binds directly,
/// changes mirror to UserDefaults via the property setters.
@Observable
@MainActor
final class BridgeSettings {
    var voice: BridgeVoice {
        didSet { UserDefaults.standard.set(voice.rawValue, forKey: Preferences.K.chatVoice) }
    }
    var inputLanguage: BridgeInputLanguage {
        didSet { UserDefaults.standard.set(inputLanguage.rawValue, forKey: Preferences.K.chatInputLang) }
    }
    var transcriptionModel: BridgeTranscriptionModel {
        didSet { UserDefaults.standard.set(transcriptionModel.rawValue, forKey: Preferences.K.chatTranscribeModel) }
    }
    var transcriptProvider: BridgeTranscriptProvider {
        didSet { UserDefaults.standard.set(transcriptProvider.rawValue, forKey: Preferences.K.bridgeTranscriptProvider) }
    }
    var roomMode: Bool {
        didSet { UserDefaults.standard.set(roomMode, forKey: Preferences.K.chatRoomMode) }
    }
    var vadThreshold: Double {
        didSet { UserDefaults.standard.set(vadThreshold, forKey: Preferences.K.chatVadThreshold) }
    }
    var instructions: String {
        didSet { UserDefaults.standard.set(instructions, forKey: Preferences.K.chatInstructionsKey) }
    }

    /// Explicit lang pair — Bridge mediates between these two sides.
    /// Changing either side auto-rebuilds `instructions` if the user is still
    /// on a known default prompt, so the prompt editor never shows stale
    /// UK/ES wording after a side swap. User-customized prompts are kept.
    var langA: PhraseLanguage {
        didSet {
            UserDefaults.standard.set(langA.code, forKey: Preferences.K.bridgeLangA)
            rebuildPromptIfDefault()
        }
    }
    var langB: PhraseLanguage {
        didSet {
            UserDefaults.standard.set(langB.code, forKey: Preferences.K.bridgeLangB)
            rebuildPromptIfDefault()
        }
    }

    /// Backward-compatible mirror for older code/tests. New UI should use
    /// `transcriptProvider`; setting this flips between Soniox and GPT
    /// Realtime Whisper.
    var useSoniox: Bool {
        get { transcriptProvider == .sonioxRealtime }
        set {
            transcriptProvider = newValue ? .sonioxRealtime : .gptRealtimeWhisper
            UserDefaults.standard.set(newValue, forKey: Preferences.K.bridgeUseSoniox)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        self.voice = BridgeVoice(rawValue: defaults.string(forKey: Preferences.K.chatVoice) ?? "") ?? .marin
        self.inputLanguage = BridgeInputLanguage(rawValue: defaults.string(forKey: Preferences.K.chatInputLang) ?? "") ?? .auto
        self.transcriptionModel = BridgeTranscriptionModel(rawValue: defaults.string(forKey: Preferences.K.chatTranscribeModel) ?? "") ?? .gpt4oTranscribe
        if let rawProvider = defaults.string(forKey: Preferences.K.bridgeTranscriptProvider),
           let provider = BridgeTranscriptProvider(rawValue: rawProvider) {
            self.transcriptProvider = provider
        } else {
            let oldUseSoniox = defaults.object(forKey: Preferences.K.bridgeUseSoniox) as? Bool ?? true
            self.transcriptProvider = oldUseSoniox ? .sonioxRealtime : .gptRealtimeWhisper
        }
        self.roomMode = defaults.bool(forKey: Preferences.K.chatRoomMode)
        let thr = defaults.double(forKey: Preferences.K.chatVadThreshold)
        self.vadThreshold = thr == 0 ? 0.5 : thr
        self.instructions = defaults.string(forKey: Preferences.K.chatInstructionsKey) ?? DefaultPrompt.uaToEs
        let aCode = defaults.string(forKey: Preferences.K.bridgeLangA) ?? "uk"
        let bCode = defaults.string(forKey: Preferences.K.bridgeLangB) ?? "es"
        self.langA = PhraseLanguages.find(aCode) ?? PhraseLanguages.all[0]
        self.langB = PhraseLanguages.find(bCode) ?? PhraseLanguages.all[2]
        // Migration: if the saved prompt is a known default but doesn't match
        // the current lang pair, regenerate it. Catches existing installs
        // where the UK/ES default was saved before the auto-rebuild on
        // langA/langB didSet existed.
        let expected = DefaultPrompt.make(langA: langA.code, langB: langB.code)
        if Self.isDefaultPrompt(self.instructions) && self.instructions != expected {
            self.instructions = expected
        }
    }

    func resetInstructionsToDefault() {
        instructions = DefaultPrompt.make(langA: langA.code, langB: langB.code)
    }

    /// Heuristic: true when `text` is one of the auto-generated default
    /// prompts (any historic version). Used to decide whether changing the
    /// language pair should silently regenerate the prompt or leave a
    /// user-customized version alone.
    private static func isDefaultPrompt(_ text: String) -> Bool {
        text.isEmpty
            || text.hasPrefix("You are a STRICT live voice translator")
            || text.hasPrefix("You are a STRICT live voice")
            || text.hasPrefix("You are a live voice translator")
    }

    private func rebuildPromptIfDefault() {
        guard Self.isDefaultPrompt(instructions) else { return }
        instructions = DefaultPrompt.make(langA: langA.code, langB: langB.code)
    }
}
