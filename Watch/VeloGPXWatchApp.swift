import SwiftUI

@main
struct VeloGPXWatchApp: App {
    @StateObject private var rideStore = WatchRideStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchRideView(store: rideStore)
            }
        }
    }
}
