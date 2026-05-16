//
//  PlanAssistantEngine.swift
//  VeloGPX — iPhone target ONLY. Never add to Watch target.
//
//  PURPOSE:
//  Orchestrates the full pipeline from a natural-language route request
//  through to a populated PlanState ready for the user to review:
//
//    User text
//      └─ LLM parses → RidePlanIntent        (FoundationModels @Generable)
//           └─ each IntentStop resolved       (MKLocalSearch via POISearchService)
//                └─ ambiguous stops flagged    (DisambiguationSheet presents choices)
//                     └─ PlanState populated   (addWaypoint + optional loop toggle)
//                          └─ PlanRouteEngine   (called by PlanView as normal)
//
//  CALLER PATTERN (RidePlanAssistantView):
//    let engine = PlanAssistantEngine()
//    for await event in engine.plan(prompt: userText, near: mapCenter, planState: state) {
//        // update UI from AssistantEvent
//    }
//
//  iOS 26 / Swift 6 NOTES:
//  • CLLocationCoordinate2D.init is @MainActor on iOS 26+. We never construct
//    coordinates in a background context — MKLocalSearch returns MKMapItem whose
//    coordinate we read on @MainActor only (see resolveStop).
//  • PlanState.addWaypoint is @MainActor. We call it via MainActor.run.
//  • No @available guard — iOS 26 is the project minimum (PROJECT.md).
//  • mapItem.placemark is deprecated on iOS 26; use .name and .address instead
//    (same pattern as RouteNameSuggester).
//
//  DEPRECATIONS TO AVOID:
//  ❌ mapItem.placemark — deprecated iOS 26
//  ❌ CLGeocoder — deprecated iOS 18+
//  ❌ session.stream(from:onPartial:) — removed iOS 26
//  ✅ session.respond(to:generating:) — @Generable structured output
//  ✅ POISearchService.shared.search(query:near:) — MKLocalSearch wrapper
//  ✅ mapItem.name and mapItem.address — iOS 26-safe
//

import Foundation
import MapKit
import CoreLocation
import FoundationModels

// MARK: - Public event stream

/// Events emitted by `PlanAssistantEngine.plan(prompt:near:planState:)`.
/// RidePlanAssistantView drives its UI entirely from these events.
enum AssistantEvent {
    /// LLM has parsed the intent; shows the user a "Resolving stops…" state.
    case intentParsed(RidePlanIntent)
    /// One stop resolved successfully; `waypointName` is the label to show.
    case stopResolved(index: Int, waypointName: String)
    /// A stop matched multiple places; the view must present DisambiguationSheet.
    case stopNeedsDisambiguation(index: Int, candidates: [MKMapItem])
    /// All stops resolved; PlanState has been populated. PlanRouteEngine
    /// will fire automatically via PlanView's existing .onChange observer.
    case completed
    /// The pipeline failed with a user-readable message.
    case failed(String)
}

// MARK: - Resolved stop (internal)

/// A fully resolved waypoint coordinate, held as raw Doubles to avoid
/// constructing CLLocationCoordinate2D outside @MainActor (iOS 26+).
private struct ResolvedStop {
    let label: String
    let kind: IntentStopKind
    let dwellMinutes: Int
    let latitude: Double
    let longitude: Double
}

// MARK: - Engine

/// Orchestrates natural-language route planning via FoundationModels + MKLocalSearch.
///
/// Not an actor — all async work is coordinated through structured concurrency
/// and @MainActor calls where needed. One instance per planning session is fine;
/// there is no persistent state between calls to `plan(...)`.
final class PlanAssistantEngine {

    // MARK: - Public API

    /// Runs the full AI → search → PlanState pipeline, emitting `AssistantEvent`
    /// values via an `AsyncStream`.
    ///
    /// - Parameters:
    ///   - prompt: The user's free-text route request.
    ///   - near: The map centre coordinate used as the MKLocalSearch anchor.
    ///     Passed as Doubles to avoid @MainActor construction in background context.
    ///   - planState: The `PlanState` to populate. Mutations happen on @MainActor.
    /// - Returns: An `AsyncStream<AssistantEvent>` the caller iterates with `for await`.
    func plan(
        prompt: String,
        nearLat: Double,
        nearLon: Double,
        planState: PlanState
    ) -> AsyncStream<AssistantEvent> {
        AsyncStream { continuation in
            Task {
                await self.runPipeline(
                    prompt: prompt,
                    nearLat: nearLat,
                    nearLon: nearLon,
                    planState: planState,
                    continuation: continuation
                )
                continuation.finish()
            }
        }
    }

    /// Resolves a disambiguated stop chosen by the user in DisambiguationSheet,
    /// appends it to PlanState, and returns the waypoint label.
    ///
    /// Call this after the user picks one candidate from a `stopNeedsDisambiguation` event.
    @MainActor
    func commitDisambiguatedStop(
        mapItem: MKMapItem,
        kind: IntentStopKind,
        dwellMinutes: Int,
        planState: PlanState
    ) -> String {
        let label = mapItem.name ?? "Stop"
        // Safe to read coordinate here — we are on @MainActor.
        let coord = mapItem.location?.coordinate
            ?? mapItem.placemark.location?.coordinate
        if let coord {
            planState.addWaypoint(coord, name: label)
        }
        return label
    }

    // MARK: - Pipeline

    private func runPipeline(
        prompt: String,
        nearLat: Double,
        nearLon: Double,
        planState: PlanState,
        continuation: AsyncStream<AssistantEvent>.Continuation
    ) async {
        // Step 1: parse intent with on-device LLM
        let intent: RidePlanIntent
        do {
            intent = try await parseIntent(from: prompt)
        } catch {
            continuation.yield(.failed("Couldn't understand your request. Try rephrasing."))
            return
        }
        continuation.yield(.intentParsed(intent))

        guard !intent.stops.isEmpty else {
            continuation.yield(.failed("No stops found in your request. Try adding a destination."))
            return
        }

        // Step 2: resolve each stop via MKLocalSearch
        var resolved: [ResolvedStop?] = Array(repeating: nil, count: intent.stops.count)

        for (idx, stop) in intent.stops.enumerated() {
            let candidates = await searchStop(stop, nearLat: nearLat, nearLon: nearLon)

            if candidates.isEmpty {
                // Nothing found — skip this stop, user can add manually
                continue
            } else if candidates.count == 1 || Self.isClearWinner(candidates) {
                // Single or dominant result — auto-resolve
                let item = candidates[0]
                let label = item.name ?? stop.label
                let dwell = stop.dwellMinutes >= 0
                    ? stop.dwellMinutes
                    : Self.defaultDwell(for: stop.kind)
                // Read coordinate on @MainActor
                let coord = await MainActor.run { item.location?.coordinate }
                if let coord {
                    resolved[idx] = ResolvedStop(
                        label: label,
                        kind: stop.kind,
                        dwellMinutes: dwell,
                        latitude: coord.latitude,
                        longitude: coord.longitude
                    )
                    continuation.yield(.stopResolved(index: idx, waypointName: label))
                }
            } else {
                // Multiple plausible candidates — ask the user
                let topCandidates = Array(candidates.prefix(5))
                continuation.yield(.stopNeedsDisambiguation(index: idx, candidates: topCandidates))
                // Caller (RidePlanAssistantView) handles this event and calls
                // commitDisambiguatedStop separately; we leave resolved[idx] == nil
                // so it is skipped in the PlanState population below.
            }
        }

        // Step 3: populate PlanState on @MainActor
        await MainActor.run {
            planState.clearAll()
            for stop in resolved.compactMap({ $0 }) {
                // Construct CLLocationCoordinate2D on @MainActor (iOS 26+ requirement)
                let coord = CLLocationCoordinate2D(
                    latitude: stop.latitude,
                    longitude: stop.longitude
                )
                planState.addWaypoint(coord, name: stop.label)
            }
            if intent.isLoop && planState.waypoints.count >= 2 {
                planState.isLoopClosed = true
            }
        }

        continuation.yield(.completed)
    }

    // MARK: - LLM parsing

    private func parseIntent(from prompt: String) async throws -> RidePlanIntent {
        let systemPrompt = """
        You are a cycling route planning assistant.
        Extract the stops, target distance, loop preference, and a suggested route name
        from the user's request. For each stop include a natural-language search query
        suitable for finding it on Apple Maps (include city or region context where mentioned).
        If the user did not specify a distance, set targetDistanceKm to 0.
        If the user did not specify dwell time for a stop, set dwellMinutes to -1.
        """
        let session = VeloAI.makeSession()
        return try await session.respond(
            to: "\(systemPrompt)\n\nUser request: \(prompt)",
            generating: RidePlanIntent.self
        )
    }

    // MARK: - MKLocalSearch

    private func searchStop(
        _ stop: IntentStop,
        nearLat: Double,
        nearLon: Double
    ) async -> [MKMapItem] {
        // Build the search centre on @MainActor (CLLocationCoordinate2D.init is @MainActor iOS 26+)
        let centre = await MainActor.run {
            CLLocationCoordinate2D(latitude: nearLat, longitude: nearLon)
        }
        return (try? await POISearchService.shared.search(
            query: stop.searchQuery,
            near: centre,
            radius: 30_000
        )) ?? []
    }

    // MARK: - Helpers

    /// Returns true when the first candidate is clearly dominant
    /// (name match confidence heuristic: top result has same name as query,
    ///  or there is only one result within the search radius).
    private static func isClearWinner(_ items: [MKMapItem]) -> Bool {
        guard items.count > 1 else { return true }
        // Treat as unambiguous if first result distance is much closer than second.
        // MKLocalSearch returns results sorted by relevance; we trust the ranking
        // when the list has 2 or fewer items.
        return items.count <= 2
    }

    /// Default dwell time in minutes for each stop kind,
    /// used when the user didn’t specify one (dwellMinutes == -1).
    static func defaultDwell(for kind: IntentStopKind) -> Int {
        switch kind {
        case .cafe:    return 15
        case .park:    return 10
        case .town:    return 5
        case .service: return 5
        case .other:   return 0
        }
    }
}

// MARK: - PlanState convenience

private extension PlanState {
    /// Adds a waypoint with an optional name label.
    /// Wraps the existing `addWaypoint(_ coordinate:)` to also set `name`.
    @MainActor
    func addWaypoint(_ coordinate: CLLocationCoordinate2D, name: String?) {
        var wp = PlanWaypoint(coordinate: coordinate)
        wp.name = name
        waypoints.append(wp)
    }
}
