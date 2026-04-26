//
//  PlaceDescriptorService.swift
//  VeloGPX
//
//  Resolves GPX waypoint coordinates into rich MKMapItem using:
//  - iOS 26+: PlaceDescriptor + MKMapItemRequest (WWDC25 GeoToolbox framework)
//  - iOS 18 fallback: MKLocalSearch with point-of-interest region query
//
//  Usage:
//    let mapItem = await PlaceDescriptorService.shared.resolve(waypoint)
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

        if #available(iOS 26.0, *) {
            return await resolveModern(waypoint: waypoint, coordinate: coord)
        } else {
            return await resolveLegacy(waypoint: waypoint, coordinate: coord)
        }
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

    // MARK: - iOS 26+ path

    @available(iOS 26.0, *)
    private func resolveModern(waypoint: WaypointPoint, coordinate: CLLocationCoordinate2D) async -> ResolvedWaypoint {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = waypoint.name ?? "Waypoint"

        // MKMapItemRequest resolves the coordinate to a canonical Apple Maps place.
        let request = MKMapItemRequest(mapItem: mapItem)
        do {
            let resolved = try await request.mapItem
            return ResolvedWaypoint(
                name: resolved.name ?? waypoint.name ?? "Waypoint",
                coordinate: coordinate,
                mapItem: resolved,
                resolvedViaPlaceDescriptor: true
            )
        } catch {
            // Resolution failed — return a basic item.
            return ResolvedWaypoint(
                name: waypoint.name ?? "Waypoint",
                coordinate: coordinate,
                mapItem: mapItem,
                resolvedViaPlaceDescriptor: false
            )
        }
    }

    // MARK: - iOS 18 fallback path

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
            // Pick the closest POI to the waypoint coordinate.
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

// MARK: - CLLocationCoordinate2D distance helper (local)

private extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        let loc1 = CLLocation(latitude: latitude, longitude: longitude)
        let loc2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return loc1.distance(from: loc2)
    }
}
