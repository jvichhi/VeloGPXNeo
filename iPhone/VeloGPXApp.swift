import Foundation
import SwiftUI
import UniformTypeIdentifiers

@main
struct VeloGPXApp: App {
    @StateObject private var routeStore   = RouteStore()
    @StateObject private var historyStore = RideHistoryStore()
    @StateObject private var rideStore    = RideSessionStore()
    @StateObject private var lm           = LocalizationManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(routeStore)
                .environmentObject(historyStore)
                .environmentObject(rideStore)
                .environmentObject(lm)
                // Inject locale so SwiftUI Text(), formatters, and
                // date/number formatting all use the selected language.
                .environment(\.locale, Locale(identifier: lm.currentLanguage.rawValue))
                // Inject layout direction for RTL support (Arabic etc.)
                .environment(\.layoutDirection, lm.currentLanguage.layoutDirection)
                // Expose language as a custom EnvironmentKey for child views.
                .environment(\.appLanguage, lm.currentLanguage)
                // Force the ENTIRE view tree to recreate when language changes.
                // This is the key mechanism — without .id(), views cache their
                // Text() renders and won't re-evaluate even if @Published fires.
                .id(lm.currentLanguage)
                .task {
                    routeStore.loadFromDisk()
                }
                .onOpenURL { url in
                    Task { await routeStore.importRoute(from: url) }
                }
        }
    }
}
