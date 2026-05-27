import Foundation

/// Pure logic that decides which way to translate based on the language
/// labels Soniox attaches to each token. Knows nothing about networking,
/// audio, or UI — fully unit-testable in isolation.
///
/// Behavior (from approved plan, 2026-05-19):
/// 1. Track only `isFinal: true` tokens — non-finals can flip back and forth.
/// 2. Need ≥ `minConfidence` (default 3) consecutive same-language final
///    tokens before committing a direction. A single misclassified token
///    (e.g., the filler "OK" tagged `en` in an otherwise-Ukrainian
///    utterance) won't flip direction.
/// 3. When a turn ends (caller calls `commit()`), compute:
///    - `finalText` = concatenation of every absorbed final token
///    - `sourceLang` = the language that has the majority of confident
///      same-language streaks. If no streak reached `minConfidence`,
///      fall back to whatever Soniox saw most often. If still ambiguous,
///      use the bootstrap guess (script-based) on the final text.
///    - If the resolved source isn't in {langA, langB} (third language),
///      fall back to `langA` as source so we still translate to `langB`
///      (default direction).
///    - `targetLang` = the OTHER of {langA, langB} from the source.
struct RelayDirectionResolver {
    struct Commit: Equatable {
        let sourceLang: String
        let targetLang: String
        let finalText: String
        /// True when the source language came from `langA`/`langB` per-token
        /// majority; false when we had to fall back (third language, or
        /// no language signal at all). UI surfaces a "(detected: …)" hint
        /// in that case.
        let wasFallback: Bool
    }

    let langA: String
    let langB: String
    let minConfidence: Int

    private var finalTokens: [(text: String, lang: String?)] = []

    init(langA: String, langB: String, minConfidence: Int = 3) {
        self.langA = langA
        self.langB = langB
        self.minConfidence = minConfidence
    }

    /// Absorb one Soniox token (any state). Non-final tokens are ignored —
    /// we only commit direction once a token is `isFinal`.
    mutating func absorb(text: String, language: String?, isFinal: Bool) {
        guard isFinal else { return }
        finalTokens.append((text: text, lang: language))
    }

    /// Called by the session manager when the user stops speaking (or when
    /// the idle timer fires). Returns `nil` if no final tokens have arrived
    /// — the caller should treat the turn as empty and skip translation.
    func commit() -> Commit? {
        let finalText = finalTokens
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else { return nil }

        let resolved = resolveSource(finalText: finalText)
        let (source, fellBack) = resolved
        let target = (source == langA) ? langB : langA
        return Commit(
            sourceLang: source,
            targetLang: target,
            finalText: finalText,
            wasFallback: fellBack
        )
    }

    /// Lets the session manager peek at the current best guess without
    /// committing — useful for the "(detected: UK)" eyebrow that updates as
    /// the user talks. Returns `nil` until at least one final token has a
    /// language tag.
    func currentGuess() -> String? {
        let lang = majorityFinalLang(restrictTo: nil)
        return lang
    }

    /// Reset to the empty state for a new turn.
    mutating func reset() {
        finalTokens.removeAll(keepingCapacity: true)
    }

    /// Number of finalized tokens absorbed this turn — used by the
    /// session manager's split detection for assertion-style logging.
    var finalTokenCount: Int { finalTokens.count }

    /// Pop the trailing `n` finalized tokens off this turn. Used by the
    /// session manager when a mid-turn speaker or language change is
    /// detected and we need those last `n` tokens to belong to the NEXT
    /// turn instead. Returns them in original order so the caller can
    /// feed them forward into the next turn.
    mutating func popLastFinals(_ n: Int) -> [(text: String, lang: String?)] {
        let k = min(max(n, 0), finalTokens.count)
        guard k > 0 else { return [] }
        let tail = Array(finalTokens.suffix(k))
        finalTokens.removeLast(k)
        return tail
    }

    // MARK: - Internal resolution logic

    private func resolveSource(finalText: String) -> (lang: String, fellBack: Bool) {
        // Step 1: longest consecutive same-language streak of ≥ minConfidence
        // among langA/langB. Highest priority because it ignores transient
        // misclassifications.
        if let streakLang = longestConfidentStreak(restrictTo: [langA, langB]) {
            return (streakLang, false)
        }
        // Step 2: simple majority over final tokens (restricted to the pair).
        if let majority = majorityFinalLang(restrictTo: [langA, langB]) {
            return (majority, false)
        }
        // Step 3: any lang Soniox reported (third-language case) — fall back
        // to langA per approved plan.
        if majorityFinalLang(restrictTo: nil) != nil {
            return (langA, true)
        }
        // Step 4: Soniox gave us zero language labels — bootstrap via
        // script-based guesser on the accumulated text.
        let guessed = LanguageGuesser.guess(text: finalText, langA: langA, langB: langB)
        return (guessed, false)
    }

    private func longestConfidentStreak(restrictTo allowed: [String]?) -> String? {
        var bestLang: String?
        var bestLen = 0
        var curLang: String?
        var curLen = 0
        for tok in finalTokens {
            guard let lang = tok.lang, !lang.isEmpty else {
                // Token with no language tag breaks the streak.
                curLang = nil; curLen = 0
                continue
            }
            if let allowed, !allowed.contains(lang) {
                curLang = nil; curLen = 0
                continue
            }
            if lang == curLang {
                curLen += 1
            } else {
                curLang = lang
                curLen = 1
            }
            if curLen > bestLen {
                bestLen = curLen
                bestLang = curLang
            }
        }
        return bestLen >= minConfidence ? bestLang : nil
    }

    private func majorityFinalLang(restrictTo allowed: [String]?) -> String? {
        var counts: [String: Int] = [:]
        for tok in finalTokens {
            guard let lang = tok.lang, !lang.isEmpty else { continue }
            if let allowed, !allowed.contains(lang) { continue }
            counts[lang, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
