import SwiftUI
import MapKit

struct POIDiscoverySheet: View {
    @EnvironmentObject var routeStore: RouteStore
    let route: RouteModel

    @State private var searchQuery = ""
    @State private var results: [MKMapItem] = []
    @State private var isLoading = false
    @State private var selectedCategory: String? = nil

    private let categories: [(label: String, icon: String)] = [
        ("Café",       "cup.and.saucer.fill"),
        ("Water",      "drop.fill"),
        ("Bike Shop",  "wrench.and.screwdriver"),
        ("Restaurant", "fork.knife"),
        ("Pharmacy",   "cross.case.fill")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Category chip bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.label) { cat in
                            Button {
                                selectedCategory = cat.label
                                searchQuery = cat.label
                                Task { await search() }
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
                                    selectedCategory == cat.label ? Color.blue : Color(.systemGray5),
                                    in: Capsule()
                                )
                                .foregroundStyle(selectedCategory == cat.label ? .white : .primary)
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
                        ProgressView("Searching near route start\u{2026}")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if results.isEmpty && selectedCategory != nil {
                        VStack(spacing: 14) {
                            Image(systemName: "mappin.slash")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                            Text("No results found")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Try a different category.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if selectedCategory == nil {
                        VStack(spacing: 14) {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundStyle(.blue.opacity(0.6))
                            Text("Pick a category above")
                                .font(.subheadline.weight(.medium))
                            Text("We\u{2019}ll search near the route start.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(results, id: \.self) { item in
                                    POIDiscoveryResultCard(
                                        item: item,
                                        isAdded: routeStore.selectedPOIs.contains(where: { $0.name == (item.name ?? "") }),
                                        categoryIcon: categories.first(where: { $0.label == selectedCategory })?.icon ?? "mappin",
                                        onTap: { addPOI(from: item) }
                                    )
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
            .navigationTitle("Discover POIs")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, prompt: "Search near route start\u{2026}")
            .onSubmit(of: .search) {
                selectedCategory = nil
                Task { await search() }
            }
        }
    }

    private func search() async {
        // Issue 3a fix: search from route start (trackPoints.first), not the
        // midpoint. On a long route the midpoint can be 20+ km from where the
        // rider is planning, making results irrelevant.
        guard let startPoint = route.trackPoints.first else { return }
        let origin = startPoint.coordinate.clCoordinate
        isLoading = true
        results = (try? await POISearchService.shared.search(query: searchQuery, near: origin)) ?? []
        isLoading = false
    }

    private func addPOI(from item: MKMapItem) {
        let coord = item.placemark.coordinate
        let poi = POIModel(
            name: item.name ?? "Unknown",
            category: categoryFromMapItem(item),
            coordinate: coord,
            address: item.placemark.title,
            phone: item.phoneNumber
        )
        if !routeStore.selectedPOIs.contains(where: { $0.name == poi.name }) {
            routeStore.selectedPOIs.append(poi)
        }
    }

    private func categoryFromMapItem(_ item: MKMapItem) -> POICategory {
        let name = item.name?.lowercased() ?? ""
        if name.contains("caf\u{00e9}") || name.contains("cafe") || name.contains("coffee") { return .cafe }
        if name.contains("bike") || name.contains("cycle") { return .bikeRepair }
        if name.contains("restaurant") || name.contains("food") || name.contains("pizza") { return .restaurant }
        if name.contains("pharmacy") || name.contains("drug") { return .pharmacy }
        if name.contains("water") || name.contains("fountain") { return .water }
        if name.contains("hotel") || name.contains("hostel") || name.contains("inn") { return .accommodation }
        if name.contains("camp") { return .campsite }
        return .custom
    }
}

// MARK: - Discovery Result Card

private struct POIDiscoveryResultCard: View {
    let item: MKMapItem
    let isAdded: Bool
    let categoryIcon: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isAdded ? Color.green.opacity(0.15) : Color.blue.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: isAdded ? "checkmark" : categoryIcon)
                        .font(.system(size: 17, weight: isAdded ? .bold : .regular))
                        .foregroundStyle(isAdded ? .green : .blue)
                }
                .animation(.spring(duration: 0.25), value: isAdded)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name ?? "Unknown")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let address = item.placemark.title {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(isAdded ? "Added" : "Add")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isAdded ? .green : .blue)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
    }
}
