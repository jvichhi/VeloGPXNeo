import SwiftUI
import MapKit

/// Full-screen sheet shown after a ride ends.
/// Displays stats, a map snapshot of the actual track, visited POIs,
/// and export options (track + optional planned route + POIs).
struct RideSummaryView: View {
    let summary: RideSummary
    var onDismiss: () -> Void

    @State private var mapSnapshot: UIImage?
    @State private var exportActualTrack = true
    @State private var exportPlannedRoute = false
    @State private var exportPOIs = true
    @State private var showShareSheet = false
    @State private var gpxFileURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    mapSnapshotSection
                    statsSection
                    if !summary.pois.isEmpty { poisSection }
                    exportSection
                }
                .padding()
            }
            .navigationTitle("Ride Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDismiss)
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = gpxFileURL {
                    ShareSheet(items: [url])
                }
            }
            .task { await generateMapSnapshot() }
        }
    }

    // MARK: - Map Snapshot

    @ViewBuilder
    private var mapSnapshotSection: some View {
        Group {
            if let img = mapSnapshot {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemGray5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .overlay {
                        ProgressView().tint(.secondary)
                    }
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }

    // MARK: - Stats

    @ViewBuilder
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary.routeName)
                .font(.title2.bold())

            Text(summary.startDate.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                summaryTile("Distance", String(format: "%.2f km", summary.distanceKm),  icon: "arrow.triangle.swap")
                summaryTile("Time",     summary.elapsedTime.formattedDuration,           icon: "clock.fill")
                summaryTile("Avg Speed", String(format: "%.1f km/h", summary.avgSpeedKmh), icon: "speedometer")
                summaryTile("Max Speed", String(format: "%.1f km/h", summary.maxSpeedKmh), icon: "gauge.with.dots.needle.67percent")
                summaryTile("Elev Gain", String(format: "%.0f m", summary.elevationGain),  icon: "mountain.2.fill")
                summaryTile("Stops",     "\(summary.pois.count) POI\(summary.pois.count == 1 ? "" : "s")", icon: "mappin.circle.fill")
            }
        }
        .padding()
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    @ViewBuilder
    private func summaryTile(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - POIs

    @ViewBuilder
    private var poisSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Points of Interest", systemImage: "mappin.and.ellipse")
                .font(.headline)

            ForEach(summary.pois) { poi in
                HStack(spacing: 12) {
                    Image(systemName: poi.category.systemImage)
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(poi.name).font(.subheadline.weight(.medium))
                        Text(poi.category.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                if poi.id != summary.pois.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - Export

    @ViewBuilder
    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Export as GPX", systemImage: "square.and.arrow.up")
                .font(.headline)

            VStack(spacing: 0) {
                exportToggle("Actual Track", isOn: $exportActualTrack, alwaysOn: true)
                Divider().padding(.leading, 36)
                exportToggle("Original Planned Route", isOn: $exportPlannedRoute)
                if !summary.pois.isEmpty {
                    Divider().padding(.leading, 36)
                    exportToggle("Points of Interest (\(summary.pois.count))", isOn: $exportPOIs)
                }
            }
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))

            Button {
                exportGPX()
            } label: {
                Label("Share GPX File", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!exportActualTrack && !exportPlannedRoute)
        }
        .padding()
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func exportToggle(_ label: String, isOn: Binding<Bool>, alwaysOn: Bool = false) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            if alwaysOn {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 22))
            } else {
                Toggle("", isOn: isOn).labelsHidden()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func exportGPX() {
        let options = GPXExporter.Options(
            includeActualTrack: exportActualTrack,
            includePlannedRoute: exportPlannedRoute,
            includePOIs: exportPOIs && !summary.pois.isEmpty
        )
        let gpxString = GPXExporter.export(summary, options: options)

        let filename = summary.routeName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filename)_ride.gpx")

        do {
            try gpxString.write(to: url, atomically: true, encoding: .utf8)
            gpxFileURL = url
            showShareSheet = true
        } catch {
            print("GPX export failed: \(error)")
        }
    }

    // MARK: - Map Snapshot Generator

    private func generateMapSnapshot() async {
        guard !summary.actualTrack.isEmpty else { return }

        // Compute bounding rect over the actual track
        let coords = summary.actualTrack
        let minLat = coords.map(\.latitude).min()!
        let maxLat = coords.map(\.latitude).max()!
        let minLon = coords.map(\.longitude).min()!
        let maxLon = coords.map(\.longitude).max()!

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latDelta = max((maxLat - minLat) * 1.4, 0.005)
        let lonDelta = max((maxLon - minLon) * 1.4, 0.005)
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: UIScreen.main.bounds.width - 32, height: 220)
        options.scale = UIScreen.main.scale
        options.mapType = .standard
        options.showsBuildings = false

        do {
            let snapshotter = MKMapSnapshotter(options: options)
            let snapshot = try await snapshotter.start()

            // Draw actual track overlay on snapshot
            let image = UIGraphicsImageRenderer(size: options.size).image { _ in
                snapshot.image.draw(at: .zero)

                let path = UIBezierPath()
                for (i, coord) in coords.enumerated() {
                    let point = snapshot.point(for: coord)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                UIColor.systemBlue.withAlphaComponent(0.85).setStroke()
                path.lineWidth = 3
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()

                // Draw planned track in lighter blue if present
                if !summary.plannedTrack.isEmpty {
                    let planned = UIBezierPath()
                    for (i, coord) in summary.plannedTrack.enumerated() {
                        let point = snapshot.point(for: coord)
                        if i == 0 { planned.move(to: point) } else { planned.addLine(to: point) }
                    }
                    UIColor.systemBlue.withAlphaComponent(0.25).setStroke()
                    planned.lineWidth = 2
                    planned.setLineDash([6, 4], count: 2, phase: 0)
                    planned.stroke()
                }

                // Draw POI dots
                for poi in summary.pois {
                    let pt = snapshot.point(for: poi.coordinate.clCoordinate)
                    let dot = UIBezierPath(ovalIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10))
                    UIColor.systemOrange.setFill()
                    UIColor.white.setStroke()
                    dot.fill()
                    dot.lineWidth = 1.5
                    dot.stroke()
                }
            }
            mapSnapshot = image
        } catch {
            // Snapshot failed silently — map section stays as a placeholder
        }
    }
}

// MARK: - Duration formatting

private extension TimeInterval {
    var formattedDuration: String {
        let h = Int(self) / 3600
        let m = (Int(self) % 3600) / 60
        let s = Int(self) % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - UIActivityViewController wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
