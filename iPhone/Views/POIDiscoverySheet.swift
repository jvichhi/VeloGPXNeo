import SwiftUI
import MapKit
import FoundationModels

struct POIDiscoverySheet: View {
    @EnvironmentObject var routeStore: RouteStore
    let route: RouteModel

    @State private var searchQuery = ""
    @State private var results: [MKMapItem] = []
    @State private var rankedResults: [RankedPOI] = []
    @State private var isLoading = false
    @State private var isRanking = false
    @State private var selectedCategory: String? = nil
    @State private var sortOrder: POISortOrder = .suggested

    // F-A3
    @AppStorage(VeloAI.enabledKey) private var aiEnabled = true

    private let categories: [(label: String, icon: String)] = [
        ("Café",       "cup.and.saucer.fill"),
        ("Water",      "drop.fill"),
        ("Bike Shop",  "storefront.fill"),
        ("Restaurant", "fork.knife"),
        ("Pharmacy",   "cross.fill"),
        ("Restroom",   "figure.walk"),
        ("Scenic",     "photo.on.rectangle")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category filter chips
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
                    .padding(.vertical, 10)
                }

                // Sort picker — only shown when results are available
                if !results.isEmpty {
                    Divider()
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(POISortOrder.allCases) { order in
                            if order == .suggested && !(VeloAI.isAvailable && aiEnabled) {
                                EmptyView()
                            } else {
                                Label(order.label, systemImage: order.icon).tag(order)
                            }
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .onChange(of: sortOrder) { _, newOrder in
                        if newOrder == .suggested { Task { await rankResults() } }
                    }
                }

                Divider()

                Group {
                    if isLoading {
                        ProgressView("Searching near route start…")
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
                            Text("We'll search near the route start.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            if isRanking {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small).tint(.purple)
                                    Text("Ranking by relevance…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 12)
                            }

                            LazyVStack(spacing: 10) {
                                ForEach(displayItems) { ranked in
                                    let mapItem = results.first(where: { $0.deterministicPOIID == ranked.poi.id })
                                    let isAdded = routeStore.selectedPOIs.contains { $0.id == ranked.poi.id }
                                    // ⚠️ REGRESSION GUARD — DO NOT INLINE THIS BACK INTO onTap ⚠️
                                    // The overloaded addPOI(from:) calls inside a ForEach closure
                                    // cause "compiler unable to type-check" (line 128) when inlined.
                                    // Keep the action extracted as a local let binding.
                                    let action: () -> Void = {
                                        if let mi = mapItem {
                                            addPOI(from: mi)
                                        } else {
                                            addPOI(from: ranked.poi)
                                        }
                                    }
                                    POIDiscoveryResultCard(
                                        item: ranked.poi,
                                        isAdded: isAdded,
                                        reason: sortOrder == .suggested ? ranked.reason : "",
                                        categoryIcon: ranked.poi.category.systemImage,
                                        onTap: action
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
            .searchable(text: $searchQuery, prompt: "Search near route start…")
            .onSubmit(of: .search) {
                selectedCategory = nil
                Task { await search() }
            }
        }
    }

    // MARK: - Computed display items

    private var displayItems: [RankedPOI] {
        // Convert MKMapItem results → POIModel for display
        let asPOIs = results.map { item in
            item.toPOIModel(category: categoryFromMapItem(item), distanceFromRoute: 0)
        }

        switch sortOrder {
        case .suggested:
            return rankedResults.isEmpty
                ? asPOIs.map { RankedPOI(poi: $0, score: 0.5, reason: "") }
                : rankedResults

        case .nearest:
            guard let start = route.trackPoints.first else {
                return asPOIs.map { RankedPOI(poi: $0, score: 0.5, reason: "") }
            }
            let originLocation = CLLocation(
                latitude:  start.coordinate.latitude,
                longitude: start.coordinate.longitude
            )
            // ⚠️ REGRESSION GUARD — DO NOT REMOVE EXPLICIT TYPES ⚠️
            // This closure has regressed 3 times (commits e8e7b25, c0ff0b5, 870227b).
            // The Swift type-checker cannot infer types for CLLocation distance calls
            // inside a .sorted closure without explicit annotations. Removing the
            // explicit `(a: POIModel, b: POIModel) -> Bool` types will cause:
            // "The compiler is unable to type-check this expression in reasonable time"
            let sorted: [POIModel] = asPOIs.sorted { (a: POIModel, b: POIModel) -> Bool in
                let distA = CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude)
                    .distance(from: originLocation)
                let distB = CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude)
                    .distance(from: originLocation)
                return distA < distB
            }
            return sorted.map { RankedPOI(poi: $0, score: 0.5, reason: "") }

        case .byCategory:
            let sorted = asPOIs.sorted { $0.category.rawValue < $1.category.rawValue }
            return sorted.map { RankedPOI(poi: $0, score: 0.5, reason: "") }
        }
    }

    // MARK: - Search

    private func search() async {
        guard let startPoint = route.trackPoints.first else { return }
        let origin = CLLocationCoordinate2D(
            latitude:  startPoint.coordinate.latitude,
            longitude: startPoint.coordinate.longitude
        )
        isLoading = true
        rankedResults = []
        results = (try? await POISearchService.shared.search(query: searchQuery, near: origin)) ?? []
        isLoading = false

        if sortOrder == .suggested && VeloAI.isAvailable && aiEnabled && !results.isEmpty {
            Task { await rankResults() }
        }
    }

    // MARK: - F-A3: Rank

    private func rankResults() async {
        guard VeloAI.isAvailable && aiEnabled && !results.isEmpty else { return }
        isRanking = true
        let pois = results.map { item in
            item.toPOIModel(category: categoryFromMapItem(item), distanceFromRoute: 0)
        }
        let context = RideContext(
            distanceCovered:    0,
            totalElevationGain: route.elevationGain,
            completionRatio:    0,
            currentTime:        Date()
        )
        let engine = POIRankingEngine()
        rankedResults = (try? await engine.ranking(pois: pois, context: context)) ?? []
        isRanking = false
    }

    // MARK: - Helpers

    private func routeDifficulty() -> String {
        switch route.elevationGain {
        case ..<200:     return "easy"
        case 200..<500:  return "moderate"
        case 500..<1000: return "hard"
        default:         return "epic"
        }
    }

    // MARK: - Add POI (from MKMapItem)

    private func addPOI(from item: MKMapItem) {
        let id = item.deterministicPOIID
        guard !routeStore.selectedPOIs.contains(where: { $0.id == id }) else { return }
        let poi = item.toPOIModel(
            category: categoryFromMapItem(item),
            distanceFromRoute: 0
        )
        routeStore.selectedPOIs.append(poi)
    }

    // MARK: - Add POI (from POIModel — fallback when MKMapItem not found)

    private func addPOI(from poi: POIModel) {
        guard !routeStore.selectedPOIs.contains(where: { $0.id == poi.id }) else { return }
        routeStore.selectedPOIs.append(poi)
    }

    // MARK: - Category detection

    private func categoryFromMapItem(_ item: MKMapItem) -> POICategory {
        if let poiCat = item.pointOfInterestCategory {
            switch poiCat {
            case .cafe:                             return .cafe
            case .restaurant, .foodMarket:         return .restaurant
            case .pharmacy:                         return .pharmacy
            case .hotel:                            return .accommodation
            case .campground:                       return .campsite
            case .nationalPark, .park:              return .water
            default:                                return .custom
            }
        }
        let name = item.name?.lowercased() ?? ""
        if name.contains("café") || name.contains("cafe") || name.contains("coffee") { return .cafe }
        if name.contains("bike") || name.contains("cycle") { return .bikeRepair }
        if name.contains("restaurant") || name.contains("food") { return .restaurant }
        if name.contains("pharmacy") { return .pharmacy }
        if name.contains("water") || name.contains("fountain") { return .water }
        if name.contains("hotel") || name.contains("hostel") || name.contains("inn") { return .accommodation }
        if name.contains("camp") { return .campsite }
        return .custom
    }
}

// MARK: - Sort Order

enum POISortOrder: String, CaseIterable, Identifiable {
    case suggested  = "suggested"
    case nearest    = "nearest"
    case byCategory = "byCategory"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .suggested:  return "Suggested"
        case .nearest:    return "Nearest"
        case .byCategory: return "Category"
        }
    }

    var icon: String {
        switch self {
        case .suggested:  return "sparkles"
        case .nearest:    return "location"
        case .byCategory: return "tag"
        }
    }
}

// MARK: - Discovery Result Card

private struct POIDiscoveryResultCard: View {
    let item: POIModel
    let isAdded: Bool
    let reason: String
    let categoryIcon: String
    let onTap: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
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
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let address = item.address {
                            Text(address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if !reason.isEmpty {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.purple.opacity(0.8))
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                    }

                    Spacer()

                    Text(isAdded ? "Added" : "Add")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isAdded ? .green : .blue)
                }
            }
            .buttonStyle(.plain)

            if let mapsURL = item.mapsURL {
                Button {
                    openURL(mapsURL)
                } label: {
                    Image(systemName: "map")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color(.systemGray6), in: Circle())
                }
                .accessibilityLabel("Open in Maps")
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
    }
}
