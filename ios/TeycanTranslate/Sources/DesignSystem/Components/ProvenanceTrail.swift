import SwiftUI

/// V9 turn-card header — a "UA → M → ES" provenance line in JetBrains Mono
/// accent, with timestamp + per-turn latency on the right. Shown above each
/// archived conversation card so the user can see exactly which way the
/// translation flowed through the M mediator.
///
/// Per DESIGN.md § Three Modes > Bridge: provenance trail keeps the translator
/// visible as a first-class actor in the conversation, instead of letting it
/// fade into the chrome.
struct ProvenanceTrail: View {
    let fromCode: String     // e.g. "uk"
    let toCode: String       // e.g. "es"
    let timestamp: String    // "MM:SS" relative to session start
    /// Optional — `nil` while translation is still streaming.
    let latencyMs: Int?

    var body: some View {
        HStack {
            Text("\(fromCode.uppercased()) → M → \(toCode.uppercased())")
                .font(DS.Font.eyebrow)
                .foregroundStyle(DS.Color.accent)
                .tracking(DS.Tracking.eyebrow)
            Spacer()
            HStack(spacing: 4) {
                Text(timestamp)
                    .font(DS.Font.mono)
                    .foregroundStyle(DS.Color.textSubtle)
                if let ms = latencyMs {
                    Text("·")
                        .font(DS.Font.mono)
                        .foregroundStyle(DS.Color.textSubtle)
                    Text(formatLatency(ms))
                        .font(DS.Font.mono)
                        .foregroundStyle(DS.Color.textSubtle)
                        .monospacedDigit()
                }
            }
        }
    }

    private func formatLatency(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        let secs = Double(ms) / 1000.0
        return String(format: "%.1fs", secs)
    }
}

/// Small `⎘` icon button that copies arbitrary text to the system clipboard.
/// Shows a brief `✓` confirmation when tapped. Used on each archived
/// translation in Bridge so the user can paste it into Messages / Mail /
/// Notes without re-typing.
struct CopyButton: View {
    let text: String
    @State private var didCopy = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            withAnimation(.easeOut(duration: 0.15)) { didCopy = true }
            DiagLogger.shared.log(.app, "UI: copied translation \"\(String(text.prefix(40)))…\"")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: 0.2)) { didCopy = false }
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(didCopy ? DS.Color.success : DS.Color.textSubtle)
                .frame(width: 22, height: 22)
                .background(DS.Color.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .stroke(didCopy ? DS.Color.success : DS.Color.hairline,
                                lineWidth: DS.Stroke.hairline)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(didCopy ? "Copied" : "Copy translation")
    }
}

#Preview {
    VStack(spacing: 16) {
        ProvenanceTrail(fromCode: "uk", toCode: "es", timestamp: "02:47", latencyMs: 800)
        ProvenanceTrail(fromCode: "es", toCode: "uk", timestamp: "02:53", latencyMs: 600)
        ProvenanceTrail(fromCode: "uk", toCode: "es", timestamp: "03:01", latencyMs: nil)
        HStack {
            Text("Hola, ¿cómo estás hoy?")
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textMuted)
            Spacer()
            CopyButton(text: "Hola, ¿cómo estás hoy?")
        }
    }
    .padding(20)
    .background(DS.Color.bgCanvas)
}
