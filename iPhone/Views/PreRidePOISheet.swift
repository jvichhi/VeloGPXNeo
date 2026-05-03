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
    @EnvironmentObject private var routeStore: RouteStore
    @State private var showSearch = false
    @State private var snapIndexCache: [UUID: Int] = [:]   // poiID → track snap index
    @Environment(\.dismiss) private var dismiss

    // POIs sorted by snap index (along-route order).
    private var sortedPOIs: [POIModel] {
        routeStore.selectedPOIs.sorted {
            (snapIndexCache[$0.id] ?? Int.max) < (snapIndexCache[$1.id] ?? Int.max)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: On this route
                let sectionTitle = "On this route"
                Section(sectionTitle) {
                    if routeStore.selectedPOIs.isEmpty {
                        Text("No pinned POIs yet")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(sortedPOIs) { poi in
                            let name: String = poi.name
                            let icon: String = poi.category.systemImage
                            let dist: Double? = alongRouteDistance(for: poi)
                            HStack {
                                Label {
                                    Text(name)
                                } icon: {
                                    Image(systemName: icon)
                                        .foregroundStyle(.orange)
                                }
                                Spacer()
                                if let d = dist {
                                    Text(formatDistance(d))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { (indexSet: IndexSet) in
                            let poisToRemove: [POIModel] = indexSet.map { sortedPOIs[$0] }
                            let idsToRemove: Set<UUID> = Set(poisToRemove.map { $0.id })
                            routeStore.selectedPOIs.removeAll { idsToRemove.contains($0.id) }
                            routeStore.savePOIs()
                        }
                    }
                }

                // MARK: Add nearby
                Section("Add nearby") {
                    Button {
                        showSearch = true
                    } label: {
                        Label("Search nearby\u{2026}", systemImage: "magnifyingglass")
                    }
                }
            }
            .navigationTitle("POIs")
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
