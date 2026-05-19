import SwiftUI
import UIKit

struct PromptEditorSheet: View {
    @Bindable var settings: BridgeSettings
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("System prompt")
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $settings.instructions)
                    .font(BrandFont.body)
                    .frame(minHeight: 240)
                    .padding(8)
                    .background(BrandColors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(BrandColors.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack {
                    Button(role: .destructive) {
                        settings.resetInstructionsToDefault()
                    } label: {
                        Label("Reset to default", systemImage: "arrow.counterclockwise")
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = settings.instructions
                        didCopy = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            didCopy = false
                        }
                    } label: {
                        Label(
                            didCopy ? "Copied" : "Copy",
                            systemImage: didCopy ? "checkmark" : "doc.on.doc"
                        )
                    }
                }

                Divider().padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voice log transcription")
                            .font(BrandFont.body)
                        Text(settings.transcriptProvider.detail)
                            .font(BrandFont.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                    }

                    Picker("Voice log transcription", selection: $settings.transcriptProvider) {
                        ForEach(BridgeTranscriptProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(20)
            .background(BrandColors.background)
            .navigationTitle("Edit Prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
