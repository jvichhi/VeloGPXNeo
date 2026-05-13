# VeloGPXNeo — Future Features Backlog
> Created: May 13, 2026 | Status: Not started — planned for future sprints

---

## Overview

This document tracks significant new features that are scoped, technically validated, and ready to be picked up in a future sprint. Items here are distinct from tech debt — they represent net-new user-facing capability, not fixes to existing code.

---

## F-A — Foundation Models: On-Device AI

**Priority:** High  
**API:** `FoundationModels` (iOS 26+, Apple Intelligence)  
**Requires:** iOS 26 minimum deployment target (already set)  
**Status:** Not started

### Why This Matters

`FoundationModels` runs fully on-device, fully offline — no API keys, no server costs, no network dependency. This is critical for a cycling app used on remote routes where connectivity is unreliable or absent. Unlike cloud LLMs, it respects user privacy (ride data never leaves the device) and works in airplane mode.

The framework uses Apple's on-device Apple Intelligence model, which is small enough to run at low latency and supports structured generation via `@Generable` macros.

---

### F-A1 — Ride Summary Generation

**What it does:** After a ride completes, feed the `RideSummary` data into a `FoundationModels` session to generate a natural-language summary the user can share directly (Messages, Instagram caption, Strava description, etc.).

**Input data available in `RideSummary`:**
- `routeName`, `totalDistance`, `elevationGain`, `elevationLoss`
- `maxSpeed`, `elapsedTime`, `movingTime`, `startDate`
- `actualTrack` (array of coordinates for geography context)
- `pois` (visited POIs can be mentioned by name)

**Implementation plan:**

1. Add `FoundationModels` import to `RideSummaryView.swift`
2. Create `RideSummaryGenerator.swift` in `iPhone/Services/`:
   ```swift
   import FoundationModels

   @available(iOS 26, *)
   struct RideSummaryGenerator {
       private let session = LanguageModelSession()

       func generate(from summary: RideSummary) async throws -> String {
           let distKm  = String(format: "%.1f", summary.totalDistance / 1000)
           let gainM   = Int(summary.elevationGain)
           let elapsed = formatDuration(summary.elapsedTime)
           let pois    = summary.pois.prefix(3).map { $0.name }.joined(separator: ", ")

           let prompt = """
           Write a 2-3 sentence summary for a cycling ride.
           Route: \(summary.routeName)
           Distance: \(distKm) km  |  Elevation gain: \(gainM) m  |  Time: \(elapsed)
           Notable stops: \(pois.isEmpty ? "none" : pois)
           Tone: enthusiastic but factual. No hashtags. No emojis.
           """
           let response = try await session.respond(to: prompt)
           return response.content
       }
   }
   ```
3. Surface in `RideSummaryView` as a "Generate Summary" button → inline text field pre-filled with result, editable before sharing.
4. Gate with `#available(iOS 26, *)` and `ModelAvailability.isAvailable` check; show a static template fallback on unsupported devices.

**UX placement:** `RideSummaryView` — below the stats grid, above the Share button. One tap generates; user can regenerate or edit inline before sharing.

---

### F-A2 — Smart Route Naming

**What it does:** When a user imports a GPX file with a generic filename (e.g., `track_2026-05-13.gpx`) or taps "Rename", suggest a human-readable name based on the route's geography.

**Input:** Start/end coordinates + key waypoint coordinates from `RouteModel.trackPoints`

**Implementation plan:**

1. Create `RouteNameSuggester.swift` in `iPhone/Services/`:
   ```swift
   import FoundationModels
   import CoreLocation

   @available(iOS 26, *)
   struct RouteNameSuggester {
       private let session = LanguageModelSession()
       private let geocoder = CLGeocoder()   // fallback until MK-3 migration

       func suggest(for route: RouteModel) async throws -> [String] {
           // Sample 5 evenly spaced points for geographic context
           let points = stride(from: 0, to: route.trackPoints.count,
                               by: max(1, route.trackPoints.count / 5))
               .map { route.trackPoints[$0].coordinate }

           // Reverse geocode the start and midpoint
           let startName  = try await geocodeName(points.first)
           let middleName = try await geocodeName(points[points.count / 2])

           let distKm = String(format: "%.0f", route.totalDistance / 1000)
           let gainM  = Int(route.elevationGain)

           let prompt = """
           Suggest 3 short, evocative route names for a cycling ride.
           Start area: \(startName ?? "unknown")
           Midpoint area: \(middleName ?? "unknown")
           Distance: \(distKm) km  |  Elevation gain: \(gainM) m
           Style: specific place names, loop/circuit/climb if applicable, 3-6 words max.
           Return exactly 3 names, one per line, no numbering.
           """
           let response = try await session.respond(to: prompt)
           return response.content
               .split(separator: "\n")
               .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
               .filter { !$0.isEmpty }
       }

       private func geocodeName(_ coord: Coordinate?) async throws -> String? {
           guard let coord else { return nil }
           let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
           let placemarks = try await geocoder.reverseGeocodeLocation(loc)
           return placemarks.first?.locality ?? placemarks.first?.subLocality
       }
   }
   ```
2. Show suggestions as a pill picker in the rename sheet in `RouteLibraryView`.
3. Gate with `#available(iOS 26, *)` — show a plain text field on earlier OS.

> **Note:** Replace `CLGeocoder` with `MKReverseGeocodingRequest` once MK-3 migration is complete (see TECH_DEBT.md).

---

### F-A3 — POI Relevance Ranking

**What it does:** When the user opens `POIDiscoverySheet` or `NearbySearchSheet`, rank the returned POIs by predicted relevance to the current ride context — all on-device, no server.

**Context signals available:**
- `RouteModel.difficulty` (easy/moderate/hard/epic)
- `RouteModel.elevationGain` (high gain → water sources ranked higher)
- `RideHistoryStore` — categories of POIs the user has interacted with on past rides
- `rideState.totalDistance` / elapsed time (late in long ride → food/accommodation ranked higher)

**Implementation plan:**

1. Create `POIRankingEngine.swift` in `iPhone/Services/`:
   ```swift
   import FoundationModels

   @available(iOS 26, *)
   @Generable
   struct RankedPOI: Identifiable {
       let id: UUID
       let relevanceScore: Double   // 0.0–1.0
       let reason: String           // short justification shown on hover
   }

   @available(iOS 26, *)
   actor POIRankingEngine {
       static let shared = POIRankingEngine()
       private let session = LanguageModelSession()

       func rank(_ pois: [POIModel],
                 context: RideContext) async -> [POIModel] {
           // Build a structured prompt with ride context + POI list
           // Use @Generable to get back a typed [RankedPOI] response
           // Sort pois by relevanceScore and return
       }
   }
   ```
2. `RideContext` struct captures: difficulty, elevationGain, distanceSoFar, timeOfDay, pastCategoryFrequency (from `RideHistoryStore`).
3. Integrate into `POIDiscoverySheet` — add a "Suggested" sort option alongside "Nearest" and "By Category". Default to "Suggested" when at least 3 rides of history exist.
4. Show `reason` as a subtitle under the POI name (`"Good stop for a long climb route"`).

**Fallback:** When `FoundationModels` is unavailable, keep current distance-sorted order.

---

### F-A — Shared Implementation Notes

- Add `FoundationModels` framework to the VeloGPX target in Build Phases
- All three features should check `ModelAvailability.isAvailable` before showing AI-powered UI
- Use a shared `VeloAISession` wrapper to avoid spinning up multiple concurrent `LanguageModelSession` instances
- Consider adding a user toggle in `SettingsView` — "AI Features (Apple Intelligence)" — with a clear explanation that all processing is on-device
- Language: Apple Intelligence respects the device locale; no extra localization needed for generated text in the short term

---

## F-B — Unified Maps URLs + Apple Place IDs (MK-6)

**Priority:** High (blocks shareable POI lists and stable POI identity)  
**API:** `MKMapItem.identifier` (iOS 18+)  
**Status:** Not started — full spec already in TECH_DEBT.md MK-6

### Why This Matters

`POIModel` currently uses a coordinate-based `deterministicID` for stable identity. This works but misses the **Apple Maps Place ID** (`MKMapItem.identifier`, iOS 18+), which:
- Survives business renames and minor address changes
- Enables deep-link URLs that open directly in Apple Maps (`maps://?auid=<identifier>`)
- Lays the foundation for shareable POI lists (share a route + its POIs as tappable Maps links)
- Prevents collisions when two businesses share nearly identical coordinates (café that moved 5m)

### Implementation Plan

**Step 1 — Extend `POIModel`** (`Shared/Models/POIModel.swift`):
```swift
public struct POIModel: Codable, Identifiable, Sendable, Equatable {
    // ... existing fields ...

    // New optional fields — backwards-compatible (Codable handles missing keys)
    public var mapItemIdentifier: String?   // MKMapItem.identifier.rawValue (iOS 18+)
    public var mapsURL: URL?               // maps://?auid=<identifier>
}
```

**Step 2 — Factory extension** (new file: `Shared/Models/POIModel+MapKit.swift`):
```swift
import MapKit

extension POIModel {
    static func from(_ mapItem: MKMapItem, distanceFromRoute: Double = 0) -> POIModel {
        var poi = POIModel(
            id: UUID(),
            name: mapItem.name ?? "",
            category: POICategory.from(mapItem.pointOfInterestCategory),
            coordinate: (mapItem.location?.coordinate
                         ?? mapItem.placemark.coordinate).asCoordinate,
            distanceFromRoute: distanceFromRoute
        )
        if #available(iOS 18, *) {
            poi.mapItemIdentifier = mapItem.identifier?.rawValue
            poi.mapsURL = mapItem.identifier.flatMap {
                URL(string: "maps://?auid=\($0.rawValue)")
            }
        }
        return poi
    }
}
```
> Replace `mapItem.placemark.coordinate` fallback with `mapItem.location?.coordinate` once MK-2 migration is complete.

**Step 3 — Update `isAdded` logic** in `NearbySearchSheet`, `POIDiscoverySheet`, `PreRidePOISheet`:
```swift
// Prefer identifier-based match; fall back to coordinate hash
func isAdded(_ mapItem: MKMapItem, in pois: [POIModel]) -> Bool {
    if #available(iOS 18, *),
       let id = mapItem.identifier?.rawValue {
        return pois.contains { $0.mapItemIdentifier == id }
    }
    return pois.contains { $0.id == deterministicID(for: mapItem) }
}
```

**Step 4 — "Open in Maps" button** in `NearbyResultCard` and POI detail rows:
```swift
if let url = poi.mapsURL {
    Button {
        UIApplication.shared.open(url)
    } label: {
        Label("Open in Maps", systemImage: "map")
    }
    .buttonStyle(.bordered)
}
```

**Step 5 — Shareable POI list (stretch goal)**
Once Place IDs are stable, generate a shareable text or URL containing POI identifiers. The receiver opens Maps and sees the exact same places. Implementation deferred until F-B steps 1–4 are stable.

### Backward Compatibility
- `POIModel` is `Codable` — adding optional fields with `nil` defaults is fully backwards-compatible
- Existing JSON files in `RideHistoryStore` decode without errors; new fields default to `nil`
- `deterministicID(for:)` coordinate fallback preserved for Watch builds and custom waypoints which will never have a Place ID

---

## F-C — RidePlanAssistant: AI Destination-Driven Route Planning

**Priority:** High  
**APIs:** `FoundationModels` (iOS 26+), `MKLocalSearch`, existing `PlanState` + `PlanRouteEngine`  
**Requires:** F-A foundation (shared `VeloAISession` wrapper)  
**Status:** Not started

### Why This Matters

VeloGPX currently supports two ways to start a ride: import a GPX file, or manually build a route by dropping waypoints on a map. Both are **map-first** — they require the user to already know where they're going before they start.

Many rides begin with a **destination-first** mental model: *"I want to ride to that café and back"*, *"take me somewhere new for 90 minutes"*, *"hit the lookout then come home."* There's currently no path in the app for this. The user has to mentally translate their intent into waypoints — a friction that discourages spontaneous rides.

`RidePlanAssistant` fills this gap. The user describes what they want in plain language; the assistant resolves named places, constructs a multi-stop route, and drops it into `PlanState` ready to ride. All on-device, all offline.

---

### Core Principle: The Model Understands Intent, MapKit Does Geography

The on-device model cannot know where Café Olimpico is. It doesn't have map data. Its job is strictly **language → structured intent**: parse what the user said into a typed Swift struct. `MKLocalSearch` resolves names to coordinates. `PlanRouteEngine` computes the geometry. The model never touches spatial math.

```
User text
   ↓
FoundationModels → RidePlanIntent (@Generable)
   ↓
MKLocalSearch per named stop → CLLocationCoordinate2D
   ↓
PlanState.addWaypoint() × N
   ↓
PlanRouteEngine.recomputeAll() → RouteModel preview
   ↓
RouteLibraryView "AI Planned" section → Start Ride
```

---

### F-C1 — Core: Natural Language → Route (Ship First)

#### `RidePlanIntent` — The Structured Output Contract

```swift
import FoundationModels

@available(iOS 26, *)
@Generable
struct DestinationStop {
    @Guide("Place name exactly as the user said it — preserve specificity")
    var rawName: String

    @Guide("Category: cafe, restaurant, viewpoint, park, store, home, custom")
    var stopType: StopType

    @Guide("Role in the route: waypoint (pass through / stop briefly) or destination (end point)")
    var role: StopRole

    @Guide("Optional user intent qualifier: 'lunch stop', 'fill water', 'quick coffee', nil if none stated")
    var intent: String?
}

@available(iOS 26, *)
@Generable
struct RidePlanIntent {
    @Guide("Ordered list of stops the user wants to visit, in the order stated")
    var stops: [DestinationStop]

    @Guide("True if the user wants to return to their starting point ('then home', 'loop back', 'and back')")
    var preferLoop: Bool

    @Guide("Climbing preference inferred from the request: flat, moderate, hilly, mountain. Default moderate if unspecified.")
    var climbingPreference: ClimbingPreference

    @Guide("Road type preference inferred: any, quiet_roads, bike_paths, mixed. Default mixed if unspecified.")
    var roadPreference: RoadPreference

    @Guide("Time limit in minutes if the user mentioned a time constraint, nil otherwise")
    var timeLimitMinutes: Int?

    @Guide("Target distance in km if stated, nil otherwise")
    var targetDistanceKm: Double?
}
```

#### `PlanAssistantEngine` — The Orchestrator

Create `iPhone/Services/PlanAssistantEngine.swift`:

```swift
import FoundationModels
import MapKit
import CoreLocation

@available(iOS 26, *)
@MainActor
final class PlanAssistantEngine: ObservableObject {

    enum State {
        case idle
        case parsing          // model running
        case resolving(Int, Int)  // (resolved, total) MKLocalSearch in progress
        case disambiguating(String, [MKMapItem], (MKMapItem) -> Void)  // needs user pick
        case routing          // PlanRouteEngine running
        case failed(String)
    }

    @Published var state: State = .idle

    private let session = VeloAISession.shared   // reuse shared session (see F-A notes)
    private let geocoder = CLGeocoder()

    /// Primary entry point. Parses `text`, resolves all stops, populates `plan`.
    func process(_ text: String,
                 userLocation: CLLocationCoordinate2D,
                 plan: PlanState,
                 engine: PlanRouteEngine) async {
        do {
            // 1. Parse intent
            state = .parsing
            let intent = try await parseIntent(text)

            // 2. Resolve each stop to a coordinate
            var resolvedCoords: [CLLocationCoordinate2D] = []
            let nonHomeStops = intent.stops.filter { $0.stopType != .home }

            for (i, stop) in nonHomeStops.enumerated() {
                state = .resolving(i, nonHomeStops.count)
                let coord = try await resolve(stop: stop, near: userLocation)
                resolvedCoords.append(coord)
            }

            // 3. Build waypoints: origin → stops → origin (if loop)
            plan.clearAll()
            plan.addWaypoint(at: userLocation, name: "Start")
            for (i, coord) in resolvedCoords.enumerated() {
                plan.addWaypoint(at: coord, name: nonHomeStops[i].rawName)
            }
            if intent.preferLoop {
                plan.isLoopClosed = true
            }

            // 4. Apply intent parameters to plan
            if let dist = intent.targetDistanceKm {
                plan.targetDistanceKm = dist
            }
            plan.climbingPreference  = intent.climbingPreference
            plan.roadPreference      = intent.roadPreference
            plan.timeLimitMinutes    = intent.timeLimitMinutes

            // 5. Route
            state = .routing
            await engine.recomputeAll(in: plan)
            state = .idle

        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func parseIntent(_ text: String) async throws -> RidePlanIntent {
        let prompt = """
        Parse this cycling route request into structured data.
        Request: "\(text)"
        The user is planning a bike ride. Extract all named destinations, 
        whether they want to return home, any time or distance constraints,
        and road/climbing preferences. If a stop is "home", mark stopType as .home.
        """
        return try await session.respond(to: prompt, generating: RidePlanIntent.self)
    }

    private func resolve(stop: DestinationStop,
                         near region: CLLocationCoordinate2D) async throws -> CLLocationCoordinate2D {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = stop.rawName
        request.region = MKCoordinateRegion(
            center: region,
            latitudinalMeters: 50_000,
            longitudinalMeters: 50_000
        )
        let results = try await MKLocalSearch(request: request).start()
        let items = results.mapItems

        guard !items.isEmpty else {
            throw AssistantError.placeNotFound(stop.rawName)
        }

        if items.count > 1 {
            // Surface disambiguation to the user via @Published state
            // Caller awaits the user's choice via a continuation
            let coord = try await withCheckedThrowingContinuation { continuation in
                state = .disambiguating(stop.rawName, items) { chosen in
                    continuation.resume(returning: chosen.placemark.coordinate)
                }
            }
            return coord
        }

        return items[0].placemark.coordinate
    }

    enum AssistantError: LocalizedError {
        case placeNotFound(String)
        var errorDescription: String? {
            switch self {
            case .placeNotFound(let name): return "Couldn't find \"\(name)\" nearby."
            }
        }
    }
}
```

#### `RidePlanAssistantView` — The Inline Input

Create `iPhone/Views/RidePlanAssistantView.swift`. This is an **inline expandable view** — not a modal, not a new screen. It lives inside `RouteLibraryView` and expands in-place when "Plan with AI" is tapped.

```swift
@available(iOS 26, *)
struct RidePlanAssistantView: View {
    @ObservedObject var engine: PlanAssistantEngine
    @State private var inputText = ""
    @State private var isExpanded = false
    @FocusState private var isFocused: Bool
    let onRouteReady: (PlanState) -> Void
    let userLocation: CLLocationCoordinate2D?

    // Suggestion chips shown under the input field
    private let suggestions = [
        "Café Olimpico, then home",
        "Atwater Market and back",
        "40km loop, some climbing",
        "Somewhere new, 90 minutes",
        "Camillien-Houde lookout loop",
    ]
    @State private var suggestionIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isExpanded {
                // Collapsed: single "Plan with AI" button (lives next to Import GPX)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        isExpanded = true
                    }
                    isFocused = true
                } label: {
                    Label("Plan with AI", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.tint)
                }
            } else {
                // Expanded: input field + suggestions + state feedback
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.tint)
                            .font(.system(size: 15, weight: .semibold))

                        TextField("Where do you want to ride?", text: $inputText, axis: .vertical)
                            .focused($isFocused)
                            .font(.subheadline)
                            .lineLimit(1...3)
                            .submitLabel(.go)
                            .onSubmit { submitIfReady() }

                        if !inputText.isEmpty {
                            Button {
                                withAnimation { inputText = "" }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor.opacity(0.4), lineWidth: 1.5)
                    )

                    // Suggestion chips — tappable examples
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button {
                                    inputText = suggestion
                                    submitIfReady()
                                } label: {
                                    Text(suggestion)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color(.systemGray6), in: Capsule())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // State feedback
                    stateView

                    // Cancel
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            isExpanded = false
                            inputText = ""
                            isFocused = false
                        }
                    } label: {
                        Text("Cancel")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 16))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Disambiguation sheet
        .sheet(isPresented: isDisambiguating) {
            if case .disambiguating(let name, let items, let pick) = engine.state {
                DisambiguationSheet(placeName: name, candidates: items, onSelect: pick)
            }
        }
    }

    // MARK: - State Feedback

    @ViewBuilder
    private var stateView: some View {
        switch engine.state {
        case .idle:
            EmptyView()
        case .parsing:
            statusRow(icon: "sparkles", text: "Understanding your request…", color: .tint)
        case .resolving(let done, let total):
            statusRow(icon: "mappin.and.ellipse",
                      text: "Finding places… (\(done)/\(total))",
                      color: .orange)
        case .disambiguating(let name, _, _):
            statusRow(icon: "questionmark.circle", text: "Which \"\(name)\"?", color: .orange)
        case .routing:
            statusRow(icon: "arrow.triangle.turn.up.right.diamond",
                      text: "Building your route…", color: .blue)
        case .failed(let msg):
            statusRow(icon: "exclamationmark.triangle", text: msg, color: .red)
        }
    }

    private func statusRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).font(.system(size: 13))
            Text(text).font(.caption).foregroundStyle(.secondary)
            if case .parsing = engine.state { ProgressView().scaleEffect(0.7) }
            if case .resolving = engine.state { ProgressView().scaleEffect(0.7) }
            if case .routing = engine.state { ProgressView().scaleEffect(0.7) }
        }
        .padding(.horizontal, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.easeInOut(duration: 0.2), value: text)
    }

    private var isDisambiguating: Binding<Bool> {
        Binding(
            get: { if case .disambiguating = engine.state { return true }; return false },
            set: { _ in }
        )
    }

    private func submitIfReady() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let loc = userLocation else { return }
        let plan = PlanState()
        let routeEngine = PlanRouteEngine()
        Task {
            await engine.process(text, userLocation: loc, plan: plan, engine: routeEngine)
            if case .idle = engine.state {
                onRouteReady(plan)
            }
        }
    }
}
```

#### `DisambiguationSheet` — Lightweight Place Picker

When `MKLocalSearch` returns multiple candidates for a named stop:

```swift
struct DisambiguationSheet: View {
    let placeName: String
    let candidates: [MKMapItem]
    let onSelect: (MKMapItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(candidates, id: \.self) { item in
                Button {
                    onSelect(item)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? placeName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        if let subtitle = item.placemark.title {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Which \"\(placeName)\"?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
```

#### Integration in `RouteLibraryView`

In the Routes tab, the top action bar becomes:

```swift
// RouteLibraryView — top of list, above route cards
HStack(spacing: 10) {
    // Existing
    Button {
        showImportSheet = true
    } label: {
        Label("Import GPX", systemImage: "square.and.arrow.down")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.primary)
    }

    // New — only shown on iOS 26+ with Apple Intelligence available
    if #available(iOS 26, *), ModelAvailability.isAvailable {
        RidePlanAssistantView(
            engine: assistantEngine,
            userLocation: locationManager.lastLocation?.coordinate,
            onRouteReady: { plan in
                // Save AI-planned route as temporary entry in routeStore
                let route = plan.buildRouteModel(name: PlanState.autoName())
                routeStore.addAIPlannedRoute(route)   // see F-C1 data model below
            }
        )
    }
}
.padding(.horizontal, 16)
.padding(.top, 12)
```

---

### F-C2 — Polish: Stop Icons, Dwell Time, Save/Discard UX (Ship Second)

#### "AI Planned" Section in `RouteLibraryView`

AI-planned routes are **temporary by default** — they live in a dedicated top section until explicitly saved or discarded. This prevents library pollution from one-off spontaneous rides.

**Data model addition** in `RouteStore`:
```swift
// RouteStore.swift additions
@Published var aiPlannedRoutes: [RouteModel] = []

func addAIPlannedRoute(_ route: RouteModel) {
    // Replace previous AI plan (only one at a time)
    aiPlannedRoutes = [route]
}

func saveAIPlannedRoute(_ route: RouteModel) {
    routes.append(route)
    aiPlannedRoutes.removeAll { $0.id == route.id }
    saveRoutes()
}

func discardAIPlannedRoute(_ route: RouteModel) {
    aiPlannedRoutes.removeAll { $0.id == route.id }
}
```

**Route card for AI-planned routes** (top of list, above saved routes):
```
┌──────────────────────────────────────────────────────┐
│  ✨  Café Olimpico Loop                               │
│      14.2 km · ~52 min · 180m ↑                      │
│      ● Café Olimpico  ● Home                         │ ← stop pills
│                                                      │
│  [ Save to Library ]    [ Discard ]    [ Start → ]   │
└──────────────────────────────────────────────────────┘
```

After riding an AI-planned route, it auto-saves to `RideHistoryStore` (as all rides do) but the `aiPlannedRoutes` entry is discarded — the user doesn't need the route card anymore since the ride is done.

#### Stop-Type Icons in `WaypointListSheet`

Enhance `WaypointPoint` model (or carry `DestinationStop.stopType` alongside) so each waypoint row shows a contextual icon:

| Stop Type | Icon | Colour |
|---|---|---|
| `.cafe` | `cup.and.saucer.fill` | `.brown` |
| `.restaurant` | `fork.knife` | `.orange` |
| `.viewpoint` | `binoculars.fill` | `.blue` |
| `.park` | `leaf.fill` | `.green` |
| `.store` | `bag.fill` | `.purple` |
| `.home` | `house.fill` | `.gray` |
| `.custom` | `mappin.fill` | `.red` |

#### Dwell Time in Total Outing Estimate

Map `DestinationStop.intent` to an estimated dwell time and surface a total outing time in `WaypointListSheet`:

```swift
func estimatedDwellMinutes(for intent: String?) -> Int {
    guard let intent = intent?.lowercased() else { return 10 }
    if intent.contains("lunch") || intent.contains("dinner") { return 45 }
    if intent.contains("coffee") || intent.contains("quick") { return 15 }
    if intent.contains("fill water") || intent.contains("snack") { return 5 }
    return 10  // default: quick stop
}
```

Display in `WaypointListSheet` header:
```
Ride time:    1h 42m
+ Stops:      ~30 min (2 stops)
──────────────────────
Total outing: ~2h 12m
```

---

### UX Flow Summary

```
Routes Tab
│
│  ┌──────────────────────┬──────────────────────┐
│  │  ✨ Plan with AI     │  📂 Import GPX        │
│  └──────────────────────┴──────────────────────┘
│              ↓ tap "Plan with AI"
│
│  ┌─────────────────────────────────────────────┐
│  │  🎙 "Café Olimpico, then home"              │
│  │  ─────────────────────────────              │
│  │  [Café Olimpico, then home] [40km loop] … ← chips
│  │  Finding Café Olimpico… ⠋                   │
│  │  [Cancel]                                   │
│  └─────────────────────────────────────────────┘
│              ↓ resolved
│
│  ─── AI Planned ─────────────────────────────────
│  ┌─────────────────────────────────────────────┐
│  │  ✨ Café Olimpico Loop · 14.2 km · ~52 min  │
│  │  [ Save to Library ] [Discard] [Start →]   │
│  └─────────────────────────────────────────────┘
│  ─── Saved Routes ───────────────────────────────
│  existing cards…
```

---

### New Files Required

| File | Purpose |
|---|---|
| `iPhone/Services/PlanAssistantEngine.swift` | Orchestrates model → search → `PlanState` pipeline |
| `iPhone/Services/RidePlanIntent+Generable.swift` | `@Generable` structs: `RidePlanIntent`, `DestinationStop` |
| `iPhone/Views/RidePlanAssistantView.swift` | Inline expandable input in Routes tab |
| `iPhone/Views/DisambiguationSheet.swift` | Place picker when `MKLocalSearch` returns multiple results |

### Modified Files

| File | Change |
|---|---|
| `RouteLibraryView.swift` | Add `RidePlanAssistantView` + "AI Planned" section |
| `RouteStore.swift` | Add `aiPlannedRoutes`, `addAIPlannedRoute`, `saveAIPlannedRoute`, `discardAIPlannedRoute` |
| `WaypointListSheet.swift` | Stop-type icons, dwell time in header (F-C2) |
| `PlanState.swift` | `climbingPreference`, `roadPreference`, `timeLimitMinutes`, `targetDistanceKm` fields (if not already present) |

---

### Constraints & Edge Cases

- **No Apple Intelligence on device:** `ModelAvailability.isAvailable` returns false → "Plan with AI" button is hidden entirely. No degraded state shown.
- **Place not found:** `AssistantError.placeNotFound` shown as inline error in `stateView`. User can edit text and retry.
- **Disambiguation cancelled:** User dismisses `DisambiguationSheet` without picking → that stop is skipped, route built with remaining stops.
- **No GPS fix:** "Plan with AI" button disabled (`userLocation == nil`) with a "Waiting for GPS…" label — `MKLocalSearch` region bias requires a location.
- **Watch target:** `PlanAssistantEngine`, `RidePlanIntent+Generable`, `RidePlanAssistantView` must be excluded from the Watch target in Build Phases. Watch has no `FoundationModels` access.

---

## Feature Comparison

| Feature | API | iOS Min | Offline | Net-New UX |
|---|---|---|---|---|
| F-A1 Ride summary generation | `FoundationModels` | iOS 26 | ✅ Yes | Shareable natural language summary post-ride |
| F-A2 Smart route naming | `FoundationModels` + `CLGeocoder`/`MKReverseGeocodingRequest` | iOS 26 | ✅ Yes (geocoding cached) | Auto-named routes on import |
| F-A3 POI relevance ranking | `FoundationModels` | iOS 26 | ✅ Yes | "Suggested" POI sort based on ride context |
| F-B Place IDs + Maps URLs | `MKMapItem.identifier` | iOS 18 | N/A | Stable POI identity + "Open in Maps" deep link |
| F-C1 RidePlanAssistant (core) | `FoundationModels` + `MKLocalSearch` | iOS 26 | ✅ Yes | Natural language → multi-stop route in Routes tab |
| F-C2 RidePlanAssistant (polish) | — | iOS 26 | ✅ Yes | Stop icons, dwell time, Save/Discard UX |

---

## Dependencies & Sequencing

```
MK-2 migration (TECH_DEBT) ──► F-B (POIModel+MapKit factory uses .location instead of .placemark)
MK-3 migration (TECH_DEBT) ──► F-A2 (replace CLGeocoder with MKReverseGeocodingRequest)
F-B (Place IDs stable) ──────► Stretch: shareable POI lists
F-A1 (summary gen) ──────────► Can ship independently, no other F-A prerequisites
F-A2, F-A3 ──────────────────► Can ship in any order after F-A1 validates the AI session pattern
F-A (VeloAISession pattern) ─► F-C1 (reuses shared session wrapper)
F-C1 ────────────────────────► F-C2 (polish layer on top of working core)
```

---

## Open Questions

- **F-A3 training signal:** Should `RideHistoryStore` track which POI categories the user actually visits (stops at) vs. just passes near? Requires adding a `visitedPOICategories` field to `PersistedRideSummary`.
- **F-A language:** Should generated text (ride summaries, route names) respect `LocalizationManager` language override, or always use device locale? Device locale is simpler and likely correct for v1.
- **F-B Watch compatibility:** `MKMapItem.identifier` is iOS 18+ only and not available on watchOS. The Watch target must always use the coordinate `deterministicID` fallback — ensure `POIModel+MapKit.swift` is excluded from the Watch target in Build Phases.
- **F-C multi-plan:** Should `aiPlannedRoutes` hold only one plan at a time (replace on each new request) or accumulate? Replacing keeps the UI clean; accumulating lets the user compare options. Start with replace-on-new for v1.
- **F-C offline place search:** `MKLocalSearch` requires a network connection. If offline, show a fallback message: "Place search needs a connection — tap the map to drop waypoints manually." The manual `PlanView` flow remains fully offline.
