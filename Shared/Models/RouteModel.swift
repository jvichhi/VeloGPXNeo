import Foundation
import CoreLocation
import SwiftUI

public struct RouteModel: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var sourceFormat: RouteFormat
    public var trackPoints: [TrackPoint]
    public var waypoints: [WaypointPoint]
    public var totalDistance: Double
    public var elevationGain: Double
    public var elevationLoss: Double
    public var createdAt: Date
    public var originalFilename: String?

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public init(
        id: UUID = UUID(),
        name: String,
        sourceFormat: RouteFormat,
        trackPoints: [TrackPoint],
        waypoints: [WaypointPoint] = [],
        originalFilename: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sourceFormat = sourceFormat
        self.trackPoints = trackPoints
        self.waypoints = waypoints
        self.createdAt = Date()
        self.originalFilename = originalFilename
        self.totalDistance = Self.calculateDistance(trackPoints)
        let elevation = Self.calculateElevation(trackPoints)
        self.elevationGain = elevation.gain
        self.elevationLoss = elevation.loss
    }

    public static func calculateDistance(_ points: [TrackPoint]) -> Double {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { partial, pair in
            partial + pair.0.coordinate.clCoordinate.distance(to: pair.1.coordinate.clCoordinate)
        }
    }

    public static func calculateElevation(_ points: [TrackPoint]) -> (gain: Double, loss: Double) {
        var gain = 0.0
        var loss = 0.0
        for pair in zip(points, points.dropFirst()) {
            guard let a = pair.0.elevation, let b = pair.1.elevation else { continue }
            let delta = b - a
            if delta > 0 { gain += delta } else { loss += abs(delta) }
        }
        return (gain, loss)
    }
}

public struct TrackPoint: Codable, Hashable, Sendable, Equatable {
    public let coordinate: Coordinate
    public let elevation: Double?
    public let timestamp: Date?

    public init(coordinate: CLLocationCoordinate2D, elevation: Double? = nil, timestamp: Date? = nil) {
        self.coordinate = coordinate.asCoordinate
        self.elevation = elevation
        self.timestamp = timestamp
    }
}

public struct WaypointPoint: Codable, Identifiable, Hashable, Sendable, Equatable {
    public let id: UUID
    public let coordinate: Coordinate
    public let name: String?
    public let symbol: String?

    public init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, name: String? = nil, symbol: String? = nil) {
        self.id = id
        self.coordinate = coordinate.asCoordinate
        self.name = name
        self.symbol = symbol
    }
}

public enum RouteFormat: String, Codable, Hashable, Sendable {
    case gpx
    case geojson
    case planned
}

// MARK: - Cue Sheet

public enum CueIcon: String, Codable, Sendable {
    case straight, slightLeft, left, slightRight, right
    case sharpLeft, sharpRight, roundabout, uTurn, merge, arrive

    public var systemImage: String {
        switch self {
        case .straight:    return "arrow.up"
        case .slightLeft:  return "arrow.turn.up.left"
        case .left:        return "arrow.turn.left"
        case .slightRight: return "arrow.turn.up.right"
        case .right:       return "arrow.turn.right"
        case .sharpLeft:   return "arrow.uturn.left"
        case .sharpRight:  return "arrow.uturn.right"
        case .roundabout:  return "arrow.triangle.turn.up.right.circle"
        case .uTurn:       return "arrow.uturn.backward"
        case .merge:       return "arrow.merge"
        case .arrive:      return "flag.checkered"
        }
    }
}

public struct CueSheetEntry: Identifiable, Codable, Sendable {
    public let id: UUID
    public let cumulativeDistance: Double
    public let instruction: String
    public let latitude: Double
    public let longitude: Double
    public let icon: CueIcon

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Convenience init accepting CLLocationCoordinate2D.
    /// Note: CLLocationCoordinate2D.init is @MainActor on iOS 26+,
    /// so call this only from a @MainActor context on iOS 26.
    /// For actor/background contexts use init(id:cumulativeDistance:instruction:lat:lon:icon:).
    public init(
        id: UUID = UUID(),
        cumulativeDistance: Double,
        instruction: String,
        coordinate: CLLocationCoordinate2D,
        icon: CueIcon
    ) {
        self.id = id
        self.cumulativeDistance = cumulativeDistance
        self.instruction = instruction
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.icon = icon
    }

    /// Isolation-safe init for use from actors and background tasks.
    /// Takes raw lat/lon doubles — no CLLocationCoordinate2D construction.
    public init(
        id: UUID = UUID(),
        cumulativeDistance: Double,
        instruction: String,
        lat: Double,
        lon: Double,
        icon: CueIcon
    ) {
        self.id = id
        self.cumulativeDistance = cumulativeDistance
        self.instruction = instruction
        self.latitude = lat
        self.longitude = lon
        self.icon = icon
    }
}

// MARK: - Route Difficulty

public enum RouteDifficulty: String, Codable, Comparable, Sendable {
    case easy = "Easy"
    case moderate = "Moderate"
    case hard = "Hard"
    case epic = "Epic"

    public static func < (lhs: RouteDifficulty, rhs: RouteDifficulty) -> Bool {
        let order: [RouteDifficulty] = [.easy, .moderate, .hard, .epic]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }

    public var color: Color {
        switch self {
        case .easy:     return .green
        case .moderate: return .blue
        case .hard:     return .orange
        case .epic:     return .red
        }
    }
}

public extension RouteModel {
    var difficulty: RouteDifficulty {
        let km = totalDistance / 1000
        let gain = elevationGain
        if km >= 150 || gain >= 2000 { return .epic }
        if km >= 100 || gain >= 1000 { return .hard }
        if km >= 50  || gain >= 500  { return .moderate }
        return .easy
    }

    func detectClimbs() -> [ClimbSegment] {
        guard trackPoints.count > 50 else { return [] }

        let withElevation = trackPoints.enumerated().compactMap { (i, pt) -> (Int, Double)? in
            guard let ele = pt.elevation else { return nil }
            return (i, ele)
        }
        guard withElevation.count > 10 else { return [] }

        var candidateRuns: [(start: Int, end: Int)] = []
        var runStart: Int?

        for i in 1..<withElevation.count {
            let (prevIdx, prevEle) = withElevation[i - 1]
            let (currIdx, currEle) = withElevation[i]
            let dist = trackPoints[prevIdx].coordinate.clCoordinate.distance(
                to: trackPoints[currIdx].coordinate.clCoordinate
            )
            guard dist > 0.1 else { continue }

            let grade = ((currEle - prevEle) / dist) * 100

            if grade > 2.0 {
                if runStart == nil { runStart = prevIdx }
            } else {
                if let start = runStart {
                    candidateRuns.append((start, prevIdx))
                    runStart = nil
                }
            }
        }
        if let start = runStart {
            candidateRuns.append((start, withElevation.last!.0))
        }

        let merged = mergeClimbRuns(candidateRuns)
        return merged.compactMap { segment in
            classifyClimb(start: segment.start, end: segment.end)
        }
    }

    static func trackArcDistance(from startIdx: Int, to endIdx: Int, points: [TrackPoint]) -> Double {
        guard startIdx < endIdx, endIdx < points.count else { return 0 }
        return zip(points[startIdx..<endIdx], points[(startIdx + 1)...endIdx])
            .reduce(0.0) { acc, pair in
                acc + pair.0.coordinate.clCoordinate.distance(to: pair.1.coordinate.clCoordinate)
            }
    }

    private func mergeClimbRuns(_ runs: [(start: Int, end: Int)]) -> [(start: Int, end: Int)] {
        guard runs.count > 1 else { return runs }
        var merged: [(start: Int, end: Int)] = []
        var current = runs[0]
        for next in runs.dropFirst() {
            let gapDist = Self.trackArcDistance(from: current.end, to: next.start, points: trackPoints)
            if gapDist < 200 {
                current.end = next.end
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }

    private func classifyClimb(start: Int, end: Int) -> ClimbSegment? {
        let totalDist = Self.trackArcDistance(from: start, to: end, points: trackPoints)
        guard totalDist >= 800 else { return nil }

        let elev = trackPoints[start..<end].compactMap { $0.elevation }
        guard elev.count >= 2 else { return nil }

        let gain = zip(elev, elev.dropFirst()).reduce(0.0) { acc, pair in
            let d = pair.1 - pair.0
            return acc + (d > 0 ? d : 0)
        }
        guard gain >= 50 else { return nil }

        let avgGrade = (gain / totalDist) * 100

        let category: ClimbCategory = {
            if avgGrade >= 8, totalDist >= 8000, gain >= 600 { return .hc }
            if avgGrade >= 6, totalDist >= 5000, gain >= 400 { return .one }
            if avgGrade >= 4, totalDist >= 3000, gain >= 200 { return .two }
            if avgGrade >= 3, totalDist >= 1500, gain >= 100 { return .three }
            return .four
        }()

        return ClimbSegment(
            startIndex: start,
            endIndex: end,
            totalDistance: totalDist,
            elevationGain: gain,
            avgGrade: avgGrade,
            category: category
        )
    }
}
