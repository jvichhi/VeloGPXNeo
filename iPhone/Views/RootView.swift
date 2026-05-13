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
                .tabItem { Label("Routes".localized, systemImage: "list.bullet.below.rectangle") }
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

        // "Ride This Route" action (swipe or context menu in RouteLibraryView).
        // Selecting the route, loading its POIs, and switching the tab all happen
        // here so the sequence is atomic and consistent — mirrors routeToEditInPlan.
        .onChange(of: routeStore.pendingRideRoute) { _, route in
            guard let route else { return }
            routeStore.selectedRoute = route
            routeStore.loadPOIs(forRoute: route)
            routeStore.selectedTab = .ride
            routeStore.pendingRideRoute = nil
        }

        // "Edit in Plan" action — switch to Plan tab; PlanView reads and
        // clears routeToEditInPlan in its own .task so there is no timing race.
        .onChange(of: routeStore.routeToEditInPlan) { _, route in
            if route != nil {
                routeStore.selectedTab = .plan
            }
        }
    }
}
