import Foundation
import CoreLocation

/// Captures everything about a completed ride — actual GPS track,
/// stats accumulated in RideState, visited POIs, and the original
/// planned route — so it can be displayed in RideSummaryView and
/// exported via GPXExporter.
public struct RideSummary: Sendable {
    // Ride identity
    public let id: UUID
    public let routeName: String
    public let startDate: Date
    public let endDate: Date

    // Stats
    public let totalDistance: Double       // metres
    public let elevationGain: Double       // metres
    public let maxSpeed: Double            // m/s
    public let elapsedTime: TimeInterval

    // Tracks
    /// Actual GPS breadcrumb trail recorded during the ride
    public let actualTrack: [CLLocationCoordinate2D]
    /// Original planned GPX route (for reference overlay + optional export)
    public let plannedTrack: [CLLocationCoordinate2D]

    // POIs
    /// All POIs that were active on the map during this ride
    public let pois: [POIModel]

    public init(
        id: UUID = UUID(),
        routeName: String,
        startDate: Date,
        endDate: Date,
        totalDistance: Double,
        elevationGain: Double,
        maxSpeed: Double,
        elapsedTime: TimeInterval,
        actualTrack: [CLLocationCoordinate2D],
        plannedTrack: [CLLocationCoordinate2D],
        pois: [POIModel]
    ) {
        self.id = id
        self.routeName = routeName
        self.startDate = startDate
        self.endDate = endDate
        self.totalDistance = totalDistance
        self.elevationGain = elevationGain
        self.maxSpeed = maxSpeed
        self.elapsedTime = elapsedTime
        self.actualTrack = actualTrack
        self.plannedTrack = plannedTrack
        self.pois = pois
    }

    // MARK: - Convenience

    public var distanceKm: Double { totalDistance / 1000 }
    public var maxSpeedKmh: Double { maxSpeed * 3.6 }
    public var avgSpeedKmh: Double {
        guard elapsedTime > 0 else { return 0 }
        return (totalDistance / elapsedTime) * 3.6
    }
}
