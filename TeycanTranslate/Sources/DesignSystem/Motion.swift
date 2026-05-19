import SwiftUI

/// Motion specs per `DESIGN.md` § Motion.
/// Considered, sharp, measured. Never springy. Never decorative.
extension DS {
    enum Motion {
        /// Mic button press scale 0.96 → 1.0.
        static let micTap: Animation = .easeOut(duration: 0.15)

        /// Bridge: new turn slides up 12pt + opacity.
        static let bridgeTurn: Animation = .easeOut(duration: 0.20)

        /// Companion: new transcript line slides up 8pt + opacity.
        static let companionLine: Animation = .easeOut(duration: 0.18)

        /// Live indicator pulse — repeats forever.
        static let livePulse: Animation = .linear(duration: 1.6).repeatForever(autoreverses: true)

        /// Tab change crossfade.
        static let tabChange: Animation = .easeOut(duration: 0.10)

        /// Cost-guard banner slide-in.
        static let banner: Animation = .easeOut(duration: 0.25)
    }

    enum Transitions {
        /// New Bridge turn — translateY(-12 → 0) + opacity 0 → 1.
        static let bridgeTurn: AnyTransition = .move(edge: .top).combined(with: .opacity)

        /// New Companion transcript line.
        static let companionLine: AnyTransition = .opacity.combined(with: .offset(y: 8))

        /// Cost-guard banner.
        static let banner: AnyTransition = .move(edge: .top).combined(with: .opacity)
    }
}
