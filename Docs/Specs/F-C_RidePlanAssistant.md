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

## Watch Target

None of the F-C files may be added to the Watch target. `FoundationModels` and `MKDirections` cycling routing are iPhone-only.

---

## Edge Cases

| Case | Handling |
|---|---|
| No Apple Intelligence on device | Hide "Plan with AI" button entirely |
| Place not found | Inline error, user can edit and retry |
| Multiple place results | `DisambiguationSheet` |
| No GPS fix | Button disabled with "Waiting for GPS…" |
| Offline (MKLocalSearch needs network) | Show friendly fallback, point to manual planning |
| Impossible distance (dest > half target) | Friendly error before requesting directions |
| Routed distance far outside target range | Warn user, offer to proceed |
