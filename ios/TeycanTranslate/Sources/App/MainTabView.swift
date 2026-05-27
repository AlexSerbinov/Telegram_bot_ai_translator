import SwiftUI

enum AppTab: String, Hashable, CaseIterable {
    // Display order: phrase, companion, bridge, relay (visible 4), then
    // chat + history in the "More" overflow on iOS.
    case phrase, companion, bridge, relay, chat, history

    var title: String {
        switch self {
        case .phrase:    return "Phrase"
        case .companion: return "Companion"
        case .bridge:    return "Bridge"
        case .chat:      return "Chat"
        case .relay:     return "Relay"
        case .history:   return "History"
        }
    }

    /// SF Symbol matching the mode's structural metaphor per DESIGN.md.
    var systemImage: String {
        switch self {
        case .phrase:    return "text.alignleft"            // one-shot horizontal lines
        case .companion: return "waveform"                  // listening / continuous stream
        case .bridge:    return "arrow.left.arrow.right"    // two-way exchange
        case .chat:      return "bubble.left.and.bubble.right" // free conversation
        case .relay:     return "arrow.triangle.2.circlepath" // auto-detect loop (Soniox+Groq)
        case .history:   return "clock.arrow.circlepath"    // past sessions
        }
    }
}

struct MainTabView: View {
    @State private var selected: AppTab = MainTabView.initialTab()

    /// Honors `-start-tab phrase|companion|bridge` launch argument for smoke tests.
    /// Default landing tab on first launch is `bridge` per DESIGN.md (killer feature).
    private static func initialTab() -> AppTab {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-start-tab"), idx + 1 < args.count {
            switch args[idx + 1] {
            case "phrase":    return .phrase
            case "companion": return .companion
            case "bridge":    return .bridge
            case "chat":      return .chat
            case "relay":     return .relay
            case "history":   return .history
            // Backwards-compat with old launch flags during migration.
            case "voice":     return .phrase
            case "realtime":  return .companion
            default:          break
            }
        }
        return .bridge
    }

    var body: some View {
        TabView(selection: $selected) {
            PhraseView()
                .tabItem { Label(AppTab.phrase.title, systemImage: AppTab.phrase.systemImage) }
                .tag(AppTab.phrase)

            CompanionView()
                .tabItem { Label(AppTab.companion.title, systemImage: AppTab.companion.systemImage) }
                .tag(AppTab.companion)

            BridgeView()
                .tabItem { Label(AppTab.bridge.title, systemImage: AppTab.bridge.systemImage) }
                .tag(AppTab.bridge)

            // Order: Phrase, Companion, Bridge, Relay, Chat, History.
            // iOS shows the first 4 in the main bar + last 2 in "More".
            // Relay is the daily-use tab so it stays visible; Chat is the
            // experimental no-prompt one and lives in More.
            RelayView()
                .tabItem { Label(AppTab.relay.title, systemImage: AppTab.relay.systemImage) }
                .tag(AppTab.relay)

            ChatView()
                .tabItem { Label(AppTab.chat.title, systemImage: AppTab.chat.systemImage) }
                .tag(AppTab.chat)

            HistoryView()
                .tabItem { Label(AppTab.history.title, systemImage: AppTab.history.systemImage) }
                .tag(AppTab.history)
        }
        .tint(DS.Color.accent)
        .onChange(of: selected) { old, new in
            DiagLogger.shared.log(.app, "tab \(old.rawValue) → \(new.rawValue)")
            NotificationCenter.default.post(
                name: .teycanTabChanged,
                object: nil,
                userInfo: ["from": old.rawValue, "to": new.rawValue]
            )
        }
    }
}

#Preview {
    MainTabView()
}
