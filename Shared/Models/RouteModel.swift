import Foundation
import CoreLocation

public struct RouteModel: Identifiable, Codable, Equatable, Sendable {
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

public struct TrackPoint: Codable, Sendable, Equatable {
    public let coordinate: Coordinate
    public let elevation: Double?
    public let timestamp: Date?

    public init(coordinate: CLLocationCoordinate2D, elevation: Double? = nil, timestamp: Date? = nil) {
        self.coordinate = coordinate.asCoordinate
        self.elevation = elevation
        self.timestamp = timestamp
    }
}

public struct WaypointPoint: Codable, Identifiable, Sendable, Equatable {
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

public enum RouteFormat: String, Codable, Sendable {
    case gpx
    case geojson
    /// Route created interactively in the Plan tab.
    case planned
}
