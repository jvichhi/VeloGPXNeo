import Foundation

/// Snapshot of live ride state transmitted from iPhone → Watch via WCSession.
/// Pure value type: Sendable, no actor isolation, safe to decode on any thread.
struct WatchRideSummary: Sendable {
    let isActive: Bool
    let isPaused: Bool
    let speedKmh: Double
    let distanceKm: Double
    let elapsedTime: TimeInterval
    let movingTime: TimeInterval
    let avgSpeedKmh: Double
    let elevationGain: Double
    let elevationLoss: Double
    let heartRate: Double?
    let offRouteDistance: Double
    let isOffRoute: Bool
    let nextPOIName: String?
    let nextPOIDistance: Double?
    let nextPOICategory: String?
    let isRerouting: Bool

    nonisolated init(state: RideState) {
        self.isActive         = state.isActive
        self.isPaused         = state.isPaused
        self.speedKmh         = state.speedKmh
        self.distanceKm       = state.distanceKm
        self.elapsedTime      = state.elapsedTime
        self.movingTime       = state.movingTime
        self.avgSpeedKmh      = state.avgSpeedKmh
        self.elevationGain    = state.elevationGain
        self.elevationLoss    = state.elevationLoss
        self.heartRate        = state.heartRate
        self.offRouteDistance = state.offRouteDistance
        self.isOffRoute       = state.isOffRoute
        self.nextPOIName      = state.nextPOI?.name
        self.nextPOIDistance  = state.nextPOIDistance
        self.nextPOICategory  = state.nextPOI?.category.rawValue
        self.isRerouting      = state.isRerouting
    }
}

// Isolated from @MainActor context — safe to call from nonisolated WCSession callbacks.
nonisolated extension WatchRideSummary: Codable {}
