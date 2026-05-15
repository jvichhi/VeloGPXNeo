import SwiftUI
import MapKit
import FoundationModels

/// Full-screen sheet shown after a ride ends.
/// Displays stats, a map snapshot of the actual track, visited POIs,
/// a one-tap GPX export of the ride, and an AI-generated shareable summary (F-A1).
struct RideSummaryView: View {
    let summary: RideSummary
    var onDismiss: () -> Void
    /// Passed in so generated captions can be written back to disk.
    var persistedID: UUID? = nil
    var historyStore: RideHistoryStore? = nil

    @State private var mapSnapshot: UIImage?
    @State private var exportPOIs = true
    @State private var gpxFileURL: ShareableURL?

    // F-A1
    @AppStorage(VeloAI.enabledKey) private var aiEnabled = true
    @State private var aiSummaryText: String = ""
    @State private var aiState: AIGenerationState = .idle
    @State private var showEditSheet = false

    // MK-4: capture display scale from environment before async boundary
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 16) {
                        mapSnapshotSection
                        heroStatsSection
                        statsGridSection
                        if VeloAI.isAvailable && aiEnabled { aiSummarySection }
                        if !summary.pois.isEmpty { poisSection }
                        exportSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Ride Complete")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done", action: onDismiss)
                            .fontWeight(.semibold)
                    }
                }
                .sheet(item: $gpxFileURL) { item in
                    ShareSheet(items: [item.url])
                }
                .sheet(isPresented: $showEditSheet) {
                    AISummaryEditSheet(
                        text: $aiSummaryText,
                        routeName: summary.routeName
                    )
                }
                .task { await generateMapSnapshot(containerWidth: geo.size.width) }
                .onAppear { restorePersistedCaption() }
            }
        }
    }

    // MARK: - Restore persisted caption

    private func restorePersistedCaption() {
        guard let pid = persistedID,
              let store = historyStore,
              let entry = store.summaries.first(where: { $0.id == pid }),
              let saved = entry.aiCaption,
              !saved.isEmpty else { return }
        aiSummaryText = saved
        aiState = .done
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
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.systemGray5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .overlay {
                        ProgressView().tint(.secondary)
                    }
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    // MARK: - Hero Distance

    @ViewBuilder
    private var heroStatsSection: some View {
        VStack(spacing: 4) {
            Text(summary.routeName)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(summary.startDate.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(String(format: "%.2f", summary.distanceKm))
                    .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.blue)
                Text("km")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - Stats Grid

    @ViewBuilder
    private var statsGridSection: some View {
        VStack(spacing: 8) {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                MetricTile(label: "MOVING",  value: summary.movingTime.hhmm,                    unit: summary.movingTime.unit,  icon: "figure.outdoor.cycle",               color: .purple)
                MetricTile(label: "AVG",   value: String(format: "%.1f", summary.avgSpeedKmh),   unit: "km/h",                   icon: "speedometer",                       color: .blue)
                MetricTile(label: "MAX",   value: String(format: "%.1f", summary.maxSpeedKmh),   unit: "km/h",                   icon: "gauge.with.dots.needle.67percent",   color: .red)
                MetricTile(label: "GAIN",  value: String(format: "%.0f", summary.elevationGain), unit: "m",                      icon: "mountain.2.fill",                    color: .green)
                MetricTile(label: "LOSS",  value: String(format: "%.0f", summary.elevationLoss), unit: "m",                      icon: "arrow.down.to.line",                 color: .cyan)
                MetricTile(label: "POIs",  value: "\(summary.pois.count)",                       unit: "visited",                icon: "mappin.circle.fill",                 color: .orange)
            }

            if summary.hadPauses {
                HStack(spacing: 4) {
                    Image(systemName: "pause.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Total time including stops: \(summary.elapsedTime.hhmm)\(summary.elapsedTime.unit)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - F-A1: AI Summary

    @ViewBuilder
    private var aiSummarySection: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("Ride Summary")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if case .done = aiState {
                    Button {
                        Task { await generateAISummary() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Regenerate summary")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemGray6).opacity(0.6))

            Divider()

            // Body
            VStack(spacing: 12) {
                switch aiState {
                case .idle:
                    Button {
                        Task { await generateAISummary() }
                    } label: {
                        Label("Generate Summary", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.purple)
                    }
                    .padding(14)

                case .generating:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.purple)
                        Text("Generating\u{2026}")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)

                case .done:
                    VStack(alignment: .leading, spacing: 12) {
                        Text(aiSummaryText)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                            .animation(.easeIn(duration: 0.3), value: aiSummaryText)

                        HStack(spacing: 10) {
                            Button {
                                showEditSheet = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color(.systemGray5), in: Capsule())
                                    .foregroundStyle(.primary)
                            }
                            Button {
                                shareSummary()
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(.purple, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                        }
                    }
                    .padding(14)

                case .failed(let message):
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Retry") {
                            Task { await generateAISummary() }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                    }
                    .padding(14)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - POIs

    @ViewBuilder
    private var poisSection: some View {
        VStack(spacing: 0) {
            DetailSectionHeader(
                title: "Points of Interest",
                systemImage: "mappin.and.ellipse",
                badge: "\(summary.pois.count)"
            )
            ForEach(summary.pois) { poi in
                POIRow(poi: poi)
                if poi.id != summary.pois.last?.id {
                    Divider().padding(.leading, 50)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - Export

    @ViewBuilder
    private var exportSection: some View {
        VStack(spacing: 0) {
            DetailSectionHeader(title: "Save Ride", systemImage: "square.and.arrow.up")

            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text("GPS Track")
                        .font(.subheadline.weight(.medium))
                    Text("Your actual ride path \u{2014} \(summary.actualTrack.count) points recorded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if !summary.pois.isEmpty {
                Divider().padding(.leading, 14)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include POIs")
                            .font(.subheadline)
                        Text("\(summary.pois.count) stop\(summary.pois.count == 1 ? "" : "s") as waypoints")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $exportPOIs).labelsHidden()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            Divider()

            if summary.actualTrack.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("No GPS track recorded for this ride.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
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
                        summary.actualTrack.isEmpty ? Color(.systemGray4) : .blue,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .foregroundStyle(.white)
            }
            .padding(14)
            .disabled(summary.actualTrack.isEmpty)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - F-A1 Actions

    private func generateAISummary() async {
        aiSummaryText = ""
        aiState = .generating
        do {
            let text = try await RideSummaryGenerator().generate(from: summary)
            aiSummaryText = text
            aiState = .done
            // Persist the caption so re-opening this ride shows it immediately
            if let pid = persistedID, let store = historyStore {
                store.saveCaption(id: pid, caption: text)
            }
        } catch let error as LanguageModelSession.GenerationError {
            aiState = .failed(error.localizedDescription)
        } catch {
            aiState = .failed("Couldn't generate a response. Try again.")
        }
    }

    private func shareSummary() {
        guard !aiSummaryText.isEmpty else { return }
        let av = UIActivityViewController(activityItems: [aiSummaryText], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }

    // MARK: - Export Action

    private func exportGPX() {
        let options = GPXExporter.Options(
            includeActualTrack: true,
            includePlannedRoute: false,
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
            gpxFileURL = ShareableURL(url: url)
        } catch {
            print("GPX export failed: \(error)")
        }
    }

    // MARK: - Map Snapshot

    private func generateMapSnapshot(containerWidth: CGFloat) async {
        guard !summary.actualTrack.isEmpty else { return }
        let coords = summary.actualTrack
        let minLat = coords.map(\.latitude).min()!
        let maxLat = coords.map(\.latitude).max()!
        let minLon = coords.map(\.longitude).min()!
        let maxLon = coords.map(\.longitude).max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let latDelta = max((maxLat - minLat) * 1.4, 0.005)
        let lonDelta = max((maxLon - minLon) * 1.4, 0.005)
        let region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
        let snapshotWidth = containerWidth - 32
        let scale = displayScale
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: snapshotWidth, height: 220)
        options.scale = scale
        options.mapType = .standard
        options.showsBuildings = false
        do {
            let snapshotter = MKMapSnapshotter(options: options)
            let snapshot = try await snapshotter.start()
            let image = UIGraphicsImageRenderer(size: options.size).image { _ in
                snapshot.image.draw(at: .zero)
                let path = UIBezierPath()
                for (i, coord) in coords.enumerated() {
                    let point = snapshot.point(for: coord)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                UIColor.systemBlue.withAlphaComponent(0.85).setStroke()
                path.lineWidth = 3.5
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
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
        } catch {}
    }
}

// MARK: - AI Generation State

private enum AIGenerationState {
    case idle
    case generating
    case done
    case failed(String)
}

// MARK: - AI Summary Edit Sheet

private struct AISummaryEditSheet: View {
    @Binding var text: String
    let routeName: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $draft)
                    .font(.body)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(routeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        text = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { draft = text }
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

// MARK: - Identifiable wrappers for .sheet(item:)

struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ShareableURL: Identifiable {
    let id = UUID()
    let url: URL
}
