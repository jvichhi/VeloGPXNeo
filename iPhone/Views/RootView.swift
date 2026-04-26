import SwiftUI

struct RootView: View {
    @EnvironmentObject private var lm: LocalizationManager

    var body: some View {
        TabView {
            RouteLibraryView()
                .tabItem { Label("Routes".localized, systemImage: "map") }

            RideView()
                .tabItem { Label("Ride".localized, systemImage: "bicycle") }

            RideHistoryView()
                .tabItem { Label("My Rides".localized, systemImage: "clock.arrow.circlepath") }

            SettingsView()
                .tabItem { Label("Settings".localized, systemImage: "gearshape") }
        }
        // Extra safety net: re-stamp the TabView identity when language flips
        // so tab labels re-render even if the .id() on the WindowGroup
        // somehow doesn't propagate in time.
        .id(lm.currentLanguage)
    }
}
