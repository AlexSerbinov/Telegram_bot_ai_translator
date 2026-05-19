import SwiftUI
import AVKit

/// History — list of recent voice-log sessions, tap to see the diarized
/// transcript and (when present) play back the recorded audio.
/// Pulls from `GET /api/voice-log/sessions?deviceID=…` and the per-session
/// detail endpoint. Read-only.
struct HistoryView: View {
    @State private var sessions: [VoiceLogSessionSummaryDTO] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.bgCanvas.ignoresSafeArea()
                content
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(loading)
                }
            }
            .task { await refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading && sessions.isEmpty {
            ProgressView().controlSize(.large)
        } else if let error {
            VStack(spacing: DS.Space.md) {
                Text("Failed to load")
                    .font(DS.Font.headline)
                Text(error)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textMuted)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await refresh() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding(DS.Space.xl)
        } else if sessions.isEmpty {
            VStack(spacing: DS.Space.sm) {
                Text("No sessions yet")
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.textInk)
                Text("Bridge sessions you run will appear here with a diarized transcript and the recorded audio.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Space.xl)
            }
        } else {
            List(sessions) { session in
                NavigationLink {
                    HistoryDetailView(sessionID: session.sessionID)
                } label: {
                    HistoryRow(session: session)
                }
            }
            .listStyle(.plain)
            .refreshable { await refresh() }
        }
    }

    @MainActor
    private func refresh() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let deviceID = RemoteLogger.shared.publicDeviceID
            let list = try await APIClient.shared.voiceLogSessions(deviceID: deviceID, limit: 100)
            sessions = list.sessions
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct HistoryRow: View {
    let session: VoiceLogSessionSummaryDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DS.Space.sm) {
                ModeBadge(mode: session.mode)
                Text(dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(session.endedAt) / 1000)))
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.textInk)
                Spacer()
                if session.recordingFile != nil {
                    Image(systemName: "waveform.circle")
                        .foregroundStyle(DS.Color.accent)
                }
            }
            HStack(spacing: DS.Space.sm) {
                Text("\(session.entryCount) entries")
                Text("·")
                Text(durationLabel)
            }
            .font(DS.Font.caption)
            .foregroundStyle(DS.Color.textMuted)
        }
        .padding(.vertical, 4)
    }

    private var durationLabel: String {
        let secs = max(0, Int((session.endedAt - session.startedAt) / 1000))
        let m = secs / 60
        let s = secs % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMM d · HH:mm"
        return f
    }
}

private struct HistoryDetailView: View {
    let sessionID: String
    @State private var detail: VoiceLogSessionDetailDTO?
    @State private var loading = true
    @State private var error: String?
    @State private var player: AVPlayer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(DS.Space.xl)
                } else if let error {
                    Text("Error: \(error)")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.warning)
                        .padding(DS.Space.md)
                } else if let detail {
                    modeHeader(for: detail)
                    audioBar(for: detail)
                    ForEach(Array(detail.entries.enumerated()), id: \.offset) { _, entry in
                        entryRow(entry)
                    }
                }
            }
            .padding(DS.Space.md)
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    @ViewBuilder
    private func modeHeader(for detail: VoiceLogSessionDetailDTO) -> some View {
        HStack(spacing: DS.Space.sm) {
            ModeBadge(mode: detail.mode)
            Text(headerDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(detail.startedAt) / 1000)))
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textMuted)
            Spacer()
        }
    }

    private var headerDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMM d · HH:mm:ss"
        return f
    }

    @ViewBuilder
    private func audioBar(for detail: VoiceLogSessionDetailDTO) -> some View {
        if let path = detail.recordingFile {
            let url = Endpoints.baseURL.appending(path: String(path.dropFirst()))
            HStack(spacing: DS.Space.sm) {
                Button {
                    if player == nil {
                        player = AVPlayer(url: url)
                    }
                    if player?.timeControlStatus == .playing {
                        player?.pause()
                    } else {
                        player?.play()
                    }
                } label: {
                    Label("Play recording", systemImage: "play.circle.fill")
                        .font(DS.Font.headline)
                }
                Spacer()
            }
            .padding(DS.Space.md)
            .background(DS.Color.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: VoiceLogEntryDTO) -> some View {
        let label: String = {
            switch entry.role {
            case .human:
                let s = entry.speaker ?? "S?"
                let l = entry.lang.map { " · \($0.uppercased())" } ?? ""
                return "\(s)\(l)"
            case .model:
                return "Model" + (entry.lang.map { " · \($0.uppercased())" } ?? "")
            case .meta:
                return "—"
            }
        }()
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(DS.Font.caption)
                    .foregroundStyle(entry.role == .model ? DS.Color.accent : DS.Color.textMuted)
                Spacer()
                Text(timestamp(entry.ts))
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSubtle)
            }
            Text(entry.text)
                .font(entry.role == .meta ? DS.Font.caption.italic() : DS.Font.body)
                .foregroundStyle(entry.role == .meta ? DS.Color.textSubtle : DS.Color.textInk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Space.md)
        .background(DS.Color.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.hairline, lineWidth: DS.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private func timestamp(_ ms: Int64) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let deviceID = RemoteLogger.shared.publicDeviceID
            detail = try await APIClient.shared.voiceLogSession(sessionID, deviceID: deviceID)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Small pill that shows which tab generated a voice-log session.
/// Color-coded by mode so the History list scans fast at a glance.
private struct ModeBadge: View {
    let mode: String?

    var body: some View {
        Text(label)
            .font(DS.Font.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color)
            .clipShape(Capsule())
    }

    private var label: String {
        switch (mode ?? "").lowercased() {
        case "phrase":    return "Phrase"
        case "companion": return "Companion"
        case "bridge":    return "Bridge"
        case "chat":      return "Chat"
        default:          return "—"
        }
    }

    private var color: Color {
        switch (mode ?? "").lowercased() {
        case "phrase":    return Color.indigo
        case "companion": return Color.teal
        case "bridge":    return DS.Color.accent
        case "chat":      return Color.orange
        default:          return DS.Color.textSubtle
        }
    }
}
