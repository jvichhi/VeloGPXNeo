import SwiftUI
import MapKit

struct NearbySearchSheet: View {
    @EnvironmentObject var routeStore: RouteStore
    let coordinate: CLLocationCoordinate2D

    @State private var results: [MKMapItem] = []
    @State private var isLoading = false
    @State private var selectedCategory = "Caf\u00e9"
    // Bug 2 fix: shown when coordinate is invalid so the user isn't
    // silently served results from (0, 0).
    @State private var hasInvalidCoordinate = false

    private let categories: [(label: String, icon: String, query: String)] = [
        ("Caf\u00e9",       "cup.and.saucer.fill",      "Caf\u00e9"),
        ("Water",      "drop.fill",                "Water"),
        ("Bike Shop",  "wrench.and.screwdriver",   "Bike Shop"),
        ("Restaurant", "fork.knife",               "Restaurant")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Category chip bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.query) { cat in
                            Button {
                                selectedCategory = cat.query
                                Task { await load() }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(cat.label)
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedCategory == cat.query ? Color.blue : Color(.systemGray5),
                                    in: Capsule()
                                )
                                .foregroundStyle(selectedCategory == cat.query ? .white : .primary)
                            }
                            .animation(.spring(duration: 0.2), value: selectedCategory)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Divider()

                // Content
                Group {
                    if hasInvalidCoordinate {
                        // Bug 2 fix: show a clear error instead of searching (0,0).
                        VStack(spacing: 14) {
                            Image(systemName: "location.slash.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.orange)
                            Text("GPS signal lost")
                                .font(.subheadline.weight(.semibold))
                            Text("Nearby search needs a valid location.\nMove to open sky and try again.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if isLoading {
                        ProgressView("Searching\u{2026}")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if results.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                            Text("No results nearby")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(results, id: \.self) { item in
                                    NearbyResultCard(
                                        item: item,
                                        searchCoordinate: coordinate,
                                        categoryIcon: categories.first(where: { $0.query == selectedCategory })?.icon ?? "mappin",
                                        isAdded: isAdded(item),
                                        onToggle: { toggle(item) }
                                    )
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
            .navigationTitle("Near This Point")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load() }
    }

    // MARK: - ID-based POI matching
    // MKMapItem has no stable ID, so we derive a deterministic UUID from
    // the coordinate rounded to 6 decimal places.

    private func deterministicID(for item: MKMapItem) -> UUID {
        let lat = (item.placemark.coordinate.latitude * 1_000_000).rounded() / 1_000_000
        let lon = (item.placemark.coordinate.longitude * 1_000_000).rounded() / 1_000_000
        let seed = "\(lat),\(lon)"
        var hash = seed.utf8.reduce(UInt64(14695981039346656037)) { acc, byte in
            (acc ^ UInt64(byte)) &* 1099511628211
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(hash & 0xFF)
            hash >>= 8
        }
        var hash2 = seed.reversed().description.utf8.reduce(UInt64(14695981039346656037)) { acc, byte in
            (acc ^ UInt64(byte)) &* 1099511628211
        }
        for i in 8..<16 {
            bytes[i] = UInt8(hash2 & 0xFF)
            hash2 >>= 8
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func isAdded(_ item: MKMapItem) -> Bool {
        let itemID = deterministicID(for: item)
        return routeStore.selectedPOIs.contains { $0.id == itemID }
    }

    private func toggle(_ item: MKMapItem) {
        let itemID = deterministicID(for: item)
        if let idx = routeStore.selectedPOIs.firstIndex(where: { $0.id == itemID }) {
            routeStore.selectedPOIs.remove(at: idx)
        } else {
            let poi = POIModel(
                id: itemID,
                name: item.name ?? "POI",
                category: category(for: selectedCategory),
                coordinate: item.placemark.coordinate,
                distanceFromRoute: 0,
                address: item.placemark.thoroughfare,
                phone: item.phoneNumber,
                website: item.url?.absoluteString
            )
            routeStore.selectedPOIs.append(poi)
        }
    }

    func load() async {
        // Bug 2 fix: guard against an invalid coordinate before firing the search.
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude != 0 || coordinate.longitude != 0 else {
            hasInvalidCoordinate = true
            return
        }
        hasInvalidCoordinate = false
        isLoading = true
        results = (try? await POISearchService.shared.search(query: selectedCategory, near: coordinate)) ?? []
        isLoading = false
    }

    private func category(for query: String) -> POICategory {
        switch query {
        case "Caf\u00e9":       return .cafe
        case "Water":      return .water
        case "Bike Shop":  return .bikeRepair
        case "Restaurant": return .restaurant
        default:           return .custom
        }
    }
}

// MARK: - Result Card

private struct NearbyResultCard: View {
    let item: MKMapItem
    let searchCoordinate: CLLocationCoordinate2D
    let categoryIcon: String
    let isAdded: Bool
    let onToggle: () -> Void

    private var distanceMeters: CLLocationDistance {
        CLLocation(latitude: searchCoordinate.latitude, longitude: searchCoordinate.longitude)
            .distance(from: CLLocation(latitude: item.placemark.coordinate.latitude,
                                       longitude: item.placemark.coordinate.longitude))
    }

    private var distanceLabel: String {
        distanceMeters < 1000
            ? String(format: "%.0f m away", distanceMeters)
            : String(format: "%.1f km away", distanceMeters / 1000)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: categoryIcon)
                    .font(.system(size: 17))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name ?? "Unknown")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let address = item.placemark.thoroughfare {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(distanceLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .fill(isAdded ? Color.blue : Color(.systemGray5))
                        .frame(width: 34, height: 34)
                    Image(systemName: isAdded ? "checkmark" : "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isAdded ? .white : .secondary)
                }
            }
            .animation(.spring(duration: 0.25), value: isAdded)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
    }
}
