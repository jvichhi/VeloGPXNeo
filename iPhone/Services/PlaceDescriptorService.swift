//
//  PlaceDescriptorService.swift
//  VeloGPX
//
//  Resolves GPX waypoint coordinates into rich MKMapItem using:
//  - iOS 26+: CLGeocoder reverse geocoding for canonical place name
//  - Fallback: MKLocalSearch with point-of-interest region query
//
//  Usage:
//    let resolved = await PlaceDescriptorService.shared.resolve(waypoint)
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
        let coord = waypoint.coordinate.clCoordinate
        // Try reverse geocoding first for a canonical place name.
        if let resolved = await resolveViaGeocoder(waypoint: waypoint, coordinate: coord) {
            return resolved
        }
        // Fallback: MKLocalSearch POI lookup.
        return await resolveLegacy(waypoint: waypoint, coordinate: coord)
    }

    /// Resolves an array of waypoints concurrently.
    func resolveAll(_ waypoints: [WaypointPoint]) async -> [ResolvedWaypoint] {
        await withTaskGroup(of: ResolvedWaypoint.self) { group in
            for wp in waypoints {
                group.addTask { await self.resolve(wp) }
            }
            var results: [ResolvedWaypoint] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    // MARK: - Reverse geocoder path

    private func resolveViaGeocoder(waypoint: WaypointPoint, coordinate: CLLocationCoordinate2D) async -> ResolvedWaypoint? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            let name = placemark.name ?? placemark.thoroughfare ?? waypoint.name ?? "Waypoint"
            let mkPlacemark = MKPlacemark(placemark: placemark)
            let mapItem = MKMapItem(placemark: mkPlacemark)
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

    // MARK: - MKLocalSearch fallback path

    private func resolveLegacy(waypoint: WaypointPoint, coordinate: CLLocationCoordinate2D) async -> ResolvedWaypoint {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 100,
            longitudinalMeters: 100
        )
        let request = MKLocalSearch.Request()
        request.region = region
        request.pointOfInterestFilter = .includingAll
        request.resultTypes = .pointOfInterest

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            let closest = response.mapItems.min(by: {
                $0.placemark.coordinate.distance(to: coordinate) <
                $1.placemark.coordinate.distance(to: coordinate)
            })
            return ResolvedWaypoint(
                name: closest?.name ?? waypoint.name ?? "Waypoint",
                coordinate: coordinate,
                mapItem: closest,
                resolvedViaPlaceDescriptor: false
            )
        } catch {
            let placemark = MKPlacemark(coordinate: coordinate)
            let item = MKMapItem(placemark: placemark)
            item.name = waypoint.name ?? "Waypoint"
            return ResolvedWaypoint(
                name: waypoint.name ?? "Waypoint",
                coordinate: coordinate,
                mapItem: item,
                resolvedViaPlaceDescriptor: false
            )
        }
    }
}
