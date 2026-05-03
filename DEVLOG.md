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

---

## In Progress — Next to Code

### 1. Route Line Visibility
**Status:** Planned. Not yet coded.

All `MapPolyline` stroke widths in `RideView.mapLayer` to be doubled:

| Polyline | Current outline / fill | Target outline / fill |
|---|---|---|
| Remaining route | white 9 / blue 6 | white 18 / blue 12 |
| Ridden route | white 7 / blue 4 | white 14 / blue 8 |
| Reroute | white 8 / orange 5 | white 16 / orange 10 |
| Spur inbound (next) | green 4 dashed | green 8 dashed |
| Spur outbound (next) | red 3.5 dashed | red 7 dashed |

---

### 2. POI Overhaul
**Status:** Planned. Not yet coded. Full detail in `TECH_DEBT.md` P1.

**Root causes identified:**
- Two-copy split at ride start: `routeStore.selectedPOIs` → `rideStore.pois`. Map annotations render from `routeStore`, tracking runs off `rideStore`. They can diverge, making mid-ride removal unreliable.
- `×` chip button broken: `.buttonStyle(.plain)` inside `Capsule` swallows the inner button touch — gesture never fires.
- No removal path for POIs that aren’t the next one within 2000 m.
- Spur lines draw from rider’s live GPS position to POI (rubber-band), not from the route track point. Looks wrong and wiggles constantly.
- Spurs + `nextPOI` activate too early — up to 5 km away.
- No pre-ride POI inventory — user can’t see or remove already-saved POIs before starting.

**Agreed implementation plan:**
1. **Single source of truth:** map annotations render from `rideStore.pois` once ride is active.
2. **Long-press to delete:** 56 pt annotation tap target. Long-press (0.5 s) shows fixed-position confirmation overlay (not a MapKit popover — immune to camera pan). Two-step: highlights red on first press, deletes on second. Camera pauses tracking 3 s then resumes.
3. **Chip display-only:** remove `×` from `nextPOIChip`. Chip shows icon + distance only.
4. **Pre-ride POI sheet:** 📍 button opens sheet with two sections — *On this route* (list + swipe-to-delete) and *Add nearby* (existing search).
5. **Spur anchor fix:** spur `inbound` line originates from nearest route track point to POI, not rider position.
6. **Proximity gating:** spurs + chip only activate when rider is ≤500 m (along-route) from POI snap point. Approach alert stays at 200 m straight-line.

---

## Open Bugs

| # | Where | Description |
|---|---|---|
| B-1 | `RideView` | `×` on `nextPOIChip` never fires — `.buttonStyle(.plain)` inside `Capsule` swallows touch. **Fix:** remove `×`, use long-press on annotation instead (POI Overhaul item 2). |

---

## Open Features

| # | Feature | Notes |
|---|---|---|
| F-1 | Route line visibility | Double all stroke widths in `RideView.mapLayer` |
| F-2 | POI overhaul | Full plan above. Touches `RideView`, `RideSessionStore`, `RideSessionStore+Spurs`, `RouteStore` |

---

## Notes / Watch-outs

- `TECH_DEBT.md` P0: **Duplicate `POISearchService.swift`** — root-level copy vs `iPhone/Services/` copy. Remove root-level, verify Build Phases before next TestFlight build.
- `TECH_DEBT.md` P0: `×` chip broken — do not attempt a patch fix; the whole POI removal pattern is being replaced (see F-2).
- `RideSessionStore.swift` is ~23 KB. P1 God Object split (`RideLocationEngine` + `POITrackingEngine` + `WatchSyncManager`) is overdue — do before adding more features.
- `POIDiscoverySheet` vs `NearbySearchSheet` overlap — no blocker now; worth consolidating before 1.0.
