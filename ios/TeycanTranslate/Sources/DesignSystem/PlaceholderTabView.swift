import SwiftUI

/// Used by all three tabs in Phase 1 — replaced with real content in later phases.
struct PlaceholderTabView: View {
    let title: String
    let subtitle: String
    let icon: String
    let description: String

    var body: some View {
        ZStack {
            BrandColors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: icon)
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(BrandColors.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(BrandFont.title)
                                .foregroundStyle(BrandColors.textPrimary)
                            Text(subtitle)
                                .font(BrandFont.caption)
                                .foregroundStyle(BrandColors.textSecondary)
                        }
                    }
                    .padding(.top, 8)

                    Text(description)
                        .font(BrandFont.body)
                        .foregroundStyle(BrandColors.textPrimary.opacity(0.85))
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BrandColors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(BrandColors.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    Text("Phase 1 placeholder · build 0.1.0")
                        .font(BrandFont.mono)
                        .foregroundStyle(BrandColors.textSecondary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle(title)
    }
}

#Preview {
    PlaceholderTabView(
        title: "Companion",
        subtitle: "gpt-realtime-translate · WebRTC",
        icon: "waveform.circle.fill",
        description: "Phase 2 placeholder."
    )
}
