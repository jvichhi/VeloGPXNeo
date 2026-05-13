//
//  CyclingRouteService.swift
//  VeloGPX
//
//  Computes cycling directions between two points using MKDirections.
//  - iOS 26+: uses .cycling transport type + MKMapItem(coordinate:)
//  - Fallback: uses .walking + MKPlacemark
//  Returns the first MKRoute plus metadata (name, ETA).
//

import Foundation
import MapKit
import CoreLocation

// MARK: - Route Result

struct CyclingRouteResult {
    let route: MKRoute
    let routeName: String?
    let matchedSource: MKMapItem?
    let matchedDestination: MKMapItem?
    let isCycling: Bool
}

// MARK: - Helpers

/// iOS 26+: MKMapItem(coordinate:). Earlier: MKPlacemark wrapper.
private func mapItem(for coordinate: CLLocationCoordinate2D) -> MKMapItem {
    if #available(iOS 26.0, *) {
        return MKMapItem(coordinate: coordinate)
    } else {
        return MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
    }
}

// MARK: - Service

actor CyclingRouteService {

    static let shared = CyclingRouteService()
    private init() {}

    func calculateRoute(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> CyclingRouteResult {
        let sourceItem = mapItem(for: source)
        let destinationItem = mapItem(for: destination)

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

        return CyclingRouteResult(
            route: firstRoute,
            routeName: firstRoute.name.isEmpty ? nil : firstRoute.name,
            matchedSource: sourceItem,
            matchedDestination: destinationItem,
            isCycling: isCycling
        )
    }

    func calculateAlternativeRoutes(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> [CyclingRouteResult] {
        let sourceItem = mapItem(for: source)
        let destinationItem = mapItem(for: destination)

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
            let lastCoord = points.last!.coordinate
            let lastCL = CLLocationCoordinate2D(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
            return [makeArrivalCue(at: lastCL, distance: route.totalDistance)]
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
            let lastCL = CLLocationCoordinate2D(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
            let currCL = CLLocationCoordinate2D(
                latitude: points[i].coordinate.latitude,
                longitude: points[i].coordinate.longitude
            )
            let distSinceLast = CLLocation(latitude: currCL.latitude, longitude: currCL.longitude)
                .distance(from: CLLocation(latitude: lastCL.latitude, longitude: lastCL.longitude))

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
            let aCL = CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude)
            let bCL = CLLocationCoordinate2D(latitude: b.latitude, longitude: b.longitude)
            accumulated += CLLocation(latitude: aCL.latitude, longitude: aCL.longitude)
                .distance(from: CLLocation(latitude: bCL.latitude, longitude: bCL.longitude))
            result.append(bCL)
            idx = next
        }
        return result
    }

    // MARK: - Routing

    private func routeBetween(keypoints: [Coordinate]) async -> [(coordinate: CLLocationCoordinate2D, steps: [(String, Double)])] {
        let pairs = Array(zip(keypoints, keypoints.dropFirst()))

        typealias SegmentSteps = (index: Int, coord: CLLocationCoordinate2D, steps: [(String, Double)])
        var results: [SegmentSteps] = []

        await withTaskGroup(of: SegmentSteps?.self) { group in
            for (i, pair) in pairs.enumerated() {
                let from = CLLocationCoordinate2D(latitude: pair.0.latitude, longitude: pair.0.longitude)
                let to   = CLLocationCoordinate2D(latitude: pair.1.latitude, longitude: pair.1.longitude)
                group.addTask {
                    do {
                        let result = try await CyclingRouteService.shared.calculateRoute(from: from, to: to)
                        let steps = result.route.steps.map { ($0.instructions, $0.distance) }
                        return (i, from, steps)
                    } catch {
                        let dist = CLLocation(latitude: from.latitude, longitude: from.longitude)
                            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
                        let bearingDeg = self.bearing(from: from, to: to)
                        let icon = self.bearingToIcon(bearingDeg)
                        let desc = self.geometryInstruction(for: icon)
                        return (i, from, [(desc, dist)])
                    }
                }
            }
            for await seg in group {
                if let s = seg { results.append(s) }
            }
        }

        results.sort { $0.index < $1.index }
        return results.map { (coordinate: $0.coord, steps: $0.steps) }
    }

    // MARK: - Cue assembly

    private func assembleCueSheet(from segments: [(coordinate: CLLocationCoordinate2D, steps: [(String, Double)])]) -> [CueSheetEntry] {
        var entries: [CueSheetEntry] = []
        var cumulative: Double = 0

        for seg in segments {
            for (instruction, distance) in seg.steps {
                let icon = cueIcon(from: instruction)
                entries.append(CueSheetEntry(
                    cumulativeDistance: cumulative,
                    instruction: instruction,
                    coordinate: seg.coordinate,
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
                coordinate: last.coordinate,
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

    private func makeArrivalCue(at coord: CLLocationCoordinate2D, distance: Double) -> CueSheetEntry {
        CueSheetEntry(cumulativeDistance: distance, instruction: "Arrive at destination", coordinate: coord, icon: .arrive)
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

    // MARK: - Math

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
