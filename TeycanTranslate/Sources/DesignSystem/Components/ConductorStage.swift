import SwiftUI

/// V9 Conductor stage — the top half of the Bridge tab. Replaces the old
/// "Side A pill / swap / Side B pill" + center M layout. Three actors are
/// visible at once (left endpoint, central M, right endpoint) and the
/// realtime cycle phase drives:
///
/// 1. **Endpoint activation** — the side whose turn it is gets the accent
///    border + soft fill, plus a state label (`listening` / `done` / `hearing`).
/// 2. **Dataflow between endpoint and M** — when meaning is flowing one way,
///    the corresponding `DataFlow` strip animates 3 accent dots in that
///    direction.
/// 3. **M's halo + orbit** — during `.translating` the M node grows three
///    orbiting dots; the halo behind it intensifies.
/// 4. **Live caption** — last partial transcript text shown below the stage
///    in a centered caption box. Empty state shows a one-line hint.
///
/// Tapping either endpoint invokes `onTapSideA` / `onTapSideB` (production:
/// opens `BridgeLangPickerSheet`). The M node is non-interactive — model is
/// changed via the prompt-editor sheet, not by tapping M.
struct ConductorStage: View {
    let phase: BridgeSessionManager.CyclePhase
    let langA: PhraseLanguage
    let langB: PhraseLanguage
    /// Most recent streaming-or-final text to show under the stage. Pass the
    /// last bubble's text from `BridgeViewModel`.
    let liveCaption: String
    /// Which side the live caption belongs to (so we can label it correctly).
    let liveCaptionSide: BridgeSessionManager.ConductorSide?
    /// True while the caption text is still streaming (not yet finalized).
    let isPartial: Bool
    var onTapSideA: () -> Void
    var onTapSideB: () -> Void

    var body: some View {
        let leftFlow = dataflow(for: .a)
        let rightFlow = dataflow(for: .b)
        VStack(spacing: DS.Space.md) {
            HStack(alignment: .center, spacing: DS.Space.sm) {
                EndpointPill(
                    eyebrow: "Side A",
                    flag: langA.flag,
                    code: langA.code,
                    isActive: isSideActive(.a),
                    state: stateLabel(for: .a),
                    onTap: onTapSideA
                )

                DataFlow(
                    direction: leftFlow.direction,
                    isActive: leftFlow.active
                )
                .frame(minWidth: 36)

                centralM

                DataFlow(
                    direction: rightFlow.direction,
                    isActive: rightFlow.active
                )
                .frame(minWidth: 36)

                EndpointPill(
                    eyebrow: "Side B",
                    flag: langB.flag,
                    code: langB.code,
                    isActive: isSideActive(.b),
                    state: stateLabel(for: .b),
                    onTap: onTapSideB
                )
            }

            captionBox
        }
        .padding(DS.Space.md)
        .background(DS.Color.accent.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(DS.Color.hairline, lineWidth: DS.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .animation(.easeOut(duration: 0.2), value: phase)
    }

    // MARK: - Central M

    private var centralM: some View {
        ZStack {
            // Halo: idle = subtle (0.4 opacity, small), translating = dramatic
            // (1.0 opacity, bigger, brighter). Animates between states so the
            // transition from "phrase ended" to "model thinking" is obvious.
            Circle()
                .fill(DS.Color.accentGlow)
                .frame(width: isTranslating ? 104 : 72,
                       height: isTranslating ? 104 : 72)
                .blur(radius: isTranslating ? 16 : 10)
                .opacity(isTranslating ? 1.0 : 0.4)
                .animation(.easeOut(duration: 0.35), value: isTranslating)
            Circle()
                .fill(DS.Color.bgSurface)
                .frame(width: 48, height: 48)
            Circle()
                .strokeBorder(DS.Color.accent,
                              lineWidth: isTranslating ? 2.0 : DS.Stroke.accent)
                .frame(width: 48, height: 48)
                .animation(.easeOut(duration: 0.25), value: isTranslating)
            Text("M")
                .font(DS.Font.monoEmphasis)
                .foregroundStyle(DS.Color.accent)
                .scaleEffect(isTranslating ? 1.1 : 1.0)
                .animation(.easeOut(duration: 0.25), value: isTranslating)
            // Orbiting dots when translating — three of them whirl around M
            // at 1.0s linear loop, signaling "model is generating".
            if isTranslating {
                OrbitDots()
            }
        }
        .frame(width: 56, height: 56)
    }

    // MARK: - Caption

    @ViewBuilder
    private var captionBox: some View {
        VStack(spacing: 2) {
            if let side = liveCaptionSide {
                let lang = side == .a ? langA : langB
                Text("\(lang.flag) \(lang.code.uppercased())")
                    .font(DS.Font.eyebrow)
                    .foregroundStyle(DS.Color.textSubtle)
            } else {
                Text(" ").font(DS.Font.eyebrow)  // height-stable spacer
            }
            Text(liveCaption.isEmpty
                 ? "Tap mic. M will detect language and translate to the other side."
                 : liveCaption)
                .font(liveCaption.isEmpty ? DS.Font.caption : DS.Font.bodyEmphasis)
                .foregroundStyle(liveCaption.isEmpty ? DS.Color.textSubtle : DS.Color.textInk)
                .italic(isPartial && !liveCaption.isEmpty)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, DS.Space.sm)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 56)
        .padding(.top, DS.Space.sm)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DS.Color.hairline)
                .frame(height: DS.Stroke.hairline)
        }
    }

    // MARK: - Phase → visual state

    private func isSideActive(_ s: BridgeSessionManager.ConductorSide) -> Bool {
        switch phase {
        case .idle: return false
        case .sourceListening(let side), .sourceFinished(let side): return side == s
        case .translating: return false  // both endpoints rest while M generates
        case .targetSpeaking(let side): return side == s
        }
    }

    private func isFlowing(from s: BridgeSessionManager.ConductorSide) -> Bool {
        dataflow(for: s).active
    }

    /// Per-side dataflow state: which way the dots travel AND whether they
    /// animate at all. Layout: Side A on the left, M in the middle, Side B on
    /// the right. Direction always matches "from origin to target":
    /// - sourceListening(.a) → A is speaking, meaning flows A → M (LR)
    /// - sourceListening(.b) → B is speaking, meaning flows B → M (RL)
    /// - targetSpeaking(.a)  → M is speaking to A, meaning flows M → A (RL)
    /// - targetSpeaking(.b)  → M is speaking to B, meaning flows M → B (LR)
    /// Both endpoints rest during `.sourceFinished` and `.translating` —
    /// the cognitive work is on M during translation, no flow yet.
    private func dataflow(for s: BridgeSessionManager.ConductorSide) -> (active: Bool, direction: DataFlow.Direction) {
        switch phase {
        case .sourceListening(let side) where side == s:
            return (true, s == .a ? .leftToRight : .rightToLeft)
        case .targetSpeaking(let side) where side == s:
            return (true, s == .a ? .rightToLeft : .leftToRight)
        default:
            return (false, s == .a ? .leftToRight : .rightToLeft)
        }
    }

    private var isTranslating: Bool {
        if case .translating = phase { return true }
        return false
    }

    private func stateLabel(for s: BridgeSessionManager.ConductorSide) -> String {
        switch phase {
        case .idle: return ""
        case .sourceListening(let side) where side == s: return "speaking"
        case .sourceFinished(let side) where side == s: return "done"
        case .translating: return ""
        case .targetSpeaking(let side) where side == s: return "hearing"
        default: return ""
        }
    }
}

/// Three orbiting dots around the M node — only shown during `.translating`.
private struct OrbitDots: View {
    @State private var angle: Double = 0
    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .fill(DS.Color.accent)
                    .frame(width: 5, height: 5)
                    .offset(x: 32, y: 0)
                    .rotationEffect(.degrees(Double(i) * 120 + angle))
            }
        }
        .frame(width: 56, height: 56)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                angle = 360
            }
        }
    }
}

#Preview {
    let uk = PhraseLanguages.find("uk")!
    let es = PhraseLanguages.find("es")!
    return VStack(spacing: 16) {
        ConductorStage(
            phase: .idle,
            langA: uk, langB: es,
            liveCaption: "",
            liveCaptionSide: nil,
            isPartial: false,
            onTapSideA: {}, onTapSideB: {}
        )
        ConductorStage(
            phase: .sourceListening(side: .a),
            langA: uk, langB: es,
            liveCaption: "Привіт, як справи..",
            liveCaptionSide: .a,
            isPartial: true,
            onTapSideA: {}, onTapSideB: {}
        )
        ConductorStage(
            phase: .translating(sourceSide: .a),
            langA: uk, langB: es,
            liveCaption: "Привіт, як справи сьогодні?",
            liveCaptionSide: .a,
            isPartial: false,
            onTapSideA: {}, onTapSideB: {}
        )
        ConductorStage(
            phase: .targetSpeaking(side: .b),
            langA: uk, langB: es,
            liveCaption: "Hola, ¿cómo estás hoy?",
            liveCaptionSide: .b,
            isPartial: false,
            onTapSideA: {}, onTapSideB: {}
        )
    }
    .padding(20)
    .background(DS.Color.bgCanvas)
}
