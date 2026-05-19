import SwiftUI

/// Phrase — one-shot translator. Per DESIGN.md § Three Modes > Phrase:
/// header → lang pair selector → output card with original + translation +
/// actions → SQUARE mic at the bottom.
///
/// Phase 6 addition: original + translation are now editable via TextEditor.
/// User can tap the mic to dictate (Soniox real-time STT), then keyboard-edit
/// the result before pressing Speak (Groq translate → ElevenLabs MP3).
struct PhraseView: View {
    @State private var vm = PhraseViewModel()
    @State private var pendingToggle = false
    @State private var showFromPicker = false
    @State private var showToPicker = false
    @State private var showSettings = false

    enum FocusField { case source, translation }
    @FocusState private var focused: FocusField?

    var body: some View {
        @Bindable var session = vm.session
        ZStack(alignment: .bottom) {
            DS.Color.bgCanvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    header
                    languagePair
                    outputCard(session: session)
                    LogPanel()
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.md)
                .padding(.bottom, 140) // leave room for sticky mic
            }
            .scrollDismissesKeyboard(.interactively)

            stickyMic
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
                    .font(DS.Font.body.weight(.semibold))
                    .foregroundStyle(DS.Color.accent)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Phrase")
                    .font(DS.Font.title)
                    .foregroundStyle(DS.Color.textInk)
                EyebrowLabel(text: headerEyebrow, leadingDash: true)
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(DS.Font.body.weight(.semibold))
                    .foregroundStyle(DS.Color.textInk)
                    .padding(DS.Space.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .stroke(DS.Color.hairlineStrong, lineWidth: DS.Stroke.hairline)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Phrase settings")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showSettings) {
            PhraseSettingsSheet(settings: vm.settings)
        }
    }

    private var headerEyebrow: String {
        let tts = vm.settings.ttsProvider.displayName
        return "One-shot · Soniox + Groq · TTS \(tts)"
    }

    // MARK: - Language pair

    private var languagePair: some View {
        HStack(spacing: DS.Space.sm) {
            LangPill(
                eyebrow: "From",
                flag: vm.primaryLanguage.flag,
                code: vm.primaryLanguage.code
            ) { showFromPicker = true }

            LangSwapButton(disabled: vm.isBusy || vm.isRecording) {
                vm.swapLanguages()
            }

            LangPill(
                eyebrow: "To",
                flag: vm.secondaryLanguage.flag,
                code: vm.secondaryLanguage.code
            ) { showToPicker = true }
        }
        .sheet(isPresented: $showFromPicker) {
            LanguagePickerSheet(title: "Speak in", selection: $vm.primaryLanguage)
        }
        .sheet(isPresented: $showToPicker) {
            LanguagePickerSheet(title: "Translate to", selection: $vm.secondaryLanguage)
        }
    }

    // MARK: - Output card

    private func outputCard(session: PhraseLiveSession) -> some View {
        @Bindable var session = session
        return VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                EyebrowLabel(text: outputEyebrow)
                Spacer()
                if !session.sourceText.isEmpty {
                    Button {
                        session.sourceText = ""
                        session.translation = ""
                        focused = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DS.Color.textSubtle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            }

            ZStack(alignment: .topLeading) {
                if session.sourceText.isEmpty {
                    Text(vm.isRecording
                         ? "Listening…"
                         : "Type \(vm.primaryLanguage.name), or tap the mic.")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textSubtle)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $session.sourceText)
                    .font(DS.Font.bodyEmphasis)
                    .foregroundStyle(DS.Color.textInk)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60, maxHeight: 180)
                    .focused($focused, equals: .source)
                    .disabled(vm.isRecording) // mic owns the field while live
                    .opacity(vm.isRecording ? 0.85 : 1.0)
                    .submitLabel(.done)
            }

            Rectangle()
                .fill(DS.Color.hairline)
                .frame(height: DS.Stroke.hairline)

            HStack {
                EyebrowLabel(text: "Translation", color: DS.Color.accent)
                Spacer()
                if vm.isTranslating {
                    ProgressView().tint(DS.Color.accent).scaleEffect(0.7)
                }
            }

            ZStack(alignment: .topLeading) {
                if session.translation.isEmpty {
                    Text("Translation appears here.")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textSubtle)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $session.translation)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textMuted)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 50, maxHeight: 160)
                    .focused($focused, equals: .translation)
                    .submitLabel(.done)
            }

            actionRow(session: session)
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(focused != nil ? DS.Color.accent.opacity(0.4) : DS.Color.hairline, lineWidth: DS.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .animation(.easeOut(duration: 0.15), value: focused)
    }

    private var outputEyebrow: String {
        let words = vm.session.sourceText.split(separator: " ").count
        let lang = (vm.session.detectedLanguage ?? vm.primaryLanguage.code).uppercased()
        if words == 0 { return "Original" }
        return "Original · \(lang) · \(words) word\(words == 1 ? "" : "s")"
    }

    private func actionRow(session: PhraseLiveSession) -> some View {
        HStack(spacing: DS.Space.sm) {
            Button {
                focused = nil
                Task { await vm.translateNow() }
            } label: {
                Label("Translate", systemImage: "arrow.right.arrow.left")
                    .font(DS.Font.body.weight(.semibold))
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .stroke(DS.Color.accent, lineWidth: DS.Stroke.hairline)
                    )
                    .foregroundStyle(DS.Color.accent)
            }
            .buttonStyle(.plain)
            .disabled(session.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isRecording)
            .opacity((session.sourceText.isEmpty || vm.isRecording) ? 0.4 : 1.0)

            Button {
                Task { await vm.speakTranslation() }
            } label: {
                Label("Speak", systemImage: "speaker.wave.2.fill")
                    .font(DS.Font.body.weight(.semibold))
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.sm)
                    .background(DS.Color.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            }
            .buttonStyle(.plain)
            .disabled(!vm.canSpeak)
            .opacity(vm.canSpeak ? 1.0 : 0.4)

            Button {
                UIPasteboard.general.string = session.translation
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(DS.Font.body)
                    .padding(DS.Space.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .stroke(DS.Color.hairlineStrong, lineWidth: DS.Stroke.hairline)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.Color.textInk)
            .disabled(session.translation.isEmpty)
            .opacity(session.translation.isEmpty ? 0.4 : 1.0)
            .accessibilityLabel("Copy translation")

            Spacer()
        }
        .padding(.top, DS.Space.xs)
    }

    // MARK: - Mic

    private var stickyMic: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(LinearGradient(
                    colors: [DS.Color.bgCanvas.opacity(0), DS.Color.bgCanvas],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(height: 24)
                .allowsHitTesting(false)

            VStack(spacing: DS.Space.sm) {
                MicButton(
                    shape: .square,
                    isActive: vm.isRecording,
                    isBusy: vm.isBusy || pendingToggle,
                    label: vm.isRecording ? "Stop" : "Tap to speak",
                    action: {
                        focused = nil
                        pendingToggle = true
                        Task {
                            await vm.toggleRecord()
                            pendingToggle = false
                        }
                    }
                )
                Text(vm.statusText)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textMuted)
                    .padding(.bottom, DS.Space.lg)
            }
            .frame(maxWidth: .infinity)
            .background(DS.Color.bgCanvas)
        }
    }
}

// MARK: - Language picker sheet

struct LanguagePickerSheet: View {
    let title: String
    @Binding var selection: PhraseLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(PhraseLanguages.all) { lang in
                Button {
                    selection = lang
                    dismiss()
                } label: {
                    HStack {
                        Text(lang.flag)
                        Text(lang.name)
                            .foregroundStyle(DS.Color.textInk)
                        Spacer()
                        if lang == selection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(DS.Color.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    PhraseView()
}
