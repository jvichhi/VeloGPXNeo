//
//  CyclingRouteService.swift
//  VeloGPX
//
//  Computes cycling directions between two points using MKDirections.
//  - iOS 26+: uses .cycling transport type (WWDC25 new API)
//  - iOS 18 fallback: uses .walking
//  Returns the first MKRoute plus rich metadata (name, notices, ETA).
//

import Foundation
import MapKit
import CoreLocation

// MARK: - Route Result

struct CyclingRouteResult {
    /// The computed MKRoute (polyline, steps, distance, ETA).
    let route: MKRoute

    /// Localized route name provided by MapKit (iOS 26+), nil on older OS.
    let routeName: String?

    /// Road closure / restriction notices (iOS 26+), empty on older OS.
    let notices: [String]

    /// The matched source MapItem MapKit actually used (may differ from request).
    let matchedSource: MKMapItem?

    /// The matched destination MapItem MapKit actually used.
    let matchedDestination: MKMapItem?

    /// Whether the route was computed using .cycling (true) or .walking fallback (false).
    let isCycling: Bool
}

// MARK: - Service

actor CyclingRouteService {

    static let shared = CyclingRouteService()
    private init() {}

    /// Calculates a cycling route from `source` to `destination`.
    /// Automatically selects .cycling on iOS 26+, falls back to .walking on iOS 18.
    func calculateRoute(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> CyclingRouteResult {

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
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

        // iOS 26: response exposes richer metadata via matched items and notices.
        var routeName: String? = nil
        var notices: [String] = []
        var matchedSource: MKMapItem? = nil
        var matchedDestination: MKMapItem? = nil

        if #available(iOS 26.0, *) {
            routeName = firstRoute.name.isEmpty ? nil : firstRoute.name
            notices = response.notices.map { $0.description }
            matchedSource = response.source
            matchedDestination = response.destination
        }

        return CyclingRouteResult(
            route: firstRoute,
            routeName: routeName,
            notices: notices,
            matchedSource: matchedSource,
            matchedDestination: matchedDestination,
            isCycling: isCycling
        )
    }

    /// Returns all alternative routes (up to the first 3).
    func calculateAlternativeRoutes(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> [CyclingRouteResult] {

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
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
            var routeName: String? = nil
            var notices: [String] = []
            var matchedSource: MKMapItem? = nil
            var matchedDestination: MKMapItem? = nil

            if #available(iOS 26.0, *) {
                routeName = route.name.isEmpty ? nil : route.name
                notices = response.notices.map { $0.description }
                matchedSource = response.source
                matchedDestination = response.destination
            }

            return CyclingRouteResult(
                route: route,
                routeName: routeName,
                notices: notices,
                matchedSource: matchedSource,
                matchedDestination: matchedDestination,
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
