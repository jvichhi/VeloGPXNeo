import Foundation
import MapKit
import CoreLocation

/// Canonical POI search service.
/// iOS 18+: uses typed MKPointOfInterestFilter for structured category searches.
/// Falls back to naturalLanguageQuery for free-text / unknown categories.
@MainActor
final class POISearchService {
    static let shared = POISearchService()
    private init() {}

    // MARK: - Category → MKPointOfInterestCategory mapping

    static func poiCategory(for query: String) -> MKPointOfInterestCategory? {
        switch query.lowercased() {
        case "café", "cafe", "coffee":   return .cafe
        case "restaurant", "food":       return .restaurant
        case "bike shop", "bike repair": return .bicycle
        case "pharmacy":                 return .pharmacy
        case "water", "water fountain":  return .nationalPark  // closest available; see note
        case "hotel", "accommodation":   return .hotel
        case "gas station", "petrol":    return .gasStation
        case "atm", "bank":              return .atm
        case "hospital":                 return .hospital
        case "parking":                  return .parking
        default:                         return nil
        }
    }

    // MARK: - Search

    func search(
        query: String,
        near coordinate: CLLocationCoordinate2D,
        radius: CLLocationDistance = 5000
    ) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radius,
            longitudinalMeters: radius
        )

        if let category = Self.poiCategory(for: query) {
            // Typed filter path: structured results, better ranking (iOS 18+)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [category])
            // Still set NL query as a hint for relevance ranking
            request.naturalLanguageQuery = query
        } else {
            // Free-text fallback for custom/unknown queries
            request.naturalLanguageQuery = query
        }

        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        return response.mapItems
    }

    func searchAlongRoute(
        query: String,
        coordinates: [CLLocationCoordinate2D]
    ) async throws -> [MKMapItem] {
        guard let startPoint = coordinates.first else { return [] }
        return try await search(query: query, near: startPoint)
    }
}

private extension Array {
    var middle: Element? {
        guard !isEmpty else { return nil }
        return self[count / 2]
    }
}
