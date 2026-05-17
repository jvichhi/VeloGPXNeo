# F-D — Draw Route

> Status: **Specced** — not started
> Sprint: 5 (after Sprint 4 stability pass)
> Strava parity feature: finger-draw road-snapped route creation

---

## Summary

The user draws a route by dragging a finger across a full-screen map. The raw gesture trace is
road-snapped in rolling segments via `MKDirections` (`.cycling` profile). The result feeds into
the existing `AIPendingRouteCard` flow (Save / Discard / Start) with a green "DRAWN" badge.
No new downstream infrastructure — only `DrawRouteView` and `DrawRouteEngine` are new.

---

## Entry Point

**Routes tab toolbar** — a `pencil.and.map` button sits to the left of the existing `+` import
button. Tapping it presents `DrawRouteView` as a full-screen sheet.

```swift
// RouteLibraryView toolbar — after F-D
ToolbarItem(placement: .topBarTrailing) {
    HStack(spacing: 4) {
        Button { isDrawRoutePresented = true } label: {
            Image(systemName: "pencil.and.map")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(.tint.opacity(0.12), in: Circle())
        }
        .accessibilityLabel("Draw a route")

        Button { isImporterPresented = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(.tint.opacity(0.12), in: Circle())
        }
    }
}
```

---

## Data Model

### SnappedSegment

```swift
struct SnappedSegment: Sendable {
    let coordinates: [CLLocationCoordinate2D]   // road-snapped polyline points
    let distance: CLLocationDistance            // metres, from MKRoute.distance
    let elevationGain: Double                   // metres, derived from MKRoute.steps
}
```

### DrawRouteEngine (actor)

Owns all mutable draw state. `@Observable` for SwiftUI binding.

```swift
@Observable
actor DrawRouteEngine {
    // Committed road-snapped segments (the undo stack)
    private(set) var segments: [SnappedSegment] = []

    // Raw gesture points for the current open (unsnapped) segment
    private(set) var pendingTrace: [CLLocationCoordinate2D] = []

    // True while a MKDirections request is in-flight
    private(set) var isSnapping: Bool = false

    // Error from the last snap attempt (shown as toast, does not block drawing)
    private(set) var lastSnapError: String? = nil

    // Derived
    var allSnappedCoordinates: [CLLocationCoordinate2D] { segments.flatMap(\.coordinates) }
    var totalDistance: CLLocationDistance { segments.reduce(0) { $0 + $1.distance } }
    var totalElevationGain: Double { segments.reduce(0) { $0 + $1.elevationGain } }
    var canUndo: Bool { !segments.isEmpty }
    var hasContent: Bool { !segments.isEmpty || !pendingTrace.isEmpty }

    func addGesturePoint(_ coordinate: CLLocationCoordinate2D) async { ... }
    func snapPendingSegment(to destination: CLLocationCoordinate2D) async { ... }
    func undoLastSegment() { segments.removeLast() }
    func finaliseTrace() async { ... }   // snap whatever remains in pendingTrace on finger lift
    func reset() { segments = []; pendingTrace = []; isSnapping = false }
}
```

---

## Snap Strategy

### Spatial debounce — primary gate

A snap request fires when the finger has travelled ≥ **180 m** from the last committed snap
anchor. 180 m is a good cycling granularity — fine enough to follow curves, coarse enough to
keep requests rare.

```
lastSnapAnchor ──── 180 m ────► fire MKDirections(lastAnchor → currentPoint)
                                commit SnappedSegment, advance anchor
```

### Temporal debounce — secondary gate

If the finger pauses (< 5 m movement in 300 ms), fire a snap for whatever has accumulated
since the last anchor. This catches short deliberate strokes that never reach 180 m.

### In-flight guard

Only one `MKDirections` request lives at a time. While `isSnapping == true`, accumulate points
into `pendingTrace` but do not fire a new request. When the in-flight request completes, check
if `pendingTrace` has advanced ≥ 180 m from the new anchor and fire immediately if so.

### Segment length cap

Before passing waypoints to `MKDirections`, if the straight-line distance between origin and
destination exceeds **8 km**, insert an intermediate waypoint at the midpoint. `MKDirections`
has undocumented length limits and degrades on very long segments.

### Snap request construction

```swift
let request = MKDirections.Request()
request.source      = MKMapItem(placemark: MKPlacemark(coordinate: origin))
request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
request.transportType = .cycling        // F-D always uses cycling profile
request.requestsAlternateRoutes = false // take first (best) route only

let directions = MKDirections(request: request)
let response   = try await directions.calculate()
// Use response.routes.first
```

### Snap failure handling

If `MKDirections` throws (no road nearby, over water, throttled):
- Silently skip the segment — do not add to stack
- Set `lastSnapError` to a short user-readable string
- `DrawRouteView` shows a 2-second dismissing toast ("Couldn't snap to road — try drawing closer to a path")
- The raw `pendingTrace` is discarded; `lastSnapAnchor` resets to the current finger position
- Drawing continues uninterrupted

---

## Visual Layers (MapKit)

Two simultaneous overlays on the draw canvas map:

| Layer | Type | Appearance | When visible |
|---|---|---|---|
| **Snapped polyline** | `MapPolyline` | Solid blue, strokeWidth 4 | Always (when segments > 0) |
| **Pending trace** | `MapPolyline` | Dashed blue-grey, strokeWidth 2, opacity 0.6 | While finger is down |

While `isSnapping == true`, the pending trace pulses: `opacity` animates between 0.4 and 0.8
on a 0.9 s repeat (`Animation.easeInOut(duration: 0.45).repeatForever(autoreverses: true)`).
Pulsing stops immediately when the snap resolves and the snapped segment appears.

When a snap resolves, the new snapped segment "grows in" along its path using a
`trim(from:to:)` animation on the `MapPolyline` stroke — 0 → 1 over 0.35 s with `.easeOut`.

---

## DrawRouteView Layout

```
┌─────────────────────────────────────┐
│  [✕ Cancel]          [↩ Undo]       │  ← NavigationBar, inline title hidden
│                                     │
│                                     │
│           MAP CANVAS                │  ← Map(.standard), userLocation shown
│      (full screen, no tab bar)      │
│                                     │
│   - - - pending trace - - -         │
│   ————— snapped polyline ————        │
│                                     │
├─────────────────────────────────────┤
│  ● 12.4 km  ↑ 180 m   [snapping…]  │  ← stats pill (hidden until first point)
│  [           Done            ]      │  ← disabled until ≥ 1 snapped segment
└─────────────────────────────────────┘
```

### Cancel behaviour

- Zero segments, no pending trace → dismiss immediately, no alert
- Any content present → `confirmationDialog` ("Discard this route?", destructive "Discard",
  cancel "Keep Drawing") → on confirm: `engine.reset()`, dismiss

### Undo button

- Enabled when `engine.canUndo`
- Disabled (greyed) when stack empty
- Taps trigger `engine.undoLastSegment()` + haptic `.light`
- If undo empties the stack, the Done button disables again

### Done button

- Disabled until `engine.segments.count ≥ 1`
- On tap:
  1. If `pendingTrace` is non-empty, fire a final `snapPendingSegment` and await it
  2. Build a `RouteModel` from `engine.allSnappedCoordinates` (see below)
  3. Call `routeStore.addAIPlannedRoute(route)` — reuses the existing pending card slot
  4. Dismiss the sheet
  5. `AIPendingRouteCard` appears in Routes list with green "DRAWN" pill

---

## RouteModel Construction

```swift
// Inside DrawRouteView on Done
let coordinates = engine.allSnappedCoordinates
let trackPoints = coordinates.map { TrackPoint(coordinate: $0, elevation: nil, timestamp: nil) }

let route = RouteModel(
    name: "Drawn Route",          // user can rename via existing RouteRenameSheet
    trackPoints: trackPoints,
    sourceFormat: .drawn,         // new case — see below
    createdAt: .now
)
```

### New `sourceFormat` case

Add `.drawn` to whatever enum `RouteModel.sourceFormat` uses (`.gpx`, `.geojson`, `.planned`).
`RouteRow` and `PillBadge` treat `.drawn` the same as `.planned` for icon purposes
(`map.fill`) but use `.green` tint and label "DRAWN".

---

## RouteStore Integration

No new methods needed. `DrawRouteView` calls `routeStore.addAIPlannedRoute(route)` — the same
method used by `PlanAssistantEngine`. The `AIPendingRouteCard` then renders with the green pill.

`saveAIPlannedRoute()` and `discardAIPlannedRoute()` are already implemented (F-C2). Zero
changes to `RouteStore`.

---

## Files

### New

| File | Target | Purpose |
|---|---|---|
| `iPhone/Services/DrawRouteEngine.swift` | iPhone | Actor owning segment stack + snap logic |
| `iPhone/Views/DrawRouteView.swift` | iPhone | Full-screen draw canvas sheet |

### Modified

| File | Change |
|---|---|
| `RouteLibraryView.swift` | Add `pencil.and.map` toolbar button + `isDrawRoutePresented` state + `.fullScreenCover` |
| `RouteModel.swift` (or wherever `sourceFormat` lives) | Add `.drawn` case |
| `RouteLibraryView.swift` → `RouteRow` | `.drawn` renders green "DRAWN" pill |

### Not touched

`RouteStore`, `AIPendingRouteCard`, `PlanAssistantEngine`, `RidePlanAssistantView`,
`WaypointListSheet` — all unchanged.

---

## Edge Cases

| Case | Handling |
|---|---|
| User draws over water / no road | Snap fails silently, toast shown, segment skipped |
| Very fast long stroke (> 8 km) | Intermediate waypoint inserted before `MKDirections` call |
| Snap throttled by MapKit | Same as snap failure — toast, skip, continue |
| Undo past empty | Button disabled — not possible |
| Done tapped while snap in-flight | Button shows `ProgressView` spinner, disabled until snap resolves |
| App backgrounded mid-draw | Sheet remains; `pendingTrace` preserved in engine actor; snapping resumes on foreground |
| Finger lifts before 180 m threshold | Temporal debounce (300 ms stillness) fires the snap |
| Route has only 1 snapped segment | Valid — Done enabled, produces a short route |

---

## Accessibility

- Cancel button: `accessibilityLabel("Cancel drawing")`
- Undo button: `accessibilityLabel("Undo last segment")`
- Done button: `accessibilityLabel("Finish and save route")`
- Stats pill: `accessibilityElement(children: .combine)` — reads as "12.4 kilometres, 180 metres elevation gain"
- Map canvas drag gesture: VoiceOver users cannot use drag-to-draw; consider a future waypoint-tap fallback (out of scope for F-D)

---

## Out of Scope (F-D)

- Waypoint-tap mode (drop pins, auto-connect) — future F-D2
- Walking / mixed transport profiles — cycling only
- Elevation profile chart in draw canvas — shown post-save in `RouteDetailView`
- Redo (re-apply undone segment) — not in Strava either; out of scope
- Multi-finger pan while drawing — standard MapKit pan gesture is disabled during active draw stroke; re-enabled on finger lift
