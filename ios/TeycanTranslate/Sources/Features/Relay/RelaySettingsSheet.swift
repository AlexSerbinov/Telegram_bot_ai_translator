import SwiftUI

/// Relay tab settings sheet, opened from the gear button in the header.
/// Today: TTS provider picker (ElevenLabs vs Soniox).
struct RelaySettingsSheet: View {
    @Bindable var settings: RelaySettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(RelayTtsProvider.allCases) { provider in
                        Button {
                            settings.ttsProvider = provider
                        } label: {
                            HStack(alignment: .center, spacing: DS.Space.md) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.displayName)
                                        .font(DS.Font.body.weight(.semibold))
                                        .foregroundStyle(DS.Color.textInk)
                                    Text(provider.subtitle)
                                        .font(DS.Font.caption)
                                        .foregroundStyle(DS.Color.textMuted)
                                }
                                Spacer()
                                if settings.ttsProvider == provider {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(DS.Color.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Voice (Text-to-Speech)")
                } footer: {
                    Text("ElevenLabs Flash is the snappiest. Soniox is slower to start but stays inside one provider for the whole STT→translate→TTS chain.")
                }
            }
            .navigationTitle("Relay settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(DS.Font.body.weight(.semibold))
                        .foregroundStyle(DS.Color.accent)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
