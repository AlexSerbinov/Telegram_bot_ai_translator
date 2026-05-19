import SwiftUI

/// Editorial-strict language selector pill per DESIGN.md § Components > Lang Pill.
/// Used in Phrase (top, From / To), Bridge (top, A / B), and Companion (target).
///
/// Composition:
///   - 4pt corner, surface bg, hairline border
///   - Inner: eyebrow label (Mono 9–11pt UPPER 0.14em) + value (15pt Semibold)
///   - Tap target: full pill, presents a sheet with the language list.
struct LangPill: View {
    let eyebrow: String
    let flag: String
    let code: String
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                EyebrowLabel(text: eyebrow)
                HStack(spacing: 6) {
                    Text(flag)
                    Text(code.uppercased())
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.Color.textInk)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(DS.Color.textMuted)
                }
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .stroke(DS.Color.hairline, lineWidth: DS.Stroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(eyebrow): \(code)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Compact 28pt swap button between two `LangPill`s. Mono `⇄` glyph.
struct LangSwapButton: View {
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.left.arrow.right")
                .font(DS.Font.mono)
                .foregroundStyle(DS.Color.textInk)
                .frame(width: 28, height: 28)
                .background(DS.Color.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .stroke(DS.Color.hairline, lineWidth: DS.Stroke.hairline)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel("Swap languages")
    }
}

#Preview {
    HStack(spacing: 8) {
        LangPill(eyebrow: "FROM", flag: "🇺🇦", code: "ua") {}
        LangSwapButton {}
        LangPill(eyebrow: "TO", flag: "🇪🇸", code: "es") {}
    }
    .padding(20)
    .background(DS.Color.bgCanvas)
}
