# VeloGPXNeo — Plan Feature Specification
> Authored: April 26, 2026  
> Status: **Specification — Implementation In Progress**

---

## Overview

The Plan feature introduces interactive cycling route creation directly inside VeloGPXNeo. Rather than requiring users to import pre-built GPX files, Plan lets a rider place waypoints on a map, automatically snaps them to real cycling-appropriate roads using `MKCyclingRoute` (iOS 26+ / WWDC25), previews the full route with elevation, and either rides it immediately or saves it to the GPX library.

Key capabilities:
- Tap-to-place waypoints anywhere on the map
- Road-snapped cycling route computed between each consecutive waypoint pair
- **Close the loop** — one-tap to add a final leg back to the start
- Live preview of total distance and elevation gain as waypoints are added
- Save to library (as a named `RouteModel`, persisted to disk) or ride immediately
- Full cycling routing via `CyclingRouteService.shared` (`MKCyclingRoute` on iOS 26+, walking fallback)

---

## Navigation Architecture

### Current Tab Structure (before Plan)
```
Routes | Ride | My Rides | Settings
```

### New Tab Structure
```
Routes | Plan | Ride | My Rides | Settings
```

`Plan` is inserted as the second tab. The **Ride** tab behaviour is unchanged — it still reads `routeStore.selectedRoute`. Plan can populate that same `selectedRoute` by either:
1. Tapping **"Ride Now"** — sets `routeStore.selectedRoute` then switches to the Ride tab
2. Tapping **"Save to Library"** — persists the route, user selects it from Routes tab normally

### `RootView.swift` change
Add a `PlanView()` tab between `RouteLibraryView` and `RideView`:

```swift
PlanView()
    .tabItem { Label("Plan", systemImage: "map.fill") }
    .tag(Tab.plan)
```

---

## File Structure

All new files go under `iPhone/`. No new folders needed — they slot into existing groups.

```
iPhone/
├── Views/
│   ├── PlanView.swift              ← NEW  Main Plan tab container
│   ├── PlanMapView.swift           ← NEW  Map with tap-to-place + polyline overlay
│   └── WaypointListSheet.swift     ← NEW  Draggable bottom sheet listing waypoints
├── Services/
│   └── PlanRouteEngine.swift       ← NEW  Chains CyclingRouteService between waypoints
└── Models/
    └── PlanState.swift             ← NEW  ObservableObject holding plan session state
```

`CyclingRouteService.swift` and `GPXExporter.swift` are consumed as-is — no changes required.

---

## Data Model — `PlanState`

```swift
// iPhone/Models/PlanState.swift

@MainActor
final class PlanState: ObservableObject {

    // Ordered list of user-placed waypoints
    @Published var waypoints: [PlanWaypoint] = []

    // Stitched polyline segments between consecutive waypoint pairs
    // segments[i] = road-snapped path from waypoints[i] → waypoints[i+1]
    @Published var segments: [PlanSegment] = []

    // Whether a close-loop leg is active (last waypoint → first waypoint)
    @Published var isLoopClosed: Bool = false

    // True while any segment is being computed
    @Published var isRouting: Bool = false

    // Last routing error message (shown as dismissible banner)
    @Published var routingError: String? = nil

    // Derived — total distance of all segments in metres
    var totalDistance: CLLocationDistance { ... }

    // Derived — total elevation gain across all segments
    var totalElevationGain: Double { ... }

    // Derived — full flat coordinate array for MapPolyline rendering
    var fullPolyline: [CLLocationCoordinate2D] { ... }

    // Derived — whether the plan has enough waypoints to be rideable
    var isRideable: Bool { waypoints.count >= 2 && !segments.isEmpty }

    func addWaypoint(_ coord: CLLocationCoordinate2D) { ... }
    func removeWaypoint(id: UUID) { ... }
    func moveWaypoint(fromOffsets: IndexSet, toOffset: Int) { ... }
    func closeLoop() { ... }        // adds/removes the close-loop leg
    func clearAll() { ... }
    func buildRouteModel(name: String) -> RouteModel { ... }
}

struct PlanWaypoint: Identifiable {
    let id: UUID
    var coordinate: CLLocationCoordinate2D
    var name: String?               // optional reverse-geocoded label
}

struct PlanSegment: Identifiable {
    let id: UUID
    let from: UUID                  // PlanWaypoint.id
    let to: UUID                    // PlanWaypoint.id
    let coordinates: [CLLocationCoordinate2D]
    let distance: CLLocationDistance
    let elevationGain: Double
    let isLoop: Bool                // true for the close-loop leg
}
```

---

## Service — `PlanRouteEngine`

`PlanRouteEngine` sits between `PlanState` and `CyclingRouteService`. It is responsible for:

1. Watching `PlanState.waypoints` changes (via `onChange`)
2. Identifying which segments are dirty (new, moved, or deleted endpoints)
3. Firing `CyclingRouteService.shared.calculateRoute(from:to:)` for each dirty pair
4. Writing results back to `PlanState.segments` on the main actor
5. Handling errors gracefully — a failed segment falls back to a straight-line stub so the user isn't blocked

```swift
// iPhone/Services/PlanRouteEngine.swift

@MainActor
final class PlanRouteEngine {

    // Recomputes only the segment(s) affected by the most recent waypoint change.
    // Pass the indices of waypoints that changed — engine derives which segments to refresh.
    func refreshSegments(in state: PlanState, affectedIndices: [Int]) async { ... }

    // Convenience: recompute ALL segments (used after reorder or full clear)
    func recomputeAll(in state: PlanState) async { ... }
}
```

### Segment Chaining Logic

```
waypoints = [A, B, C, D]

Segments computed:
  seg[0]: A → B   (via CyclingRouteService)
  seg[1]: B → C   (via CyclingRouteService)
  seg[2]: C → D   (via CyclingRouteService)

If isLoopClosed:
  seg[3]: D → A   (via CyclingRouteService, isLoop: true)
```

Each `calculateRoute` call is fired concurrently via `withTaskGroup`. Only segments with dirty endpoints are recomputed — unaffected segments are reused from cache.

---

## View — `PlanView`

`PlanView` is the root container for the Plan tab. It owns a `@StateObject private var plan = PlanState()` and a `PlanRouteEngine`.

### Layout

```
┌─────────────────────────────────┐
│  NavigationStack                │
│  ┌───────────────────────────┐  │
│  │  PlanMapView              │  │
│  │  (full screen, edge-edge) │  │
│  │                           │  │
│  │  [Waypoint pins]          │  │
│  │  [Route polyline]         │  │
│  │                           │  │
│  │  ┌─── Top bar ──────────┐ │  │
│  │  │ "Plan Route"  [Clear]│ │  │
│  │  └──────────────────────┘ │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌─── Bottom Sheet ───────────┐ │
│  │  ↕ drag handle             │ │
│  │  Distance · Elevation      │ │
│  │  [WaypointListSheet]       │ │
│  │  [Close Loop toggle]       │ │
│  │  [Save to Library] [Ride]  │ │
│  └────────────────────────────┘ │
└─────────────────────────────────┘
```

### Empty State

When `plan.waypoints.isEmpty`:
- Map shows user's current location centred
- Overlay prompt: **"Tap the map to place your first waypoint"**
- Bottom sheet shows minimal height with just the drag handle and the prompt

### Tap-to-Place

`PlanMapView` wraps `Map` and uses `onTapGesture` on a transparent overlay to capture taps. Tapped coordinate is passed to `plan.addWaypoint(_:)`, which immediately adds a pin and triggers `PlanRouteEngine.refreshSegments(in:affectedIndices:)` for the new trailing segment.

Reverse geocoding runs asynchronously via `ReverseGeocodingService` after placement — waypoint label updates once it resolves (shows coordinate in the meantime).

### Waypoint Pins

Each `PlanWaypoint` renders as a `MapAnnotation`:
- **Start pin**: green filled circle with "S" label
- **Intermediate pins**: numbered dark circles (1, 2, 3…)
- **End pin**: red filled circle with "E" label (or "S/E" when loop is closed)
- Tapping a pin shows a popover: **"Remove"** button

### Route Polyline

`PlanState.fullPolyline` rendered as a single `MapPolyline` in blue. The close-loop segment renders in a slightly lighter blue with a dashed stroke to distinguish it visually.

While routing is in progress (`plan.isRouting == true`), a pulsing opacity animation plays on the polyline.

---

## View — `WaypointListSheet`

Presented as a `presentationDetents([.height(200), .medium, .large])` bottom sheet from `PlanView`.

### Contents

```
Drag handle
────────────────────────────────
 📍 Start (reverse geocoded)          [drag]
 📍 2 · Somewhere Ave               [drag]
 📍 3 · Another Place               [drag]
 📍 End                               [drag]
────────────────────────────────
[↩ Close Loop]  (toggle, shows loop distance when active)
────────────────────────────────
Total: 24.3 km  ↑ 312 m
[Save to Library]    [Ride Now →]
```

- **Reorder**: standard `List` with `.onMove` — triggers `plan.moveWaypoint` + full recompute
- **Delete**: swipe-to-delete on each row — triggers `plan.removeWaypoint` + partial recompute
- **Close Loop**: toggle button — calls `plan.closeLoop()`, displays the extra leg's distance inline
- **Save to Library**: presents a `TextField` alert for the route name, then calls `plan.buildRouteModel(name:)` → `routeStore.addRoute(_:)` → `routeStore.saveToDisk()`
- **Ride Now**: same save (with auto-generated name "Planned Route \(date)") + sets `routeStore.selectedRoute` + switches `TabView` selection to the Ride tab

---

## Close the Loop

Close Loop adds a final `PlanSegment` from the **last waypoint back to the first waypoint**, routed via `CyclingRouteService` just like any other segment.

Behaviour:
- Available as soon as `waypoints.count >= 2`
- Toggle — tapping again removes the loop segment
- Loop segment styled with dashed polyline in `PlanMapView`
- Loop distance shown inline next to the toggle
- Included in `totalDistance` and `totalElevationGain` when active
- `buildRouteModel()` includes all segments including the loop leg

---

## Save → `RouteModel` Conversion

`PlanState.buildRouteModel(name:)` stitches all segment coordinates into `RouteModel.trackPoints` and returns a fully populated model that `RouteStore` can persist and `RideSessionStore` can load directly.

```swift
func buildRouteModel(name: String) -> RouteModel {
    let allCoords = segments.flatMap { $0.coordinates }
    let trackPoints = allCoords.map { coord in
        TrackPoint(coordinate: PersistedCoordinate(coord), elevation: nil)
    }
    return RouteModel(
        id: UUID(),
        name: name,
        trackPoints: trackPoints,
        waypoints: waypoints.map { Waypoint(name: $0.name, coordinate: PersistedCoordinate($0.coordinate)) },
        sourceFormat: .planned          // new enum case — see below
    )
}
```

### `RouteModel.sourceFormat` — new case

Add `.planned` to the existing `SourceFormat` enum so planned routes are visually distinguished in `RouteLibraryView` with a different badge label ("PLANNED" vs "GPX" / "GEOJSON").

---

## `CyclingRouteService` Usage

All routing in `PlanRouteEngine` goes through the existing `CyclingRouteService.shared.calculateRoute(from:to:)`. No new routing code is needed. The service already handles:
- `MKCyclingRoute` on iOS 26+
- `.walking` fallback on older OS
- Error propagation

If a segment fails, `PlanRouteEngine` logs the error and creates a straight-line stub `PlanSegment` so the user sees their waypoints connected and can continue planning. The error is surfaced in `plan.routingError` and shown as a dismissible banner.

---

## `GPXExporter` Integration

`Save to Library` uses `plan.buildRouteModel(name:)` directly — no GPX file write is needed for the in-app library since `RouteStore` persists `RouteModel` as JSON.

An optional **"Export GPX"** action (share sheet) can call `GPXExporter.export(route:)` on the built `RouteModel`. This is a P2 enhancement — not required for initial ship.

---

## Implementation Phases

### Phase 1 — Core (current session)

- [ ] `PlanState.swift` — full model with waypoints, segments, derived properties
- [ ] `PlanRouteEngine.swift` — segment chaining via `CyclingRouteService`
- [ ] `PlanView.swift` — map + bottom sheet shell, tap-to-place, waypoint pins, route polyline
- [ ] `WaypointListSheet.swift` — list, reorder, delete, close-loop toggle, summary bar
- [ ] `RootView.swift` — add Plan tab
- [ ] `RouteModel.sourceFormat` — add `.planned` case
- [ ] `RouteLibraryView` — display "PLANNED" badge for planned routes

### Phase 2 — Polish

- [ ] Reverse geocoding labels on waypoints via `ReverseGeocodingService`
- [ ] Tap-pin popover with "Remove" action
- [ ] Routing progress animation (pulsing polyline while computing)
- [ ] "Export GPX" share sheet action
- [ ] Empty state animation ("Tap to place waypoint" arrow)
- [ ] Undo last waypoint button in top bar

### Phase 3 — Advanced

- [ ] Drag-to-reposition existing waypoint pins on map
- [ ] Elevation profile chart in bottom sheet (matches `RideView` elevation strip style)
- [ ] Suggested waypoints from `POISearchService` (e.g., "add a café stop")
- [ ] Route name suggestions from start/end reverse geocode labels

---

## Open Questions

| Question | Decision |
|---|---|
| Does planned route GPX file get written to disk or only JSON? | JSON only (Phase 1). GPX export is Phase 2 share sheet. |
| Is `PlanState` preserved across app restarts? | No for Phase 1 — plan is ephemeral per session. Phase 2 can add draft persistence. |
| Should close-loop routing avoid re-tracing the outbound path? | Not enforced — MKCyclingRoute chooses. Future: add waypoint to force detour. |
| Tab order: Plan before or after Ride? | Plan is tab 2 (after Routes, before Ride) — plan precedes riding. |

---

## Related Files (do not modify without cross-checking)

| File | Relevance |
|---|---|
| `iPhone/Services/CyclingRouteService.swift` | All routing calls go here — no new routing code |
| `iPhone/Services/ReverseGeocodingService.swift` | Waypoint label resolution |
| `iPhone/Stores/RouteStore.swift` | `addRoute()`, `saveToDisk()`, `selectedRoute` |
| `iPhone/Views/RideView.swift` | Ride tab — reads `routeStore.selectedRoute` |
| `iPhone/Views/RootView.swift` | Tab bar — add Plan tab here |
| `Shared/Models/RouteModel.swift` | Add `.planned` to `sourceFormat` enum |
| `Shared/GPXExporter.swift` | Phase 2 export — no change needed in Phase 1 |
