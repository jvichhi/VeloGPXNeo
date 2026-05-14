import SwiftUI
import MapKit

struct NearbySearchSheet: View {
    @EnvironmentObject var routeStore: RouteStore
    let coordinate: CLLocationCoordinate2D

    @State private var results: [MKMapItem] = []
    @State private var isLoading = false
    @State private var selectedCategory = "Caf\u00e9"
    @State private var hasInvalidCoordinate = false

    private let categories: [(label: String, icon: String, query: String)] = [
        ("Caf\u00e9",        "cup.and.saucer.fill",      "Caf\u00e9"),
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

    // MARK: - Added state

    private func isAdded(_ item: MKMapItem) -> Bool {
        routeStore.selectedPOIs.contains { $0.id == item.deterministicPOIID }
    }

    // MARK: - Toggle

    private func toggle(_ item: MKMapItem) {
        let id = item.deterministicPOIID
        if let idx = routeStore.selectedPOIs.firstIndex(where: { $0.id == id }) {
            routeStore.selectedPOIs.remove(at: idx)
        } else {
            let poi = item.toPOIModel(category: category(for: selectedCategory))
            routeStore.selectedPOIs.append(poi)
        }
    }

    // MARK: - Load

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

    // MARK: - Category mapping

    private func category(for query: String) -> POICategory {
        switch query {
        case "Caf\u00e9":        return .cafe
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

    @Environment(\.openURL) private var openURL

    private var distanceMeters: CLLocationDistance {
        CLLocation(latitude: searchCoordinate.latitude, longitude: searchCoordinate.longitude)
            .distance(from: CLLocation(
                latitude:  item.poiCoordinate.latitude,
                longitude: item.poiCoordinate.longitude
            ))
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
                if let address = item.shortAddress {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(distanceLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(spacing: 6) {
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

                if let url = item.openInMapsActionURL() {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "map")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                    .accessibilityLabel("Open in Maps")
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
    }
}
