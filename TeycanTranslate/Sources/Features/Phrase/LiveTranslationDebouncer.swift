import Foundation

/// Schedules a single async translate call after the source transcript has
/// been quiet for `quietMs` (default 350 ms). Mirrors the Mini App's live
/// translate debounce — each new transcript update cancels any pending
/// in-flight schedule and reschedules.
@MainActor
final class LiveTranslationDebouncer {
    private var task: Task<Void, Never>?
    private let quietMs: UInt64
    let translate: (String) async -> Void

    init(quietMs: Int = 350, translate: @escaping (String) async -> Void) {
        self.quietMs = UInt64(quietMs) * 1_000_000
        self.translate = translate
    }

    /// Call on every transcript update. Cancels any pending fire and schedules
    /// a new one for `quietMs` from now.
    func schedule(text: String) {
        task?.cancel()
        let waitNs = quietMs
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: waitNs)
            guard let self, !Task.isCancelled else { return }
            await self.translate(text)
        }
    }

    /// Force-cancel any pending translate fire.
    func cancel() {
        task?.cancel()
        task = nil
    }
}
