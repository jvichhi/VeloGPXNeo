import Foundation
import MapKit
import CoreLocation

@MainActor
final class POISearchService {
    static let shared = POISearchService()
    private init() {}

    func search(query: String, near coordinate: CLLocationCoordinate2D, radius: CLLocationDistance = 5000) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radius,
            longitudinalMeters: radius
        )
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        return response.mapItems
    }

    func searchAlongRoute(query: String, coordinates: [CLLocationCoordinate2D]) async throws -> [MKMapItem] {
        guard let midpoint = coordinates.middle else { return [] }
        return try await search(query: query, near: midpoint)
    }
}

private extension Array {
    var middle: Element? {
        guard !isEmpty else { return nil }
        return self[count / 2]
    }
}
