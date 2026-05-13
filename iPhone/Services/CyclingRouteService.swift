//
//  CyclingRouteService.swift
//  VeloGPX
//
//  Computes cycling directions between two points using MKDirections.
//  - iOS 26+: .cycling transport type + MKMapItem(location:address:)
//  - Fallback: .walking + MKMapItem(placemark: MKPlacemark(coordinate:))
//
//  MKMapItem and MKRoute are @MainActor-isolated.
//  Pattern: MainActor.run to build request → directions.calculate() off-actor
//           → MainActor.run to read route properties into plain Sendable struct.
//

import Foundation
import MapKit
import CoreLocation

// MARK: - Route Result

/// Plain-Sendable snapshot of MKRoute data extracted on @MainActor.
/// Callers (SwiftUI views) are already @MainActor, so using `route` for
/// MapPolyline / distance / ETA is safe there.
struct CyclingRouteResult: @unchecked Sendable {
    let route: MKRoute                                          // @MainActor-isolated; access only from @MainActor
    let steps: [(instructions: String, distance: Double)]      // pre-extracted Sendable copy
    let totalDistance: Double
    let expectedTravelTime: TimeInterval
    let routeName: String?
    let matchedSource: MKMapItem?
    let matchedDestination: MKMapItem?
    let isCycling: Bool
}

// MARK: - Service

actor CyclingRouteService {

    static let shared = CyclingRouteService()
    private init() {}

    func calculateRoute(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> CyclingRouteResult {

        // Step 1: build MKMapItems + request on @MainActor
        let (sourceItem, destinationItem, request) = await MainActor.run { () -> (MKMapItem, MKMapItem, MKDirections.Request) in
            let src: MKMapItem
            let dst: MKMapItem
            if #available(iOS 26.0, *) {
                src = MKMapItem(location: CLLocation(latitude: source.latitude, longitude: source.longitude), address: nil)
                dst = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
            } else {
                src = MKMapItem(placemark: MKPlacemark(coordinate: source))
                dst = MKMapItem(placemark: MKPlacemark(coordinate: destination))
            }
            let req = MKDirections.Request()
            req.source = src
            req.destination = dst
            req.requestsAlternateRoutes = true
            if #available(iOS 26.0, *) {
                req.transportType = .cycling
            } else {
                req.transportType = .walking
            }
            return (src, dst, req)
        }

        // Step 2: fire network call off @MainActor
        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        guard let firstRoute = response.routes.first else {
            throw CyclingRouteError.noRoutesFound
        }

        // Step 3: extract all @MainActor-isolated route properties on @MainActor
        return await MainActor.run {
            let isCycling: Bool
            if #available(iOS 26.0, *) { isCycling = true } else { isCycling = false }
            return CyclingRouteResult(
                route: firstRoute,
                steps: firstRoute.steps.map { ($0.instructions, $0.distance) },
                totalDistance: firstRoute.distance,
                expectedTravelTime: firstRoute.expectedTravelTime,
                routeName: firstRoute.name.isEmpty ? nil : firstRoute.name,
                matchedSource: sourceItem,
                matchedDestination: destinationItem,
                isCycling: isCycling
            )
        }
    }

    func calculateAlternativeRoutes(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> [CyclingRouteResult] {

        let (sourceItem, destinationItem, request) = await MainActor.run { () -> (MKMapItem, MKMapItem, MKDirections.Request) in
            let src: MKMapItem
            let dst: MKMapItem
            if #available(iOS 26.0, *) {
                src = MKMapItem(location: CLLocation(latitude: source.latitude, longitude: source.longitude), address: nil)
                dst = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
            } else {
                src = MKMapItem(placemark: MKPlacemark(coordinate: source))
                dst = MKMapItem(placemark: MKPlacemark(coordinate: destination))
            }
            let req = MKDirections.Request()
            req.source = src
            req.destination = dst
            req.requestsAlternateRoutes = true
            if #available(iOS 26.0, *) {
                req.transportType = .cycling
            } else {
                req.transportType = .walking
            }
            return (src, dst, req)
        }

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()

        return await MainActor.run {
            let isCycling: Bool
            if #available(iOS 26.0, *) { isCycling = true } else { isCycling = false }
            return response.routes.prefix(3).map { route in
                CyclingRouteResult(
                    route: route,
                    steps: route.steps.map { ($0.instructions, $0.distance) },
                    totalDistance: route.distance,
                    expectedTravelTime: route.expectedTravelTime,
                    routeName: route.name.isEmpty ? nil : route.name,
                    matchedSource: sourceItem,
                    matchedDestination: destinationItem,
                    isCycling: isCycling
                )
            }
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

// MARK: - GPX Cue Engine

/// Generates turn-by-turn cue sheets from GPX track geometry.
actor GPXCueEngine {
    static let shared = GPXCueEngine()
    private init() {}

    private let minBearingChange: Double = 30
    private let minKeypointSpacing: Double = 50
    private let windowDistanceMeters: Double = 50

    func generateCues(for route: RouteModel) async -> [CueSheetEntry] {
        let points = route.trackPoints
        guard points.count > 2 else { return [] }

        let keypoints = extractKeypoints(from: points)
        guard keypoints.count >= 2 else {
            let last = points.last!.coordinate
            return [CueSheetEntry(
                cumulativeDistance: route.totalDistance,
                instruction: "Arrive at destination",
                lat: last.latitude,
                lon: last.longitude,
                icon: .arrive
            )]
        }

        let segments = await routeBetween(keypoints: keypoints)
        return assembleCueSheet(from: segments)
    }

    // MARK: - Keypoint extraction

    private func extractKeypoints(from points: [TrackPoint]) -> [Coordinate] {
        var keypoints: [Coordinate] = [points.first!.coordinate]

        for i in 1..<(points.count - 1) {
            let behind = gatherWindow(points: points, center: i, windowM: windowDistanceMeters, backward: true)
            let ahead  = gatherWindow(points: points, center: i, windowM: windowDistanceMeters, backward: false)
            guard behind.count >= 2, ahead.count >= 2 else { continue }

            let inBearing  = bearing(from: behind.first!, to: behind.last!)
            let outBearing = bearing(from: ahead.first!, to: ahead.last!)
            var delta = abs(outBearing - inBearing)
            if delta > 180 { delta = 360 - delta }

            let lastCoord = keypoints.last!
            let distSinceLast = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
                .distance(from: CLLocation(latitude: points[i].coordinate.latitude, longitude: points[i].coordinate.longitude))

            if delta >= minBearingChange, distSinceLast >= minKeypointSpacing {
                keypoints.append(points[i].coordinate)
            }
        }

        keypoints.append(points.last!.coordinate)
        return keypoints
    }

    private func gatherWindow(points: [TrackPoint], center: Int, windowM: Double, backward: Bool) -> [CLLocationCoordinate2D] {
        var accumulated: Double = 0
        let centerCoord = points[center].coordinate
        var result: [CLLocationCoordinate2D] = [
            CLLocationCoordinate2D(latitude: centerCoord.latitude, longitude: centerCoord.longitude)
        ]
        var idx = center
        while accumulated < windowM {
            let next = backward ? idx - 1 : idx + 1
            guard next >= 0, next < points.count else { break }
            let a = points[idx].coordinate
            let b = points[next].coordinate
            accumulated += CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            result.append(CLLocationCoordinate2D(latitude: b.latitude, longitude: b.longitude))
            idx = next
        }
        return result
    }

    // MARK: - Routing

    private func routeBetween(keypoints: [Coordinate]) async -> [(lat: Double, lon: Double, steps: [(String, Double)])] {
        let pairs = Array(zip(keypoints, keypoints.dropFirst()))

        typealias SegmentSteps = (index: Int, lat: Double, lon: Double, steps: [(String, Double)])
        var results: [SegmentSteps] = []

        await withTaskGroup(of: SegmentSteps?.self) { group in
            for (i, pair) in pairs.enumerated() {
                let fromLat = pair.0.latitude
                let fromLon = pair.0.longitude
                let toLat   = pair.1.latitude
                let toLon   = pair.1.longitude
                group.addTask {
                    let from = CLLocationCoordinate2D(latitude: fromLat, longitude: fromLon)
                    let to   = CLLocationCoordinate2D(latitude: toLat,   longitude: toLon)
                    do {
                        let result = try await CyclingRouteService.shared.calculateRoute(from: from, to: to)
                        return (i, fromLat, fromLon, result.steps)
                    } catch {
                        let dist = CLLocation(latitude: fromLat, longitude: fromLon)
                            .distance(from: CLLocation(latitude: toLat, longitude: toLon))
                        let bearingDeg = self.bearing(from: from, to: to)
                        let icon = self.bearingToIcon(bearingDeg)
                        let desc = self.geometryInstruction(for: icon)
                        return (i, fromLat, fromLon, [(desc, dist)])
                    }
                }
            }
            for await seg in group {
                if let s = seg { results.append(s) }
            }
        }

        results.sort { $0.index < $1.index }
        return results.map { (lat: $0.lat, lon: $0.lon, steps: $0.steps) }
    }

    // MARK: - Cue assembly

    private func assembleCueSheet(from segments: [(lat: Double, lon: Double, steps: [(String, Double)])]) -> [CueSheetEntry] {
        var entries: [CueSheetEntry] = []
        var cumulative: Double = 0

        for seg in segments {
            for (instruction, distance) in seg.steps {
                let icon = cueIcon(from: instruction)
                entries.append(CueSheetEntry(
                    cumulativeDistance: cumulative,
                    instruction: instruction,
                    lat: seg.lat,
                    lon: seg.lon,
                    icon: icon
                ))
                cumulative += distance
            }
        }

        if let last = entries.last,
           last.instruction.lowercased().contains("arrive") || last.instruction.lowercased().contains("destination") {
            entries[entries.count - 1] = CueSheetEntry(
                id: last.id,
                cumulativeDistance: last.cumulativeDistance,
                instruction: "Arrive at destination",
                lat: last.latitude,
                lon: last.longitude,
                icon: .arrive
            )
        }

        var deduped: [CueSheetEntry] = []
        for entry in entries {
            if let prev = deduped.last, prev.instruction == entry.instruction { continue }
            deduped.append(entry)
        }
        return deduped
    }

    // MARK: - Icon mapping

    private func cueIcon(from instructions: String) -> CueIcon {
        let lower = instructions.lowercased()
        if lower.contains("roundabout")           { return .roundabout }
        if lower.contains("u-turn")               { return .uTurn }
        if lower.contains("merge")                { return .merge }
        if lower.contains("slight left")          { return .slightLeft }
        if lower.contains("slight right")         { return .slightRight }
        if lower.contains("sharp left")           { return .sharpLeft }
        if lower.contains("sharp right")          { return .sharpRight }
        if lower.contains("turn left")            { return .left }
        if lower.contains("turn right")           { return .right }
        if lower.contains("left")                 { return .left }
        if lower.contains("right")                { return .right }
        if lower.contains("arrive") || lower.contains("destination") { return .arrive }
        return .straight
    }

    nonisolated private func bearingToIcon(_ bearing: Double) -> CueIcon {
        switch bearing {
        case 330...360, 0..<30:  return .straight
        case 30..<60:            return .slightRight
        case 60..<120:           return .right
        case 120..<150:          return .sharpRight
        case 150..<210:          return .uTurn
        case 210..<240:          return .sharpLeft
        case 240..<300:          return .left
        case 300..<330:          return .slightLeft
        default:                 return .straight
        }
    }

    nonisolated private func geometryInstruction(for icon: CueIcon) -> String {
        switch icon {
        case .sharpLeft:   return "Sharp left ahead"
        case .sharpRight:  return "Sharp right ahead"
        case .left:        return "Turn left ahead"
        case .right:       return "Turn right ahead"
        case .slightLeft:  return "Slight left ahead"
        case .slightRight: return "Slight right ahead"
        case .uTurn:       return "Make a U-turn ahead"
        default:           return "Continue straight"
        }
    }

    nonisolated private func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let b = atan2(y, x) * 180 / .pi
        return (b + 360).truncatingRemainder(dividingBy: 360)
    }
}
