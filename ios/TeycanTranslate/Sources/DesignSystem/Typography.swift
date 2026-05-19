import SwiftUI
import UIKit

/// Typography roles per `DESIGN.md` § Typography.
/// Sans-only (SF Pro Display + SF Pro Text) for prose. JetBrains Mono is bundled
/// via `Resources/Fonts/` for monospaced data, durations, eyebrow labels.
extension DS {
    enum Font {
        // MARK: Display + Title
        static let displayXL: SwiftUI.Font   = .system(size: 88, weight: .bold,    design: .default)
        static let displayL:  SwiftUI.Font   = .system(size: 44, weight: .bold,    design: .default)
        static let title:     SwiftUI.Font   = .system(size: 26, weight: .bold,    design: .default)

        // MARK: Body
        static let headline:      SwiftUI.Font = .system(size: 17, weight: .semibold)
        static let body:          SwiftUI.Font = .system(size: 15, weight: .regular)
        static let bodyEmphasis:  SwiftUI.Font = .system(size: 15, weight: .medium)
        static let caption:       SwiftUI.Font = .system(size: 13, weight: .regular)

        // MARK: Mono (JetBrains Mono — bundled, falls back to .monospaced if missing)
        /// Eyebrow label — UPPER 0.18em via `.tracking()` at the call site.
        static let eyebrow:       SwiftUI.Font = mono(weight: .medium,   size: 11)
        /// Tabular durations + IDs.
        static let mono:          SwiftUI.Font = mono(weight: .regular,  size: 12)
        /// Status badges — UPPER 0.16em.
        static let monoEmphasis:  SwiftUI.Font = mono(weight: .semibold, size: 11)

        // MARK: Helpers
        private static func mono(weight: JBMonoWeight, size: CGFloat) -> SwiftUI.Font {
            if UIFont(name: weight.fontName, size: size) != nil {
                return .custom(weight.fontName, size: size)
            }
            // System monospaced fallback so we keep building offline before the
            // font registers. Tone is identical enough for layout work.
            return .system(size: size, weight: weight.systemWeight, design: .monospaced)
        }
    }

    /// Tracking values (in em-equivalent points for SF/Mono at the spec sizes).
    enum Tracking {
        /// Display headlines `-0.04em` etc.
        static let displayTight: CGFloat = -3.5
        static let titleTight:   CGFloat = -0.5
        /// `0.18em` at 11pt → ~2pt.
        static let eyebrow:      CGFloat = 2.0
        /// `0.16em` at 11pt → ~1.8pt.
        static let monoEmphasis: CGFloat = 1.8
        /// `0.02em` tab labels at 10pt.
        static let tabLabel:     CGFloat = 0.2
    }
}

private enum JBMonoWeight {
    case regular, medium, semibold

    var fontName: String {
        switch self {
        case .regular:  return "JetBrainsMono-Regular"
        case .medium:   return "JetBrainsMono-Medium"
        case .semibold: return "JetBrainsMono-SemiBold"
        }
    }

    var systemWeight: SwiftUI.Font.Weight {
        switch self {
        case .regular:  return .regular
        case .medium:   return .medium
        case .semibold: return .semibold
        }
    }
}

// MARK: - Legacy shim (TODO remove)

enum BrandFont {
    static let largeTitle = DS.Font.displayL
    static let title      = DS.Font.title
    static let body       = DS.Font.body
    static let caption    = DS.Font.caption
    static let mono       = DS.Font.mono
}
