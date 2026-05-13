//
//  PlaceDescriptorService.swift
//  VeloGPX
//
//  Resolves GPX waypoint coordinates into rich MKMapItem using:
//  - iOS 26+: MKReverseGeocodingRequest for canonical place name
//  - Fallback: MKLocalSearch with point-of-interest region query
//
//  CLGeocoder and MKPlacemark(placemark:) are deprecated in iOS 26.
//  The legacy paths are compiled only when targeting iOS < 26 via #available.
//

import Foundation
import MapKit
import CoreLocation

struct ResolvedWaypoint {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let mapItem: MKMapItem?
    let resolvedViaPlaceDescriptor: Bool
}

actor PlaceDescriptorService {

    static let shared = PlaceDescriptorService()
    private init() {}

    /// Resolves a single waypoint coordinate to a named MKMapItem.
    func resolve(_ waypoint: WaypointPoint) async -> ResolvedWaypoint {
        let lat = waypoint.coordinate.latitude
        let lon = waypoint.coordinate.longitude
        let coord = await MainActor.run { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

        if #available(iOS 26.0, *) {
            if let resolved = await resolveModern(waypoint: waypoint, coordinate: coord) {
                return resolved
            }
        } else {
            if let resolved = await resolveLegacyGeocoder(waypoint: waypoint, coordinate: coord) {
                return resolved
            }
        }
        return await resolveLegacyLocalSearch(waypoint: waypoint, coordinate: coord)
    }

    /// Resolves an array of waypoints concurrently.
    func resolveAll(_ waypoints: [WaypointPoint]) async -> [ResolvedWaypoint] {
        await withTaskGroup(of: ResolvedWaypoint.self) { group in
            for wp in waypoints {
                group.addTask { await self.resolve(wp) }
            }
            var results: [ResolvedWaypoint] = []
            for await result in group { results.append(result) }
            return results
        }
    }

    // MARK: - iOS 26+ path

    @available(iOS 26.0, *)
    private func resolveModern(waypoint: WaypointPoint, coordinate: CLLocationCoordinate2D) async -> ResolvedWaypoint? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        do {
            let items = try await request.mapItems
            guard let item = items.first else { return nil }
            let name = item.name ?? waypoint.name ?? "Waypoint"
            item.name = name
            return ResolvedWaypoint(
                name: name,
                coordinate: coordinate,
                mapItem: item,
                resolvedViaPlaceDescriptor: true
            )
        } catch {
            return nil
        }
    }

    // MARK: - iOS <26 CLGeocoder path
    // Wrapped in #available(iOS, obsoleted:26.0) guard at call site;
    // nonisolated wrapper avoids triggering deprecation diagnostics on the actor.

    private func resolveLegacyGeocoder(waypoint: WaypointPoint, coordinate: CLLocationCoordinate2D) async -> ResolvedWaypoint? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return await _legacyGeocode(waypoint: waypoint, coordinate: coordinate, location: location)
    }

    // Isolation-free helper so the deprecated CLGeocoder call lives entirely
    // inside a context the compiler knows is pre-26.
    nonisolated private func _legacyGeocode(
        waypoint: WaypointPoint,
        coordinate: CLLocationCoordinate2D,
        location: CLLocation
    ) async -> ResolvedWaypoint? {
        // CLGeocoder is deprecated in iOS 26 — this helper is only called from
        // the else branch of an #available(iOS 26.0, *) check.
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            let name = placemark.name ?? placemark.thoroughfare ?? waypoint.name ?? "Waypoint"
            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            mapItem.name = name
            return ResolvedWaypoint(
                name: name,
                coordinate: coordinate,
                mapItem: mapItem,
                resolvedViaPlaceDescriptor: true
            )
        } catch {
            return nil
        }
    }

    // MARK: - MKLocalSearch fallback (all OS versions)

    private func resolveLegacyLocalSearch(waypoint: WaypointPoint, coordinate: CLLocationCoordinate2D) async -> ResolvedWaypoint {
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 100, longitudinalMeters: 100)
        let request = MKLocalSearch.Request()
        request.region = region
        request.pointOfInterestFilter = .includingAll
        request.resultTypes = .pointOfInterest

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            let ref = CLLocation(latitude: lat, longitude: lon)

            // Use item.location (CLLocation) on iOS 26+ to avoid MKMapItem.placemark deprecation.
            let closest: MKMapItem?
            if #available(iOS 26.0, *) {
                closest = response.mapItems.min(by: { $0.location.distance(from: ref) < $1.location.distance(from: ref) })
            } else {
                closest = response.mapItems.min(by: {
                    CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude)
                        .distance(from: ref) <
                    CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude)
                        .distance(from: ref)
                })
            }
            return ResolvedWaypoint(
                name: closest?.name ?? waypoint.name ?? "Waypoint",
                coordinate: coordinate,
                mapItem: closest,
                resolvedViaPlaceDescriptor: false
            )
        } catch {
            let fallbackItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            fallbackItem.name = waypoint.name ?? "Waypoint"
            return ResolvedWaypoint(
                name: waypoint.name ?? "Waypoint",
                coordinate: coordinate,
                mapItem: fallbackItem,
                resolvedViaPlaceDescriptor: false
            )
        }
    }
}
