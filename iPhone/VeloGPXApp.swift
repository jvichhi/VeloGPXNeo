import Foundation
import SwiftUI
import UniformTypeIdentifiers

@main
struct VeloGPXApp: App {
    @StateObject private var routeStore = RouteStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(routeStore)
                .task {
                    routeStore.loadFromDisk()
                }
                .onOpenURL { url in
                    Task { await routeStore.importRoute(from: url) }
                }
        }
    }
}
