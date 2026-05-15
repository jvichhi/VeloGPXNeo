//
//  PlaceDescriptorService.swift
//  VeloGPX
//
//  Resolves GPX waypoint coordinates into rich MKMapItem.
//  iOS 26+ only: MKReverseGeocodingRequest (primary) + MKLocalSearch (fallback).
//  @available(iOS 26,*) annotation removed — deployment target is iOS 26 (PROJECT.md).
//  CLGeocoder and MKPlacemark(placemark:) fully removed.
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

    func resolve(_ waypoint: WaypointPoint) async -> ResolvedWaypoint {
        let lat = waypoint.coordinate.latitude
        let lon = waypoint.coordinate.longitude
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)

        if let resolved = await resolveViaReverseGeocoding(waypoint: waypoint, coordinate: coord) {
            return resolved
        }
        return await resolveViaLocalSearch(waypoint: waypoint, coordinate: coord)
    }

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

    // MARK: - MKReverseGeocodingRequest

    private func resolveViaReverseGeocoding(
        waypoint: WaypointPoint,
        coordinate: CLLocationCoordinate2D
    ) async -> ResolvedWaypoint? {
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

    // MARK: - MKLocalSearch fallback

    private func resolveViaLocalSearch(
        waypoint: WaypointPoint,
        coordinate: CLLocationCoordinate2D
    ) async -> ResolvedWaypoint {
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
            let response = try await MKLocalSearch(request: request).start()
            let ref = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            // item.location is CLLocation (non-optional iOS 26) — .placemark deprecated
            let closest = response.mapItems.min(by: {
                $0.location.distance(from: ref) < $1.location.distance(from: ref)
            })
            return ResolvedWaypoint(
                name: closest?.name ?? waypoint.name ?? "Waypoint",
                coordinate: coordinate,
                mapItem: closest,
                resolvedViaPlaceDescriptor: false
            )
        } catch {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let fallbackItem = MKMapItem(location: location, address: nil)
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
