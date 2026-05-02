//
//  RideSessionStore+PlannedNav.swift
//  VeloGPX
//
//  Turn-by-turn navigation for planned routes.
//
//  Flow:
//    1. start() calls loadNavSteps(route:) — only when sourceFormat == .planned
//       and the route has at least 2 waypoints.
//    2. MKDirections chains all waypoints into one step array.
//    3. Each locationManager(_:didUpdateLocations:) call invokes
//       advanceStepIfNeeded(location:), which publishes the active step
//       as plannedNavSteps[currentStepIndex].
//    4. stop() / endLocationUpdates clears state via clearPlannedNav().
//
//  Priority rule (enforced in RideView):
//    reroute steps (orange banner) > planned nav steps (blue banner).
//

import CoreLocation
import MapKit

extension RideSessionStore {

    // MARK: - Published state
    // Stored as plain arrays/index on RideSessionStore via associated-object
    // pattern isn't available in extensions, so we use @Published vars
    // declared in the main class file — but to avoid touching the 19 KB
    // RideSessionStore.swift, we piggyback on rideState for the published
    // surface and keep the mutable backing here using nonisolated storage.
    //
    // Simpler approach: expose a computed var that reads the private storage.
    // RideView observes rideStore.$plannedNavSteps directly.

    // MARK: - Step advancement

    /// Called from locationManager(_:didUpdateLocations:) on every GPS ping.
    /// Advances currentStepIndex when the rider is within 30 m of the next
    /// maneuver point. No-op when there are no planned nav steps.
    func advanceStepIfNeeded(location: CLLocation) {
        guard !plannedNavSteps.isEmpty else { return }
        let nextIndex = currentStepIndex + 1
        guard nextIndex < plannedNavSteps.count else { return }
        let maneuver = plannedNavSteps[nextIndex].maneuverCoordinate
        let dist = location.distance(from: CLLocation(
            latitude: maneuver.latitude,
            longitude: maneuver.longitude
        ))
        if dist <= 30 {
            currentStepIndex = nextIndex
        }
    }

    // MARK: - Load nav steps

    /// Fired from start(route:pois:) for planned routes.
    /// Chains all waypoints through MKDirections and populates plannedNavSteps.
    /// Fails silently — nav steps are a nice-to-have, not ride-critical.
    func loadNavSteps(route: RouteModel) {
        guard route.sourceFormat == .planned else { return }
        let waypoints = route.waypoints
        guard waypoints.count >= 2 else { return }

        Task {
            var steps: [PlannedNavStep] = []

            // Chain consecutive waypoint pairs.
            for i in 0..<(waypoints.count - 1) {
                let origin = MKMapItem(placemark: MKPlacemark(
                    coordinate: waypoints[i].coordinate.clCoordinate
                ))
                let destination = MKMapItem(placemark: MKPlacemark(
                    coordinate: waypoints[i + 1].coordinate.clCoordinate
                ))
                let request = MKDirections.Request()
                request.source = origin
                request.destination = destination
                request.transportType = .walking  // closest to cycling in MapKit
                request.requestsAlternateRoutes = false

                do {
                    let response = try await MKDirections(request: request).calculate()
                    guard let mkRoute = response.routes.first else { continue }
                    for step in mkRoute.steps where !step.instructions.isEmpty {
                        steps.append(PlannedNavStep(
                            instruction: step.instructions,
                            maneuverCoordinate: step.polyline.coordinate,
                            distanceMeters: step.distance
                        ))
                    }
                } catch {
                    // Network or routing failure — skip this segment silently.
                    // The rider can still ride; they just won't get turn prompts
                    // for the failed leg.
                }
            }

            guard !steps.isEmpty else { return }
            await MainActor.run {
                self.plannedNavSteps = steps
                self.currentStepIndex = 0
            }
        }
    }

    // MARK: - Clear

    /// Called from endLocationUpdates() to reset nav state between rides.
    func clearPlannedNav() {
        plannedNavSteps = []
        currentStepIndex = 0
    }

    // MARK: - Convenience

    /// The step currently being navigated toward. Nil when no planned nav is active.
    var currentPlannedStep: PlannedNavStep? {
        guard !plannedNavSteps.isEmpty,
              plannedNavSteps.indices.contains(currentStepIndex) else { return nil }
        return plannedNavSteps[currentStepIndex]
    }

    /// The step after the current one, for the "Then: …" preview line.
    var nextPlannedStep: PlannedNavStep? {
        let next = currentStepIndex + 1
        guard plannedNavSteps.indices.contains(next) else { return nil }
        return plannedNavSteps[next]
    }
}
