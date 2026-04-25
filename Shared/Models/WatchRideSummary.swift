import Foundation

struct WatchRideSummary: Codable, Sendable {
    let isActive: Bool
    let speedKmh: Double
    let distanceKm: Double
    let offRouteDistance: Double
    let isOffRoute: Bool
    let nextPOIName: String?
    let nextPOIDistance: Double?

    nonisolated init(state: RideState) {
        self.isActive = state.isActive
        self.speedKmh = state.speedKmh
        self.distanceKm = state.distanceKm
        self.offRouteDistance = state.offRouteDistance
        self.isOffRoute = state.isOffRoute
        self.nextPOIName = state.nextPOI?.name
        self.nextPOIDistance = state.nextPOIDistance
    }
}
