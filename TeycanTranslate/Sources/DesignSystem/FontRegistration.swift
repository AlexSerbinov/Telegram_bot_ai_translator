import CoreText
import Foundation
import UIKit

/// Programmatic font registration. Backup path in case `UIAppFonts` Info.plist
/// entries don't pick up (xcodegen sometimes mis-paths bundle resources).
/// Called once from `TeycanTranslateApp.init`.
enum FontRegistration {
    static func registerJetBrainsMono() {
        let names = [
            "JetBrainsMono-Regular",
            "JetBrainsMono-Medium",
            "JetBrainsMono-SemiBold",
        ]
        for name in names {
            // 1. Already loaded via Info.plist UIAppFonts — fast path.
            if UIFont(name: name, size: 12) != nil { continue }

            // 2. Programmatic registration as fallback.
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                NSLog("[fonts] Missing TTF in bundle: \(name)")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let err = (error?.takeRetainedValue()).map { String(describing: $0) } ?? "unknown"
                NSLog("[fonts] Register failed for \(name): \(err)")
            }
        }
    }
}
