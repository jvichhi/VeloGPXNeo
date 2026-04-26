import Foundation
import SwiftUI
import UniformTypeIdentifiers

@main
struct VeloGPXApp: App {
    @StateObject private var routeStore   = RouteStore()
    @StateObject private var historyStore = RideHistoryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(routeStore)
                .environmentObject(historyStore)
                .task {
                    routeStore.loadFromDisk()
                }
                .onOpenURL { url in
                    Task { await routeStore.importRoute(from: url) }
                }
        }
    }
}
