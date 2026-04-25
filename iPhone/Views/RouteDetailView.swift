import SwiftUI
import Charts
import MapKit

struct RouteDetailView: View {
    @EnvironmentObject private var routeStore: RouteStore
    let route: RouteModel

    @State private var isRenaming = false
    @State private var pendingName = ""
    @State private var showPOIDiscovery = false
    @State private var showReverseConfirm = false

    var body: some View {
        List {
            if hasElevationData {
                Section("Elevation Profile") {
                    Chart(elevationSamples, id: \.distance) { sample in
                        AreaMark(
                            x: .value("Distance", sample.distance),
                            y: .value("Elevation", sample.elevation)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue.opacity(0.4), .blue.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("Distance", sample.distance),
                            y: .value("Elevation", sample.elevation)
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    .chartXAxisLabel("Distance (km)")
                    .chartYAxisLabel("m")
                    .frame(height: 160)
                    .padding(.vertical, 8)
                }
            }

            Section("Route") {
                if isRenaming {
                    HStack {
                        TextField("Route name", text: $pendingName)
                            .onSubmit { commitRename() }
                        Button("Save", action: commitRename)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        Button("Cancel") { isRenaming = false }
                            .controlSize(.small)
                    }
                } else {
                    LabeledContent("Name", value: route.name)
                        .onTapGesture {
                            pendingName = route.name
                            isRenaming = true
                        }
                        .overlay(alignment: .trailing) {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 4)
                        }
                }
                LabeledContent("Format", value: route.sourceFormat.rawValue.uppercased())
                LabeledContent("Distance", value: String(format: "%.1f km", route.totalDistance / 1000))
                LabeledContent("Elevation Gain", value: String(format: "%.0f m", route.elevationGain))
                LabeledContent("Elevation Loss", value: String(format: "%.0f m", route.elevationLoss))
                LabeledContent("Track Points", value: "\(route.trackPoints.count)")
                if let originalFilename = route.originalFilename {
                    LabeledContent("File", value: originalFilename)
                }

                Button(role: .destructive) {
                    showReverseConfirm = true
                } label: {
                    Label("Reverse Route Direction", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                }
                .confirmationDialog(
                    "Reverse this route?",
                    isPresented: $showReverseConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Reverse", role: .destructive) {
                        routeStore.reverseRoute(route)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The start and end points will be swapped. This cannot be undone.")
                }
            }

            // MARK: - POIs section
            Section {
                if routeStore.selectedPOIs.isEmpty {
                    Text("No POIs added yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(routeStore.selectedPOIs) { poi in
                    HStack(spacing: 10) {
                        Image(systemName: poi.category.systemImage)
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(poi.name)
                                .font(.subheadline)
                            Text(poi.category.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.forEach { routeStore.removePOI(routeStore.selectedPOIs[$0]) }
                }

                Button {
                    showPOIDiscovery = true
                } label: {
                    Label("Discover POIs along route", systemImage: "sparkle.magnifyingglass")
                        .foregroundStyle(.orange)
                }
            } header: {
                HStack {
                    Text("Points of Interest")
                    Spacer()
                    Text("\(routeStore.selectedPOIs.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Embedded Waypoints") {
                if route.waypoints.isEmpty {
                    Text("No embedded waypoints").foregroundStyle(.secondary)
                } else {
                    ForEach(route.waypoints) { waypoint in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(waypoint.name ?? "Waypoint")
                            Text(String(format: "%.5f, %.5f",
                                        waypoint.coordinate.latitude,
                                        waypoint.coordinate.longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Route Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPOIDiscovery) {
            POIDiscoverySheet(route: route)
                .onDisappear { routeStore.savePOIs() }
        }
    }

    private var hasElevationData: Bool {
        route.trackPoints.contains { $0.elevation != nil }
    }

    private struct ElevationSample {
        let distance: Double
        let elevation: Double
    }

    private var elevationSamples: [ElevationSample] {
        var samples: [ElevationSample] = []
        var cumulative = 0.0
        let points = route.trackPoints
        for (i, point) in points.enumerated() {
            guard let ele = point.elevation else { continue }
            if i > 0 {
                cumulative += point.coordinate.clCoordinate.distance(to: points[i - 1].coordinate.clCoordinate)
            }
            samples.append(ElevationSample(distance: cumulative / 1000, elevation: ele))
        }
        if samples.count > 300 {
            let stride = samples.count / 300
            samples = samples.enumerated().filter { $0.offset % stride == 0 }.map { $0.element }
        }
        return samples
    }

    private func commitRename() {
        let trimmed = pendingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        routeStore.renameRoute(route, to: trimmed)
        isRenaming = false
    }
}
