import SwiftUI

/// V9 Conductor-stage dataflow indicator — 3 small accent-colored dots that
/// travel along a horizontal track when `isActive`, signaling that meaning is
/// currently flowing between an endpoint and the central M node.
///
/// Per DESIGN.md anti-Duolingo principle: restrained motion, monochrome dots,
/// no bounce/spring easing. Dots animate at 1.6s linear loop with staggered
/// delays — same cadence as `LiveIndicator`'s pulse so the visual rhythm of
/// the screen stays coherent.
struct DataFlow: View {
    enum Direction { case leftToRight, rightToLeft }

    var direction: Direction = .leftToRight
    var isActive: Bool = false

    private let dotCount = 3
    private let cycle: Double = 1.6

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isActive {
                    ForEach(0..<dotCount, id: \.self) { i in
                        FlowDot(
                            width: geo.size.width,
                            direction: direction,
                            cycle: cycle,
                            delay: Double(i) * (cycle / Double(dotCount))
                        )
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 16)
    }
}

private struct FlowDot: View {
    let width: CGFloat
    let direction: DataFlow.Direction
    let cycle: Double
    let delay: Double
    @State private var t: Double = 0

    var body: some View {
        Circle()
            .fill(DS.Color.accent)
            .frame(width: 4, height: 4)
            .offset(x: offsetX, y: 0)
            .opacity(opacity)
            .onAppear {
                // Start with the delay already "consumed" so dots are spaced
                // out at first render instead of clumping at the origin.
                t = -delay
                withAnimation(.linear(duration: cycle).repeatForever(autoreverses: false)) {
                    t = cycle - delay
                }
            }
    }

    private var progress: Double {
        // t goes from -delay → cycle-delay; normalize to 0..1
        let raw = (t + delay).truncatingRemainder(dividingBy: cycle) / cycle
        return raw < 0 ? raw + 1 : raw
    }

    private var offsetX: CGFloat {
        let p = max(0, min(1, progress))
        switch direction {
        case .leftToRight: return width * p - width / 2
        case .rightToLeft: return width * (1 - p) - width / 2
        }
    }

    private var opacity: Double {
        let p = progress
        // Fade in over first 10%, full opacity, fade out over last 10%.
        if p < 0.1 { return p / 0.1 }
        if p > 0.9 { return (1 - p) / 0.1 }
        return 1
    }
}

#Preview {
    VStack(spacing: 20) {
        DataFlow(direction: .leftToRight, isActive: true).frame(width: 80)
        DataFlow(direction: .rightToLeft, isActive: true).frame(width: 80)
        DataFlow(direction: .leftToRight, isActive: false).frame(width: 80)
    }
    .padding(40)
    .background(DS.Color.bgCanvas)
}
