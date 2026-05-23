# F-D — Draw Route

> Status: **Shipped (core)** — Sprint 5
> Remaining: inline route naming on Done (currently hardcodes `"Drawn Route"`)
> Strava parity feature: finger-draw road-snapped route creation

---

## Summary

The user draws a route by dragging a finger across a full-screen map. The raw gesture trace is
road-snapped in rolling segments via `MKDirections` (`.cycling` profile). The result feeds into
the existing `AIPendingRouteCard` flow (Save / Discard / Start) with a teal "DRAWN" badge.
No new downstream infrastructure — only `DrawRouteView` and `DrawRouteEngine` are new.

---

## Entry Point (F-D3 — shipped May 23)

**Plan tab → empty prompt** — a "Draw Route" row appears in `WaypointListSheet.emptyPrompt`
below "Plan with AI". Tapping it presents `DrawRouteView` as a `.sheet`.

This matches Strava's UX model: route creation lives in the map/planning context, not
alongside the saved route library.

```swift
// WaypointListSheet emptyPrompt — F-D3
Button { showDrawRoute = true } label: {
    HStack(spacing: 8) {
        Image(systemName: "pencil.and.map").foregroundStyle(.teal)
        Text("Draw Route").foregroundStyle(.teal)
        Spacer()
        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
    }
}
```

The `showDrawRoute: Bool` binding is owned by `PlanView` and threaded down to `WaypointListSheet`.
`PlanView` presents `DrawRouteView` via `.sheet(isPresented: $showDrawRoute)`.

> **Previous entry point (removed F-D3):** `RouteLibraryView` toolbar `pencil.and.map` button.
> Removed because it placed route *creation* next to route *management*, not where users are
> already thinking about the map.

---

## Pan / Draw Mode Toggle (F-D4 — shipped May 23)

`DrawRouteView` has two modes:

| Mode | Toolbar icon | Map behaviour | Gesture |
|---|---|---|---|
| **Pan** (default) | `pencil.circle` (outline) | Normal pan + zoom | `Map` receives all touches |
| **Draw** | `pencil.circle.fill` (filled blue) | Frozen | `DragGesture` → `DrawRouteEngine` |

### Why pan is the default

If every drag draws, there is no way to navigate to the area of interest before starting.
Defaulting to pan matches Strava's model and prevents the most common new-user confusion
("why is my map moving everywhere when I draw?").

### Implementation

The `DragGesture` lives inside a `Color.clear` overlay that **only exists when `isDrawMode == true`**:

```swift
.overlay {
    if isDrawMode {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .local)
                    .onChanged { value in
                        guard let coord = proxy.convert(value.location, from: .local) else { return }
                        engine.addGesturePoint(lat: coord.latitude, lon: coord.longitude)
                    }
                    .onEnded { _ in Task { await engine.finaliseTrace() } }
            )
    }
}
```

**Why `Color.clear` overlay, not `.simultaneousGesture`:**
`simultaneousGesture` fires both the map's internal pan recogniser and the `DragGesture`
simultaneously — the map pans while coordinates are collected, producing garbage geometry.
The `Color.clear` overlay with `.contentShape(Rectangle())` intercepts all touches when
present. When absent (pan mode), `Map` receives touches normally.

### Visual feedback

- **Toolbar button** fills to `pencil.circle.fill` in blue when draw mode is active.
- **"Draw Mode" pill** appears at the top of the map canvas (non-interactive) while drawing.
- **Hint label** shown in empty-state bottom bar: "Tap the pencil to start drawing".
- **Haptic** (`.medium`) fires on every mode toggle.

---

## Data Model

### SnappedSegment

```swift
struct SnappedSegment: Sendable {
    let latitudes: [Double]          // raw doubles — CLLocationCoordinate2D is @MainActor on iOS 26+
    let longitudes: [Double]
    let distance: CLLocationDistance
    let elevationGain: Double

    @MainActor var coordinates: [CLLocationCoordinate2D] { ... }  // for SwiftUI consumption
}
```

> `CLLocationCoordinate2D` is `@MainActor` on iOS 26+, making it non-`Sendable` across actor
> boundaries. `SnappedSegment` stores raw `Double` arrays and exposes a `@MainActor` computed
> property for SwiftUI. This is the iOS 26 strict concurrency pattern.

### DrawRouteEngine

`@Observable final class DrawRouteEngine: @unchecked Sendable`

Owns all mutable draw state. Published properties are read on `@MainActor` via SwiftUI bindings.

```swift
private(set) var segments: [SnappedSegment] = []
private(set) var pendingLats: [Double] = []
private(set) var pendingLons: [Double] = []
private(set) var isSnapping: Bool = false
private(set) var lastSnapError: String? = nil

// Derived (call on @MainActor)
@MainActor var allSnappedCoordinates: [CLLocationCoordinate2D]
@MainActor var pendingCoordinates: [CLLocationCoordinate2D]

func addGesturePoint(lat: Double, lon: Double) async
func finaliseTrace() async
func undoLastSegment()
func reset()
func clearSnapError()
```

---

## Snap Strategy

### Spatial debounce — primary gate

Snap fires when the finger has travelled ≥ **180 m** from the last committed snap anchor.

### Temporal debounce — secondary gate

If the finger pauses (< 5 m movement in **300 ms**), snap whatever has accumulated since the
last anchor. Catches short deliberate strokes that never reach 180 m.

### In-flight guard

Only one `MKDirections` request at a time (`isSnapping` flag). New points accumulate into
`pendingLats/Lons` while a request is in-flight.

### Segment length cap

If straight-line distance origin → destination exceeds **8 km**, insert a midpoint waypoint.

### Snap request

```swift
let request = MKDirections.Request()
request.source      = MKMapItem(location: CLLocation(latitude:..., longitude:...), address: nil)
request.destination = MKMapItem(location: CLLocation(latitude:..., longitude:...), address: nil)
request.transportType = .cycling
request.requestsAlternateRoutes = false
```

> Uses `MKMapItem(location:address:)` — `MKPlacemark` init is deprecated on iOS 26.

### Snap failure

Silently skips segment, sets `lastSnapError` for 2-second toast, advances anchor to current
finger position, continues drawing.

---

## Visual Layers

| Layer | Appearance | When visible |
|---|---|---|
| **Snapped polyline** | Solid blue, lineWidth 4 | When `segments.count > 0` |
| **Pending trace** | Dashed blue, lineWidth 2, opacity 0.4–0.6 | While finger is down |

---

## DrawRouteView Layout

```
┌─────────────────────────────────────┐
│  [✕ Cancel]  [✏ pencil toggle] [↩]  │  ← NavigationBar
│  ┌──────────────────────────────┐   │
│  │  ✏ Draw Mode — drag to trace │   │  ← blue pill (draw mode only)
│  └──────────────────────────────┘   │
│                                     │
│           MAP CANVAS                │
│      (full screen, no tab bar)      │
│                                     │
├─────────────────────────────────────┤
│  ✏ Tap the pencil to start drawing  │  ← hint (empty + pan mode only)
│  ● 12.4 km  ↑ 180 m  [snapping…]   │  ← stats pill (after first segment)
│  [           Done            ]      │  ← disabled until ≥ 1 snapped segment
└─────────────────────────────────────┘
```

---

## Done → Commit Flow

1. `finaliseTrace()` — snaps any remaining pending trace
2. `commitRoute()` — builds `RouteModel(name: "Drawn Route", sourceFormat: .drawn, ...)`
3. `routeStore.addAIPlannedRoute(route)` — reuses pending card slot
4. Dismiss sheet → `AIPendingRouteCard` appears in Routes list with teal "DRAWN" pill

> **Remaining:** `"Drawn Route"` is hardcoded. Sprint 5 polish: add inline `TextField` before
> commit, or show `RouteRenameSheet` immediately after dismiss.

---

## Files

### New

| File | Target | Purpose |
|---|---|---|
| `iPhone/Services/DrawRouteEngine.swift` | iPhone | `@Observable` class owning segment stack + snap logic |
| `iPhone/Views/DrawRouteView.swift` | iPhone | Full-screen draw canvas sheet with pan/draw toggle |

### Modified

| File | Change |
|---|---|
| `iPhone/Views/PlanView.swift` | `@State showDrawRoute`, binding to `WaypointListSheet`, `.sheet` for `DrawRouteView` |
| `iPhone/Views/WaypointListSheet.swift` | `@Binding showDrawRoute`, Draw Route row in `emptyPrompt` |
| `iPhone/Views/RouteLibraryView.swift` | Removed `pencil.and.map` button + draw sheet (F-D3 entry point move) |
| `Shared/Models/RouteModel.swift` | `.drawn` case on `sourceFormat` enum |
| `iPhone/Views/RouteLibraryView.swift` → `RouteRow` | `.drawn` renders teal "DRAWN" pill |

### Not touched

`RouteStore`, `AIPendingRouteCard`, `PlanAssistantEngine`, `RidePlanAssistantView` — unchanged.

---

## Edge Cases

| Case | Handling |
|---|---|
| Draw over water / no road | Snap fails silently, toast shown, segment skipped |
| Very fast long stroke (> 8 km) | Midpoint waypoint inserted before `MKDirections` call |
| Snap throttled by MapKit | Same as snap failure |
| Undo past empty | Button disabled |
| Done tapped while snap in-flight | ProgressView spinner, button disabled |
| App backgrounded mid-draw | Sheet remains; `pendingLats/Lons` preserved; snapping resumes on foreground |
| Finger lifts before 180 m | Temporal debounce (300 ms) fires snap |
| Pan mode — finger drags | Map pans normally; no points collected |

---

## Accessibility

- Cancel: `accessibilityLabel("Cancel drawing")`
- Mode toggle: `accessibilityLabel("Switch to draw mode")` / `"Switch to pan mode"`
- Undo: `accessibilityLabel("Undo last segment")`
- Done: `accessibilityLabel("Finish and save route")`
- Stats pill: `accessibilityElement(children: .combine)`

---

## Out of Scope (F-D)

- Walking / mixed transport profiles — cycling only
- Elevation profile chart in draw canvas — shown post-save in `RouteDetailView`
- Redo (re-apply undone segment)
- Multi-finger gestures while drawing
