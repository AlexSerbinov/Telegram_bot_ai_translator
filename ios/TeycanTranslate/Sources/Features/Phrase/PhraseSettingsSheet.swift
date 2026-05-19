import SwiftUI

/// Phrase tab settings sheet, opened from the gear button in the header.
/// Today: TTS provider picker (ElevenLabs vs Soniox).
struct PhraseSettingsSheet: View {
    @Bindable var settings: PhraseSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PhraseTtsProvider.allCases) { provider in
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
                    Text("Used when you tap Speak to play back the translation.")
                }
            }
            .navigationTitle("Phrase settings")
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
