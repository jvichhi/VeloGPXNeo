//
//  PlaceDescriptorService.swift
//  VeloGPX
//
//  Resolves GPX waypoint coordinates into rich MKMapItem using:
//  - iOS 26+: MKReverseGeocodingRequest for canonical place name
//  - Fallback: MKLocalSearch with point-of-interest region query
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
        let coord = CLLocationCoordinate2D(
            latitude: waypoint.coordinate.latitude,
            longitude: waypoint.coordinate.longitude
        )
        if let resolved = await resolveViaGeocoder(waypoint: waypoint, coordinate: coord) {
            return resolved
        }
        return await resolveLegacy(waypoint: waypoint, coordinate: coord)
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

    // MARK: - iOS 26+ reverse geocoding path

    private func resolveViaGeocoder(waypoint: WaypointPoint, coordinate: CLLocationCoordinate2D) async -> ResolvedWaypoint? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        if #available(iOS 26.0, *) {
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
        } else {
            return await resolveViaGeocoderLegacy(waypoint: waypoint, coordinate: coordinate, location: location)
        }
    }

    // MARK: - CLGeocoder fallback (iOS <26)

    @available(iOS, deprecated: 26.0, message: "Use MKReverseGeocodingRequest on iOS 26+")
    private func resolveViaGeocoderLegacy(
        waypoint: WaypointPoint,
        coordinate: CLLocationCoordinate2D,
        location: CLLocation
    ) async -> ResolvedWaypoint? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            let name = placemark.name ?? placemark.thoroughfare ?? waypoint.name ?? "Waypoint"
            // iOS 26 deprecated MKPlacemark(placemark:) — use init(coordinate:) and set name manually
            let mkPlacemark = MKPlacemark(coordinate: coordinate)
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
            let ref = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let closest: MKMapItem? = response.mapItems.min(by: {
                let aLoc: CLLocation
                let bLoc: CLLocation
                if #available(iOS 26.0, *) {
                    aLoc = $0.location
                    bLoc = $1.location
                } else {
                    aLoc = CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude)
                    bLoc = CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude)
                }
                return aLoc.distance(from: ref) < bLoc.distance(from: ref)
            })
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
