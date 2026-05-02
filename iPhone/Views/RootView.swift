import SwiftUI

enum AppTab: Int {
    case routes, plan, ride, history, settings
}

struct RootView: View {
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var routeStore: RouteStore

    var body: some View {
        TabView(selection: $routeStore.selectedTab) {

            RouteLibraryView()
                .tabItem { Label("Routes".localized, systemImage: "map") }
                .tag(AppTab.routes)

            PlanView(
                switchToRide: { routeStore.selectedTab = .ride },
                switchToRoutes: { routeStore.selectedTab = .routes }
            )
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
        // When routeToEditInPlan is set (e.g. from Routes "Plan" swipe action
        // or context menu), switch to the Plan tab. PlanView reads and clears
        // routeToEditInPlan in its own .task so there is no timing race.
        .onChange(of: routeStore.routeToEditInPlan) { _, route in
            if route != nil {
                routeStore.selectedTab = .plan
            }
        }
        // Reload persisted POIs whenever the selected route changes.
        .onChange(of: routeStore.selectedRoute?.id) { _, _ in
            guard let route = routeStore.selectedRoute else { return }
            routeStore.loadPOIs(forRoute: route)
        }
    }
}
