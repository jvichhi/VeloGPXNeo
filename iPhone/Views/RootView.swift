import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            RouteLibraryView()
                .tabItem { Label("Routes", systemImage: "map") }

            RideView()
                .tabItem { Label("Ride", systemImage: "bicycle") }

            RideHistoryView()
                .tabItem { Label("My Rides", systemImage: "clock.arrow.circlepath") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
