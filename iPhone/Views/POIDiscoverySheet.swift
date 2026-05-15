import SwiftUI
import MapKit
import FoundationModels

struct POIDiscoverySheet: View {
    @EnvironmentObject var routeStore: RouteStore
    let route: RouteModel

    @State private var searchQuery = ""
    @State private var results: [MKMapItem] = []
    @State private var rankedResults: [RankedPOIResult] = []
    @State private var isLoading = false
    @State private var isRanking = false
    @State private var selectedCategory: String? = nil
    @State private var sortOrder: POISortOrder = .suggested

    // F-A3
    @AppStorage(VeloAI.enabledKey) private var aiEnabled = true

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
                                ForEach(displayItems, id: \.poi) { ranked in
                                    let item = ranked.poi
                                    let isAdded = routeStore.selectedPOIs.contains {
                                        $0.id == item.deterministicPOIID
                                    }
                                    POIDiscoveryResultCard(
                                        item: item,
                                        isAdded: isAdded,
                                        reason: sortOrder == .suggested ? ranked.reason : "",
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
            .searchable(text: $searchQuery, prompt: "Search near route start…")
            .onSubmit(of: .search) {
                selectedCategory = nil
                Task { await search() }
            }
        }
    }

    // MARK: - Computed display items

    private var displayItems: [RankedPOIResult] {
        switch sortOrder {
        case .suggested:
            return rankedResults.isEmpty
                ? results.map { RankedPOIResult(poi: $0, reason: "") }
                : rankedResults

        case .nearest:
            guard let start = route.trackPoints.first else {
                return results.map { RankedPOIResult(poi: $0, reason: "") }
            }
            // Break the sort into explicit sub-expressions to avoid type-checker timeout
            let origin = CLLocationCoordinate2D(
                latitude:  start.coordinate.latitude,
                longitude: start.coordinate.longitude
            )
            let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            let sorted = results.sorted { a, b in
                let coordA = a.poiCoordinate
                let coordB = b.poiCoordinate
                let distA = CLLocation(latitude: coordA.latitude, longitude: coordA.longitude)
                    .distance(from: originLocation)
                let distB = CLLocation(latitude: coordB.latitude, longitude: coordB.longitude)
                    .distance(from: originLocation)
                return distA < distB
            }
            return sorted.map { RankedPOIResult(poi: $0, reason: "") }

        case .byCategory:
            let sorted = results.sorted {
                ($0.pointOfInterestCategory?.rawValue ?? "") < ($1.pointOfInterestCategory?.rawValue ?? "")
            }
            return sorted.map { RankedPOIResult(poi: $0, reason: "") }
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
        let context = buildRideContext()
        rankedResults = await POIRankingEngine.shared.rank(results, context: context)
        isRanking = false
    }

    private func buildRideContext() -> RideContext {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: String
        switch hour {
        case 5..<12:  timeOfDay = "morning"
        case 12..<17: timeOfDay = "afternoon"
        default:      timeOfDay = "evening"
        }

        let gain = route.elevationGain
        let difficulty: String
        switch gain {
        case ..<200:    difficulty = "easy"
        case 200..<500: difficulty = "moderate"
        case 500..<1000: difficulty = "hard"
        default:         difficulty = "epic"
        }

        return RideContext(
            routeName:         route.name,
            difficulty:        difficulty,
            elevationGainM:    route.elevationGain,
            distanceTotalKm:   route.totalDistance / 1000,
            distanceSoFarKm:   0,
            timeOfDay:         timeOfDay,
            topPastCategories: []
        )
    }

    // MARK: - Add POI

    private func addPOI(from item: MKMapItem) {
        let id = item.deterministicPOIID
        guard !routeStore.selectedPOIs.contains(where: { $0.id == id }) else { return }
        let poi = item.toPOIModel(
            category: categoryFromMapItem(item),
            distanceFromRoute: 0
        )
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
    let item: MKMapItem
    let isAdded: Bool
    let reason: String
    let categoryIcon: String
    let onTap: () -> Void

    @Environment(\.openURL) private var openURL

    // Compute once to avoid calling toPOIModel() twice
    private var poiModel: POIModel { item.toPOIModel(category: .custom) }

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
                        Text(item.name ?? "Unknown")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let address = item.shortAddress {
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

            if let mapsURL = poiModel.mapsURL {
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
