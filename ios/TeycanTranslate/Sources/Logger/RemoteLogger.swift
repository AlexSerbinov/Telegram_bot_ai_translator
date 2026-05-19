import Foundation
import UIKit

/// Ships `DiagLogger` entries to the backend's `/api/logs` ring buffer so a
/// developer can `curl https://…/api/logs?limit=200` and watch the device's
/// internal state in near real-time.
///
/// Lifecycle: the singleton is created early in app launch and runs forever.
/// It batches incoming log lines and flushes them every `flushInterval`
/// seconds, or sooner if the queue exceeds `maxBatch`. Failures are silent —
/// remote logging must never affect the foreground flow.
actor RemoteLogger {
    static let shared = RemoteLogger()

    private struct WireEntry: Encodable {
        let ts: Int64
        let tag: String
        let line: String
    }
    private struct Envelope: Encodable {
        let deviceID: String
        let entries: [WireEntry]
    }

    private let flushInterval: TimeInterval = 2.0
    private let maxBatch = 200
    private var queue: [WireEntry] = []
    private var flushTask: Task<Void, Never>?
    private let deviceID: String
    /// Allows the embedder to point logs at a different env (e.g. simulator
    /// dev) without touching `Endpoints`. Defaults to whatever Endpoints
    /// resolved at app launch.
    private var endpoint: URL = Endpoints.logs

    init() {
        // Stable per-install identifier so I can grep one device out of many.
        let key = "remoteLogger.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            deviceID = existing
        } else {
            let new = UUID().uuidString.prefix(8).lowercased()
            UserDefaults.standard.set(String(new), forKey: key)
            deviceID = String(new)
        }
    }

    /// Returns the device id so the user / agent knows which `?deviceID=…`
    /// filter to use when querying the server.
    nonisolated var publicDeviceID: String {
        UserDefaults.standard.string(forKey: "remoteLogger.deviceID") ?? "?"
    }

    func setEndpoint(_ url: URL) {
        self.endpoint = url
    }

    func enqueue(tag: String, line: String) {
        queue.append(WireEntry(ts: Int64(Date().timeIntervalSince1970 * 1000), tag: tag, line: line))
        if queue.count >= maxBatch {
            Task { await self.flush() }
        } else {
            scheduleFlushIfNeeded()
        }
    }

    private func scheduleFlushIfNeeded() {
        guard flushTask == nil else { return }
        let interval = flushInterval
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            await self?.flush()
        }
    }

    private func flush() async {
        flushTask = nil
        guard !queue.isEmpty else { return }
        let batch = queue
        queue.removeAll(keepingCapacity: true)
        let envelope = Envelope(deviceID: deviceID, entries: batch)

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 4
        do {
            req.httpBody = try JSONEncoder().encode(envelope)
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                // Bubble back to the local console so a dev can spot it.
                print("[RemoteLogger] flush HTTP \(http.statusCode) — \(batch.count) entries dropped")
            }
        } catch {
            print("[RemoteLogger] flush failed (\(error.localizedDescription)) — \(batch.count) entries dropped")
        }
    }
}
