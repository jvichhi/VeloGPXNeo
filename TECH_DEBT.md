# VeloGPXNeo — Tech Debt Checkpoint
> Last reviewed: May 2, 2026 (POI overhaul + route line session)

---

## 🔴 P0 — Fix Immediately

- [ ] **Duplicate `POISearchService.swift`**
  `iPhone/POISearchService.swift` (root-level, 1040 B) vs `iPhone/Services/POISearchService.swift` (1078 B).
  Will cause a compiler error or silent shadowing. Delete the root-level copy and verify `.pbxproj`
  Build Phases contain only the `Services/` version.

- [ ] **POI `×` button in `nextPOIChip` is broken / unreachable**
  The `×` on the next-POI chip only shows when a POI is the *next* one AND within 2000 m.
  Any POI further away or already passed has no removal path.
  Additionally the tap target is too small to reliably hit mid-ride.
  **Fix (planned this session):** replace chip `×` with long-press on the map annotation to delete.
  See POI Overhaul plan below.

- [ ] **POI toggle uses name-matching instead of ID**
  `NearbySearchSheet.toggle()` and `isAdded()` match POIs by `name` string.
  Breaks when two POIs share a name (e.g., two "Café" locations).
  Fix: use `deterministicID(for:)` based on coordinate (6 d.p.) or assign a stable `UUID` at creation.
  *(Note: a previous entry marked this "already fixed" — re-verify in current build)*

---

## 🟡 P1 — Next Sprint

### POI Overhaul (planned May 2, 2026)

Full breakdown of issues found and the agreed fix approach:

**Problems identified:**
1. **Two-copy split at ride start** — `start(route:pois:)` copies `routeStore.selectedPOIs` into
   `rideStore.pois`. Map annotations render from `routeStore.selectedPOIs`; tracking runs off
   `rideStore.pois`. These can diverge, making removal unreliable.
2. **No pre-ride POI management** — pre-ride screen has no way to view or remove already-saved POIs.
   The 📍 button only opens search with no inventory of what's pinned.
3. **Spur lines anchor to rider position, not route** — `computeSpurs()` draws from
   `currentCoord → poiCoord`. This creates a live rubber-band line that wiggles as the rider moves,
   rather than showing the static detour geometry from the route to the POI.
4. **Spurs and nextPOI activate too early** — spurs show for any POI within 2 km regardless of
   route position. `nextPOI` fires for POIs up to 5 km away. Both should be proximity-gated
   relative to the *route snap point*, not straight-line distance from rider.
5. **No mid-ride removal path** — only the `nextPOI` chip within 2000 m had an `×`; it was
   too small to tap reliably and permanently deleted from the persisted sidecar (destructive with no undo).
6. **`×` tap broken** — the chip's `.buttonStyle(.plain)` inside a `Capsule` background swallows
   the touch for the inner button; the gesture never reaches the `×`.

**Agreed fix plan:**
- **Single source of truth during ride:** map annotations render from `rideStore.pois` (not `routeStore.selectedPOIs`) once a ride is active.
- **Long-press annotation to delete:** 56 pt tap target on POI annotation. Long-press (0.5 s) shows
  a confirmation overlay anchored to a fixed screen position (not MapKit popover — immune to camera
  panning). Two-step confirm: first press highlights red, second press removes. Camera pauses tracking
  for 3 s on annotation interaction then resumes.
- **Remove chip `×`:** `nextPOIChip` becomes display-only (icon + distance). Deletion is annotation-only.
- **Pre-ride POI sheet:** 📍 button opens sheet with two sections:
  - *On this route* — list of saved POIs with swipe-to-delete
  - *Add nearby* — existing `POIDiscoverySheet` search experience
- **Spur anchor fix:** spur `inbound` line originates from the nearest route track point to the POI,
  not from the rider's live coordinate. Outbound leg unchanged (POI → route snap).
- **Proximity gating:**
  - Spurs only rendered when rider is ≤500 m along-route from the POI's track snap point.
  - `nextPOI` chip only shown when POI is ≤500 m straight-line.
  - Approach alert (haptic + notification) unchanged at 200 m.

- [x] **Replace `.walking`/`.automobile` routing with `.cycling` (WWDC25)**
  All `MKDirections` calls now route through `CyclingRouteService.shared`.
  Uses `#available(iOS 26.0, *)` to gate `.cycling`; falls back to `.walking` on older OS.

- [ ] **Extract `RideView` into sub-views** (`RideView.swift` is ~35 KB — God View)
  Candidates:
  - `RideMapLayer` — map, camera, polylines, annotations
  - `RideHUDPanel` — metric tiles, buttons, elevation strip
  - `RideBirdsEyePanel` — aerial overview layout branch
  Move all `MKDirections` spur calls into a dedicated `POISpurService`.

- [ ] **Split `RideSessionStore` (12 KB God Object)**
  Current responsibilities: `CLLocationManager`, `WCSession`, heading, off-route detection,
  rerouting, POI proximity, breadcrumbs, notifications, history persistence.
  Proposed split:
  - `RideLocationEngine` — CLLocation, heading, breadcrumbs
  - `POITrackingEngine` — proximity, nextPOI, spur requests
  - `WatchSyncManager` — WCSession framing and throttle
  `RideSessionStore` becomes a thin coordinator.

- [x] **Fix `nextPOI` to use on-route ordering, not raw distance**
  POIs projected onto GPX track, sorted by `trackIndex`. Only ahead-of-position POIs considered.

- [x] **Replace manual `Annotation("You", ...)` with `UserAnnotation()`**
  Done. System pulsing blue dot + accuracy ring. iOS 26 location rendering pipeline.

- [x] **`hudHeight` uses `DispatchQueue.asyncAfter` timing hack**
  Replaced with `HUDHeightKey: PreferenceKey`. Height reported via `.preference` in
  `ridingHUDPanel`, consumed via `.onPreferenceChange` in `ridingLayout`.

---

### Route Line Visibility (planned May 2, 2026)

**Problem:** Route polylines are too thin to read at a glance while riding.

**Current values in `RideView.mapLayer`:**

| Polyline | Outline | Fill |
|---|---|---|
| Remaining route | white 9 pt | blue 6 pt |
| Ridden route | white 7 pt | blue/0.45 4 pt |
| Reroute | white 8 pt | orange 5 pt |
| POI spur inbound (next) | — | green 4 pt dashed |
| POI spur outbound (next) | — | red 3.5 pt dashed |

**Fix:** Double all stroke widths:

| Polyline | Outline | Fill |
|---|---|---|
| Remaining route | white 18 pt | blue 12 pt |
| Ridden route | white 14 pt | blue/0.45 8 pt |
| Reroute | white 16 pt | orange 10 pt |
| POI spur inbound (next) | — | green 8 pt dashed |
| POI spur outbound (next) | — | red 7 pt dashed |
| Non-next spurs scale proportionally |

---

## 🟢 P2 — Backlog

- [ ] **Elevation gain has no noise smoothing**
  Raw GPS altitude deltas accumulated on every update. Over-counts due to GPS noise.
  Fix: threshold gate (only accumulate deltas > 2 m) or simple Kalman filter on altitude stream.

- [ ] **`PlaceDescriptorService` (4.1 KB) is not wired to any consumer**
  No visible call site in `RideView`, `NearbySearchSheet`, or any sheet.
  Intended for AI-powered place summaries. Wire to `NearbyResultCard` detail view, or delete.

- [x] **`NextPOIBanner.swift` stub deleted**
  Was 856 B, used `MKMapItem` not `POIModel`, superseded by `RideView.nextPOIChip()`.

- [ ] **`RouteNoticeView.swift` — kept but unconnected**
  Intended for `MKDirections` road closure/restriction notices (iOS 26+).
  Wire into `CyclingRouteService` result and surface in `topBanners`.

- [ ] **`POIDiscoverySheet` vs `NearbySearchSheet` — two overlapping sheets (8.4 KB / 7.8 KB)**
  No enforced distinction in model or routing — the pre-ride vs mid-ride split could collapse silently.
  Fix: document the intended split clearly, or merge into one sheet with a `mode: .preRide | .midRide` parameter.

- [ ] **`RouteStore+POI.swift` is suspiciously thin (866 B)**
  POI persistence logic is scattered — `routeStore.savePOIs()` called from `RideView`.
  Consolidate POI persistence fully into `RouteStore` or a dedicated `POIPersistenceService`.

- [ ] **`MKLocalSearch` uses raw string queries — migrate to typed `MKPointOfInterestFilter`**
  `POISearchService` sends plain text like `"Café"`. WWDC25 provides typed category constants.
  Use `.cafe`, `.gasStation`, `.restroom` etc. for more reliable, structured results.

- [ ] **`MapStyle` — expose cycling overlay option (WWDC25)**
  Add a user setting to toggle between `.standard`, `.hybrid(elevation: .realistic)`,
  and a cycling-focused style with lane overlays.

- [ ] **Two `.onAppear` blocks in `RideView`**
  ```swift
  .onAppear { rideStore.prepare() ... }
  .onAppear { rideStore.setHistoryStore(historyStore) }
  ```
  Both fire but ordering is fragile. Merge into one `.onAppear` block.

---

## 🔵 P3 — Nice to Have

- [x] **Throttle `sendWatchUpdate()` to 1 Hz** — done.

- [x] **Surface routing/rerouting errors to the user**
  `RideSessionStore.lastError: String?` published. `showError()` auto-dismisses after 6s.
  `RideView.topBanners` shows orange dismissible capsule banner. Tap to clear.

- [x] **`MapCameraAnimation` for smooth heading transitions (WWDC25)**
  `updateRidingCamera` now wraps `position` update in `withAnimation(.linear(duration: 0.3))`.

- [ ] **`RideHistoryStore` has no pagination**
  All history items loaded at once. Slow for users with many rides.
  Fix: lazy loading with `SwiftData` or paginated JSON file reads.

- [ ] **Hardcoded English strings — not using `LocalizationManager`**
  `"Start Ride"`, `"Off Route"`, `"End Ride"` etc. hardcoded in `RideView`, `NearbySearchSheet`, `RideSummaryView`.
  Run a pass to move all user-visible strings through the localization system.

- [ ] **No unit tests for core logic**
  Zero test coverage for: `minimumDistance`, `updateNextPOI` ordering,
  elevation accumulation noise, `bearing()` function.
  Add `XCTestCase` tests for these as highest-risk logic paths.

---

## ✅ Completed

| Item | Resolved |
|---|---|
| All routing uses `.cycling` via `CyclingRouteService` (iOS 26+) | Apr 26, 2026 |
| `nextPOI` uses on-route track index ordering | Apr 26, 2026 |
| `sendWatchUpdate()` throttled to 1 Hz | Apr 26, 2026 |
| Two `.onAppear` blocks merged into one | Apr 26, 2026 |
| POI toggle uses coordinate-based deterministic ID | Apr 26, 2026 |
| `UserAnnotation()` replaces manual blue dot | Apr 26, 2026 |
| `HUDHeightKey` PreferenceKey replaces `asyncAfter` hack | Apr 26, 2026 |
| Error surfacing via `lastError` + dismissible HUD banner | Apr 26, 2026 |
| `MapCameraAnimation` for smooth camera transitions | Apr 26, 2026 |
| `NextPOIBanner.swift` stub deleted | Apr 26, 2026 |
| POI overhaul + route line plan documented | May 2, 2026 |
