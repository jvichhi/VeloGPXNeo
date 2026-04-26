import Foundation
import MapKit

/// Resolves POIModel instances to live MKMapItems via MKMapItemRequest (iOS 19+).
/// Falls back to a bare-placemark MKMapItem on iOS 18 so the map always has something to show.
/// Results are cached in-memory for the lifetime of the ride session.
actor POIMapItemCache {
    static let shared = POIMapItemCache()
    private var cache: [UUID: MKMapItem] = [:]

    /// Returns a resolved MKMapItem for `poi`, using the cache when available.
    func item(for poi: POIModel) async -> MKMapItem {
        if let cached = cache[poi.id] { return cached }
        let resolved = await resolve(poi)
        cache[poi.id] = resolved
        return resolved
    }

    /// Warm the cache for a full list of POIs concurrently.
    func warmCache(for pois: [POIModel]) async {
        await withTaskGroup(of: Void.self) { group in
            for poi in pois {
                group.addTask { _ = await self.item(for: poi) }
            }
        }
    }

    func invalidate() { cache.removeAll() }

    // MARK: Private

    private func resolve(_ poi: POIModel) async -> MKMapItem {
        // iOS 19+: try to resolve via GeoToolbox PlaceDescriptor for rich live data
        if #available(iOS 19.0, *) {
            let descriptor = MKGeoToolbox.PlaceDescriptor(
                name: poi.name,
                coordinate: poi.coordinate.clCoordinate
            )
            if let request = try? MKMapItemRequest(descriptor: descriptor),
               let item = try? await request.mapItem {
                return item
            }
        }
        // iOS 18 fallback: bare placemark — still works with Marker(item:) and Place Card
        let placemark = MKPlacemark(coordinate: poi.coordinate.clCoordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = poi.name
        return item
    }
}
