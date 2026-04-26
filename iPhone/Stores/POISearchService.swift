import Foundation
import MapKit

@MainActor
final class POISearchService {
    static let shared = POISearchService()

    // MARK: - Nearby search (used during riding)
    func search(
        query: String,
        near coordinate: CLLocationCoordinate2D,
        radius: CLLocationDistance = 5000
    ) async throws -> [MKMapItem] {
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

    // MARK: - Reverse geocode using MKReverseGeocodingRequest (WWDC 2025, replaces CLGeocoder)
    /// Returns a full MKMapItem with rich MKAddressRepresentations instead of a plain placemark.
    func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> MKMapItem? {
        if #available(iOS 19.0, *) {
            let request = MKReverseGeocodingRequest(coordinate: coordinate)
            let items = try? await request.mapItems
            return items?.first
        } else {
            // Fallback: wrap CLGeocoder result in MKMapItem
            return await withCheckedContinuation { continuation in
                let geocoder = CLGeocoder()
                geocoder.reverseGeocodeLocation(
                    CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                ) { placemarks, _ in
                    if let placemark = placemarks?.first {
                        let mkPlacemark = MKPlacemark(placemark: placemark)
                        continuation.resume(returning: MKMapItem(placemark: mkPlacemark))
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    // MARK: - Route-aware search (used in POI discovery)
    /// Searches at evenly-spaced sample points along the route, deduplicates,
    /// then keeps only results whose perpendicular distance to the route is <= maxOffRouteMeters.
    func searchAlongRoute(
        query: String,
        coordinates: [CLLocationCoordinate2D],
        maxOffRouteMeters: CLLocationDistance = 200
    ) async throws -> [MKMapItem] {
        guard !coordinates.isEmpty else { return [] }
        let samplePoints = coordinates.sampled(maxCount: 12)
        let searchRadius = maxOffRouteMeters * 2.5
        var seen = Set<String>()
        var combined: [MKMapItem] = []
        for point in samplePoints {
            let results = (try? await search(query: query, near: point, radius: searchRadius)) ?? []
            for item in results {
                let key = item.name ?? UUID().uuidString
                if seen.insert(key).inserted {
                    combined.append(item)
                }
            }
        }
        return combined.filter { item in
            minimumDistanceToRoute(
                from: item.placemark.coordinate,
                routeCoordinates: coordinates
            ) <= maxOffRouteMeters
        }
    }

    // MARK: - Geometry

    private func minimumDistanceToRoute(
        from point: CLLocationCoordinate2D,
        routeCoordinates: [CLLocationCoordinate2D]
    ) -> CLLocationDistance {
        guard routeCoordinates.count > 1 else {
            return point.distance(to: routeCoordinates.first ?? point)
        }
        var minDist = CLLocationDistance.greatestFiniteMagnitude
        for i in 0 ..< routeCoordinates.count - 1 {
            let d = point.perpendicularDistance(
                toSegment: routeCoordinates[i],
                end: routeCoordinates[i + 1]
            )
            if d < minDist { minDist = d }
        }
        return minDist
    }
}

// MARK: - Array helpers

extension Array {
    var middle: Element? {
        guard !isEmpty else { return nil }
        return self[count / 2]
    }

    func sampled(maxCount: Int) -> [Element] {
        guard count > maxCount else { return self }
        var result: [Element] = []
        let step = Double(count - 1) / Double(maxCount - 1)
        for i in 0 ..< maxCount {
            result.append(self[Int((Double(i) * step).rounded())])
        }
        return result
    }
}
