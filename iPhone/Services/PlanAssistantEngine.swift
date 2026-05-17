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
//    for await event in engine.plan(prompt: userText, nearLat: lat, nearLon: lon, planState: state) {
//        // update UI from AssistantEvent
//    }
//
//  FoundationModels API (verified from Apple docs):
//    session.respond(to:)             → async throws → Response<String>  — text via .content
//    session.respond(to:generating:)  → async throws → Response<T>      — struct via .content
//
//  iOS 26 API NOTES:
//  • MKMapItem.location is CLLocation (non-optional) — use .coordinate directly.
//  • CLLocationCoordinate2D is a plain C struct — safe to construct on any actor/thread.
//  • PlanState.addWaypoint IS @MainActor — wrapped in MainActor.run below.
//  • MKLocalSearch.Request.resultTypes = [.address] is the correct iOS 13+ API for
//    resolving civic addresses (e.g. "2284 rue Kenneth-Patrick"). No deprecated APIs needed.
//
//  DEPRECATIONS TO AVOID:
//  ❌ mapItem.placemark — deprecated iOS 26; use mapItem.placemark.locality etc (CLPlacemark)
//  ❌ CLGeocoder — deprecated iOS 18+
//  ❌ session.stream(from:onPartial:) — removed iOS 26
//
//  STOP RESOLUTION STRATEGY:
//  • Civic address queries (start with digits, e.g. "2284 Kenneth-Patrick Laval") →
//    MKLocalSearch with resultTypes = [.address] for precise geocoding.
//  • All other queries (named POIs, neighbourhoods, cities) →
//    POISearchService.shared.search() which applies category filters where applicable.
//
//  F-C2 (May 16 2026): engine now passes kind + dwellMinutes through to
//  PlanWaypoint so WaypointListSheet can show stop-type icons and dwell chips.
//  IntentStopKind → WaypointStopKind mapping lives in waypointKind(from:).
//

import Foundation
import MapKit
import CoreLocation
import FoundationModels

// MARK: - Public event stream

/// Events emitted by `PlanAssistantEngine.plan(prompt:nearLat:nearLon:planState:)`.
enum AssistantEvent {
    /// LLM parsed the intent; caller can show “Resolving stops…” state.
    case intentParsed(RidePlanIntent)
    /// One stop resolved; `waypointName` is the label to show.
    case stopResolved(index: Int, waypointName: String)
    /// A stop matched multiple places; caller should present a picker.
    case stopNeedsDisambiguation(index: Int, candidates: [MKMapItem])
    /// All stops resolved; PlanState populated.
    case completed
    /// Pipeline failed with a user-readable message.
    case failed(String)
}

// MARK: - Resolved stop (internal)

private struct ResolvedStop {
    let label: String
    let kind: IntentStopKind
    let dwellMinutes: Int
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Engine

final class PlanAssistantEngine {

    // MARK: - Public API

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

    /// Appends a user-picked disambiguation result to PlanState.
    @MainActor
    func commitDisambiguatedStop(
        mapItem: MKMapItem,
        planState: PlanState
    ) -> String {
        let label = mapItem.name ?? "Stop"
        planState.addWaypoint(
            mapItem.location.coordinate,
            name: label,
            intentKind: .other,
            dwellMinutes: PlanAssistantEngine.defaultDwell(for: .other)
        )
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
        // 1. Parse intent
        let intent: RidePlanIntent
        do {
            intent = try await parseIntent(from: prompt)
        } catch {
            continuation.yield(.failed("Couldn't understand your request. Try rephrasing."))
            return
        }
        continuation.yield(.intentParsed(intent))

        guard !intent.stops.isEmpty else {
            continuation.yield(.failed("No stops found. Try adding a destination."))
            return
        }

        // 2. Resolve each stop
        let centre = CLLocationCoordinate2D(latitude: nearLat, longitude: nearLon)
        var resolved: [ResolvedStop?] = Array(repeating: nil, count: intent.stops.count)

        for (idx, stop) in intent.stops.enumerated() {
            let candidates = await searchStop(stop, near: centre)

            if candidates.isEmpty {
                continue
            } else if candidates.count <= 2 {
                let item = candidates[0]
                let label = item.name ?? stop.label
                let dwell = stop.dwellMinutes >= 0
                    ? stop.dwellMinutes
                    : Self.defaultDwell(for: stop.kind)
                resolved[idx] = ResolvedStop(
                    label: label,
                    kind: stop.kind,
                    dwellMinutes: dwell,
                    coordinate: item.location.coordinate
                )
                continuation.yield(.stopResolved(index: idx, waypointName: label))
            } else {
                continuation.yield(.stopNeedsDisambiguation(
                    index: idx,
                    candidates: Array(candidates.prefix(5))
                ))
            }
        }

        // 3. Populate PlanState on @MainActor
        // Pass intentKind and dwellMinutes so WaypointListSheet can show icons + chips.
        await MainActor.run {
            planState.clearAll()
            for stop in resolved.compactMap({ $0 }) {
                planState.addWaypoint(
                    stop.coordinate,
                    name: stop.label,
                    intentKind: Self.waypointKind(from: stop.kind),
                    dwellMinutes: stop.dwellMinutes > 0 ? stop.dwellMinutes : nil
                )
            }
            if intent.isLoop && planState.waypoints.count >= 2 {
                planState.isLoopClosed = true
            }
        }

        continuation.yield(.completed)
    }

    // MARK: - LLM

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
        // respond(to:generating:) returns Response<T> — unwrap the struct via .content
        let response = try await session.respond(
            to: "\(systemPrompt)\n\nUser request: \(prompt)",
            generating: RidePlanIntent.self
        )
        return response.content
    }

    // MARK: - MKLocalSearch

    private func searchStop(
        _ stop: IntentStop,
        near centre: CLLocationCoordinate2D
    ) async -> [MKMapItem] {
        // Civic address queries (e.g. "2284 rue Kenneth-Patrick Laval") need
        // resultTypes = [.address] for accurate geocoding. MKLocalSearch handles
        // both POIs and addresses via this flag — no deprecated CLGeocoder needed.
        // Detection: query starts with one or more digits followed by a space.
        if Self.looksLikeCivicAddress(stop.searchQuery) {
            return await searchAddress(stop.searchQuery, near: centre)
        }
        return (try? await POISearchService.shared.search(
            query: stop.searchQuery,
            near: centre,
            radius: 30_000
        )) ?? []
    }

    /// Address-mode search using `resultTypes = [.address]`.
    /// Uses a wide region so a full civic address anywhere near the ride area is found.
    private func searchAddress(
        _ query: String,
        near centre: CLLocationCoordinate2D
    ) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address]
        request.region = MKCoordinateRegion(
            center: centre,
            latitudinalMeters: 50_000,
            longitudinalMeters: 50_000
        )
        let results = try? await MKLocalSearch(request: request).start()
        return results?.mapItems ?? []
    }

    /// Returns true when the query looks like a civic address:
    /// starts with one or more digits then a space (e.g. "2284 Kenneth-Patrick").
    private static func looksLikeCivicAddress(_ query: String) -> Bool {
        query.first?.isNumber == true
    }

    // MARK: - Helpers

    static func defaultDwell(for kind: IntentStopKind) -> Int {
        switch kind {
        case .cafe:    return 15
        case .park:    return 10
        case .town:    return 5
        case .service: return 5
        case .other:   return 0
        }
    }

    /// Maps FoundationModels-dependent IntentStopKind → Watch-safe WaypointStopKind.
    static func waypointKind(from kind: IntentStopKind) -> WaypointStopKind {
        switch kind {
        case .cafe:    return .cafe
        case .park:    return .park
        case .town:    return .town
        case .service: return .service
        case .other:   return .other
        }
    }
}

// MARK: - PlanState convenience

private extension PlanState {
    @MainActor
    func addWaypoint(
        _ coordinate: CLLocationCoordinate2D,
        name: String?,
        intentKind: WaypointStopKind? = nil,
        dwellMinutes: Int? = nil
    ) {
        let wp = PlanWaypoint(
            coordinate: coordinate,
            name: name,
            intentKind: intentKind,
            dwellMinutes: dwellMinutes
        )
        waypoints.append(wp)
    }
}
