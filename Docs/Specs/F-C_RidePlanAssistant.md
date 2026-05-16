# F-C — RidePlanAssistant

**Priority:** High
**APIs:** `FoundationModels` (iOS 26+), `MKLocalSearch`, `MKDirections` with `.cycling`
**Requires:** Sprint 2 AI foundation (already shipped)
**Status:** Ready for Sprint 3

---

## Goal

Turn natural language ride requests into cyclist-suitable routes. The on-device model parses intent; Apple Maps handles geography and cycling-optimized pathfinding.

Example prompts:
- `"Café Olimpico, then home"`
- `"50 km ride through Laval"`
- `"Atwater Market and back"`
- `"Somewhere new, 90 minutes"`

---

## Core Principle: AI for Intent, MapKit for Pathfinding

The on-device model does **not** generate coordinates, route geometry, or turn-by-turn shape data. Its only job is language → typed struct.

```text
User text
  ↓
FoundationModels → RidePlanIntent (@Generable)
  ↓
MKLocalSearch resolves named stops to coordinates
  ↓
App logic computes turnaround / via points for loops
  ↓
MKDirections(.cycling) computes cyclist-suitable route legs
  ↓
Route preview / "AI Planned" card in Routes tab
```

---

## MapKit Cycling Directions

`MKDirections.Request.transportType = .cycling` is a real, supported developer API.
— `developer.apple.com/documentation/mapkit/mkdirectionstransporttype/cycling`

Apple Maps uses cycling infrastructure (bike lanes, quiet roads, elevation awareness) when this type is set. Use it first before reaching for a third-party routing service.

---

## Loop Generation Strategy

Apple Maps has no native "generate a N km loop" API. Loop logic belongs in `PlanRouteEngine`.

For a request like **"50 km ride through Laval"**:

1. Treat the target distance as approximate — cyclist-suitable routing matters more than hitting exactly 50 km.
2. If `preferLoop == true` or the user says "and back" / "loop" / "return home", treat it as a round trip where each leg is roughly `targetDistanceKm / 2`.
3. Resolve the destination with `MKLocalSearch`.
4. Compute the **outbound leg** with `MKDirections(.cycling)`: Start → Destination.
5. For the **return leg**, introduce a lateral via point to prevent Apple Maps from reversing the exact same road:
   - Calculate the bearing from Destination back to Start.
   - Offset that bearing ~30° and project a point roughly `targetDistanceKm / 4` away.
   - Compute: Destination → Via Point → Start with `.cycling`.
6. Accept near-matches. Do not over-optimize for exact kilometers.

**Sanity check:** If `routeDistance < targetDistanceKm * 0.5` or `> targetDistanceKm * 1.5` after routing, warn the user and offer to proceed anyway.

**Impossible plan check:** If the resolved destination is already farther than `targetDistanceKm / 2` in straight-line distance, surface a friendly error before even requesting directions.

---

## F-C1 — Core (Ship First)

### New files

| File | Purpose |
|---|---|
| `iPhone/Services/RidePlanIntent+Generable.swift` | `@Generable` structs — the AI output contract |
| `iPhone/Services/PlanAssistantEngine.swift` | Orchestrator: parse → resolve → loop math → route |
| `iPhone/Views/RidePlanAssistantView.swift` | Inline expandable input in Routes tab |
| `iPhone/Views/DisambiguationSheet.swift` | Place picker when `MKLocalSearch` returns >1 result |

### Modified files

| File | Change |
|---|---|
| `RouteLibraryView.swift` | Add `aiAssistantSection` view extension + "AI Planned" section |
| `RouteStore.swift` | Add `aiPlannedRoutes`, `addAIPlannedRoute`, `saveAIPlannedRoute`, `discardAIPlannedRoute` |
| `PlanState.swift` | Add `targetDistanceKm`, `timeLimitMinutes`, `climbingPreference`, `roadPreference` if not present |

### `RidePlanIntent` contract

```swift
import FoundationModels

@Generable
struct DestinationStop {
    @Guide("Place name exactly as the user said it")
    var rawName: String

    @Guide("Category: cafe, restaurant, viewpoint, park, store, home, custom")
    var stopType: StopType

    @Guide("Role in route: waypoint or destination")
    var role: StopRole

    @Guide("Optional stop intent: coffee, lunch, water, quick stop, nil if not stated")
    var intent: String?
}

@Generable
struct RidePlanIntent {
    @Guide("Ordered stops in the order stated")
    var stops: [DestinationStop]

    @Guide("True if the user wants to return to start")
    var preferLoop: Bool

    @Guide("Target distance in km if stated, nil otherwise")
    var targetDistanceKm: Double?

    @Guide("Time limit in minutes if stated, nil otherwise")
    var timeLimitMinutes: Int?

    @Guide("Road preference inferred: any, quiet_roads, bike_paths, mixed. Default mixed.")
    var roadPreference: RoadPreference

    @Guide("Climbing preference inferred: flat, moderate, hilly, mountain. Default moderate.")
    var climbingPreference: ClimbingPreference
}
```

### `PlanAssistantEngine` states

```swift
enum State {
    case idle
    case parsing                              // model running
    case resolving(Int, Int)                  // (resolved, total)
    case disambiguating(String, [MKMapItem], (MKMapItem) -> Void)
    case routing                              // MKDirections running
    case failed(String)
}
```

### Integration in `RouteLibraryView`

Add via a `private extension RouteLibraryView` to minimise changes to the main `body`:

```swift
extension RouteLibraryView {
    @ViewBuilder
    var aiAssistantSection: some View {
        if VeloAI.isAvailable {
            RidePlanAssistantView(
                engine: assistantEngine,
                userLocation: locationManager.lastLocation?.coordinate,
                onRouteReady: { plan in
                    let route = plan.buildRouteModel(name: PlanState.autoName())
                    routeStore.addAIPlannedRoute(route)
                }
            )
        }
    }
}
```

Insert `aiAssistantSection` in the existing `body` with a single line. Nothing else changes in `body`.

---

## F-C2 — Polish (Ship Second)

- **"AI Planned" section:** Temporary top section with Save / Discard / Start actions. One plan at a time (replace on new request).
- **Stop-type icons** in `WaypointListSheet` — icon + colour per `stopType`.
- **Dwell time** per stop intent, total outing estimate in sheet header.
- **F-3 `RideView` split** — extract `RideMapLayer` and `RideHUDPanel` as a move-first commit, then add F-C2 feature changes on top.

---

## F-C3 — Finger Sketch Route (Ship Third)

Inspired by Strava's finger-draw route builder. The user traces a rough path with their finger on the map; the app simplifies the gesture, then snaps each segment to real cycling roads via `MKDirections(.cycling)`.

### Why This Matters

Covers the mental model neither text nor waypoints serve well: *"I want to go roughly this way."* No typing, no precision. Just draw an intent and let Apple Maps find the roads.

### Verified APIs (iOS 17+ / iOS 26)

| Task | API | Source |
|---|---|---|
| Convert finger position to coordinate | `MapProxy.convert(_ point: CGPoint, from: .local) -> CLLocationCoordinate2D?` | `developer.apple.com/documentation/mapkit/mapproxy/convert(_:to:)` |
| Capture drag gesture | `DragGesture` inside `MapReader { proxy in ... }` | SwiftUI standard |
| Live sketch preview | `MapPolyline(coordinates: [CLLocationCoordinate2D])` | Confirmed iOS 26 |
| Snap to cycling roads | `MKDirections.Request` with `.cycling` | Confirmed earlier in this spec |

> ⚠️ `onTapGesture` inside `MapReader` was deprecated in iOS 18. For tap-to-drop-waypoint, use the new `.onTapGesture { screenPoint in proxy.convert(...) }` pattern instead.

### Pipeline

```text
User drags finger across map
  ↓
DragGesture samples raw CGPoints
  ↓
MapProxy.convert(point, from: .local) → [CLLocationCoordinate2D] (raw, ~100-200 pts)
  ↓
Ramer-Douglas-Peucker simplification → 3–8 intent waypoints
  ↓
For each consecutive pair: MKDirections.Request(.cycling)
  ↓
Merge MKRoute.polyline segments → single snapped route
  ↓
MapPolyline preview on map
  ↓
[Use Route]  [Redo]  [Clear]
```

### Ramer-Douglas-Peucker Simplification

Pure Swift, no external dependency. Reduces hundreds of raw touch coordinates to 3–8 meaningful waypoints that capture the shape of the user's intent without over-constraining the cycling directions engine.

Epsilon (tolerance) tuning:
- Too small → too many waypoints → too many `MKDirections` requests → slow and noisy result.
- Too large → too few waypoints → route ignores the shape the user drew.
- Start with ε ≈ 0.001 degrees (~100 m) and tune from device testing.

### New File

| File | Purpose |
|---|---|
| `iPhone/Views/RouteSketchView.swift` | Map + gesture capture + simplification + snapping + preview |

### Modified Files

| File | Change |
|---|---|
| `RouteLibraryView.swift` | Add "Draw Route" entry point alongside "Plan with AI" and "Import GPX" |
| `RouteStore.swift` | Reuse `addAIPlannedRoute` — sketched routes go through the same "AI Planned" temporary section |

### UX Behaviour

```
Routes Tab — top action bar:
[ ✨ Plan with AI ]  [ ✏️ Draw Route ]  [ 📂 Import GPX ]
                          ↓ tap
Full-screen map enters sketch mode
  — Faint crosshair or "draw your route" hint
  — User drags finger
  — Raw path shown as thin dashed blue line in real time
  — On finger lift: simplification runs → MKDirections requests fire
  — Snapped cycling route replaces dashed line
  ── toolbar: [ Use Route ] [ Redo ] [ Clear ] [ Cancel ]
```

### Edge Cases

| Case | Handling |
|---|---|
| Sketch too short (< 2 simplified points) | Show "Draw a longer path" hint, don't fire directions |
| No cycling route found for a leg | Skip that leg, connect remaining segments, warn user |
| Offline | `MKDirections` will fail — show "Snapping needs a connection" |
| Very jagged sketch | RDP simplification smooths this out before directions are requested |

---

## Watch Target

None of the F-C files may be added to the Watch target. `FoundationModels` and `MKDirections` cycling routing are iPhone-only.

---

## Edge Cases (All F-C)

| Case | Handling |
|---|---|
| No Apple Intelligence on device | Hide "Plan with AI" button entirely; Draw Route still works |
| Place not found | Inline error, user can edit and retry |
| Multiple place results | `DisambiguationSheet` |
| No GPS fix | AI Plan button disabled with "Waiting for GPS…" |
| Offline (MKLocalSearch / MKDirections needs network) | Show friendly fallback, point to manual planning |
| Impossible distance (dest > half target) | Friendly error before requesting directions |
| Routed distance far outside target range | Warn user, offer to proceed |
