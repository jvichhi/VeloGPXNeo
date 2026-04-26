import Foundation
import CoreLocation
import MapKit
import UIKit
import UserNotifications
import WatchConnectivity
import Combine

struct RouteProgress {
    let ridden: [CLLocationCoordinate2D]
    let remaining: [CLLocationCoordinate2D]
}

@MainActor
final class RideSessionStore: NSObject, ObservableObject, CLLocationManagerDelegate, WCSessionDelegate {
    @Published var rideState = RideState()
    @Published var currentLocation: CLLocation?
    @Published var routeProgress: RouteProgress?
    @Published var progressPercent: Double = 0
    @Published var reroutePolyline: [CLLocationCoordinate2D] = []
    /// Surfaced routing/rerouting error message. Shown as a dismissible HUD banner in RideView.
    /// Cleared automatically after 6 seconds or when the user taps the banner.
    @Published var lastError: String? = nil

    private var manager: CLLocationManager!
    private var route: RouteModel?
    private var pois: [POIModel] = []
    private var lastLocation: CLLocation?
    private var startTime: Date?
    private var lastAlertedPOIID: UUID?
    private var nearestTrackIndex: Int = 0
    private var lastRerouteTime: Date?
    private var historyStore: RideHistoryStore?
    private var errorClearTask: Task<Void, Never>?

    // MARK: - Watch throttle
    private var lastWatchUpdateTime: Date = .distantPast
    private let watchUpdateInterval: TimeInterval = 1.0

    // MARK: - Breadcrumb trail
    private var breadcrumbs: [CLLocationCoordinate2D] = []

    override init() {
        super.init()
        manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        #if !targetEnvironment(simulator)
        manager.allowsBackgroundLocationUpdates = true
        #endif
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func prepare() {
        manager.requestWhenInUseAuthorization()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func start(route: RouteModel, pois: [POIModel] = []) {
        UIApplication.shared.isIdleTimerDisabled = true
        self.route = route
        self.pois = pois
        self.rideState = RideState(isActive: true)
        self.startTime = Date()
        self.lastLocation = nil
        self.lastAlertedPOIID = nil
        self.nearestTrackIndex = 0
        self.routeProgress = nil
        self.progressPercent = 0
        self.reroutePolyline = []
        self.breadcrumbs = []
        self.lastWatchUpdateTime = .distantPast
        self.lastError = nil
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func updatePOIs(_ newPOIs: [POIModel]) {
        pois = newPOIs
        let currentIDs = Set(pois.map { $0.id })
        if let alerted = lastAlertedPOIID, !currentIDs.contains(alerted) {
            lastAlertedPOIID = nil
        }
        sendWatchUpdate()
    }

    /// Dismiss the error banner manually (called when user taps it).
    func clearError() {
        errorClearTask?.cancel()
        lastError = nil
    }

    @discardableResult
    func stopAndBuildSummary() -> RideSummary? {
        UIApplication.shared.isIdleTimerDisabled = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        rideState.isActive = false
        reroutePolyline = []
        sendWatchUpdate()

        guard let route, let startTime else { return nil }
        let summary = RideSummary(
            routeName: route.name,
            startDate: startTime,
            endDate: Date(),
            totalDistance: rideState.totalDistance,
            elevationGain: rideState.elevationGain,
            elevationLoss: rideState.elevationLoss,
            maxSpeed: rideState.maxSpeed,
            elapsedTime: rideState.elapsedTime,
            actualTrack: breadcrumbs,
            plannedTrack: route.trackPoints.map { $0.coordinate.clCoordinate },
            pois: pois
        )
        historyStore?.save(summary)
        return summary
    }

    func stop() {
        UIApplication.shared.isIdleTimerDisabled = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        rideState.isActive = false
        reroutePolyline = []
        sendWatchUpdate()
    }

    func setHistoryStore(_ store: RideHistoryStore) {
        historyStore = store
    }

    // MARK: - Location

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        rideState.currentCoordinate = location.coordinate.asCoordinate
        let newSpeed = max(location.speed, 0)
        rideState.speed = newSpeed
        if newSpeed > rideState.maxSpeed { rideState.maxSpeed = newSpeed }

        if let lastLocation {
            let delta = location.distance(from: lastLocation)
            if delta < 200 {
                rideState.totalDistance += delta
                breadcrumbs.append(location.coordinate)
            }
            let elevationDelta = location.altitude - lastLocation.altitude
            if elevationDelta > 0 {
                rideState.elevationGain += elevationDelta
            } else {
                rideState.elevationLoss += abs(elevationDelta)
            }
        } else {
            breadcrumbs.append(location.coordinate)
        }
        self.lastLocation = location

        if let startTime {
            rideState.elapsedTime = Date().timeIntervalSince(startTime)
        }

        if let route {
            rideState.offRouteDistance = minimumDistance(from: location.coordinate, to: route)
            rideState.isOffRoute = rideState.offRouteDistance > 50
            updateRouteProgress(from: location.coordinate, route: route)
            handleOffRoute(from: location.coordinate, route: route)
        }

        updateNextPOI(from: location.coordinate)
        sendWatchUpdate()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        rideState.currentHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }

    // MARK: - Off-route handling

    private func handleOffRoute(from coordinate: CLLocationCoordinate2D, route: RouteModel) {
        guard rideState.isOffRoute else {
            rideState.bearingToRoute = nil
            rideState.rerouteSteps = []
            reroutePolyline = []
            return
        }

        let nearestPoint = route.trackPoints[nearestTrackIndex].coordinate.clCoordinate

        if rideState.offRouteDistance <= 200 {
            rideState.bearingToRoute = bearing(from: coordinate, to: nearestPoint)
            rideState.rerouteSteps = []
            reroutePolyline = []
        } else {
            rideState.bearingToRoute = bearing(from: coordinate, to: nearestPoint)
            let now = Date()
            if let last = lastRerouteTime, now.timeIntervalSince(last) < 30 { return }
            lastRerouteTime = now
            requestReroute(from: coordinate, to: nearestPoint)
        }
    }

    // MARK: - Reroute via CyclingRouteService (.cycling on iOS 26+)

    private func requestReroute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) {
        rideState.isRerouting = true
        Task {
            do {
                let result = try await CyclingRouteService.shared.calculateRoute(from: from, to: to)
                reroutePolyline = result.route.polyline.coordinates
                rideState.rerouteSteps = result.route.steps.map {
                    RerouteStep(instructions: $0.instructions, distanceMeters: $0.distance)
                }.filter { !$0.instructions.isEmpty }
            } catch {
                showError("Couldn't find a route back. Keep riding — retrying shortly.")
            }
            rideState.isRerouting = false
        }
    }

    // MARK: - Error helpers

    private func showError(_ message: String) {
        errorClearTask?.cancel()
        lastError = message
        // Auto-dismiss after 6 seconds
        errorClearTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            lastError = nil
        }
    }

    private func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let b = atan2(y, x) * 180 / .pi
        return (b + 360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: - Route progress

    private func updateRouteProgress(from coordinate: CLLocationCoordinate2D, route: RouteModel) {
        let points = route.trackPoints
        guard points.count > 1 else { return }
        var bestIndex = nearestTrackIndex
        var bestDist = coordinate.distance(to: points[bestIndex].coordinate.clCoordinate)
        let searchEnd = min(nearestTrackIndex + 50, points.count - 1)
        for i in nearestTrackIndex...searchEnd {
            let d = coordinate.distance(to: points[i].coordinate.clCoordinate)
            if d < bestDist { bestDist = d; bestIndex = i }
        }
        nearestTrackIndex = bestIndex
        let ridden = Array(points[0...bestIndex].map { $0.coordinate.clCoordinate })
        let remaining = Array(points[bestIndex...].map { $0.coordinate.clCoordinate })
        routeProgress = RouteProgress(ridden: ridden, remaining: remaining)
        progressPercent = Double(bestIndex) / Double(points.count - 1)
    }

    private func minimumDistance(from coordinate: CLLocationCoordinate2D, to route: RouteModel) -> Double {
        let points = route.trackPoints
        guard points.count > 1 else { return .greatestFiniteMagnitude }
        var minDistance = Double.greatestFiniteMagnitude
        for pair in zip(points, points.dropFirst()) {
            let d = coordinate.perpendicularDistance(
                toSegment: pair.0.coordinate.clCoordinate,
                end: pair.1.coordinate.clCoordinate
            )
            minDistance = min(minDistance, d)
        }
        return minDistance
    }

    // MARK: - POI tracking

    private func updateNextPOI(from coordinate: CLLocationCoordinate2D) {
        guard !pois.isEmpty, let route else {
            rideState.nextPOI = nil
            rideState.nextPOIDistance = nil
            return
        }

        let trackPoints = route.trackPoints
        guard trackPoints.count > 1 else {
            rideState.nextPOI = nil
            rideState.nextPOIDistance = nil
            return
        }

        let searchStart = nearestTrackIndex
        let searchRange = trackPoints.indices.filter { $0 >= searchStart }

        struct POIWithIndex {
            let poi: POIModel
            let trackIndex: Int
            let straightLineDistance: Double
        }

        let candidatesAhead: [POIWithIndex] = pois.compactMap { poi in
            let poiCoord = poi.coordinate.clCoordinate
            var bestIdx = searchStart
            var bestDist = poiCoord.distance(to: trackPoints[searchStart].coordinate.clCoordinate)
            for i in searchRange {
                let d = poiCoord.distance(to: trackPoints[i].coordinate.clCoordinate)
                if d < bestDist { bestDist = d; bestIdx = i }
            }
            guard bestIdx >= searchStart else { return nil }
            let straightLine = coordinate.distance(to: poiCoord)
            guard straightLine < 5000 else { return nil }
            return POIWithIndex(poi: poi, trackIndex: bestIdx, straightLineDistance: straightLine)
        }

        let sorted = candidatesAhead.sorted { $0.trackIndex < $1.trackIndex }

        if let first = sorted.first {
            rideState.nextPOI = first.poi
            rideState.nextPOIDistance = first.straightLineDistance
            if first.straightLineDistance < 200 {
                triggerApproachAlert(for: first.poi)
            }
        } else {
            rideState.nextPOI = nil
            rideState.nextPOIDistance = nil
        }
    }

    private func triggerApproachAlert(for poi: POIModel) {
        guard poi.id != lastAlertedPOIID else { return }
        lastAlertedPOIID = poi.id
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        let content = UNMutableNotificationContent()
        content.title = "Upcoming: \(poi.name)"
        content.body = "\(poi.category.displayName) in ~200m"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: poi.id.uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Watch (throttled to 1 Hz)

    private func sendWatchUpdate() {
        let now = Date()
        guard now.timeIntervalSince(lastWatchUpdateTime) >= watchUpdateInterval else { return }
        lastWatchUpdateTime = now
        guard WCSession.default.isReachable else { return }
        let summary = WatchRideSummary(state: rideState)
        guard let data = try? JSONEncoder().encode(summary) else { return }
        WCSession.default.sendMessage(["rideState": data], replyHandler: nil, errorHandler: nil)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {}
}

// MARK: - MKPolyline helper
extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
