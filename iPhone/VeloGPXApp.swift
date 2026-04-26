import Foundation
import SwiftUI
import UniformTypeIdentifiers

@main
struct VeloGPXApp: App {
    @StateObject private var routeStore   = RouteStore()
    @StateObject private var historyStore = RideHistoryStore()
    @StateObject private var lm           = LocalizationManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(routeStore)
                .environmentObject(historyStore)
                .environmentObject(lm)
                // Force the entire view tree to rebuild when language changes.
                // SwiftUI re-creates every view that holds @EnvironmentObject lm,
                // so all Text() calls re-evaluate with the new bundle.
                .id(lm.currentLanguage)
                .environment(\.layoutDirection, lm.currentLanguage.layoutDirection)
                .environment(\.appLanguage, lm.currentLanguage)
                .task {
                    routeStore.loadFromDisk()
                }
                .onOpenURL { url in
                    Task { await routeStore.importRoute(from: url) }
                }
        }
    }
}
