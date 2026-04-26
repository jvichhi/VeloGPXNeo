//
//  CyclingRouteService.swift
//  VeloGPX
//
//  Computes cycling directions between two points using MKDirections.
//  - iOS 26+: uses .cycling transport type
//  - Fallback: uses .walking
//  Returns the first MKRoute plus metadata (name, ETA).
//

import Foundation
import MapKit
import CoreLocation

// MARK: - Route Result

struct CyclingRouteResult {
    /// The computed MKRoute (polyline, steps, distance, ETA).
    let route: MKRoute

    /// Localized route name provided by MapKit, nil if empty.
    let routeName: String?

    /// The source MapItem used for the request.
    let matchedSource: MKMapItem?

    /// The destination MapItem used for the request.
    let matchedDestination: MKMapItem?

    /// Whether the route was computed using .cycling (true) or .walking fallback (false).
    let isCycling: Bool
}

// MARK: - Service

actor CyclingRouteService {

    static let shared = CyclingRouteService()
    private init() {}

    /// Calculates a cycling route from `source` to `destination`.
    func calculateRoute(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> CyclingRouteResult {

        let sourceItem = MKMapItem(placemark: MKPlacemark(coordinate: source))
        let destinationItem = MKMapItem(placemark: MKPlacemark(coordinate: destination))

        let request = MKDirections.Request()
        request.source = sourceItem
        request.destination = destinationItem
        request.requestsAlternateRoutes = true

        var isCycling = false
        if #available(iOS 26.0, *) {
            request.transportType = .cycling
            isCycling = true
        } else {
            request.transportType = .walking
        }

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()

        guard let firstRoute = response.routes.first else {
            throw CyclingRouteError.noRoutesFound
        }

        let routeName = firstRoute.name.isEmpty ? nil : firstRoute.name

        return CyclingRouteResult(
            route: firstRoute,
            routeName: routeName,
            matchedSource: sourceItem,
            matchedDestination: destinationItem,
            isCycling: isCycling
        )
    }

    /// Returns all alternative routes (up to the first 3).
    func calculateAlternativeRoutes(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> [CyclingRouteResult] {

        let sourceItem = MKMapItem(placemark: MKPlacemark(coordinate: source))
        let destinationItem = MKMapItem(placemark: MKPlacemark(coordinate: destination))

        let request = MKDirections.Request()
        request.source = sourceItem
        request.destination = destinationItem
        request.requestsAlternateRoutes = true

        var isCycling = false
        if #available(iOS 26.0, *) {
            request.transportType = .cycling
            isCycling = true
        } else {
            request.transportType = .walking
        }

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()

        return response.routes.prefix(3).map { route in
            CyclingRouteResult(
                route: route,
                routeName: route.name.isEmpty ? nil : route.name,
                matchedSource: sourceItem,
                matchedDestination: destinationItem,
                isCycling: isCycling
            )
        }
    }
}

// MARK: - Errors

enum CyclingRouteError: LocalizedError {
    case noRoutesFound

    var errorDescription: String? {
        switch self {
        case .noRoutesFound:
            return NSLocalizedString(
                "No cycling route found between those two points.",
                comment: "CyclingRouteError.noRoutesFound"
            )
        }
    }
}
