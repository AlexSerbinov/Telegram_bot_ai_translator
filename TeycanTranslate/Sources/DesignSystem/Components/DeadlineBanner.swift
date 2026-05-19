import SwiftUI

/// Cost-guard banner per DESIGN.md § Components > Cost Guard Banner.
/// Appears in the last 30 seconds before auto-stop.
struct DeadlineBanner: View {
    var remainingSeconds: Int = 30
    let onContinue: () -> Void

    @State private var pulse = false

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                EyebrowLabel(text: "Cost guard", color: DS.Color.warning)
                HStack(spacing: 4) {
                    Text(timeText)
                        .font(DS.Font.monoEmphasis)
                        .monospacedDigit()
                    Text("до автозупинки")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textMuted)
                }
                .foregroundStyle(DS.Color.textInk)
            }

            Spacer()

            Button(action: onContinue) {
                Text("Continue +2 хв")
                    .font(DS.Font.body.weight(.semibold))
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.sm)
                    .background(DS.Color.warning)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Continue session for two more minutes")
        }
        .padding(DS.Space.md)
        .background(DS.Color.warning.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.warning.opacity(pulse ? 1.0 : 0.6), lineWidth: DS.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) { pulse.toggle() }
        }
    }

    private var timeText: String {
        let s = max(0, remainingSeconds)
        return String(format: "0:%02d", s)
    }
}

#Preview {
    DeadlineBanner(remainingSeconds: 30) {}
        .padding(20)
        .background(DS.Color.bgCanvas)
}
