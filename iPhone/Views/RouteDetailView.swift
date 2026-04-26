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
    // WWDC 2025: LookAround
    @State private var lookAroundScene: MKLookAroundScene? = nil
    @State private var showLookAround = false
    @State private var lookAroundUnavailable = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // MARK: LookAround Preview (WWDC 2025)
                // Shows a tappable street-level preview of the route start.
                // Hidden automatically when LookAround has no imagery for the location.
                if !lookAroundUnavailable {
                    lookAroundCard
                }

                // MARK: Hero Elevation Card
                if hasElevationData {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Elevation Profile", systemImage: "mountain.2.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Chart(elevationSamples, id: \.distance) { sample in
                            AreaMark(
                                x: .value("Distance", sample.distance),
                                y: .value("Elevation", sample.elevation)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue.opacity(0.35), .blue.opacity(0.04)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            LineMark(
                                x: .value("Distance", sample.distance),
                                y: .value("Elevation", sample.elevation)
                            )
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        }
                        .chartXAxisLabel("km")
                        .chartYAxisLabel("m")
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) {
                                AxisGridLine().foregroundStyle(Color(.systemGray5))
                                AxisValueLabel()
                            }
                        }
                        .chartYAxis {
                            AxisMarks(values: .automatic(desiredCount: 3)) {
                                AxisGridLine().foregroundStyle(Color(.systemGray5))
                                AxisValueLabel()
                            }
                        }
                        .frame(height: 160)
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
                }

                // MARK: Key Stats Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MetricTile(label: "DISTANCE", value: String(format: "%.1f", route.totalDistance / 1000), unit: "km", icon: "arrow.left.and.right", color: .blue)
                    MetricTile(label: "GAIN", value: String(format: "%.0f", route.elevationGain), unit: "m", icon: "arrow.up", color: .green)
                    MetricTile(label: "LOSS", value: String(format: "%.0f", route.elevationLoss), unit: "m", icon: "arrow.down", color: .orange)
                }

                // MARK: Route Info Card
                VStack(spacing: 0) {
                    DetailSectionHeader(title: "Route", systemImage: "map")

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
                        .padding(14)
                    } else {
                        DetailRow(label: "Name", value: route.name)
                            .onTapGesture {
                                pendingName = route.name
                                isRenaming = true
                            }
                            .overlay(alignment: .trailing) {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.trailing, 14)
                            }
                    }
                    Divider().padding(.leading, 14)
                    DetailRow(label: "Format", value: route.sourceFormat.rawValue.uppercased())
                    Divider().padding(.leading, 14)
                    DetailRow(label: "Track Points", value: "\(route.trackPoints.count)")
                    if let filename = route.originalFilename {
                        Divider().padding(.leading, 14)
                        DetailRow(label: "File", value: filename)
                    }
                    Divider().padding(.leading, 14)
                    Button(role: .destructive) {
                        showReverseConfirm = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .frame(width: 20)
                            Text("Reverse Route Direction")
                            Spacer()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .padding(14)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                .confirmationDialog(
                    "Reverse this route?",
                    isPresented: $showReverseConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Reverse", role: .destructive) { routeStore.reverseRoute(route) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The start and end points will be swapped. This cannot be undone.")
                }

                // MARK: POIs Card
                VStack(spacing: 0) {
                    DetailSectionHeader(
                        title: "Points of Interest",
                        systemImage: "mappin.and.ellipse",
                        badge: routeStore.selectedPOIs.count > 0 ? "\(routeStore.selectedPOIs.count)" : nil
                    )

                    if routeStore.selectedPOIs.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.slash")
                                .foregroundStyle(.tertiary)
                            Text("No POIs added yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                    } else {
                        ForEach(routeStore.selectedPOIs) { poi in
                            POIRow(poi: poi)
                            if poi.id != routeStore.selectedPOIs.last?.id {
                                Divider().padding(.leading, 50)
                            }
                        }
                    }

                    Divider().padding(.leading, 14)
                    Button {
                        showPOIDiscovery = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkle.magnifyingglass")
                                .frame(width: 20)
                            Text("Discover POIs along route")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)
                        .padding(14)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)

                // MARK: Waypoints Card
                if !route.waypoints.isEmpty {
                    VStack(spacing: 0) {
                        DetailSectionHeader(
                            title: "Embedded Waypoints",
                            systemImage: "flag",
                            badge: "\(route.waypoints.count)"
                        )
                        ForEach(route.waypoints) { wp in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(wp.name ?? "Waypoint")
                                    .font(.subheadline.weight(.medium))
                                Text(String(format: "%.5f, %.5f",
                                            wp.coordinate.latitude,
                                            wp.coordinate.longitude))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            if wp.id != route.waypoints.last?.id {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Route Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPOIDiscovery) {
            POIDiscoverySheet(route: route)
                .onDisappear { routeStore.savePOIs() }
        }
        // WWDC 2025: LookAround full-screen viewer
        .fullScreenCover(isPresented: $showLookAround) {
            if let scene = lookAroundScene {
                LookAroundViewer(scene: scene)
                    .ignoresSafeArea()
                    .overlay(alignment: .topTrailing) {
                        Button { showLookAround = false } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.9))
                                .shadow(radius: 4)
                        }
                        .padding(20)
                    }
            }
        }
        .task { await fetchLookAroundScene() }
    }

    // MARK: - LookAround Card

    @ViewBuilder
    private var lookAroundCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Street Preview")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Route Start")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemGray6).opacity(0.6))

            if let scene = lookAroundScene {
                // SwiftUI-native LookAroundPreview (iOS 17+)
                LookAroundPreview(initialScene: scene)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 0))
                    .overlay(alignment: .bottomTrailing) {
                        Button {
                            showLookAround = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Expand")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                        }
                        .padding(10)
                    }
            } else {
                // Shimmer placeholder while fetching
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color(.systemGray5))
                    .frame(height: 180)
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
    }

    // MARK: - LookAround Fetch

    private func fetchLookAroundScene() async {
        guard let firstPoint = route.trackPoints.first else {
            lookAroundUnavailable = true
            return
        }
        let request = MKLookAroundSceneRequest(coordinate: firstPoint.coordinate.clCoordinate)
        do {
            if let scene = try await request.scene {
                lookAroundScene = scene
            } else {
                lookAroundUnavailable = true
            }
        } catch {
            lookAroundUnavailable = true
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

// MARK: - LookAround Full-Screen Viewer (UIKit bridge)

private struct LookAroundViewer: UIViewControllerRepresentable {
    let scene: MKLookAroundScene

    func makeUIViewController(context: Context) -> MKLookAroundViewController {
        let vc = MKLookAroundViewController(scene: scene)
        vc.showsRoadLabels = true
        vc.pointsOfInterestFilter = .includingAll
        return vc
    }

    func updateUIViewController(_ uiViewController: MKLookAroundViewController, context: Context) {
        uiViewController.scene = scene
    }
}

// MARK: - Shared Sub-components

struct DetailSectionHeader: View {
    let title: String
    let systemImage: String
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.blue)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.blue, in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.systemGray6).opacity(0.6))
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
            Text(unit)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
    }
}

struct POIRow: View {
    let poi: POIModel

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: poi.category.systemImage)
                    .font(.system(size: 15))
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(poi.name)
                    .font(.subheadline.weight(.medium))
                Text(poi.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
