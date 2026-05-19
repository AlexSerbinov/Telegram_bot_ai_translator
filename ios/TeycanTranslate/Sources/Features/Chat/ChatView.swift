import SwiftUI

/// Chat — plain voice conversation with `gpt-realtime`, no translation prompt.
/// The user talks to a generic voice assistant; turn-taking handled by
/// server-side VAD. UI is intentionally simpler than Bridge / Companion:
/// one scrolling thread of user + assistant bubbles + a sticky square mic.
struct ChatView: View {
    @State private var vm = ChatViewModel()
    @State private var pendingToggle = false
    @State private var elapsedSeconds = 0
    @State private var elapsedTimer: Timer?

    /// Combined key so `onChange` fires both when a new message lands and when
    /// the last bubble's text grows — keeps the scroll glued to the bottom.
    private var combinedScrollKey: String {
        let count = vm.manager.messages.count
        let lastLen = vm.manager.messages.last?.text.count ?? 0
        return "\(count)|\(lastLen)"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DS.Color.bgCanvas.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.lg) {
                        header
                        threadStream
                        Color.clear.frame(height: 1).id("chat-tail")
                        LogPanel()
                    }
                    .padding(.horizontal, DS.Space.xl)
                    .padding(.top, DS.Space.md)
                    .padding(.bottom, 140)
                }
                .onChange(of: combinedScrollKey) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("chat-tail", anchor: .bottom)
                    }
                }
            }

            stickyMic
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
                Text("Chat")
                    .font(DS.Font.title)
                    .foregroundStyle(DS.Color.textInk)
                EyebrowLabel(text: "Voice · gpt-realtime · no prompt", leadingDash: true)
            }
            Spacer()
            if vm.isRunning {
                LiveIndicator(elapsedSeconds: elapsedSeconds)
            }
        }
    }

    // MARK: - Message thread

    private var threadStream: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if vm.manager.messages.isEmpty {
                emptyState
            } else {
                ForEach(vm.manager.messages) { msg in
                    bubble(for: msg)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            EyebrowLabel(text: "Stream")
            Text("Tap the mic and start talking. The model will reply with voice.")
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

    @ViewBuilder
    private func bubble(for msg: ChatMessage) -> some View {
        let isUser = msg.role == .user
        HStack(alignment: .top, spacing: DS.Space.sm) {
            if !isUser {
                Rectangle()
                    .fill(DS.Color.accent)
                    .frame(width: DS.Stroke.accentBold)
            }
            VStack(alignment: .leading, spacing: 4) {
                EyebrowLabel(
                    text: isUser ? "You" : "Assistant",
                    color: isUser ? DS.Color.textMuted : DS.Color.accent
                )
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
                MicButton(
                    shape: .square,
                    isActive: vm.isRunning,
                    isBusy: vm.manager.phase == .starting || pendingToggle,
                    label: vm.isRunning ? "Stop chat" : "Start chat",
                    action: micTap
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

    // MARK: - Actions

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

#Preview {
    ChatView()
}
