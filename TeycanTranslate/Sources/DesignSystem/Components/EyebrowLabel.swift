import SwiftUI

/// JetBrains Mono Medium 11pt UPPERCASE 0.18em — used as section labels,
/// mode subtitles, eyebrows above output cards, status badges.
/// Per `DESIGN.md` § Components > Eyebrow Label.
struct EyebrowLabel: View {
    let text: String
    var color: Color = DS.Color.textMuted
    /// Per DESIGN.md, editorial-strict version uses leading em-dash + space.
    var leadingDash: Bool = false

    var body: some View {
        Text((leadingDash ? "— " : "") + text.uppercased())
            .font(DS.Font.eyebrow)
            .tracking(DS.Tracking.eyebrow)
            .foregroundStyle(color)
            .accessibilityLabel(text)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        EyebrowLabel(text: "Original · UK · 15 words")
        EyebrowLabel(text: "→ Target language", color: DS.Color.accent)
        EyebrowLabel(text: "Live", color: DS.Color.accent, leadingDash: true)
    }
    .padding(40)
    .background(DS.Color.bgCanvas)
}
