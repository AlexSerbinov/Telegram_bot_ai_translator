import SwiftUI

/// `<accent dot 6pt> + Live · MM:SS` per DESIGN.md § Components > Live Indicator.
/// Dot pulses 1.6s linear repeat-forever. Time is tabular-mono so digits
/// don't shift width as seconds tick.
///
/// Usage: place top-right of a screen header while a session is running.
struct LiveIndicator: View {
    /// Total elapsed seconds since session start. Will format as `MM:SS`.
    let elapsedSeconds: Int
    var label: String = "Live"

    @State private var pulse = false

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Circle()
                .fill(DS.Color.accent)
                .frame(width: 6, height: 6)
                .opacity(pulse ? 0.45 : 1.0)
                .onAppear {
                    withAnimation(DS.Motion.livePulse) { pulse.toggle() }
                }
                .accessibilityHidden(true)

            HStack(spacing: 4) {
                Text(label.uppercased())
                Text("·")
                Text(formatted)
                    .monospacedDigit()
            }
            .font(DS.Font.monoEmphasis)
            .tracking(DS.Tracking.monoEmphasis)
            .foregroundStyle(DS.Color.textInk)
            .accessibilityLabel("\(label), \(formatted)")
        }
    }

    private var formatted: String {
        let m = max(0, elapsedSeconds) / 60
        let s = max(0, elapsedSeconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

#Preview {
    VStack(spacing: 24) {
        LiveIndicator(elapsedSeconds: 0)
        LiveIndicator(elapsedSeconds: 47)
        LiveIndicator(elapsedSeconds: 167)
    }
    .padding(40)
    .background(DS.Color.bgCanvas)
}
