//
//  PlaceDescriptorService.swift
//  VeloGPX
//
//  Resolves GPX waypoint coordinates into rich MKMapItem.
//
//  iOS 26+ only: MKReverseGeocodingRequest (primary) + MKLocalSearch (fallback).
//  CLGeocoder and MKPlacemark(placemark:) are deprecated in iOS 26 and
//  have been fully removed — VeloGPX targets iOS 26+ exclusively.
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

@available(iOS 26.0, *)
actor PlaceDescriptorService {

    static let shared = PlaceDescriptorService()
    private init() {}

    func resolve(_ waypoint: WaypointPoint) async -> ResolvedWaypoint {
        let lat = waypoint.coordinate.latitude
        let lon = waypoint.coordinate.longitude
        let coord = await MainActor.run { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

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

    // MARK: - MKReverseGeocodingRequest (iOS 26+)

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
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 100, longitudinalMeters: 100)

        let request = MKLocalSearch.Request()
        request.region = region
        request.pointOfInterestFilter = .includingAll
        request.resultTypes = .pointOfInterest

        do {
            let response = try await MKLocalSearch(request: request).start()
            let ref = CLLocation(latitude: lat, longitude: lon)
            // Use item.location (CLLocation) — MKMapItem.placemark is deprecated in iOS 26
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
            // Build a bare MKMapItem using iOS 26 API
            let location = CLLocation(latitude: lat, longitude: lon)
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
