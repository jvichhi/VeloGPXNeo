# VeloGPXNeo — Dev Log
> Active work tracker. Updated each session so the next session can onboard instantly.
> For longer-lived tech debt, see `TECH_DEBT.md`.

---

## Current State — May 1, 2026

**Build:** ✅ Clean (iOS 26+, SwiftUI / MapKit / CoreLocation / Supabase / WatchConnectivity)

---

## Recently Landed (this session)

| Commit | What |
|---|---|
| `d94d20f` | `NearbySearchSheet.swift` — replaced `\u00e9` unicode escapes with literal `é`; also cleaned up `\u{2026}` in ProgressView |
| `dd2da15` | Deleted `RouteStore+POI.swift` — duplicate `savePOIs()` redeclaration; canonical impl lives in `RouteStore.swift` |
| `e4ac4ad` | `RideSummary` — added `Identifiable` conformance so `sheet(item:)` compiles |

### Fixes that landed before this session (on `main`)
- `POIDiscoverySheet(route: route)` — missing `route` arg passed at both call sites
- `RideSessionStore` injected as `@StateObject` + `.environmentObject(rideStore)` in `VeloGPXApp` — was causing launch crash
- Start Ride `.disabled` guard removed — replaced with "Waiting for GPS…" caption
- Background GPS battery drain — `allowsBackgroundLocationUpdates` only `true` during active ride; `pausesLocationUpdatesAutomatically` restored to `true` when idle
- `RouteStore.savePOIs()` + `loadPOIs(forRoute:)` + `poisStorageURL(for:)` implemented — POIs now persisted to a sidecar JSON file keyed to route UUID
- `NearbySearchSheet.load()` guards against `(0,0)` / invalid coordinate (Bug 2 fix already in file)

---

## Open Bugs

### 🐛 Bug 3 — Elevation gain noise (P2)
- **File:** `iPhone/Stores/RideSessionStore.swift` — `locationManager(_:didUpdateLocations:)`
- **Problem:** Every GPS altitude delta, no matter how small, accumulates into `elevationGain`/`elevationLoss`. GPS/barometric jitter (±1–3 m) inflates both figures significantly on long flat rides.
- **Fix:** Gate accumulation behind `abs(elevationDelta) > 2.0` threshold. Optionally smooth altitude with a rolling average of last 3–5 readings.
- **Also tracked in:** `TECH_DEBT.md` → P2 "Elevation gain has no noise smoothing"

---

## Planned Features

### ✨ Feature 1 — Ride Pause / Resume  *(Priority: HIGH)*
**Motivation:** No way to pause at a café mid-ride without ending the session. Core use-case given the POI system.

**Files to touch:**
- `Shared/Models/RideState` — add `isPaused: Bool`, `pausedDuration: TimeInterval`
- `iPhone/Stores/RideSessionStore.swift` — add `pause()` / `resume()` methods
  - `pause()`: stop location updates, disable background GPS, freeze elapsed timer, keep `isActive = true`
  - `resume()`: re-enable GPS + background updates, restart timer from offset
- `iPhone/Views/RideView.swift` — End button becomes Pause → confirm-End two-step; chips row updates
- `iPhone/Views/RideSummaryView.swift` — display moving time (elapsed − pausedDuration) vs total elapsed

**Suggested branch:** `feature/ride-pause-resume`

---

### ✨ Feature 2 — Grade % HUD Tile  *(Priority: MEDIUM — additive, low risk)*
**Motivation:** Current HUD shows Distance · Speed · Time · Remaining. A live gradient % tile is immediately useful on hilly routes.

**Files to touch:**
- `iPhone/Stores/RideSessionStore.swift` — add `@Published var currentGrade: Double = 0`; compute from last ~50 m of breadcrumbs vs altitude delta; smooth over last 3 pairs
- `iPhone/Views/RideView.swift` — add grade tile to `metricsHUD`; colour-code: grey (<2%), green (2–5%), amber (5–8%), red (>8%)
- Formula: `grade = (Δaltitude / Δdistance) × 100`

**Suggested branch:** `feature/grade-hud-tile`

---

## Suggested Next Branch Order

```
main
  └── fix/elevation-noise-threshold      (2-line change, ship fast)
  └── feature/ride-pause-resume          (biggest, most impactful)
  └── feature/grade-hud-tile             (self-contained, can run parallel)
```

---

## Notes / Watch-outs

- `TECH_DEBT.md` P0: **Duplicate `POISearchService.swift`** — root-level copy vs `iPhone/Services/` copy. Verify only the `Services/` version is in Build Phases before next TestFlight build.
- `TECH_DEBT.md` P2: `POIDiscoverySheet` vs `NearbySearchSheet` overlap — no blocker now but worth consolidating before 1.0.
- `RideSessionStore.swift` is ~17 KB. Pause/Resume feature will add more — keep the P1 God Object split (`RideLocationEngine` + `POITrackingEngine` + `WatchSyncManager`) in mind as a follow-up after features land.
