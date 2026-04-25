import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("Import") {
                    Text("VeloGPX can register GPX and GeoJSON as document types so files downloaded from Safari or opened from Files can be sent straight into the app.")
                }
                Section("Map") {
                    Text("V2 uses newer SwiftUI MapKit APIs with MapCameraPosition, MapPolyline, and Annotation support.")
                }
                Section("Watch") {
                    Text("Apple Watch remains the lightweight glance and haptics companion.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
