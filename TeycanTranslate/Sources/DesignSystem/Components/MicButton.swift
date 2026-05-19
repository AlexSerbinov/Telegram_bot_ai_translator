import SwiftUI

/// Two shapes per DESIGN.md § Components > Mic Button:
///  - `.round`  — 64pt diameter, full radius. **Bridge** (2-way symmetric).
///  - `.square` — 64pt × 64pt, 4pt corner. **Phrase / Companion** (directional).
///
/// Both use accent fill, white SF Symbol glyph, and a subtle `accent.glow`
/// shadow + 1pt accent stroke. Active state swaps glyph to `stop.fill` and
/// shows `semantic.error` fill.
enum MicShape { case round, square }

struct MicButton: View {
    let shape: MicShape
    let isActive: Bool
    var isBusy: Bool = false
    var size: CGFloat = 64
    var label: String? = nil
    var action: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            Button(action: action) {
                ZStack {
                    background
                    if isBusy {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: isActive ? "stop.fill" : "mic.fill")
                            .font(.system(size: size * 0.34, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: size, height: size)
                .shadow(color: DS.Color.accentGlow, radius: 12, y: 4)
            }
            .buttonStyle(MicPressStyle())
            .disabled(isBusy)
            .accessibilityLabel(isActive ? "Stop" : "Start")
            .accessibilityAddTraits(.isButton)

            if let label {
                EyebrowLabel(text: label, color: DS.Color.textMuted)
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        let fill = isActive ? DS.Color.error : DS.Color.accent
        switch shape {
        case .round:
            Circle()
                .fill(fill)
                .overlay(Circle().strokeBorder(fill.opacity(0.6), lineWidth: DS.Stroke.accent))
        case .square:
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .strokeBorder(fill.opacity(0.6), lineWidth: DS.Stroke.accent)
                )
        }
    }
}

/// Subtle press animation per DESIGN.md § Motion (scale 0.96 → 1.0 ease-out).
private struct MicPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(DS.Motion.micTap, value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 32) {
        MicButton(shape: .square, isActive: false, label: "Tap to speak") {}
        MicButton(shape: .square, isActive: true, label: "Stop listening") {}
        MicButton(shape: .round, isActive: false, label: "Speaking · auto-detect") {}
        MicButton(shape: .round, isActive: false, isBusy: true, label: "Connecting…") {}
    }
    .padding(40)
    .background(DS.Color.bgCanvas)
}
