import SwiftUI

/// Bridge — two-way mediator (V9 layout). Per DESIGN.md § Three Modes > Bridge:
/// header → ConductorStage (3-actor live triad with central M + animated
/// dataflow + live caption) → archive of paired turn cards with
/// ProvenanceTrail → LogPanel → ROUND mic at bottom. Tab bar is owned by
/// MainTabView.
struct BridgeView: View {
    @State private var vm = BridgeViewModel()
    @State private var pendingToggle = false
    @State private var showPromptEditor = false
    @State private var showLangSheet = false
    @State private var langSheetTarget: LangSheetTarget = .a
    @State private var elapsedSeconds = 0
    @State private var elapsedTimer: Timer?

    private enum LangSheetTarget { case a, b }

    /// One string that changes whenever the conversation grows OR the last
    /// bubble's text changes. SwiftUI's `onChange` only fires on transitions,
    /// so we squash both signals into a single comparable value.
    private var combinedScrollKey: String {
        let count = vm.manager.messages.count
        let last = vm.manager.messages.last?.text ?? ""
        return "\(count)|\(last.count)"
    }

    var body: some View {
        @Bindable var settings = vm.settings
        ZStack(alignment: .bottom) {
            DS.Color.bgCanvas.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.lg) {
                        header(settings: settings)
                        ConductorStage(
                            phase: vm.manager.cyclePhase,
                            langA: settings.langA,
                            langB: settings.langB,
                            liveCaption: vm.manager.messages.last(where: { !$0.isFinalized })?.text ?? "",
                            liveCaptionSide: liveCaptionSide(settings: settings),
                            isPartial: !(vm.manager.messages.last?.isFinalized ?? true),
                            onTapSideA: {
                                langSheetTarget = .a
                                showLangSheet = true
                            },
                            onTapSideB: {
                                langSheetTarget = .b
                                showLangSheet = true
                            }
                        )
                        archiveStack(settings: settings)
                        // Anchor at the very bottom of the message list so we
                        // can scroll the latest bubble + its growing text into
                        // view as new content streams in.
                        Color.clear.frame(height: 1).id("bridge-tail")
                        LogPanel()
                    }
                    .padding(.horizontal, DS.Space.xl)
                    .padding(.top, DS.Space.md)
                    .padding(.bottom, 140)
                }
                // Scroll to bottom whenever a new bubble is appended OR the
                // last bubble's text grows (streaming Soniox tokens, streaming
                // model translation). `combinedScrollKey` collapses both
                // signals into one value the scroll-handler can observe.
                .onChange(of: combinedScrollKey) { _, _ in
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo("bridge-tail", anchor: .bottom)
                    }
                }
            }

            stickyMic
        }
        .sheet(isPresented: $showPromptEditor) {
            PromptEditorSheet(settings: vm.settings)
        }
        .sheet(isPresented: $showLangSheet) {
            BridgeLangPickerSheet(
                title: langSheetTarget == .a ? "Side A" : "Side B",
                selection: langSheetTarget == .a ? $settings.langA : $settings.langB
            )
        }
        .onChange(of: vm.isRunning) { _, running in
            if running { startElapsedTimer() } else { stopElapsedTimer() }
        }
        .onDisappear { stopElapsedTimer() }
    }

    // MARK: - Header

    private func header(settings: BridgeSettings) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bridge")
                    .font(DS.Font.title)
                    .foregroundStyle(DS.Color.textInk)
                EyebrowLabel(
                    text: "Two-way · \(settings.langA.code.uppercased()) ↔ \(settings.langB.code.uppercased()) · Mediator",
                    leadingDash: true
                )
            }
            Spacer()
            if vm.isRunning {
                LiveIndicator(elapsedSeconds: elapsedSeconds)
            }
            Button {
                showPromptEditor = true
            } label: {
                Image(systemName: "text.alignleft")
                    .font(.title3)
                    .foregroundStyle(DS.Color.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit system prompt")
        }
    }

    // MARK: - V9 archive — paired turn cards with provenance trail

    /// Which side the live caption belongs to right now. Drives the flag/code
    /// eyebrow inside ConductorStage's caption box.
    ///
    /// Prefer the actual streaming message's detected language over the
    /// cyclePhase side — during `.translating` the caption text becomes the
    /// assistant's translation (target language), and labelling it as the
    /// source side would visibly mismatch (e.g. ES text labelled "🇺🇦 UK").
    /// Falls back to cyclePhase when no streaming message exists yet.
    private func liveCaptionSide(settings: BridgeSettings) -> BridgeSessionManager.ConductorSide? {
        if let streaming = vm.manager.messages.last(where: { !$0.isFinalized }),
           let lang = streaming.language {
            return lang == settings.langA.code ? .a : .b
        }
        switch vm.manager.cyclePhase {
        case .idle: return nil
        case .sourceListening(let s), .sourceFinished(let s),
             .targetSpeaking(let s):
            return s
        case .translating(let src):
            return src
        }
    }

    /// Renders the conversation archive — pairs each user message with the
    /// next assistant message into a single card with a ProvenanceTrail,
    /// source text, hairline divider, and translation + copy button. A user
    /// bubble with no assistant yet renders as an open turn (translation
    /// shows `…`). Empty state shows the paw-print easter egg.
    private func archiveStack(settings: BridgeSettings) -> some View {
        let pairs = pairedTurns()
        return Group {
            if pairs.isEmpty {
                emptyArchive
            } else {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    ForEach(pairs) { pair in
                        pairedTurnCard(pair, settings: settings)
                            .transition(DS.Transitions.bridgeTurn)
                    }
                }
                .padding(.horizontal, DS.Space.xs)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minHeight: 80)
    }

    private var emptyArchive: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear.frame(height: 80)
            // Easter-egg paw print at 12% opacity
            Image(systemName: "pawprint.fill")
                .font(.system(size: 28))
                .foregroundStyle(DS.Color.accent.opacity(0.12))
                .padding(.trailing, DS.Space.md)
                .accessibilityHidden(true)
        }
    }

    /// Pair user messages with their (next) assistant message. Open user
    /// utterances (no assistant yet) come back with `assistant == nil`.
    private func pairedTurns() -> [TurnPair] {
        var result: [TurnPair] = []
        var pendingUser: BridgeMessage?
        for msg in vm.manager.messages {
            switch msg.role {
            case .user:
                if let p = pendingUser { result.append(TurnPair(user: p, assistant: nil)) }
                pendingUser = msg
            case .assistant:
                if let u = pendingUser {
                    result.append(TurnPair(user: u, assistant: msg))
                    pendingUser = nil
                } else {
                    // Orphan assistant (shouldn't happen in normal flow but
                    // keep it visible rather than dropping silently).
                    result.append(TurnPair(user: nil, assistant: msg))
                }
            }
        }
        if let p = pendingUser { result.append(TurnPair(user: p, assistant: nil)) }
        return result
    }

    private func pairedTurnCard(_ pair: TurnPair, settings: BridgeSettings) -> some View {
        let sourceText = pair.user?.text ?? ""
        let targetText = pair.assistant?.text ?? ""
        let sourceLang: String = pair.user?.language
            ?? pair.assistant.flatMap { msg in
                // Assistant lang is whatever side is OPPOSITE to its language.
                msg.language == settings.langA.code ? settings.langB.code : settings.langA.code
            }
            ?? settings.langA.code
        let targetLang: String = (sourceLang == settings.langA.code) ? settings.langB.code : settings.langA.code
        let isLeftSide = (sourceLang == settings.langA.code)
        let timestamp = format(date: pair.user?.createdAt ?? pair.assistant?.createdAt ?? Date(),
                               relativeTo: vm.manager.sessionStartedAt)
        let latencyMs = pair.user.flatMap { vm.manager.latencyByItemID[$0.id] }

        return HStack(alignment: .top) {
            if !isLeftSide { Spacer().frame(width: 36) }
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                ProvenanceTrail(
                    fromCode: sourceLang,
                    toCode: targetLang,
                    timestamp: timestamp,
                    latencyMs: latencyMs
                )
                Text(sourceText.isEmpty ? "…" : sourceText)
                    .font(DS.Font.bodyEmphasis)
                    .foregroundStyle(DS.Color.textInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle()
                    .fill(DS.Color.hairline)
                    .frame(height: DS.Stroke.hairline)
                HStack(alignment: .top, spacing: DS.Space.sm) {
                    Text(targetText.isEmpty ? "…" : targetText)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !targetText.isEmpty {
                        CopyButton(text: targetText)
                    }
                }
            }
            .padding(DS.Space.md)
            .background(DS.Color.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Color.hairline, lineWidth: DS.Stroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            if isLeftSide { Spacer().frame(width: 36) }
        }
        .frame(maxWidth: .infinity)
    }

    /// MM:SS string relative to session start. Falls back to wall-clock HH:MM
    /// when no session is running (shouldn't happen for archived cards but
    /// keeps the UI stable across edge cases like phase restarts).
    private func format(date: Date, relativeTo start: Date?) -> String {
        if let start {
            let secs = max(0, Int(date.timeIntervalSince(start)))
            return String(format: "%02d:%02d", secs / 60, secs % 60)
        }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// Wrapper used by `ForEach` — pairs a user-bubble with its assistant
    /// translation (or `nil` if not yet streamed).
    private struct TurnPair: Identifiable {
        let user: BridgeMessage?
        let assistant: BridgeMessage?
        var id: String {
            (user?.id ?? "") + "/" + (assistant?.id ?? "")
        }
    }

    // MARK: - Mic

    private var stickyMic: some View {
        VStack(spacing: 0) {
            if vm.manager.inWarnWindow {
                DeadlineBanner(remainingSeconds: 30, onContinue: vm.continueSession)
                    .padding(.horizontal, DS.Space.xl)
                    .padding(.bottom, DS.Space.sm)
                    .transition(DS.Transitions.banner)
            }
            VStack(spacing: DS.Space.sm) {
                MicButton(
                    shape: .round,
                    isActive: vm.isRunning,
                    isBusy: vm.manager.phase == .starting || pendingToggle,
                    label: vm.isRunning ? "Listening · auto-detect" : "Speaking · auto-detect",
                    action: {
                        pendingToggle = true
                        Task {
                            await vm.toggle()
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

    private func startElapsedTimer() {
        elapsedSeconds = 0
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in elapsedSeconds += 1 }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        elapsedSeconds = 0
    }
}

private struct BridgeLangPickerSheet: View {
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
    BridgeView()
}
