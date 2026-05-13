import Foundation
import WatchConnectivity
import WatchKit
import Combine

@MainActor
final class WatchRideStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var summary: WatchRideSummary?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["rideState"] as? Data else { return }
        // Decode on the nonisolated thread before hopping to MainActor.
        // WatchRideSummary is Sendable so this is safe under Swift 6.
        let decoded = try? JSONDecoder().decode(WatchRideSummary.self, from: data)
        guard let decoded else { return }
        Task { @MainActor in
            self.summary = decoded
            if decoded.isOffRoute || decoded.nextPOIDistance.map({ $0 < 200 }) == true {
                WKInterfaceDevice.current().play(.notification)
            }
        }
    }
}
