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
//                └─ ambiguous stops flagged    (stopNeedsDisambiguation event)
//                     └─ PlanState populated   (addWaypoint + optional loop toggle)
//                          └─ PlanRouteEngine   (fires via PlanView's .onChange as normal)
//
//  CALLER PATTERN (RidePlanAssistantView):
//    let engine = PlanAssistantEngine()
//    for await event in engine.plan(prompt: userText, near: mapCenter, planState: state) {
//        // update UI from AssistantEvent
//    }
//
//  CLLocationCoordinate2D NOTE:
//  CLLocationCoordinate2D is a plain C struct — safe to construct on any actor/thread.
//  No @MainActor wrapping is needed or used here. This matches every other file in
//  the codebase (PlanState, CyclingRouteService, POISearchService).
//
//  PlanState.addWaypoint IS @MainActor, so the PlanState population block
//  in runPipeline is wrapped with MainActor.run as required.
//
//  DEPRECATIONS TO AVOID:
//  ❌ mapItem.placemark — deprecated iOS 26; use .name / .address / .location
//  ❌ CLGeocoder — deprecated iOS 18+
//  ❌ session.stream(from:onPartial:) — removed iOS 26
//  ✅ session.respond(to:generating:) — @Generable structured output
//  ✅ POISearchService.shared.search(query:near:) — existing MKLocalSearch wrapper
//  ✅ mapItem.location?.coordinate — iOS 26-safe (MKMapItem.location is CLLocation)
//

import Foundation
import MapKit
import CoreLocation
import FoundationModels

// MARK: - Public event stream

/// Events emitted by `PlanAssistantEngine.plan(prompt:nearLat:nearLon:planState:)`.
/// RidePlanAssistantView drives its UI entirely from these events.
enum AssistantEvent {
    /// LLM has parsed the intent; caller can show "Resolving stops…" state.
    case intentParsed(RidePlanIntent)
    /// One stop resolved successfully; `waypointName` is the label to show.
    case stopResolved(index: Int, waypointName: String)
    /// A stop matched multiple places; caller should present a picker.
    case stopNeedsDisambiguation(index: Int, candidates: [MKMapItem])
    /// All stops resolved; PlanState has been populated.
    /// PlanRouteEngine fires automatically via PlanView’s existing .onChange.
    case completed
    /// The pipeline failed with a user-readable message.
    case failed(String)
}

// MARK: - Resolved stop (internal)

/// Fully resolved waypoint, held until we can write to PlanState on @MainActor.
private struct ResolvedStop {
    let label: String
    let kind: IntentStopKind
    let dwellMinutes: Int
    let coordinate: CLLocationCoordinate2D   // plain C struct — safe anywhere
}

// MARK: - Engine

/// Orchestrates natural-language route planning via FoundationModels + MKLocalSearch.
///
/// Not an actor — one instance per planning session; no persistent mutable state
/// between `plan(...)` calls.
final class PlanAssistantEngine {

    // MARK: - Public API

    /// Runs the full AI → search → PlanState pipeline.
    ///
    /// - Parameters:
    ///   - prompt: The user’s free-text route request.
    ///   - nearLat/nearLon: Map centre used as MKLocalSearch anchor.
    ///   - planState: The `PlanState` to populate (mutations on @MainActor).
    /// - Returns: `AsyncStream<AssistantEvent>` to iterate with `for await`.
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

    /// Resolves a stop the user picked from a disambiguation list,
    /// appends it to PlanState, and returns its display label.
    @MainActor
    func commitDisambiguatedStop(
        mapItem: MKMapItem,
        planState: PlanState
    ) -> String {
        let label = mapItem.name ?? "Stop"
        if let coord = mapItem.location?.coordinate {
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
        // 1. Parse intent with on-device LLM
        let intent: RidePlanIntent
        do {
            intent = try await parseIntent(from: prompt)
        } catch {
            continuation.yield(.failed("Couldn’t understand your request. Try rephrasing."))
            return
        }
        continuation.yield(.intentParsed(intent))

        guard !intent.stops.isEmpty else {
            continuation.yield(.failed("No stops found. Try adding a destination."))
            return
        }

        // 2. Resolve each stop via MKLocalSearch
        let centre = CLLocationCoordinate2D(latitude: nearLat, longitude: nearLon)
        var resolved: [ResolvedStop?] = Array(repeating: nil, count: intent.stops.count)

        for (idx, stop) in intent.stops.enumerated() {
            let candidates = await searchStop(stop, near: centre)

            if candidates.isEmpty {
                continue  // skip — user can add manually
            } else if candidates.count <= 2 {
                // Single or near-certain result — auto-resolve
                let item = candidates[0]
                let label = item.name ?? stop.label
                let dwell = stop.dwellMinutes >= 0
                    ? stop.dwellMinutes
                    : Self.defaultDwell(for: stop.kind)
                if let coord = item.location?.coordinate {
                    resolved[idx] = ResolvedStop(
                        label: label,
                        kind: stop.kind,
                        dwellMinutes: dwell,
                        coordinate: coord
                    )
                    continuation.yield(.stopResolved(index: idx, waypointName: label))
                }
            } else {
                // Ambiguous — let the user pick
                continuation.yield(.stopNeedsDisambiguation(
                    index: idx,
                    candidates: Array(candidates.prefix(5))
                ))
                // resolved[idx] stays nil; caller handles via commitDisambiguatedStop
            }
        }

        // 3. Populate PlanState — @MainActor required for addWaypoint
        await MainActor.run {
            planState.clearAll()
            for stop in resolved.compactMap({ $0 }) {
                planState.addWaypoint(stop.coordinate, name: stop.label)
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
        from the user’s request. For each stop include a natural-language search query
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
        near centre: CLLocationCoordinate2D
    ) async -> [MKMapItem] {
        (try? await POISearchService.shared.search(
            query: stop.searchQuery,
            near: centre,
            radius: 30_000
        )) ?? []
    }

    // MARK: - Helpers

    /// Default dwell time in minutes when the user didn’t specify one.
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
    /// Appends a waypoint with an optional name.
    /// Wraps `PlanWaypoint(coordinate:)` to also set `.name`.
    @MainActor
    func addWaypoint(_ coordinate: CLLocationCoordinate2D, name: String?) {
        var wp = PlanWaypoint(coordinate: coordinate)
        wp.name = name
        waypoints.append(wp)
    }
}
