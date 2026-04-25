import Foundation
import MapKit

extension RouteStore {
    func nearbyPOIs(for category: String) async -> [MKMapItem] {
        guard let route = selectedRoute,
              !route.trackPoints.isEmpty else { return [] }
        let midpoint = route.trackPoints[route.trackPoints.count / 2].coordinate.clCoordinate
        return (try? await POISearchService.shared.search(query: category, near: midpoint)) ?? []
    }

    func nextPOI(category: String, from coordinate: CLLocationCoordinate2D) async -> MKMapItem? {
        let results = try? await POISearchService.shared.search(query: category, near: coordinate, radius: 2000)
        return results?.first
    }

    func removePOI(_ poi: POIModel) {
        selectedPOIs.removeAll { $0.id == poi.id }
    }

    func savePOIs() {
        // Persistence handled by RouteStore's existing save mechanism
    }
}
