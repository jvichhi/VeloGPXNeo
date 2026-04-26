# VeloGPXNeo — Tech Debt Checkpoint
> Last reviewed: April 26, 2026

---

## 🔴 P0 — Fix Immediately

- [ ] **Duplicate `POISearchService.swift`**
  `iPhone/POISearchService.swift` (root-level) confirmed absent — verify in Xcode project file (.pbxproj)
  that no stale reference remains. Remove from Build Phases if present.

- [ ] **POI toggle uses name-matching instead of ID** — *already fixed*
  `NearbySearchSheet` now uses `deterministicID(for:)` based on coordinate (6 d.p.).
  *(mark complete — already landed)*

---

## 🟡 P1 — Next Sprint

- [x] **Replace `.walking`/`.automobile` routing with `.cycling` (WWDC25)**
  All `MKDirections` calls now route through `CyclingRouteService.shared`.
  Uses `#available(iOS 26.0, *)` to gate `.cycling`; falls back to `.walking` on older OS.

- [ ] **Extract `RideView` into sub-views** (`RideView.swift` is 35 KB)
  Candidates: `RideMapLayer`, `RideHUDPanel`, `RideBirdsEyePanel`.
  Move spur computation into a dedicated `POISpurService`.

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
  Fix: threshold gate (only accumulate deltas > 2 m) or simple Kalman filter.

- [ ] **`PlaceDescriptorService` is not wired to any consumer**
  Wire to `NearbyResultCard` detail view, or delete if feature is cut.

- [x] **`NextPOIBanner.swift` stub deleted**
  Was 856 B, used `MKMapItem` not `POIModel`, superseded by `RideView.nextPOIChip()`.

- [ ] **`RouteNoticeView.swift` — kept, needs wiring**
  Displays `MKDirections` road closure/restriction notices (iOS 26+).
  Wire into `CyclingRouteService` result and surface in `topBanners`.

- [ ] **`POIDiscoverySheet` vs `NearbySearchSheet` — two overlapping sheets**
  Document the pre-ride vs mid-ride split, or merge with a `mode` parameter.

- [ ] **`RouteStore+POI.swift` is suspiciously thin (866 B)**
  Consolidate POI persistence fully into `RouteStore`.

- [ ] **`MKLocalSearch` uses raw string queries — migrate to typed `MKPointOfInterestFilter`**
  Use `.cafe`, `.gasStation`, etc. for more reliable WWDC25 results.

- [ ] **`MapStyle` — expose cycling overlay option (WWDC25)**
  Add a user setting to toggle between standard, hybrid, and cycling-focused style.

---

## 🔵 P3 — Nice to Have

- [x] **Throttle `sendWatchUpdate()` to 1 Hz** — done.

- [x] **Surface routing/rerouting errors to the user**
  `RideSessionStore.lastError: String?` published. `showError()` auto-dismisses after 6s.
  `RideView.topBanners` shows orange dismissible capsule banner. Tap to clear.

- [x] **`MapCameraAnimation` for smooth heading transitions (WWDC25)**
  `updateRidingCamera` now wraps `position` update in `withAnimation(.linear(duration: 0.3))`.

- [ ] **`RideHistoryStore` has no pagination**
  Lazy loading with `SwiftData` or paginated JSON reads.

- [ ] **Hardcoded English strings — not using `LocalizationManager`**
  Run a pass to move all user-visible strings through the localization system.

- [ ] **No unit tests for core logic**
  Add `XCTestCase` coverage for `minimumDistance`, `updateNextPOI`, elevation accumulation, `bearing()`.

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
