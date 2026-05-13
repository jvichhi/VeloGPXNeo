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

// MARK: - Background notification identifier

private let kRideInProgressNotificationID = "com.velogpx.rideInProgress"

@MainActor
final class RideSessionStore: NSObject, ObservableObject, CLLocationManagerDelegate, WCSessionDelegate {
    @Published var rideState = RideState()
    @Published var currentLocation: CLLocation?
    @Published var routeProgress: RouteProgress?
    @Published var progressPercent: Double = 0
    @Published var reroutePolyline: [CLLocationCoordinate2D] = []
    /// Estimated arrival time — nil until the rider has enough speed history (10+ s).
    @Published var eta: Date? = nil
    /// Surfaced routing/rerouting error message. Shown as a dismissible HUD banner in RideView.
    /// Cleared automatically after 6 seconds or when the user taps the banner.
    @Published var lastError: String? = nil

    // MARK: - Grade
    /// Current road gradient in percent, smoothed over the last 3 breadcrumb pairs
    /// spanning at least 20 m of horizontal distance. Zero when insufficient data.
    @Published var currentGrade: Double = 0

    // MARK: - Cue sheet tracking
    @Published var nextCue: CueSheetEntry?
    @Published var thenCue: CueSheetEntry?

    private var manager: CLLocationManager!

    // internal so file-separated extensions (RideSessionStore+Spurs) can read these.
    var route: RouteModel?
    var pois: [POIModel] = []
    var nearestTrackIndex: Int = 0
    private var cueEntries: [CueSheetEntry] = []
    private var nextCueIndex: Int = 0

    private var lastLocation: CLLocation?
    private var startTime: Date?
    private var pauseStartTime: Date?
    private var lastAlertedPOIID: UUID?
    private var lastRerouteTime: Date?
    private var historyStore: RideHistoryStore?
    private var errorClearTask: Task<Void, Never>?

    // MARK: - Elapsed-time timer
    private var elapsedTimer: Timer?

    // MARK: - Watch throttle
    private var lastWatchUpdateTime: Date = .distantPast
    private let watchUpdateInterval: TimeInterval = 1.0

    // MARK: - Breadcrumb trail
    private var breadcrumbLocations: [CLLocation] = []

    // MARK: - Altitude smoothing
    private var altitudeBuffer: [Double] = []
    private let altitudeBufferSize = 3
    private var smoothedAltitude: Double? {
        guard !altitudeBuffer.isEmpty else { return nil }
        return altitudeBuffer.reduce(0, +) / Double(altitudeBuffer.count)
    }

    // MARK: - Speed smoothing
    private var smoothedSpeed: Double = 0
    private let speedSmoothingFactor: Double = 0.35

    // MARK: - Grade smoothing + climb detection
    private var smoothedGrade: Double = 0
    private var climbSegments: [ClimbSegment] = []
    private let gradeEmaFactor: Double = 0.35

    // MARK: - ETA speed buffer
    private var speedBuffer: [(date: Date, speed: Double)] = []
    private let speedBufferWindow: TimeInterval = 30

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

    func start(route: RouteModel, pois: [POIModel] = [], cues: [CueSheetEntry] = []) {
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
        self.speedBuffer = []
        self.smoothedSpeed = 0
        self.smoothedGrade = 0
        self.climbSegments = route.detectClimbs()
        self.cueEntries = cues
        self.nextCueIndex = 0
        self.nextCue = nil
        self.thenCue = nil
        self.currentGrade = 0
        self.eta = nil
        self.lastWatchUpdateTime = .distantPast
        self.lastError = nil
        #if !targetEnvironment(simulator)
        manager.allowsBackgroundLocationUpdates = true
        #endif
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        startElapsedTimer()
        postRideInProgressNotification(routeName: route.name)
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let startTime = self.startTime,
                      self.rideState.isActive,
                      !self.rideState.isPaused else { return }
                self.rideState.elapsedTime = Date().timeIntervalSince(startTime) - self.rideState.pausedDuration
            }
        }
        RunLoop.main.add(elapsedTimer!, forMode: .common)
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    // MARK: - Pause / Resume

    func pause() {
        guard rideState.isActive, !rideState.isPaused else { return }
        pauseStartTime = Date()
        rideState.isPaused = true
        stopElapsedTimer()
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        #if !targetEnvironment(simulator)
        manager.allowsBackgroundLocationUpdates = false
        #endif
        manager.pausesLocationUpdatesAutomatically = true
        rideState.speed = 0
        currentGrade = 0
        eta = nil
        sendWatchUpdate()
    }

    func resume() {
        guard rideState.isActive, rideState.isPaused else { return }
        if let ps = pauseStartTime {
            rideState.pausedDuration += Date().timeIntervalSince(ps)
        }
        pauseStartTime = nil
        rideState.isPaused = false
        lastLocation = nil
        speedBuffer = []
        smoothedSpeed = 0
        smoothedGrade = 0
        #if !targetEnvironment(simulator)
        manager.allowsBackgroundLocationUpdates = true
        #endif
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        startElapsedTimer()
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
        stopElapsedTimer()
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
        eta = nil
        reroutePolyline = []
        cancelRideInProgressNotification()
        sendWatchUpdate()
    }

    // MARK: - Background ride notification
    //
    // Posts a persistent banner so the rider knows VeloGPX is still recording
    // when they leave the app mid-ride (e.g. check Messages, lock screen).
    // Uses a fixed identifier so repeated calls replace the existing notification
    // rather than stacking up, and so cancelRideInProgressNotification() can
    // reliably remove it by ID.
    //
    // No sound — this is a status indicator, not an alert.
    // No trigger — delivered immediately and stays in Notification Centre until
    // cancelled or the app removes it.

    private func postRideInProgressNotification(routeName: String) {
        let content = UNMutableNotificationContent()
        content.title = "\u{1F6B4} Ride in Progress"
        content.body = "\(routeName) \u{00B7} VeloGPX is recording your ride."
        content.sound = nil
        // categoryIdentifier lets the user dismiss from Notification Centre
        // without accidentally ending the ride (no destructive action attached).
        content.categoryIdentifier = "RIDE_IN_PROGRESS"
        let request = UNNotificationRequest(
            identifier: kRideInProgressNotificationID,
            content: content,
            trigger: nil          // deliver immediately, no repeat
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func cancelRideInProgressNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [kRideInProgressNotificationID])
        center.removeDeliveredNotifications(withIdentifiers: [kRideInProgressNotificationID])
    }

    // MARK: - Location

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        guard !rideState.isPaused else { return }

        currentLocation = location
        rideState.currentCoordinate = location.coordinate.asCoordinate

        let rawGPSSpeed = location.speed >= 0 ? location.speed : 0
        var computedSpeed: Double? = nil
        if let lastLocation {
            let deltaDist = location.distance(from: lastLocation)
            let deltaTime = location.timestamp.timeIntervalSince(lastLocation.timestamp)
            if deltaTime > 0.1, deltaDist < 200 {
                computedSpeed = deltaDist / deltaTime
            }
        }

        let bestRaw = computedSpeed.map { max(rawGPSSpeed, $0) } ?? rawGPSSpeed
        smoothedSpeed = speedSmoothingFactor * bestRaw + (1 - speedSmoothingFactor) * smoothedSpeed
        let newSpeed = smoothedSpeed
        rideState.speed = newSpeed
        if newSpeed > rideState.maxSpeed { rideState.maxSpeed = newSpeed }

        if let lastLocation {
            let delta = location.distance(from: lastLocation)
            if delta < 200 {
                rideState.totalDistance += delta
                breadcrumbLocations.append(location)
            }

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
            rideState.elapsedTime = Date().timeIntervalSince(startTime) - rideState.pausedDuration
        }

        updateGrade()

        if let route {
            rideState.offRouteDistance = minimumDistance(from: location.coordinate, to: route)
            rideState.isOffRoute = rideState.offRouteDistance > 50
            updateRouteProgress(from: location.coordinate, route: route)
            updateNextCue()
            handleOffRoute(from: location.coordinate, route: route)
        }

        updateNextPOI(from: location.coordinate)
        updateSpeedBuffer(speed: newSpeed)
        updateETA()
        sendWatchUpdate()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        rideState.currentHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }

    // MARK: - Grade computation

    private let gradeWindowDistance: Double = 50
    private let gradeMinDistance:    Double = 20

    private func updateGrade() {
        guard breadcrumbLocations.count >= 2 else { currentGrade = 0; return }

        var accumulated: Double = 0
        var altitudeDelta: Double = 0
        var pairs = 0

        let crumbs = breadcrumbLocations
        var i = crumbs.count - 1
        while i > 0 && accumulated < gradeWindowDistance {
            let a = crumbs[i]
            let b = crumbs[i - 1]
            let horizDist = a.distance(from: b)
            let altDiff   = a.altitude - b.altitude
            accumulated   += horizDist
            altitudeDelta += altDiff
            pairs         += 1
            i             -= 1
        }

        guard accumulated >= gradeMinDistance else { currentGrade = 0; return }

        let raw = (altitudeDelta / accumulated) * 100
        smoothedGrade = gradeEmaFactor * raw + (1 - gradeEmaFactor) * smoothedGrade
        currentGrade = min(max(smoothedGrade, -30), 30)
    }

    // MARK: - Climb detection

    private func activeClimb(for trackIndex: Int) -> ClimbSegment? {
        climbSegments.first { $0.startIndex <= trackIndex && trackIndex < $0.endIndex }
    }

    // MARK: - ETA

    private func updateSpeedBuffer(speed: Double) {
        let now = Date()
        speedBuffer.append((date: now, speed: speed))
        speedBuffer = speedBuffer.filter {
            now.timeIntervalSince($0.date) <= speedBufferWindow
        }
    }

    private func updateETA() {
        guard let route else { eta = nil; return }
        guard let oldest = speedBuffer.first,
              Date().timeIntervalSince(oldest.date) >= 10 else {
            eta = nil
            return
        }
        let avgSpeed = speedBuffer.map { $0.speed }.reduce(0, +) / Double(speedBuffer.count)
        guard avgSpeed > (1.0 / 3.6) else { eta = nil; return }
        let remainingDistance = remainingRouteDistance(route: route)
        guard remainingDistance > 0 else { eta = nil; return }
        let secondsRemaining = remainingDistance / avgSpeed
        eta = Date().addingTimeInterval(secondsRemaining)
    }

    private func remainingRouteDistance(route: RouteModel) -> CLLocationDistance {
        guard let progress = routeProgress, progress.remaining.count > 1 else {
            return route.totalDistance
        }
        return zip(progress.remaining, progress.remaining.dropFirst())
            .reduce(0) { $0 + $1.0.distance(to: $1.1) }
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

        let searchStart = nearestTrackIndex
        let searchEnd = nearestTrackIndex == 0
            ? points.count - 1
            : min(nearestTrackIndex + 50, points.count - 1)

        var bestIndex = searchStart
        var bestDist = coordinate.distance(to: points[searchStart].coordinate.clCoordinate)
        for i in searchStart...searchEnd {
            let d = coordinate.distance(to: points[i].coordinate.clCoordinate)
            if d < bestDist { bestDist = d; bestIndex = i }
        }
        nearestTrackIndex = bestIndex
        let ridden = Array(points[0...bestIndex].map { $0.coordinate.clCoordinate })
        let remaining = Array(points[bestIndex...].map { $0.coordinate.clCoordinate })
        routeProgress = RouteProgress(ridden: ridden, remaining: remaining)

        let routeTotal = route.totalDistance
        progressPercent = routeTotal > 0
            ? min(rideState.totalDistance / routeTotal, 1.0)
            : 0

        if let climb = activeClimb(for: nearestTrackIndex) {
            rideState.activeClimb = climb
            rideState.activeClimbRemaining = trackArcDistance(from: nearestTrackIndex, to: climb.endIndex, points: points)
        } else {
            rideState.activeClimb = nil
            rideState.activeClimbRemaining = nil
        }
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

    // MARK: - Track arc distance helper
    func trackArcDistance(from startIdx: Int, to endIdx: Int, points: [TrackPoint]) -> Double {
        RouteModel.trackArcDistance(from: startIdx, to: endIdx, points: points)
    }

    // MARK: - Cue tracking

    private func updateNextCue() {
        guard !cueEntries.isEmpty, let route else {
            nextCue = nil; thenCue = nil; return
        }
        let progressDist = trackArcDistance(from: 0, to: nearestTrackIndex, points: route.trackPoints)
        let lookahead = progressDist + 50

        if let idx = cueEntries.firstIndex(where: { $0.cumulativeDistance > lookahead }) {
            nextCueIndex = idx
            nextCue = cueEntries[idx]
            thenCue = idx + 1 < cueEntries.count ? cueEntries[idx + 1] : nil
        } else {
            nextCue = nil
            thenCue = nil
        }
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
            // Issue 1b fix: if the rider has already passed the current nextPOI's
            // snap index, advance immediately without waiting for the next GPS tick.
            // This closes the 1-2 tick gap where nextPOI was stale after passing a POI.
            if let current = rideState.nextPOI,
               let currentCandidate = sorted.first(where: { $0.poi.id == current.id }),
               currentCandidate.trackIndex < searchStart {
                // current nextPOI is now behind us — pick the new first candidate
                rideState.nextPOI = first.poi
                rideState.nextPOIDistance = first.straightLineDistance
            } else {
                rideState.nextPOI = first.poi
                rideState.nextPOIDistance = first.straightLineDistance
            }
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
