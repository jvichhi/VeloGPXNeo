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

// MARK: - NavStep protocol
//
// Shared by RerouteStep (off-route, orange) and PlannedNavStep (on-route, blue)
// so RideView.floatingNavBanner() can accept either as `[any NavStep]`.

protocol NavStep {
    var instructions: String { get }
    var distanceMeters: Double { get }
}

// RerouteStep already has matching stored properties — retroactive conformance only.
extension RerouteStep: NavStep {}

// MARK: - PlannedNavStep

struct PlannedNavStep: Identifiable {
    let id = UUID()
    /// Human-readable turn instruction from MKRouteStep (e.g. "Turn left onto Rue Saint-Jacques").
    let instructions: String
    /// Distance in metres until the next maneuver.
    let distanceMeters: Double
    /// The coordinate the rider must reach before we advance to the next step.
    let maneuverCoordinate: CLLocationCoordinate2D
}

extension PlannedNavStep: NavStep {}

// MARK: - Extension

extension RideSessionStore {

    // MARK: - Step advancement

    /// Called from locationManager(_:didUpdateLocations:) on every GPS ping.
    ///
    /// Checks whether the rider is within 30 m of the *current* step's maneuver
    /// coordinate. If so, advances to the next step. If the current step was the
    /// last one (destination reached), clears planned nav so the banner dismisses.
    ///
    /// Previous bug: was checking plannedNavSteps[nextIndex] instead of
    /// plannedNavSteps[currentStepIndex], causing step 0 to never be shown
    /// and advancement to start from step 1.
    func advanceStepIfNeeded(location: CLLocation) {
        guard !plannedNavSteps.isEmpty,
              plannedNavSteps.indices.contains(currentStepIndex) else { return }

        let maneuver = plannedNavSteps[currentStepIndex].maneuverCoordinate
        let dist = location.distance(from: CLLocation(
            latitude:  maneuver.latitude,
            longitude: maneuver.longitude
        ))

        guard dist <= 30 else { return }

        let nextIndex = currentStepIndex + 1
        if nextIndex >= plannedNavSteps.count {
            // Destination reached — dismiss the banner.
            clearPlannedNav()
        } else {
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
                            instructions: step.instructions,
                            distanceMeters: step.distance,
                            maneuverCoordinate: step.polyline.coordinate
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

    /// Resets planned nav state. Called from start() (fresh ride) and
    /// endLocationUpdates() (ride ended), and automatically from
    /// advanceStepIfNeeded() when the destination is reached.
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

    /// The step after the current one, for the "Then: …" preview line in the banner.
    var nextPlannedStep: PlannedNavStep? {
        let next = currentStepIndex + 1
        guard plannedNavSteps.indices.contains(next) else { return nil }
        return plannedNavSteps[next]
    }
}
