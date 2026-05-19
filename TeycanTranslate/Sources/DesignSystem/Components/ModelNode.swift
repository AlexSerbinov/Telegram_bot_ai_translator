import SwiftUI

/// 28pt circle with `M` letter — the model "node" sitting at the center of
/// the Bridge conversation axis. Per DESIGN.md § Three Modes > Bridge.
///
/// - `accent.signature` border 1pt
/// - `bg.surface` background
/// - `M` glyph in JetBrains Mono Semibold, accent color
/// - Optional pulse animation while a turn is being processed
struct ModelNode: View {
    var isActive: Bool = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Ambient halo — replaces the old vertical axis as the visual
            // signal that this node is the mediator.
            Circle()
                .fill(DS.Color.accentGlow)
                .frame(width: 56, height: 56)
                .blur(radius: 8)
            Circle()
                .fill(DS.Color.bgSurface)
            Circle()
                .strokeBorder(DS.Color.accent, lineWidth: DS.Stroke.accent)
            Text("M")
                .font(DS.Font.monoEmphasis)
                .foregroundStyle(DS.Color.accent)
        }
        .frame(width: 28, height: 28)
        .opacity(isActive && pulse ? 0.55 : 1.0)
        .onChange(of: isActive) { _, active in
            if active {
                withAnimation(DS.Motion.livePulse) { pulse = true }
            } else {
                pulse = false
            }
        }
        .accessibilityLabel("Model")
    }
}

#Preview {
    HStack(spacing: 32) {
        ModelNode(isActive: false)
        ModelNode(isActive: true)
    }
    .padding(40)
    .background(DS.Color.bgCanvas)
}
