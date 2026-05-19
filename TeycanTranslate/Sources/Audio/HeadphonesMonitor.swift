import AVFoundation
import Foundation
import Observation

/// Observes the current audio route and reports whether headphones / AirPods
/// are connected. Used by the Companion (Realtime) tab as the headphones gate
/// — playing realtime translation through the iPhone speaker creates audio
/// feedback and is wrong UX in public.
///
/// Detection covers wired headphones and Bluetooth (A2DP, LE, HFP profiles).
@Observable
@MainActor
final class HeadphonesMonitor {
    static let shared = HeadphonesMonitor()

    private(set) var isConnected: Bool = false
    /// User-facing description, e.g. "AirPods Pro", "Wired headphones".
    private(set) var deviceLabel: String = "No headphones"

    @ObservationIgnored
    private var observer: NSObjectProtocol?

    nonisolated private init() {
        // Initialize on MainActor lazily — observers wired the first time
        // someone reads the singleton.
        Task { @MainActor in
            HeadphonesMonitor.shared.refresh()
            HeadphonesMonitor.shared.observeRouteChanges()
        }
    }

    func refresh() {
        let route = AVAudioSession.sharedInstance().currentRoute
        let headphoneOutputs = route.outputs.filter { Self.isHeadphone($0.portType) }
        if let first = headphoneOutputs.first {
            isConnected = true
            deviceLabel = first.portName
        } else {
            isConnected = false
            deviceLabel = route.outputs.first?.portName ?? "No headphones"
        }
    }

    private func observeRouteChanges() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    private static func isHeadphone(_ portType: AVAudioSession.Port) -> Bool {
        switch portType {
        case .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .airPlay:
            return true
        default:
            return false
        }
    }
}
