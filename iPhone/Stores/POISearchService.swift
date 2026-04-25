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

    // MARK: - Route-aware search (used in POI discovery)
    /// Searches at evenly-spaced sample points along the route, deduplicates,
    /// then keeps only results whose perpendicular distance to the route is ≤ maxOffRouteMeters.
    func searchAlongRoute(
        query: String,
        coordinates: [CLLocationCoordinate2D],
        maxOffRouteMeters: CLLocationDistance = 200
    ) async throws -> [MKMapItem] {
        guard !coordinates.isEmpty else { return [] }

        // More sample points needed for a tight 200 m corridor —
        // gaps between samples could otherwise let distant results slip through the filter.
        let samplePoints = coordinates.sampled(maxCount: 12)

        // Search radius per sample: just wide enough to catch anything
        // within the corridor from that point, with a small buffer.
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

        // Hard filter: drop anything further than maxOffRouteMeters from the route polyline
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

    /// Returns up to `maxCount` evenly-spaced elements, always including first and last.
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
