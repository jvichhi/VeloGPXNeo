import SwiftUI
import MapKit

struct NearbySearchSheet: View {
    @EnvironmentObject var routeStore: RouteStore
    let coordinate: CLLocationCoordinate2D

    @State private var results: [MKMapItem] = []
    @State private var isLoading = false
    @State private var selectedCategory = "Café"
    @State private var selectedMapItem: MKMapItem? = nil
    @State private var showPlaceCard = false

    private let categories: [(label: String, icon: String, query: String)] = [
        ("Café",       "cup.and.saucer.fill",      "Café"),
        ("Water",      "drop.fill",                "Water Fountain"),
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

                Group {
                    if isLoading {
                        ProgressView("Searching…")
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
                                        onToggle: { toggle(item) },
                                        onInfoTap: {
                                            selectedMapItem = item
                                            showPlaceCard = true
                                        }
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
            // WWDC 2025: Native Apple Maps Place Card sheet
            .sheet(isPresented: $showPlaceCard) {
                if let item = selectedMapItem {
                    MapItemDetailView(item: item)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
        }
        .task { await load() }
    }

    private func isAdded(_ item: MKMapItem) -> Bool {
        guard let name = item.name else { return false }
        return routeStore.selectedPOIs.contains { $0.name == name }
    }

    private func toggle(_ item: MKMapItem) {
        let name = item.name ?? "POI"
        if let idx = routeStore.selectedPOIs.firstIndex(where: { $0.name == name }) {
            routeStore.selectedPOIs.remove(at: idx)
        } else {
            // WWDC 2025: use MKAddressRepresentations for rich address display
            let address: String?
            if #available(iOS 19.0, *),
               let addr = item.placemark.addressRepresentation {
                address = addr.formattedAddressLines.first
            } else {
                address = item.placemark.thoroughfare
            }
            let poi = POIModel(
                name: name,
                category: category(for: selectedCategory),
                coordinate: item.placemark.coordinate,
                distanceFromRoute: 0,
                address: address,
                phone: item.phoneNumber,
                website: item.url?.absoluteString
            )
            routeStore.selectedPOIs.append(poi)
        }
    }

    func load() async {
        isLoading = true
        results = (try? await POISearchService.shared.search(query: selectedCategory, near: coordinate)) ?? []
        isLoading = false
    }

    private func category(for query: String) -> POICategory {
        switch query {
        case "Café":          return .cafe
        case "Water Fountain": return .water
        case "Bike Shop":      return .bikeRepair
        case "Restaurant":     return .restaurant
        default:               return .custom
        }
    }
}

// MARK: - Native MapKit Place Card wrapper (WWDC 2025)

/// Wraps MapItemDetailViewController — the same full Place Card Apple Maps shows.
@available(iOS 18.0, *)
private struct MapItemDetailView: UIViewControllerRepresentable {
    let item: MKMapItem

    func makeUIViewController(context: Context) -> MKMapItemDetailViewController {
        let vc = MKMapItemDetailViewController()
        vc.mapItem = item
        return vc
    }

    func updateUIViewController(_ uiViewController: MKMapItemDetailViewController, context: Context) {
        uiViewController.mapItem = item
    }
}

// MARK: - Result Card

private struct NearbyResultCard: View {
    let item: MKMapItem
    let searchCoordinate: CLLocationCoordinate2D
    let categoryIcon: String
    let isAdded: Bool
    let onToggle: () -> Void
    let onInfoTap: () -> Void

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

    // WWDC 2025: MKAddressRepresentations for richer, context-aware address strings
    private var addressLine: String? {
        if #available(iOS 19.0, *),
           let addr = item.placemark.addressRepresentation {
            return addr.formattedAddressLines.first
        }
        return item.placemark.thoroughfare
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

            // Info button → Apple Maps Place Card
            Button(action: onInfoTap) {
                Image(systemName: "info.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue.opacity(0.8))
                    .frame(width: 34, height: 34)
            }

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
