# VeloGPXNeo — Dev Log
> Active work tracker. Updated each session so the next session can onboard instantly.
> For longer-lived tech debt, see `TECH_DEBT.md`.

---

## Current State — May 2, 2026 (evening)

**Build:** ✅ Clean (iOS 26+, SwiftUI / MapKit / CoreLocation / Supabase / WatchConnectivity)

---

## Recently Landed (this session)

| Commit | What |
|---|---|
| fix(Routes) | Distinct Routes tab icon (`list.bullet.below.rectangle`); Plan swipe/context-menu actions GPX-only |
| fix(PlanView) | SwiftUI overlay buttons replace unreliable native MapKit controls |
| fix(PlanView) | Rounded drawer corners (20 pt), header pinned top, waypoint swipe-delete via `.swipeActions` |
| feat(RideView) | **F-1** All MapPolyline stroke widths doubled across all 5 pairs |
| feat(POI) | **F-2a** Single source of truth — map annotations render from `rideStore.pois` during active ride |
| feat(POI) | **F-2b** Long-press delete on POI annotations: 56pt target, 0.5s, two-step red-highlight → trash, camera pauses 3s |
| feat(POI) | **F-2c** `×` removed from `nextPOIChip` — chip is display-only (icon + distance) |
| feat(POI) | **F-2d** `PreRidePOISheet.swift` added; 📍 button opens *On this route* + *Add nearby* sections |
| feat(POI) | **F-2e** Spur inbound anchor fixed: nearest route track point → POI (not rider position → POI) |
| feat(POI) | **F-2f** Proximity gate: spurs + chip only active ≤500m along-route; approach alert stays at 200m |
| fix(P0) | Duplicate `POISearchService.swift` (root-level copy) removed from project + Build Phases |

---

## In Progress — Next to Code

Nothing currently in flight. Build is clean, all planned session work landed.

---

## Open Bugs

*None blocking build.*

---

## Open Features

| # | Feature | Notes |
|---|---|---|
| F-3 | `RideView` God View split | Extract `RideMapLayer`, `RideHUDPanel`, `RideBirdsEyePanel` — see TECH_DEBT P1 |
| F-4 | `RideSessionStore` God Object split | `RideLocationEngine` + `POITrackingEngine` + `WatchSyncManager` — see TECH_DEBT P1 |

---

## Notes / Watch-outs

- `RideSessionStore.swift` is ~23 KB. P1 God Object split (`RideLocationEngine` + `POITrackingEngine` + `WatchSyncManager`) is overdue — do before adding more features.
- `POIDiscoverySheet` vs `NearbySearchSheet` overlap — no blocker now; worth consolidating before 1.0.
- `RouteStore+POI.swift` is suspiciously thin (866 B) — POI persistence still scattered across call sites in `RideView`. Consolidate before 1.0.
