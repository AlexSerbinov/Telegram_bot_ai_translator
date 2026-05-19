import Foundation
import Observation
import OSLog

enum LogTag: String {
    case app
    case auth
    case net
    case audio
    case rtc        // WebRTC
    case stt        // Speech-to-text
    case tts        // Text-to-speech
    case guard_     // CostGuard (suffixed because `guard` is reserved)

    var rawTag: String {
        switch self {
        case .guard_: return "guard"
        default:      return rawValue
        }
    }
}

private let diagOSLogger = Logger(subsystem: "solutions.techchain.teycan.translate", category: "diag")
private let diagDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

/// Process-wide diagnostic logger. Maintains an in-memory ring buffer that the
/// `LogPanel` UI subscribes to, while also forwarding lines to `os.Logger` for
/// Console.app and `Instruments` use.
///
/// Designed to be safe to call from any thread/actor — internally serialized
/// via a lock-free queue around a `MainActor`-bound observable buffer.
@Observable
@MainActor
final class DiagLogger {
    nonisolated static let shared = DiagLogger()

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let tag: String
        let message: String
    }

    /// Last `capacity` lines, newest at the end. UI binds to this.
    private(set) var entries: [Entry] = []
    private let capacity = 500

    nonisolated private init() {}

    /// Thread-safe entry point — hops to MainActor. Also fans the entry out
    /// to `RemoteLogger` so server-side ring buffer + `curl /api/logs` work.
    nonisolated func log(_ tag: LogTag, _ message: String) {
        diagOSLogger.log("[\(tag.rawTag, privacy: .public)] \(message, privacy: .public)")
        let rawTag = tag.rawTag
        Task { @MainActor in
            Self.shared.append(tag: rawTag, message: message)
        }
        Task.detached(priority: .background) {
            await RemoteLogger.shared.enqueue(tag: rawTag, line: message)
        }
    }

    private func append(tag: String, message: String) {
        let entry = Entry(timestamp: Date(), tag: tag, message: message)
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    /// Returns the entire buffer as a multi-line string, ready for clipboard.
    func snapshot() -> String {
        entries
            .map { "\(diagDateFormatter.string(from: $0.timestamp)) [\($0.tag)] \($0.message)" }
            .joined(separator: "\n")
    }

    func clear() {
        entries.removeAll()
    }
}
