import SwiftUI

enum AppTab: Int {
    case routes, plan, ride, history, settings
}

struct RootView: View {
    @EnvironmentObject private var lm: LocalizationManager
    @State private var selectedTab: AppTab = .routes

    var body: some View {
        TabView(selection: $selectedTab) {

            RouteLibraryView()
                .tabItem { Label("Routes".localized, systemImage: "map") }
                .tag(AppTab.routes)

            PlanView(switchToRide: { selectedTab = .ride })
                .tabItem { Label("Plan".localized, systemImage: "map.fill") }
                .tag(AppTab.plan)

            RideView()
                .tabItem { Label("Ride".localized, systemImage: "bicycle") }
                .tag(AppTab.ride)

            RideHistoryView()
                .tabItem { Label("My Rides".localized, systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)

            SettingsView()
                .tabItem { Label("Settings".localized, systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .id(lm.currentLanguage)
    }
}
