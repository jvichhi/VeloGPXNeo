import SwiftUI
import MapKit

struct NearbySearchSheet: View {
    @EnvironmentObject var routeStore: RouteStore
    let coordinate: CLLocationCoordinate2D

    @State private var results: [MKMapItem] = []
    @State private var isLoading = false
    @State private var query = "Café"

    private let categories = ["Café", "Water", "Bike Shop", "Restaurant"]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Searching…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    ContentUnavailableView(
                        "No results",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different category.")
                    )
                } else {
                    List(results, id: \.self) { item in
                        ResultRow(
                            item: item,
                            searchCoordinate: coordinate,   // ← pass your position
                            isAdded: isAdded(item),
                            onToggle: { toggle(item) }
                        )
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Near This Point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Category") {
                        ForEach(categories, id: \.self) { cat in
                            Button {
                                query = cat
                                Task { await load() }
                            } label: {
                                Label(cat, systemImage: category(for: cat).systemImage)
                            }
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Add / Remove

    private func isAdded(_ item: MKMapItem) -> Bool {
        guard let name = item.name else { return false }
        return routeStore.selectedPOIs.contains { $0.name == name }
    }

    private func toggle(_ item: MKMapItem) {
        let name = item.name ?? "POI"
        if let idx = routeStore.selectedPOIs.firstIndex(where: { $0.name == name }) {
            routeStore.selectedPOIs.remove(at: idx)
        } else {
            let poi = POIModel(
                name: name,
                category: category(for: query),
                coordinate: item.placemark.coordinate,
                distanceFromRoute: 0,
                address: item.placemark.thoroughfare,
                phone: item.phoneNumber,
                website: item.url?.absoluteString
            )
            routeStore.selectedPOIs.append(poi)
        }
    }

    // MARK: - Search

    func load() async {
        isLoading = true
        results = (try? await POISearchService.shared.search(query: query, near: coordinate)) ?? []
        isLoading = false
    }

    // MARK: - Category mapping

    private func category(for query: String) -> POICategory {
        switch query {
        case "Café":       return .cafe
        case "Water":      return .water
        case "Bike Shop":  return .bikeRepair
        case "Restaurant": return .restaurant
        default:           return .custom
        }
    }
}

// MARK: - Result Row

private struct ResultRow: View {
    let item: MKMapItem
    let searchCoordinate: CLLocationCoordinate2D   // ← your current position
    let isAdded: Bool
    let onToggle: () -> Void

    // Distance from your position to this result
    private var distanceMeters: CLLocationDistance {
        let from = CLLocation(latitude: searchCoordinate.latitude,
                              longitude: searchCoordinate.longitude)
        let to   = CLLocation(latitude: item.placemark.coordinate.latitude,
                              longitude: item.placemark.coordinate.longitude)
        return from.distance(from: to)
    }

    private var distanceLabel: String {
        distanceMeters < 1000
            ? String(format: "%.0f m away", distanceMeters)
            : String(format: "%.1f km away", distanceMeters / 1000)
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isAdded ? Color.blue : Color(.systemGray5))
                        .frame(width: 36, height: 36)
                    Image(systemName: isAdded ? "checkmark" : "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isAdded ? .white : .secondary)
                }
                .animation(.spring(duration: 0.25), value: isAdded)

                VStack(alignment: .leading, spacing: 2) {
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

                Text(isAdded ? "Added" : "Add")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isAdded ? .blue : .secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
