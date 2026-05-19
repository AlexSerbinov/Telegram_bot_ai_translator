import SwiftUI

/// V9 Conductor-stage endpoint. Compact 70pt-wide card with flag + code +
/// chevron + state label. Clickable — taps invoke `onTap` (typically opens
/// `BridgeLangPickerSheet`).
///
/// The pill highlights itself when `isActive` (current source or target) and
/// reflects the realtime phase via `state`. Per DESIGN.md § Three Modes >
/// Bridge — these capsules replace the old "Side A pill / swap / Side B pill"
/// row with a layout where M sits between them.
struct EndpointPill: View {
    /// Static lang content for the pill.
    let eyebrow: String
    let flag: String
    let code: String
    /// True when this side's pill is the current actor in the conductor cycle.
    var isActive: Bool = false
    /// State label shown under the flag (e.g. "listening", "done", "hearing").
    /// Empty string renders as a height-stable placeholder so layout doesn't
    /// jump between phases.
    var state: String = ""
    /// Tap target — opens the language picker sheet in production.
    var onTap: () -> Void

    /// Drives the pulse animation when active+speaking/hearing. The animated
    /// halo + scale make it obvious which side is "live" right now — fixes
    /// the pre-fix bug where users couldn't tell their pill was activated.
    @State private var pulse = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Pulse glow — only visible when pill is the live actor in
                // the cycle. Scales + fades 0.45 → 1.0 → 0.45 at 0.9s linear
                // loop so it reads as a heartbeat, not a flicker.
                if isActive && isLiveState {
                    RoundedRectangle(cornerRadius: DS.Radius.md + 4)
                        .stroke(DS.Color.accent, lineWidth: 2)
                        .blur(radius: 4)
                        .opacity(pulse ? 0.85 : 0.25)
                        .scaleEffect(pulse ? 1.08 : 1.0)
                }

                VStack(spacing: 4) {
                    EyebrowLabel(text: eyebrow, color: DS.Color.textSubtle)
                    HStack(spacing: 4) {
                        Text(flag).font(.system(size: 18))
                        Text(code.uppercased())
                            .font(DS.Font.monoEmphasis)
                            .foregroundStyle(DS.Color.textInk)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(DS.Color.accent)
                    }
                    Text(state.uppercased())
                        .font(DS.Font.eyebrow)
                        .foregroundStyle(stateColor)
                        // Fixed width slot so SPEAKING (8 chars) / HEARING (7) /
                        // DONE (4) don't shift the pill's overall width as the
                        // cycle phase advances. Truncates if a future state
                        // label grows past the slot rather than visibly jitter
                        // the layout.
                        .frame(width: 64, height: 10, alignment: .center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .opacity(state.isEmpty ? 0 : 1)
                }
                .padding(.vertical, DS.Space.sm)
                .padding(.horizontal, DS.Space.sm)
                .frame(minWidth: 84)
                .background(isActive ? DS.Color.accentSoft : DS.Color.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(isActive ? DS.Color.accent : DS.Color.hairlineStrong,
                                lineWidth: isActive ? 1.5 : DS.Stroke.hairline)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isActive)
        .onChange(of: isLiveState) { _, live in
            if live {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { pulse = false }
            }
        }
        .onAppear {
            // If we appear already in a live state (rare — most lifecycle
            // events fire AFTER initial render), kick off the animation.
            if isLiveState {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
        .accessibilityLabel("\(eyebrow): \(code). Tap to change language.")
        .accessibilityAddTraits(.isButton)
    }

    /// True while this pill is currently engaged in the cycle — driving the
    /// pulse animation. "Done" is not pulsing (it's the resting state between
    /// listening and hearing); only active dynamic states pulse.
    private var isLiveState: Bool {
        guard isActive else { return false }
        let s = state.lowercased()
        return s == "speaking" || s == "hearing" || s == "listening"
    }

    private var stateColor: SwiftUI.Color {
        switch state.lowercased() {
        case "done":     return DS.Color.success
        case "":         return DS.Color.textSubtle
        default:         return DS.Color.accent
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        EndpointPill(eyebrow: "Side A", flag: "🇺🇦", code: "uk", isActive: true, state: "listening") {}
        EndpointPill(eyebrow: "Side B", flag: "🇪🇸", code: "es", isActive: false, state: "") {}
    }
    .padding(40)
    .background(DS.Color.bgCanvas)
}
