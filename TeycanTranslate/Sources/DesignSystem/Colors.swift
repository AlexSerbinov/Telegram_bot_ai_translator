import SwiftUI
import UIKit

/// Editorial-Strict palette per `DESIGN.md` § Color (forest green, near-white canvas, near-black ink).
/// Light + dark variants resolved through UITraitCollection so the same SwiftUI
/// `Color` correctly mirrors when the user toggles Appearance.
enum DS {}

extension DS {
    enum Color {
        // MARK: Backgrounds
        /// `bg.canvas` — app background.
        static let bgCanvas    = dynamic(light: 0xFAFAFA, dark: 0x0A0A0A)
        /// `bg.surface` — cards, sheets, conversation bubbles.
        static let bgSurface   = dynamic(light: 0xFFFFFF, dark: 0x161616)
        /// `bg.surface-2` — headers, inactive areas.
        static let bgSurface2  = dynamic(light: 0xF5F5F5, dark: 0x1F1F1F)

        // MARK: Text
        static let textInk     = dynamic(light: 0x0A0A0A, dark: 0xFAFAFA)
        static let textMuted   = dynamic(light: 0x525252, dark: 0xA3A3A3)
        static let textSubtle  = dynamic(light: 0xA3A3A3, dark: 0x525252)

        // MARK: Accent (forest green)
        /// `accent.signature` — forest green, used sparingly for live state, mic, primary CTA.
        static let accent      = dynamic(light: 0x1F4A3A, dark: 0x3D8A6A)
        /// `accent.soft` — selection backgrounds, soft accent surfaces.
        static let accentSoft  = dynamic(light: 0xE0EBE5, dark: 0x1A2E25)
        /// `accent.glow` — mic shadow, focus ring.
        static let accentGlow  = SwiftUI.Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 61/255, green: 138/255, blue: 106/255, alpha: 0.18)
                : UIColor(red: 31/255, green: 74/255, blue: 58/255, alpha: 0.10)
        })

        // MARK: Hairlines
        static let hairline       = dynamic(light: 0xE5E5E5, dark: 0x262626)
        static let hairlineStrong = dynamic(light: 0xD4D4D4, dark: 0x404040)

        // MARK: Semantic
        /// Success — AirPods connected, transcribed confirmations.
        static let success = dynamic(light: 0x2D7A4D, dark: 0x5FA77C)
        /// Warning — cost-guard 30s deadline banner.
        static let warning = dynamic(light: 0xC28A2D, dark: 0xE0A05F)
        /// Error — Stop button, error states.
        static let error   = dynamic(light: 0xB8231F, dark: 0xDC4A3F)

        // MARK: Helper
        static func dynamic(light: UInt32, dark: UInt32) -> SwiftUI.Color {
            SwiftUI.Color(uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(hex: dark)
                    : UIColor(hex: light)
            })
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >>  8) & 0xFF) / 255.0
        let b = CGFloat( hex        & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

// MARK: - Legacy shims (TODO remove once all call sites migrated to DS.Color.*)

/// Bridge to the old `BrandColors` enum used through Phase 1–4. Keeps the
/// migration shippable in one PR — call sites get progressively swapped to
/// `DS.Color.*` and `BrandColors` is deleted at the end.
enum BrandColors {
    static let background      = DS.Color.bgCanvas
    static let surface         = DS.Color.bgSurface
    static let textPrimary     = DS.Color.textInk
    static let textSecondary   = DS.Color.textMuted
    static let accent          = DS.Color.accent
    static let danger          = DS.Color.error
    static let border          = DS.Color.hairline
}
