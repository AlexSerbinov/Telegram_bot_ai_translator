import SwiftUI

/// Companion — personal interpreter in your headphones (one-way listening).
/// Per DESIGN.md § Three Modes > Companion.
struct CompanionView: View {
    @State private var vm = CompanionViewModel()
    @State private var headphones = HeadphonesMonitor.shared
    @State private var pendingToggle = false
    @State private var showHeadphonesGate = false
    @State private var showTargetPicker = false
    @State private var elapsedSeconds = 0
    @State private var elapsedTimer: Timer?

    var body: some View {
        ZStack(alignment: .bottom) {
            DS.Color.bgCanvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    header
                    audioRouteCard
                    targetPickerCard
                    transcriptStream
                    LogPanel()
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.md)
                .padding(.bottom, 140)
            }

            stickyMic
        }
        .sheet(isPresented: $showTargetPicker) {
            TargetLanguagePickerSheet(selection: $vm.targetLanguage)
        }
        .fullScreenCover(isPresented: $showHeadphonesGate) {
            HeadphonesGateView { showHeadphonesGate = false }
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
                Text("Companion")
                    .font(DS.Font.title)
                    .foregroundStyle(DS.Color.textInk)
                EyebrowLabel(text: "One-way · Слухаєш в навушниках", leadingDash: true)
            }
            Spacer()
            if vm.isRunning {
                LiveIndicator(elapsedSeconds: elapsedSeconds)
            }
        }
    }

    // MARK: - Audio route status

    private var audioRouteCard: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: headphones.isConnected ? "airpodspro" : "headphones")
                .font(.system(size: 20))
                .foregroundStyle(headphones.isConnected ? DS.Color.success : DS.Color.warning)
                .frame(width: 36, height: 36)
                .background(DS.Color.bgSurface2)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            VStack(alignment: .leading, spacing: 2) {
                Text(headphones.deviceLabel)
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.textInk)
                EyebrowLabel(
                    text: headphones.isConnected ? "Connected · routing audio" : "Not connected · tap to connect",
                    color: headphones.isConnected ? DS.Color.success : DS.Color.warning
                )
            }
            Spacer()
        }
        .padding(DS.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.hairline, lineWidth: DS.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .onTapGesture {
            if !headphones.isConnected {
                openBluetoothSettings()
            }
        }
    }

    // MARK: - Target language picker

    private var targetPickerCard: some View {
        Button {
            showTargetPicker = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowLabel(text: "→ Target language", color: DS.Color.accent)
                    HStack(spacing: 6) {
                        Text(vm.targetLanguage.flag)
                        Text(vm.targetLanguage.name)
                            .font(DS.Font.headline)
                            .foregroundStyle(DS.Color.textInk)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(DS.Color.textMuted)
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

    // MARK: - Live transcript stream

    private var transcriptStream: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            EyebrowLabel(text: "Stream")
            if vm.manager.sourceTranscript.isEmpty && vm.manager.translatedTranscript.isEmpty {
                Text("Tap Start, then keep listening — translation will stream here.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSubtle)
                    .padding(.vertical, DS.Space.lg)
            } else {
                if !vm.manager.sourceTranscript.isEmpty {
                    Text(vm.manager.sourceTranscript)
                        .font(DS.Font.caption.italic())
                        .foregroundStyle(DS.Color.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !vm.manager.translatedTranscript.isEmpty {
                    HStack(alignment: .top, spacing: DS.Space.sm) {
                        Rectangle()
                            .fill(DS.Color.accent)
                            .frame(width: DS.Stroke.accentBold)
                        Text(vm.manager.translatedTranscript)
                            .font(DS.Font.bodyEmphasis)
                            .foregroundStyle(DS.Color.textInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
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
                    label: vm.isRunning ? "Stop listening" : "Start listening",
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
        // Headphones gate — block start when no headphones connected.
        if !vm.isRunning, !headphones.isConnected {
            showHeadphonesGate = true
            return
        }
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

    private func openBluetoothSettings() {
        if let url = URL(string: "App-Prefs:Bluetooth") ?? URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Headphones gate

private struct HeadphonesGateView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            DS.Color.bgSurface.ignoresSafeArea().opacity(0.96)
            VStack(spacing: DS.Space.lg) {
                Spacer()
                Image(systemName: "headphones")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(DS.Color.accent)

                Text("Connect headphones to start")
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.textInk)
                    .multilineTextAlignment(.center)

                Text("Companion plays translation in your ear in real time. To avoid audio feedback, connect AirPods, EarPods, or any headset before starting a session.")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Space.xl)

                Spacer()

                Button {
                    if let url = URL(string: "App-Prefs:Bluetooth") ?? URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Bluetooth Settings")
                        .font(DS.Font.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Space.md)
                        .background(DS.Color.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DS.Space.xl)

                Button("Not now", action: onDismiss)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textMuted)
                    .padding(.bottom, DS.Space.xl)
            }
        }
    }
}

// MARK: - Target language picker

private struct TargetLanguagePickerSheet: View {
    @Binding var selection: TargetLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(TargetLanguages.all) { lang in
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
            .navigationTitle("Translate into")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    CompanionView()
}
