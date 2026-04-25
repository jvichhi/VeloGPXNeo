import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            RouteLibraryView()
                .tabItem { Label("Routes", systemImage: "map") }

            RideView()
                .tabItem { Label("Ride", systemImage: "bicycle") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
