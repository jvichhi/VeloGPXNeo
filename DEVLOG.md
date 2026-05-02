# VeloGPXNeo — Dev Log
> Active work tracker. Updated each session so the next session can onboard instantly.
> For longer-lived tech debt, see `TECH_DEBT.md`.

---

## Current State — May 2, 2026

**Build:** ✅ Clean (iOS 26+, SwiftUI / MapKit / CoreLocation / Supabase / WatchConnectivity)

---

## Recently Landed (this session)

| Commit | What |
|---|---|
| pause/resume | `RideSessionStore` — `pause()` / `resume()` / `movingTime` / `pausedDuration`; GPS gated off during pause |
| pause/resume | `RideView` — ⏸ Pause ↔ ▶ Resume capsule + PAUSED banner above chips row |
| pause/resume | `RideSummaryView` — TIME tile → MOVING (shows `movingTime`); elapsed footnote when `hadPauses == true` |
| grade-hud | `RideSessionStore` — `@Published var currentGrade: Double`; `updateGrade()` walks back 50 m of `breadcrumbLocations`, smoothed, clamped ±30% |
| grade-hud | `RideView` — `gradeTile(grade:)` added as 5th HUD column; colour-coded grey/green/amber/red by severity |
| grade-hud | `DEVLOG.md` — marked all completed features/bugs; open list updated |

### Fixes that landed before this session (on `main`)
- `POIDiscoverySheet(route: route)` — missing `route` arg passed at both call sites
- `RideSessionStore` injected as `@StateObject` + `.environmentObject(rideStore)` in `VeloGPXApp` — was causing launch crash
- Start Ride `.disabled` guard removed — replaced with "Waiting for GPS…" caption
- Background GPS battery drain — `allowsBackgroundLocationUpdates` only `true` during active ride; `pausesLocationUpdatesAutomatically` restored to `true` when idle
- `RouteStore.savePOIs()` + `loadPOIs(forRoute:)` + `poisStorageURL(for:)` — POIs persisted to sidecar JSON keyed to route UUID ✅
- `NearbySearchSheet.load()` guards against `(0,0)` / invalid coordinate ✅
- **Elevation noise** — 3-reading rolling `altitudeBuffer` + `smoothedAltitude` + 1.5 m threshold already in `RideSessionStore.locationManager(_:didUpdateLocations:)` ✅

---

## Open Bugs

### 🐛 PlanView Drawer Obscured Behind Tab Bar
**Branch:** `fix/planview-drawer-tab-overlap`  
**File:** `iPhone/Views/PlanView.swift`  
**Priority:** P1 — visible on every device

**What's broken:** The Plan Route drawer's bottom content (the "Close Loop" toggle row and the lowest waypoint row) renders behind the system tab bar. The tab bar appears on top of the drawer.

**Root cause:** `PlanView.body` applies `.ignoresSafeArea(edges: .bottom)` to the outer `ZStack`. Inside a `TabView` child, `geo.safeAreaInsets.bottom` only reflects the home indicator (~34 pt) — **not** the tab bar height (~49 pt). The drawer therefore calculates its height and bottom padding without accounting for the ~49 pt tab bar, causing content to bleed underneath it.

`RideView` is unaffected because it presents full-screen outside the `TabView`.

**Fix — Option A (preferred):**
Move `.ignoresSafeArea` off the `ZStack` and onto the `mapLayer` only:

```swift
// BEFORE
ZStack(alignment: .bottom) {
    mapLayer
        .ignoresSafeArea(edges: .top)
    drawerCard(geo: geo).zIndex(10)
}
.ignoresSafeArea(edges: .bottom)  // ← remove

// AFTER
ZStack(alignment: .bottom) {
    mapLayer
        .ignoresSafeArea()         // ← map goes full-bleed top + bottom
    drawerCard(geo: geo).zIndex(10)
}
// ZStack now respects tab bar safe area — drawer stops above tab bar automatically
```

Also update `maxDrawer` in `drawerCard(geo:)`:
```swift
// BEFORE
let safeBottom = geo.safeAreaInsets.bottom
let maxDrawer  = geo.size.height - safeBottom - 60

// AFTER (geo.size.height now excludes tab bar after safe area fix)
let maxDrawer = geo.size.height - 60
```

**Fix — Option B (fallback):** Read actual tab bar height via `UITabBarController` and add it to the `drawerCard` bottom padding. More brittle; use only if full-bleed-behind-tab-bar is a hard design requirement.

**Also audit:** `WaypointListSheet.swift` — confirm it doesn't add its own bottom safe area padding that would double-pad after the fix.

**Acceptance criteria:**
- [ ] "Close Loop" toggle fully visible above tab bar at `kDrawerMedium` on SE / 14 Pro / 15 Pro Max
- [ ] Map still full-bleed behind status bar at the top
- [ ] Map extends to screen bottom edge (visible behind tab bar when drawer at `kDrawerPeek`)
- [ ] Drag-to-snap still works at all three snap heights
- [ ] Error banner positioning unchanged
- [ ] No overflow on iPhone SE (667 pt screen)

---

## Open Features

> None currently. All planned features are implemented. ✅

---

## Notes / Watch-outs

- `TECH_DEBT.md` P0: **Duplicate `POISearchService.swift`** — root-level copy vs `iPhone/Services/` copy. Verify only the `Services/` version is in Build Phases before next TestFlight build.
- `TECH_DEBT.md` P2: `POIDiscoverySheet` vs `NearbySearchSheet` overlap — no blocker now but worth consolidating before 1.0.
- `RideSessionStore.swift` now ~19 KB. The P1 God Object split (`RideLocationEngine` + `POITrackingEngine` + `WatchSyncManager`) is overdue — worth doing before adding any more features.
- `breadcrumbs` array renamed to `breadcrumbLocations: [CLLocation]` in this session (retains altitude per point for grade computation). `stopAndBuildSummary()` now maps to `[CLLocationCoordinate2D]` when building the summary.
