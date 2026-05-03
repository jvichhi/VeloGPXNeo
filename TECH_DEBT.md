# VeloGPXNeo — Tech Debt Checkpoint
> Last reviewed: May 2, 2026 (F-1 route line + F-2 POI overhaul + P0 duplicate resolved)

---

## 🔴 P0 — Fix Immediately

- [x] **Duplicate `POISearchService.swift`** — ✅ Resolved May 2, 2026
  Root-level copy (`iPhone/POISearchService.swift`, 1040 B) removed from project and Build Phases.
  Only `iPhone/Services/POISearchService.swift` (1078 B) remains.

- [x] **POI `×` button in `nextPOIChip` is broken / unreachable** — ✅ Resolved May 2, 2026
  Chip `×` removed entirely. `nextPOIChip` is now display-only (icon + distance).
  Deletion replaced by long-press on map annotation (see F-2b).

- [ ] **POI toggle uses name-matching instead of ID**
  `NearbySearchSheet.toggle()` and `isAdded()` match POIs by `name` string.
  Breaks when two POIs share a name (e.g., two “Café” locations).
  Fix: use `deterministicID(for:)` based on coordinate (6 d.p.) or assign a stable `UUID` at creation.
  *(Note: a previous entry marked this “already fixed” — re-verify in current build)*

---

## 🟡 P1 — Next Sprint

### POI Overhaul — ✅ Landed May 2, 2026

| Sub-item | Status |
|---|---|
| F-2a Single source of truth (`rideStore.pois` during ride) | ✅ Done |
| F-2b Long-press annotation delete (56pt, 0.5s, two-step, camera pause 3s) | ✅ Done |
| F-2c `×` removed from `nextPOIChip` — display-only chip | ✅ Done |
| F-2d `PreRidePOISheet` — 📍 button, *On this route* + *Add nearby* | ✅ Done |
| F-2e Spur inbound anchor: nearest route track point → POI | ✅ Done |
| F-2f Proximity gate: ≤500m along-route for spurs + chip; 200m approach alert unchanged | ✅ Done |

**Remaining POI follow-ups (not blocking):**
- `POIDiscoverySheet` vs `NearbySearchSheet` — no enforced distinction in model or routing. Worth merging into one sheet with a `mode: .preRide | .midRide` parameter before 1.0.
- `RouteStore+POI.swift` is suspiciously thin (866 B) — POI persistence logic is scattered (`routeStore.savePOIs()` called from `RideView`). Consolidate fully into `RouteStore` or a dedicated `POIPersistenceService`.

---

### Route Line Visibility — ✅ Landed May 2, 2026

All `MapPolyline` stroke widths in `RideView.mapLayer` doubled:

| Polyline | Outline | Fill |
|---|---|---|
| Remaining route | white 18 pt | blue 12 pt |
| Ridden route | white 14 pt | blue/0.45 8 pt |
| Reroute | white 16 pt | orange 10 pt |
| POI spur inbound (next) | — | green 8 pt dashed |
| POI spur outbound (next) | — | red 7 pt dashed |
| Non-next spurs scale proportionally (5 pt green / 4 pt red) | | |

---

- [x] **Replace `.walking`/`.automobile` routing with `.cycling` (WWDC25)**
  All `MKDirections` calls now route through `CyclingRouteService.shared`.
  Uses `#available(iOS 26.0, *)` to gate `.cycling`; falls back to `.walking` on older OS.

- [ ] **Extract `RideView` into sub-views** (`RideView.swift` is ~30 KB — God View)
  Candidates:
  - `RideMapLayer` — map, camera, polylines, annotations
  - `RideHUDPanel` — metric tiles, buttons, elevation strip
  - `RideBirdsEyePanel` — aerial overview layout branch
  Move all MKDirections spur calls into a dedicated `POISpurService`.

- [ ] **Split `RideSessionStore` (~23 KB God Object)**
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
| **F-1** All MapPolyline stroke widths doubled (5 pairs) | May 2, 2026 |
| **F-2a–f** Full POI overhaul landed | May 2, 2026 |
| **P0** Duplicate `POISearchService.swift` root copy removed | May 2, 2026 |
| **P0** `nextPOIChip` `×` removed; long-press annotation delete replaces it | May 2, 2026 |
