import SwiftUI
import UniformTypeIdentifiers


struct RouteLibraryView: View {
    @EnvironmentObject private var routeStore: RouteStore
    @State private var isImporterPresented = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(routeStore.routes) { route in
                    NavigationLink {
                        RouteDetailView(route: route)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(route.name)
                                .font(.headline)
                            HStack(spacing: 12) {
                                Text(String(format: "%.1f km", route.totalDistance / 1000))
                                Text(String(format: "%.0f m ↑", route.elevationGain))
                                Text(route.sourceFormat.rawValue.uppercased())
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        routeStore.selectedRoute = route
                    })
                }
                .onDelete { indexSet in
                    indexSet.forEach { routeStore.deleteRoute(routeStore.routes[$0]) }
                }
            }
            .navigationTitle("Routes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isImporterPresented = true } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [UTType(filenameExtension: "gpx")!, UTType(filenameExtension: "geojson")!, .json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        Task { await routeStore.importRoute(from: url) }
                    }
                case .failure:
                    routeStore.lastImportMessage = "Import cancelled"
                }
            }
            .overlay {
                if routeStore.routes.isEmpty {
                    ContentUnavailableView(
                        "No routes yet",
                        systemImage: "map",
                        description: Text("Import a GPX or GeoJSON file, or open one directly in VeloGPX from Safari, Files, or Mail.")
                    )
                }
            }
        }
        .alert("VeloGPX", isPresented: .constant(routeStore.lastImportMessage != nil), actions: {
            Button("OK") { routeStore.lastImportMessage = nil }
        }, message: {
            Text(routeStore.lastImportMessage ?? "")
        })
    }
}
