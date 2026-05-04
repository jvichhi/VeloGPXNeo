//
//  PreRidePOISheet.swift
//  VeloGPX
//
//  Pre-ride POI management sheet.
//  Opened by the 📍 button in birdsEyeLayout.
//
//  Sections:
//   - On this route: POIs sorted by along-route order (snap index),
//     each row showing along-route distance from route start.
//   - Add nearby: opens POIDiscoverySheet.
//
//  Snap indices are computed once on appear and cached in snapIndexCache
//  to avoid O(n²) work on every List redraw.
//

import SwiftUI
import CoreLocation

struct PreRidePOISheet: View {
    let route: RouteModel
    var cueEntries: [CueSheetEntry] = []
    @EnvironmentObject private var routeStore: RouteStore
    @State private var showSearch = false
    @State private var snapIndexCache: [UUID: Int] = [:]
    @State private var selectedTab = 0
    @Environment(\.dismiss) private var dismiss

    // POIs sorted by snap index (along-route order).
    private var sortedPOIs: [POIModel] {
        routeStore.selectedPOIs.sorted {
            (snapIndexCache[$0.id] ?? Int.max) < (snapIndexCache[$1.id] ?? Int.max)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $selectedTab) {
                    Text("POIs").tag(0)
                    Text("Cues").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if selectedTab == 0 {
                    poiList
                } else {
                    cueList
                }
            }
            .navigationTitle(selectedTab == 0 ? "POIs" : "Turn-by-Turn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            POIDiscoverySheet(route: route)
                .environmentObject(routeStore)
        }
        .onAppear { buildSnapIndexCache() }
        .onChange(of: routeStore.selectedPOIs) { _, _ in buildSnapIndexCache() }
    }

    // MARK: - POI list

    private var poiList: some View {
        List {
            Section("On this route") {
                if routeStore.selectedPOIs.isEmpty {
                    Text("No pinned POIs yet")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(sortedPOIs) { poi in
                        HStack {
                            Label {
                                Text(poi.name)
                            } icon: {
                                Image(systemName: poi.category.systemImage)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            if let d = alongRouteDistance(for: poi) {
                                Text(formatDistance(d))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        let poisToRemove = indexSet.map { sortedPOIs[$0] }
                        let idsToRemove = Set(poisToRemove.map { $0.id })
                        routeStore.selectedPOIs.removeAll { idsToRemove.contains($0.id) }
                        routeStore.savePOIs()
                    }
                }
            }

            Section("Add nearby") {
                Button {
                    showSearch = true
                } label: {
                    Label("Search nearby\u{2026}", systemImage: "magnifyingglass")
                }
            }
        }
    }

    // MARK: - Cue list

    private var cueList: some View {
        Group {
            if cueEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No turn-by-turn cues")
                        .font(.headline)
                    Text("This route doesn't have enough turns to generate cues, or routing is unavailable.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(cueEntries) { cue in
                        HStack(spacing: 12) {
                            Image(systemName: cue.icon.systemImage)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(cueIconColor(cue.icon))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(cue.instruction)
                                    .font(.subheadline)
                                Text(formatDistance(cue.cumulativeDistance))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func cueIconColor(_ icon: CueIcon) -> Color {
        switch icon {
        case .arrive: return .green
        case .left, .right, .sharpLeft, .sharpRight: return .orange
        case .slightLeft, .slightRight: return .blue
        case .roundabout: return .purple
        case .uTurn: return .red
        case .merge: return .cyan
        case .straight: return .secondary
        }
    }

    // MARK: - Snap index cache

    /// Computes the nearest track-point index for every POI and caches it.
    /// Called once on appear and whenever the POI list changes.
    private func buildSnapIndexCache() {
        let trackPoints = route.trackPoints
        guard !trackPoints.isEmpty else { return }
        var cache: [UUID: Int] = [:]
        for poi in routeStore.selectedPOIs {
            let poiCoord = poi.coordinate.clCoordinate
            var bestIdx = 0
            var bestDist = poiCoord.distance(to: trackPoints[0].coordinate.clCoordinate)
            for i in 1..<trackPoints.count {
                let d = poiCoord.distance(to: trackPoints[i].coordinate.clCoordinate)
                if d < bestDist { bestDist = d; bestIdx = i }
            }
            cache[poi.id] = bestIdx
        }
        snapIndexCache = cache
    }

    /// Along-route distance from the route start to the POI's snap point (metres).
    private func alongRouteDistance(for poi: POIModel) -> Double? {
        guard let snapIdx = snapIndexCache[poi.id] else { return nil }
        let pts = route.trackPoints
        guard snapIdx > 0, snapIdx < pts.count else { return 0 }
        return zip(pts[0..<snapIdx], pts[1...snapIdx])
            .reduce(0.0) { acc, pair in
                acc + pair.0.coordinate.clCoordinate.distance(to: pair.1.coordinate.clCoordinate)
            }
    }

    private func formatDistance(_ metres: Double) -> String {
        metres < 1000
            ? String(format: "%.0f m", metres)
            : String(format: "%.1f km", metres / 1000)
    }
}
