import SwiftUI

/// Relay — Soniox-based bidirectional translator with auto-detect direction.
/// Simpler UI than Bridge: no system prompt, no ConductorStage, no advanced
/// settings. Just lang pair + transcript stream + sticky mic.
struct RelayView: View {
    @State private var vm = RelayViewModel()
    @State private var pendingToggle = false
    @State private var elapsedSeconds = 0
    @State private var elapsedTimer: Timer?
    @State private var showLangSheet = false
    @State private var showSettingsSheet = false
    @State private var langSheetSide: LangSide = .a
    @State private var micPulse: Bool = false
    /// Auto-follow latest bubble. Flipped off the moment the user touches
    /// the ScrollView (DragGesture) so streaming-token re-scrolls don't
    /// yank them out of whatever they're reading. Re-armed 1.5s after the
    /// finger lifts, OR immediately when they tap the "↓ Latest" pill.
    @State private var autoFollow: Bool = true
    @State private var autoFollowResumeTask: Task<Void, Never>?

    private enum LangSide { case a, b }

    /// Re-render the scroll glue whenever new bubble appears or last bubble's
    /// text grows.
    private var combinedScrollKey: String {
        let count = vm.manager.messages.count
        let lastLen = vm.manager.messages.last?.text.count ?? 0
        return "\(count)|\(lastLen)"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.lg) {
                        header
                        if let warn = vm.quotaWarning {
                            quotaBanner(text: warn)
                        }
                        langPairPicker
                        if !vm.manager.messages.isEmpty {
                            transcriptStream
                        } else {
                            emptyState
                        }
                        // Bottom anchor for "show me the LogPanel" jump.
                        // sticky mic is wired via safeAreaInset so the
                        // ScrollView's "visible bottom" is the top of
                        // the mic — bubbles don't hide behind it.
                        Color.clear.frame(height: 1).id("relay-tail")
                        LogPanel()
                    }
                    .padding(.horizontal, DS.Space.xl)
                    .padding(.top, DS.Space.md)
                }
                .background(DS.Color.bgCanvas)
                .simultaneousGesture(
                    // Any user finger contact on the scroll view pauses
                    // auto-follow. We don't need movement — even a tap
                    // implies "I'm interacting with the history, don't
                    // yank me". `minimumDistance: 0` makes it fire on
                    // touch-down. We let SwiftUI re-arm auto-follow on
                    // touch-up via the .onEnded callback (debounced).
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in pauseAutoFollow() }
                        .onEnded { _ in scheduleAutoFollowResume() }
                )
                .onChange(of: combinedScrollKey) { _, _ in
                    // Plain jump-to-bottom (no animation — each delta
                    // would queue a new animation fighting the previous
                    // one, producing jitter). Skipped while user is
                    // reading earlier history.
                    guard autoFollow else { return }
                    if let lastID = vm.manager.messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
                .onChange(of: vm.manager.messages.count) { _, _ in
                    // A fresh bubble appearing is a strong "auto-follow"
                    // signal — re-arm immediately and scroll.
                    autoFollowResumeTask?.cancel()
                    autoFollow = true
                    if let lastID = vm.manager.messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }

                // "↓ Latest" pill — visible only while user has paused
                // auto-follow AND a new bubble or growth has happened
                // since they scrolled. One tap re-arms follow + jumps.
                if !autoFollow {
                    latestPill(proxy: proxy)
                        .padding(.bottom, DS.Space.sm)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { stickyMic }
        }
        .sheet(isPresented: $showLangSheet) {
            RelayLanguagePickerSheet(
                selection: Binding(
                    get: { langSheetSide == .a ? vm.langA : vm.langB },
                    set: { newValue in
                        if langSheetSide == .a { vm.langA = newValue }
                        else { vm.langB = newValue }
                    }
                )
            )
        }
        .sheet(isPresented: $showSettingsSheet) {
            RelaySettingsSheet(settings: vm.settings)
        }
        .onChange(of: vm.isRunning) { _, running in
            if running { startElapsedTimer() } else { stopElapsedTimer() }
        }
        .onDisappear { stopElapsedTimer() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Relay")
                    .font(DS.Font.title)
                    .foregroundStyle(DS.Color.textInk)
                EyebrowLabel(
                    text: "Soniox · auto · \(vm.settings.ttsProvider.displayName) TTS",
                    leadingDash: true
                )
            }
            Spacer()
            if vm.isRunning {
                LiveIndicator(elapsedSeconds: elapsedSeconds)
            }
            Button {
                showSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(DS.Color.textMuted)
                    .frame(width: 36, height: 36)
                    .background(DS.Color.bgSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Relay settings")
        }
    }

    // MARK: - Quota warning banner

    /// Shown when `RelaySessionManager.quotaWarning` is non-nil — i.e.,
    /// the TTS provider quota check at session start (or a live TTS 4xx
    /// error) detected a dead/depleted provider. Dismissable so the user
    /// can keep using the app and try anyway, but prominent enough that
    /// they understand WHY their words aren't being voiced.
    @ViewBuilder
    private func quotaBanner(text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Color.error)
            VStack(alignment: .leading, spacing: 2) {
                EyebrowLabel(text: "TTS quota", color: DS.Color.error)
                Text(text)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                vm.dismissQuotaWarning()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Color.textMuted)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.error.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.error.opacity(0.35), lineWidth: DS.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    // MARK: - Language pair

    private var langPairPicker: some View {
        HStack(spacing: DS.Space.sm) {
            langChip(label: "A", lang: vm.langA) { langSheetSide = .a; showLangSheet = true }
            Button {
                vm.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DS.Color.accent)
                    .frame(width: 36, height: 36)
                    .background(DS.Color.bgSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            }
            .buttonStyle(.plain)
            .disabled(vm.isRunning)
            langChip(label: "B", lang: vm.langB) { langSheetSide = .b; showLangSheet = true }
        }
    }

    @ViewBuilder
    private func langChip(label: String, lang: PhraseLanguage, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                EyebrowLabel(text: label, color: DS.Color.accent)
                HStack(spacing: 6) {
                    Text(lang.flag)
                    Text(lang.name)
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.Color.textInk)
                }
            }
            .padding(DS.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Color.hairline, lineWidth: DS.Stroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .buttonStyle(.plain)
        .disabled(vm.isRunning)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            EyebrowLabel(text: "Stream")
            Text("Tap the mic and start talking — in either language. The model will detect which language you used and reply with the other.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSubtle)
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.hairline, lineWidth: DS.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    // MARK: - Transcript

    private var transcriptStream: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ForEach(vm.manager.messages) { msg in
                bubble(for: msg)
            }
        }
    }

    @ViewBuilder
    private func bubble(for msg: RelayMessage) -> some View {
        let isUser = msg.role == .user
        let eyebrow: String = {
            let role = isUser ? "You" : "Model"
            let lang = msg.language?.uppercased() ?? "?"
            let fallback = msg.wasFallback ? " · defaulting" : ""
            return "\(role) · \(lang)\(fallback)"
        }()
        HStack(alignment: .top, spacing: DS.Space.sm) {
            if !isUser {
                Rectangle()
                    .fill(DS.Color.accent)
                    .frame(width: DS.Stroke.accentBold)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    EyebrowLabel(
                        text: eyebrow,
                        color: isUser ? DS.Color.textMuted : DS.Color.accent
                    )
                    Spacer()
                    // Manual replay button on finalized model bubbles. Useful
                    // when auto-playback got cut off or you want to hear the
                    // translation again.
                    if !isUser, msg.isFinalized, !msg.text.isEmpty {
                        Button {
                            Task { await vm.replay(msg) }
                        } label: {
                            Label("Speak", systemImage: "speaker.wave.2.fill")
                                .labelStyle(.titleAndIcon)
                                .font(DS.Font.caption.weight(.medium))
                                .foregroundStyle(DS.Color.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(DS.Color.bgSurface2)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(msg.text.isEmpty ? "…" : msg.text)
                    .font(isUser ? DS.Font.caption.italic() : DS.Font.bodyEmphasis)
                    .foregroundStyle(isUser ? DS.Color.textMuted : DS.Color.textInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.hairline, lineWidth: DS.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .id(msg.id)
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
                micRow
                Text(vm.statusText)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textMuted)
                    .padding(.bottom, DS.Space.lg)
            }
            .frame(maxWidth: .infinity)
            .background(DS.Color.bgCanvas)
        }
    }

    /// Mic + optional "Done speaking" shortcut, balanced so the central
    /// mic stays visually centered even when the Done button is hidden.
    private var micRow: some View {
        HStack(spacing: DS.Space.lg) {
            // Left spacer (matches the Done button slot so mic stays centered).
            Color.clear.frame(width: 48, height: 48)

            MicButton(
                shape: .square,
                isActive: vm.isRunning,
                isBusy: vm.manager.phase == .starting || pendingToggle,
                label: vm.isRunning ? "Stop relay" : "Start relay",
                action: micTap
            )
            // While translating / speaking, pulse the mic itself so the
            // user sees "we're working on it" without needing a separate
            // halo (which couldn't be centered cleanly on the mic-with-
            // -label VStack). Scale + glow only, no shape changes — keeps
            // the design strict.
            .scaleEffect(micPulse ? 1.06 : 1.0)
            .shadow(
                color: DS.Color.accentGlow.opacity(micPulse ? 0.9 : 0.4),
                radius: micPulse ? 18 : 12,
                y: 4
            )
            .onChange(of: vm.isWorkingOnTurn) { _, working in
                if working {
                    withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                        micPulse = true
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        micPulse = false
                    }
                }
            }
            .accessibilityHint(vm.isWorkingOnTurn ? "Translating" : "")

            // Right slot: Done button when committable, invisible spacer otherwise.
            doneShortcut
                .frame(width: 48, height: 48)
        }
        .frame(maxWidth: .infinity)
    }

    /// "Done speaking" — skips the idle wait and runs translate + TTS right
    /// away. Visible only while listening AND we already have finalized
    /// tokens to commit. Hidden otherwise so it doesn't compete with the
    /// main mic action.
    @ViewBuilder
    private var doneShortcut: some View {
        if vm.canCommitNow {
            Button {
                Task { await vm.commitNow() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(DS.Color.accent)
                    .clipShape(Circle())
                    .shadow(color: DS.Color.accentGlow, radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Done speaking")
        } else {
            Color.clear
        }
    }

    // MARK: - Actions

    private func pauseAutoFollow() {
        autoFollowResumeTask?.cancel()
        autoFollowResumeTask = nil
        if autoFollow {
            autoFollow = false
        }
    }

    /// Re-arm auto-follow ~1.5s after the user lifts their finger from
    /// the ScrollView. Long enough to feel intentional ("I scrolled up
    /// to read; new tokens shouldn't pull me back yet") but short enough
    /// that releasing and waiting brings the live transcript back.
    private func scheduleAutoFollowResume() {
        autoFollowResumeTask?.cancel()
        autoFollowResumeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled {
                autoFollow = true
            }
        }
    }

    /// Compact "↓ Latest" pill that floats above the mic. Tapping it
    /// re-enables auto-follow and jumps to the latest bubble.
    @ViewBuilder
    private func latestPill(proxy: ScrollViewProxy) -> some View {
        Button {
            autoFollowResumeTask?.cancel()
            autoFollow = true
            if let lastID = vm.manager.messages.last?.id {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .bold))
                Text("Latest")
                    .font(DS.Font.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(DS.Color.accent)
            .clipShape(Capsule())
            .shadow(color: DS.Color.accentGlow, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to latest message")
    }

    private func micTap() {
        pendingToggle = true
        Task {
            await vm.toggle()
            pendingToggle = false
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

// MARK: - Language picker sheet

private struct RelayLanguagePickerSheet: View {
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
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview { RelayView() }
