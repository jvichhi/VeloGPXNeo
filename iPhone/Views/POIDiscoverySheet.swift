import SwiftUI
import MapKit

struct POIDiscoverySheet: View {
    @EnvironmentObject var routeStore: RouteStore
    let route: RouteModel

    @State private var searchQuery = ""
    @State private var results: [MKMapItem] = []
    @State private var isLoading = false

    let categories = ["Café", "Water", "Bike Shop", "Restaurant", "Pharmacy"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { cat in
                            Button(cat) {
                                searchQuery = cat
                                Task { await search() }
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                        }
                    }
                    .padding()
                }
                Divider()
                if isLoading {
                    ProgressView().padding()
                } else if results.isEmpty {
                    ContentUnavailableView(
                        "No results",
                        systemImage: "mappin.slash",
                        description: Text("Try a category above or type a search term.")
                    )
                    .padding()
                } else {
                    List(results, id: \.self) { item in
                        Button {
                            addPOI(from: item)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.name ?? "Unknown")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if let address = item.placemark.title {
                                        Text(address)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if routeStore.selectedPOIs.contains(where: {
                                    $0.name == (item.name ?? "")
                                }) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Discover POIs")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchQuery, prompt: "Search nearby…")
            .onSubmit(of: .search) {
                Task { await search() }
            }
        }
    }

    private func search() async {
        guard !route.trackPoints.isEmpty else { return }
        let mid = route.trackPoints[route.trackPoints.count / 2].coordinate.clCoordinate
        isLoading = true
        results = (try? await POISearchService.shared.search(
            query: searchQuery,
            near: mid
        )) ?? []
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
        if name.contains("café") || name.contains("cafe") || name.contains("coffee") { return .cafe }
        if name.contains("bike") || name.contains("cycle") { return .bikeRepair }
        if name.contains("restaurant") || name.contains("food") || name.contains("pizza") { return .restaurant }
        if name.contains("pharmacy") || name.contains("drug") { return .pharmacy }
        if name.contains("water") || name.contains("fountain") { return .water }
        if name.contains("hotel") || name.contains("hostel") || name.contains("inn") { return .accommodation }
        if name.contains("camp") { return .campsite }
        return .custom
    }
}
