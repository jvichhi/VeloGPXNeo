//
//  RideSessionStore.swift
//  VeloGPX
//

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

    // MARK: - Grade
    /// Current road gradient in percent, smoothed over the last 3 breadcrumb pairs
    /// spanning at least 20 m of horizontal distance. Zero when insufficient data.
    @Published var currentGrade: Double = 0

    private var manager: CLLocationManager!

    // internal (not private) so that file-separated extensions (e.g. RideSessionStore+Spurs)
    // can read these without duplicating state.
    var route: RouteModel?
    var pois: [POIModel] = []
    var nearestTrackIndex: Int = 0

    private var lastLocation: CLLocation?
    private var startTime: Date?
    private var pauseStartTime: Date?       // non-nil only while paused
    private var lastAlertedPOIID: UUID?
    private var lastRerouteTime: Date?
    private var historyStore: RideHistoryStore?
    private var errorClearTask: Task<Void, Never>?

    // MARK: - Watch throttle
    private var lastWatchUpdateTime: Date = .distantPast
    private let watchUpdateInterval: TimeInterval = 1.0

    // MARK: - Breadcrumb trail
    // Stored as CLLocation (not just coordinate) so we retain altitude at each point.
    private var breadcrumbLocations: [CLLocation] = []

    // MARK: - Altitude smoothing (Bug 3 fix)
    // Rolling average over last 3 altitude readings suppresses barometric/GPS jitter.
    private var altitudeBuffer: [Double] = []
    private let altitudeBufferSize = 3
    private var smoothedAltitude: Double? {
        guard !altitudeBuffer.isEmpty else { return nil }
        return altitudeBuffer.reduce(0, +) / Double(altitudeBuffer.count)
    }

    override init() {
        super.init()
        manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = true
        #if !targetEnvironment(simulator)
        manager.allowsBackgroundLocationUpdates = false
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
        self.pauseStartTime = nil
        self.lastLocation = nil
        self.lastAlertedPOIID = nil
        self.nearestTrackIndex = 0
        self.routeProgress = nil
        self.progressPercent = 0
        self.reroutePolyline = []
        self.breadcrumbLocations = []
        self.altitudeBuffer = []
        self.currentGrade = 0
        self.lastWatchUpdateTime = .distantPast
        self.lastError = nil
        #if !targetEnvironment(simulator)
        manager.allowsBackgroundLocationUpdates = true
        #endif
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    // MARK: - Pause / Resume

    func pause() {
        guard rideState.isActive, !rideState.isPaused else { return }
        pauseStartTime = Date()
        rideState.isPaused = true
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        #if !targetEnvironment(simulator)
        manager.allowsBackgroundLocationUpdates = false
        #endif
        manager.pausesLocationUpdatesAutomatically = true
        rideState.speed = 0
        currentGrade = 0
        sendWatchUpdate()
    }

    func resume() {
        guard rideState.isActive, rideState.isPaused else { return }
        if let ps = pauseStartTime {
            rideState.pausedDuration += Date().timeIntervalSince(ps)
        }
        pauseStartTime = nil
        rideState.isPaused = false
        lastLocation = nil   // discard stale last location so distance delta doesn't spike
        #if !targetEnvironment(simulator)
        manager.allowsBackgroundLocationUpdates = true
        #endif
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        sendWatchUpdate()
    }

    func updatePOIs(_ newPOIs: [POIModel]) {
        pois = newPOIs
        let currentIDs = Set(pois.map { $0.id })
        if let alerted = lastAlertedPOIID, !currentIDs.contains(alerted) {
            lastAlertedPOIID = nil
        }
        sendWatchUpdate()
    }

    func clearError() {
        errorClearTask?.cancel()
        lastError = nil
    }

    @discardableResult
    func stopAndBuildSummary() -> RideSummary? {
        if rideState.isPaused { resume() }
        endLocationUpdates()
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
            movingTime: rideState.movingTime,
            actualTrack: breadcrumbLocations.map { $0.coordinate },
            plannedTrack: route.trackPoints.map { $0.coordinate.clCoordinate },
            pois: pois
        )
        historyStore?.save(summary)
        return summary
    }

    func stop() {
        endLocationUpdates()
    }

    func setHistoryStore(_ store: RideHistoryStore) {
        historyStore = store
    }

    private func endLocationUpdates() {
        UIApplication.shared.isIdleTimerDisabled = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        #if !targetEnvironment(simulator)
        manager.allowsBackgroundLocationUpdates = false
        #endif
        manager.pausesLocationUpdatesAutomatically = true
        rideState.isActive = false
        rideState.isPaused = false
        currentGrade = 0
        reroutePolyline = []
        sendWatchUpdate()
    }

    // MARK: - Location

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        guard !rideState.isPaused else { return }

        currentLocation = location
        rideState.currentCoordinate = location.coordinate.asCoordinate
        let newSpeed = max(location.speed, 0)
        rideState.speed = newSpeed
        if newSpeed > rideState.maxSpeed { rideState.maxSpeed = newSpeed }

        if let lastLocation {
            let delta = location.distance(from: lastLocation)
            if delta < 200 {
                rideState.totalDistance += delta
                breadcrumbLocations.append(location)
            }

            // Altitude smoothing: rolling average over last 3 readings,
            // 1.5 m threshold to suppress barometric/GPS jitter.
            altitudeBuffer.append(location.altitude)
            if altitudeBuffer.count > altitudeBufferSize {
                altitudeBuffer.removeFirst()
            }
            if let currentSmoothed = smoothedAltitude {
                let prevBuf = Array(altitudeBuffer.dropLast())
                let prevSmoothed: Double = prevBuf.isEmpty
                    ? lastLocation.altitude
                    : prevBuf.reduce(0, +) / Double(prevBuf.count)
                let elevationDelta = currentSmoothed - prevSmoothed
                if abs(elevationDelta) > 1.5 {
                    if elevationDelta > 0 {
                        rideState.elevationGain += elevationDelta
                    } else {
                        rideState.elevationLoss += abs(elevationDelta)
                    }
                }
            }
        } else {
            breadcrumbLocations.append(location)
            altitudeBuffer.append(location.altitude)
        }
        self.lastLocation = location

        if let startTime {
            rideState.elapsedTime = Date().timeIntervalSince(startTime)
        }

        updateGrade()

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

    // MARK: - Grade computation
    //
    // Walk back through breadcrumbLocations until we have accumulated at least
    // gradeWindowDistance metres of horizontal distance, then compute:
    //   grade% = (Δaltitude / Δdistance) × 100
    //
    // Smoothed over up to 3 breadcrumb pairs to damp GPS altitude noise.
    // Returns 0 when there is insufficient track data (< 20 m accumulated).

    private let gradeWindowDistance: Double = 50   // metres of look-back
    private let gradeMinDistance:    Double = 20   // minimum before we trust the result

    private func updateGrade() {
        guard breadcrumbLocations.count >= 2 else { currentGrade = 0; return }

        var accumulated: Double = 0
        var altitudeDelta: Double = 0
        var pairs = 0

        // Walk backwards from the most recent crumb.
        let crumbs = breadcrumbLocations
        var i = crumbs.count - 1
        while i > 0 && accumulated < gradeWindowDistance {
            let a = crumbs[i]
            let b = crumbs[i - 1]
            let horizDist = a.distance(from: b)   // CLLocation.distance ignores altitude
            let altDiff   = a.altitude - b.altitude
            accumulated   += horizDist
            altitudeDelta += altDiff
            pairs         += 1
            i             -= 1
        }

        guard accumulated >= gradeMinDistance else { currentGrade = 0; return }

        // Raw grade, clamped to ±30% to discard spurious spikes.
        let raw = (altitudeDelta / accumulated) * 100
        currentGrade = min(max(raw, -30), 30)
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

    // MARK: - Reroute

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

    func showError(_ message: String) {
        errorClearTask?.cancel()
        lastError = message
        errorClearTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            lastError = nil
        }
    }

    func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
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

    func minimumDistance(from coordinate: CLLocationCoordinate2D, to route: RouteModel) -> Double {
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
