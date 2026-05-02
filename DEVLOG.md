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
| planview-tab-overlap | `PlanView` — moved `.ignoresSafeArea()` from `ZStack` to `mapLayer` only; removed `safeBottom` from `maxDrawer` calc; drawer now stops naturally above tab bar, matching `RideView` pattern exactly |
| pause/resume | `RideSessionStore` — `pause()` / `resume()` / `movingTime` / `pausedDuration`; GPS gated off during pause |
| pause/resume | `RideView` — ⏸ Pause ↔ ▶ Resume capsule + PAUSED banner above chips row |
| pause/resume | `RideSummaryView` — TIME tile → MOVING (shows `movingTime`); elapsed footnote when `hadPauses == true` |
| grade-hud | `RideSessionStore` — `@Published var currentGrade: Double`; `updateGrade()` walks back 50 m of `breadcrumbLocations`, smoothed, clamped ±30% |
| grade-hud | `RideView` — `gradeTile(grade:)` added as 5th HUD column; colour-coded grey/green/amber/red by severity |

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

> None currently. All identified bugs are resolved. ✅

---

## Open Features

> None currently. All planned features are implemented. ✅

---

## Notes / Watch-outs

- `TECH_DEBT.md` P0: **Duplicate `POISearchService.swift`** — root-level copy vs `iPhone/Services/` copy. Verify only the `Services/` version is in Build Phases before next TestFlight build.
- `TECH_DEBT.md` P2: `POIDiscoverySheet` vs `NearbySearchSheet` overlap — no blocker now but worth consolidating before 1.0.
- `RideSessionStore.swift` now ~19 KB. The P1 God Object split (`RideLocationEngine` + `POITrackingEngine` + `WatchSyncManager`) is overdue — worth doing before adding any more features.
- `breadcrumbs` array renamed to `breadcrumbLocations: [CLLocation]` in this session (retains altitude per point for grade computation). `stopAndBuildSummary()` now maps to `[CLLocationCoordinate2D]` when building the summary.
