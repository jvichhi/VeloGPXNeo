import Foundation
import CoreLocation

/// Codable wrapper around RideSummary for on-disk persistence.
/// CLLocationCoordinate2D is not Codable so we store as flat Double arrays.
public struct PersistedRideSummary: Codable, Identifiable, Sendable {
    public let id: UUID
    public var routeName: String
    public let startDate: Date
    public let endDate: Date
    public let totalDistance: Double
    public let elevationGain: Double
    public let elevationLoss: Double
    public let maxSpeed: Double
    public let elapsedTime: TimeInterval
    public let actualTrackLats: [Double]
    public let actualTrackLons: [Double]
    public let plannedTrackLats: [Double]
    public let plannedTrackLons: [Double]
    public let pois: [POIModel]
    /// AI-generated caption saved after generation completes. nil until first generation.
    public var aiCaption: String?

    // MARK: - Init from live RideSummary
    public init(from summary: RideSummary) {
        self.id            = summary.id
        self.routeName     = summary.routeName
        self.startDate     = summary.startDate
        self.endDate       = summary.endDate
        self.totalDistance = summary.totalDistance
        self.elevationGain = summary.elevationGain
        self.elevationLoss = summary.elevationLoss
        self.maxSpeed      = summary.maxSpeed
        self.elapsedTime   = summary.elapsedTime
        self.actualTrackLats  = summary.actualTrack.map(\.latitude)
        self.actualTrackLons  = summary.actualTrack.map(\.longitude)
        self.plannedTrackLats = summary.plannedTrack.map(\.latitude)
        self.plannedTrackLons = summary.plannedTrack.map(\.longitude)
        self.pois = summary.pois
        self.aiCaption = nil
    }

    // MARK: - Reconstitute coordinates
    public var actualTrack: [CLLocationCoordinate2D] {
        zip(actualTrackLats, actualTrackLons).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
    }
    public var plannedTrack: [CLLocationCoordinate2D] {
        zip(plannedTrackLats, plannedTrackLons).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
    }

    // MARK: - Convenience
    public var distanceKm: Double   { totalDistance / 1_000 }
    public var maxSpeedKmh: Double  { maxSpeed * 3.6 }
    public var avgSpeedKmh: Double  {
        guard elapsedTime > 0 else { return 0 }
        return (totalDistance / elapsedTime) * 3.6
    }
    public var durationFormatted: String {
        let h = Int(elapsedTime) / 3600
        let m = (Int(elapsedTime) % 3600) / 60
        let s = Int(elapsedTime) % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    // MARK: - Convert back to RideSummary (for reuse in RideSummaryView)
    public func toRideSummary() -> RideSummary {
        RideSummary(
            id: id,
            routeName: routeName,
            startDate: startDate,
            endDate: endDate,
            totalDistance: totalDistance,
            elevationGain: elevationGain,
            elevationLoss: elevationLoss,
            maxSpeed: maxSpeed,
            elapsedTime: elapsedTime,
            actualTrack: actualTrack,
            plannedTrack: plannedTrack,
            pois: pois
        )
    }
}
