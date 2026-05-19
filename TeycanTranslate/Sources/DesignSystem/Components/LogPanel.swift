import SwiftUI
import UIKit

/// Diagnostic log panel — strict aesthetic, mono font for data.
/// Per DESIGN.md § Components, log entries use `DS.Font.mono` 11–13pt with
/// tabular-nums and clipped to a single line each. The full ring buffer is
/// always available via the `Copy` button (uses `DiagLogger.snapshot()`).
struct LogPanel: View {
    @State private var logger = DiagLogger.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(alignment: .center) {
                EyebrowLabel(text: "Diag log")
                Spacer()
                Button(action: copy) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textInk)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(DS.Color.textInk)

                Button(action: clear) {
                    Label("Clear", systemImage: "trash")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textMuted)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(DS.Color.textMuted)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(logger.entries.suffix(30)) { entry in
                    Text("\(timestamp(entry.timestamp)) [\(entry.tag)] \(entry.message)")
                        .font(DS.Font.mono)
                        .monospacedDigit()
                        .foregroundStyle(DS.Color.textInk.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if logger.entries.isEmpty {
                    Text("(no log entries yet)")
                        .font(DS.Font.mono)
                        .foregroundStyle(DS.Color.textSubtle)
                        .padding(.vertical, 4)
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
    }

    private func timestamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    private func copy() {
        UIPasteboard.general.string = logger.snapshot()
    }

    private func clear() {
        logger.clear()
    }
}
