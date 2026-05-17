import Foundation
import MapKit
import CoreLocation

/// Canonical POI search service.
/// iOS 18+: uses typed MKPointOfInterestFilter for structured category searches.
/// Falls back to naturalLanguageQuery for free-text / unknown categories.
///
/// Notes on missing categories:
/// - Bike shops: no MKPointOfInterestCategory constant exists. NL query "Bike Shop" returns
///   correct results via MapKit's internal classification.
/// - Water/fountains: no constant exists. NL query is more accurate than the .nationalPark proxy.
@MainActor
final class POISearchService {
    static let shared = POISearchService()
    private init() {}

    // MARK: - Category → MKPointOfInterestCategory mapping

    static func poiCategory(for query: String) -> MKPointOfInterestCategory? {
        switch query.lowercased() {
        case "café", "cafe", "coffee":   return .cafe
        case "restaurant", "food":       return .restaurant
        case "pharmacy":                 return .pharmacy
        case "hotel", "accommodation":   return .hotel
        case "gas station", "petrol":    return .gasStation
        case "atm", "bank":              return .atm
        case "hospital":                 return .hospital
        case "parking":                  return .parking
        // "bike shop", "bike repair", "water" → nil: no matching category constant.
        // Falls through to naturalLanguageQuery which works well for these.
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
            // Free-text fallback for custom/unknown queries (incl. bike shops, water)
            request.naturalLanguageQuery = query
        }

        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        return response.mapItems
    }

}
