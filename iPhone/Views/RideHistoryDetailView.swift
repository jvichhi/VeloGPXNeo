import SwiftUI
import MapKit

/// Full detail view for a saved ride — mirrors RideSummaryView but
/// adds rename, shareable card, and planned-vs-actual overlay toggle.
struct RideHistoryDetailView: View {
    let ride: PersistedRideSummary

    @EnvironmentObject private var historyStore: RideHistoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var mapSnapshot: UIImage?
    @State private var showPlannedOverlay = false
    @State private var exportPOIs = true
    @State private var showShareGPX = false
    @State private var showShareCard = false
    @State private var gpxFileURL: URL?
    @State private var shareCardImage: UIImage?
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                mapSection
                heroSection
                statsGrid
                overlayToggle
                if !ride.pois.isEmpty { poisSection }
                shareCardSection
                exportSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(ride.routeName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .alert("Rename Ride", isPresented: $isRenaming) {
            TextField("Ride name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { historyStore.rename(id: ride.id, to: trimmed) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this ride?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                historyStore.delete(id: ride.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .sheet(isPresented: $showShareGPX) {
            if let url = gpxFileURL { ShareSheet(items: [url]) }
        }
        .sheet(isPresented: $showShareCard) {
            if let img = shareCardImage { ShareSheet(items: [img]) }
        }
        .task { await generateSnapshot() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    renameText = ride.routeName
                    isRenaming = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Ride", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Map

    private var mapSection: some View {
        Group {
            if let img = mapSnapshot {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.systemGray5))
                    .frame(maxWidth: .infinity).frame(height: 220)
                    .overlay { ProgressView().tint(.secondary) }
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 4) {
            Text(ride.routeName)
                .font(.headline).foregroundStyle(.primary)
            Text(ride.startDate.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(String(format: "%.2f", ride.distanceKm))
                    .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.blue)
                Text("km")
                    .font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            MetricTile(label: "TIME",  value: ride.elapsedTime.hhmm,                       unit: ride.elapsedTime.unit, icon: "clock.fill",                      color: .purple)
            MetricTile(label: "AVG",   value: String(format: "%.1f", ride.avgSpeedKmh),    unit: "km/h",                icon: "speedometer",                     color: .blue)
            MetricTile(label: "MAX",   value: String(format: "%.1f", ride.maxSpeedKmh),    unit: "km/h",                icon: "gauge.with.dots.needle.67percent", color: .red)
            MetricTile(label: "GAIN",  value: String(format: "%.0f", ride.elevationGain),  unit: "m",                   icon: "mountain.2.fill",                  color: .green)
            MetricTile(label: "LOSS",  value: String(format: "%.0f", ride.elevationLoss),  unit: "m",                   icon: "arrow.down.to.line",               color: .cyan)
            MetricTile(label: "POIs",  value: "\(ride.pois.count)",                        unit: "visited",             icon: "mappin.circle.fill",               color: .orange)
        }
    }

    // MARK: - Overlay Toggle

    private var overlayToggle: some View {
        Group {
            if !ride.plannedTrack.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Planned vs Actual")
                            .font(.subheadline.weight(.medium))
                        Text("Show the original planned route overlay")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $showPlannedOverlay)
                        .labelsHidden()
                        .onChange(of: showPlannedOverlay) { _, _ in
                            Task { await generateSnapshot() }
                        }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            }
        }
    }

    // MARK: - POIs

    private var poisSection: some View {
        VStack(spacing: 0) {
            DetailSectionHeader(title: "Points of Interest", systemImage: "mappin.and.ellipse", badge: "\(ride.pois.count)")
            ForEach(ride.pois) { poi in
                POIRow(poi: poi)
                if poi.id != ride.pois.last?.id { Divider().padding(.leading, 50) }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - Shareable Card

    private var shareCardSection: some View {
        VStack(spacing: 0) {
            DetailSectionHeader(title: "Share Ride", systemImage: "square.and.arrow.up")
            Button {
                renderShareCard()
            } label: {
                Label("Share as Image Card", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .padding(14)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - GPX Export

    private var exportSection: some View {
        VStack(spacing: 0) {
            DetailSectionHeader(title: "Export GPX", systemImage: "doc.badge.arrow.up")
            if !ride.pois.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include POIs")
                            .font(.subheadline)
                        Text("\(ride.pois.count) stop\(ride.pois.count == 1 ? "" : "s") as waypoints")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $exportPOIs).labelsHidden()
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                Divider()
            }
            Button {
                exportGPX()
            } label: {
                Label("Share GPX File", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        ride.actualTrack.isEmpty ? Color(.systemGray4) : .blue,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .foregroundStyle(.white)
            }
            .padding(14)
            .disabled(ride.actualTrack.isEmpty)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - GPX Export Action

    private func exportGPX() {
        let summary = ride.toRideSummary()
        let options = GPXExporter.Options(
            includeActualTrack: true,
            includePlannedRoute: false,
            includePOIs: exportPOIs && !ride.pois.isEmpty
        )
        let gpxString = GPXExporter.export(summary, options: options)
        let filename = ride.routeName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filename)_ride.gpx")
        do {
            try gpxString.write(to: url, atomically: true, encoding: .utf8)
            gpxFileURL = url
            showShareGPX = true
        } catch {}
    }

    // MARK: - Share Card Render

    private func renderShareCard() {
        let cardView = ShareableRideCard(ride: ride, snapshot: mapSnapshot)
        let renderer = ImageRenderer(content: cardView)
        renderer.scale = UIScreen.main.scale
        if let img = renderer.uiImage {
            shareCardImage = img
            showShareCard = true
        }
    }

    // MARK: - Map Snapshot

    private func generateSnapshot() async {
        let actual = ride.actualTrack
        guard actual.count > 1 else { return }
        let allCoords = showPlannedOverlay ? actual + ride.plannedTrack : actual
        let lats = allCoords.map(\.latitude), lons = allCoords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let opts = MKMapSnapshotter.Options()
        opts.region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max((lats.max()! - lats.min()!) * 1.4, 0.005),
                longitudeDelta: max((lons.max()! - lons.min()!) * 1.4, 0.005)
            )
        )
        opts.size = CGSize(width: UIScreen.main.bounds.width - 32, height: 220)
        opts.scale = UIScreen.main.scale
        opts.mapType = .standard
        opts.showsBuildings = false
        do {
            let snap = try await MKMapSnapshotter(options: opts).start()
            let img = UIGraphicsImageRenderer(size: opts.size).image { _ in
                snap.image.draw(at: .zero)
                // Planned route (gray dashed)
                if showPlannedOverlay && !ride.plannedTrack.isEmpty {
                    let planned = UIBezierPath()
                    for (i, c) in ride.plannedTrack.enumerated() {
                        let pt = snap.point(for: c)
                        i == 0 ? planned.move(to: pt) : planned.addLine(to: pt)
                    }
                    UIColor.systemGray3.setStroke()
                    planned.lineWidth = 3
                    planned.setLineDash([6, 4], count: 2, phase: 0)
                    planned.stroke()
                }
                // Actual track (blue solid)
                let path = UIBezierPath()
                for (i, c) in actual.enumerated() {
                    let pt = snap.point(for: c)
                    i == 0 ? path.move(to: pt) : path.addLine(to: pt)
                }
                UIColor.systemBlue.withAlphaComponent(0.85).setStroke()
                path.lineWidth = 3.5
                path.lineCapStyle = .round
                path.stroke()
                // Start dot (green)
                if let first = actual.first {
                    let pt = snap.point(for: first)
                    let dot = UIBezierPath(ovalIn: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12))
                    UIColor.systemGreen.setFill(); UIColor.white.setStroke()
                    dot.fill(); dot.lineWidth = 2; dot.stroke()
                }
                // End dot (red)
                if let last = actual.last {
                    let pt = snap.point(for: last)
                    let dot = UIBezierPath(ovalIn: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12))
                    UIColor.systemRed.setFill(); UIColor.white.setStroke()
                    dot.fill(); dot.lineWidth = 2; dot.stroke()
                }
            }
            mapSnapshot = img
        } catch {}
    }
}
