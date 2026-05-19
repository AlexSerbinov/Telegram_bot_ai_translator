import SwiftUI

/// 4pt grid spacing scale per `DESIGN.md` § Spacing + § Layout.
extension DS {
    enum Space {
        static let space2xs: CGFloat = 2
        static let xs:       CGFloat = 4
        static let sm:       CGFloat = 8
        static let md:       CGFloat = 12
        static let lg:       CGFloat = 16
        static let xl:       CGFloat = 20
        static let space2xl: CGFloat = 32
        static let space3xl: CGFloat = 48
    }

    enum Radius {
        /// Default — buttons, lang pills, badges.
        static let sm:   CGFloat = 4
        /// Conversation cards (Bridge turns), Companion target pill.
        static let md:   CGFloat = 6
        /// Modals, sheets, output containers.
        static let lg:   CGFloat = 8
        /// Mic button (Bridge), avatars, model node ring, live dot.
        static let full: CGFloat = 9999
    }

    enum Stroke {
        static let hairline: CGFloat = 1
        /// Mic button border, model node ring.
        static let accent:   CGFloat = 1
        /// Companion translated-line left border.
        static let accentBold: CGFloat = 2
    }
}
