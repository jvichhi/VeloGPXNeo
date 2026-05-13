import SwiftUI
import MapKit

struct NearbySearchSheet: View {
    @EnvironmentObject var routeStore: RouteStore
    let coordinate: CLLocationCoordinate2D

    @State private var results: [MKMapItem] = []
    @State private var isLoading = false
    @State private var selectedCategory = "Café"
    @State private var hasInvalidCoordinate = false

    private let categories: [(label: String, icon: String, query: String)] = [
        ("Café",        "cup.and.saucer.fill",      "Café"),
        ("Water",       "drop.fill",                "Water"),
        ("Bike Shop",   "wrench.and.screwdriver",   "Bike Shop"),
        ("Restaurant",  "fork.knife",               "Restaurant")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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

                Group {
                    if hasInvalidCoordinate {
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

    // MARK: - Coordinate helper (handles iOS 26 non-optional CLLocation)

    private func itemCoordinate(_ item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
            return item.location.coordinate
        } else {
            return item.placemark.coordinate
        }
    }

    // MARK: - Deterministic coordinate-based ID

    private func deterministicID(for item: MKMapItem) -> UUID {
        let coord = itemCoordinate(item)
        let lat = (coord.latitude  * 1_000_000).rounded() / 1_000_000
        let lon = (coord.longitude * 1_000_000).rounded() / 1_000_000
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
            let coord = itemCoordinate(item)
            let address: String? = {
                if #available(iOS 26.0, *) {
                    return item.address?.shortAddress
                } else {
                    return item.placemark.thoroughfare
                }
            }()
            let poi = POIModel(
                id: itemID,
                name: item.name ?? "POI",
                category: category(for: selectedCategory),
                coordinate: coord,
                distanceFromRoute: 0,
                address: address,
                phone: item.phoneNumber,
                website: item.url?.absoluteString
            )
            routeStore.selectedPOIs.append(poi)
        }
    }

    func load() async {
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude != 0 || coordinate.longitude != 0 else {
            hasInvalidCoordinate = true
            return
        }
        hasInvalidCoordinate = false
        isLoading = true
        results = (try? await POISearchService.shared.search(
            query: selectedCategory,
            near: coordinate,
            radius: 1000
        )) ?? []
        isLoading = false
    }

    private func category(for query: String) -> POICategory {
        switch query {
        case "Café":        return .cafe
        case "Water":       return .water
        case "Bike Shop":   return .bikeRepair
        case "Restaurant":  return .restaurant
        default:            return .custom
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

    private var itemCoordinate: CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
            return item.location.coordinate
        } else {
            return item.placemark.coordinate
        }
    }

    private var distanceMeters: CLLocationDistance {
        CLLocation(latitude: searchCoordinate.latitude, longitude: searchCoordinate.longitude)
            .distance(from: CLLocation(latitude: itemCoordinate.latitude, longitude: itemCoordinate.longitude))
    }

    private var distanceLabel: String {
        distanceMeters < 1000
            ? String(format: "%.0f m away", distanceMeters)
            : String(format: "%.1f km away", distanceMeters / 1000)
    }

    private var addressLine: String? {
        if #available(iOS 26.0, *) {
            return item.address?.shortAddress
        } else {
            return item.placemark.thoroughfare
        }
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
                if let address = addressLine {
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
