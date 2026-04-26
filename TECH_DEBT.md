# VeloGPXNeo — Tech Debt Checkpoint
> Last reviewed: April 26, 2026

---

## 🔴 P0 — Fix Immediately

- [ ] **Duplicate `POISearchService.swift`**
  `iPhone/POISearchService.swift` (1040 B) and `iPhone/Services/POISearchService.swift` (1078 B) both exist.
  This will cause a compiler error or silent shadowing. Delete the root-level duplicate.

- [ ] **POI toggle uses name-matching instead of ID**
  `NearbySearchSheet.toggle()` and `isAdded()` match POIs by `name` string.
  Two POIs sharing a name (e.g. two "Café" stops) will collide.
  Fix: use coordinate fingerprint or assign/store a stable `UUID` at creation time.

---

## 🟡 P1 — Next Sprint

- [x] **Replace `.walking`/`.automobile` routing with `.cycling` (WWDC25)**
  All `MKDirections` calls now route through `CyclingRouteService.shared`.
  Uses `#available(iOS 26.0, *)` to gate `.cycling`; falls back to `.walking` on older OS.
  Affected: `RideView.fetchSpurCoordinates`, `RideView.shortestRouteBackToGPX`, `RideSessionStore.requestReroute`.

- [ ] **Extract `RideView` into sub-views** (`RideView.swift` is 35 KB)
  Candidates: `RideMapLayer`, `RideHUDPanel`, `RideBirdsEyePanel`.
  Move spur computation into a dedicated `POISpurService`.

- [ ] **Fix `nextPOI` to use on-route ordering, not raw distance** ✅ done in `RideSessionStore`
  POIs are now projected onto the GPX track and sorted by `trackIndex`.
  Only POIs ahead of `nearestTrackIndex` are considered.
  *(mark complete — already landed)*

- [ ] **Replace manual `Annotation("You", ...)` with `UserAnnotation()`**
  Current: custom blue circle drawn in `mapLayer()`.
  Fix: use `UserAnnotation()` for the system pulsing dot + accuracy ring,
  which participates in the improved WWDC25 location rendering pipeline.

- [ ] **`hudHeight` uses `DispatchQueue.asyncAfter` timing hack**
  Two `.onChange` handlers use `asyncAfter(deadline: .now() + 0.05)` to capture geometry.
  Fix: replace with a `PreferenceKey`-based height propagation or stable `onSizeChange`.

---

## 🟢 P2 — Backlog

- [ ] **Elevation gain has no noise smoothing**
  Raw GPS altitude deltas are accumulated on every update, over-counting due to GPS noise.
  Fix: add a threshold gate (only accumulate deltas > 2 m) or a simple Kalman filter.

- [ ] **`PlaceDescriptorService` is not wired to any consumer**
  The 4.1 KB service generates place descriptions but has no call site.
  Wire to `NearbyResultCard` detail view, or delete it if the feature is cut.

- [ ] **`NextPOIBanner.swift` is a near-empty stub (856 B)**
  The chip logic is inlined in `RideView.nextPOIChip()`.
  Either delete `NextPOIBanner.swift` or fully migrate the chip into it.

- [ ] **`RouteNoticeView.swift` appears vestigial (1154 B)**
  No visible integration point in `RideView`; likely superseded by the inline `offRouteChip`.
  Audit usages and delete if unused.

- [ ] **`POIDiscoverySheet` vs `NearbySearchSheet` — two overlapping sheets**
  Distinction between pre-ride discovery and mid-ride search is not enforced in the model.
  Document the intended split clearly, or merge into one sheet with a `mode` parameter.

- [ ] **`RouteStore+POI.swift` is suspiciously thin (866 B)**
  POI persistence is scattered; `routeStore.savePOIs()` is called from `RideView`.
  Consolidate POI persistence fully into `RouteStore` or flesh out the extension.

- [ ] **`MKLocalSearch` uses raw string queries — migrate to typed `MKPointOfInterestFilter`**
  `POISearchService` searches with plain strings like `"Café"`.
  WWDC25 improved `MKPointOfInterestFilter` with typed category constants.
  Fix: use `.cafe`, `.gasStation`, etc. for more reliable results.

- [ ] **`MapStyle` — expose cycling overlay option (WWDC25)**
  Currently hardcoded to `.standard(elevation: .realistic)`.
  Add a user setting to toggle between standard, hybrid, and the new cycling-focused style.

- [ ] **`MapCameraAnimation` not used for heading updates (WWDC25)**
  `updateRidingCamera` sets position directly.
  Wrap in `withAnimation` using `MapCameraAnimation` curve control for smoother heading transitions.

---

## 🔵 P3 — Nice to Have

- [x] **Throttle `sendWatchUpdate()` to 1 Hz**
  Previously encoded `WatchRideSummary` on every GPS ping.
  Fixed: gated behind `watchUpdateInterval = 1.0` in `RideSessionStore`. *(already landed)*

- [ ] **Surface routing/rerouting errors to the user**
  Every `catch {}` is silent. Users see nothing when spur routing or rerouting fails.
  Fix: add `@Published var lastError: String?` to `RideSessionStore` and show a dismissible HUD banner.

- [ ] **`RideHistoryStore` has no pagination**
  `RideHistoryView` loads all history at once.
  Fix: lazy loading with `SwiftData` or paginated JSON file reads.

- [ ] **Hardcoded English strings — not using `LocalizationManager`**
  `LocalizationManager` exists but user-visible strings in `RideView`, `NearbySearchSheet`,
  and `RideSummaryView` are hardcoded English.
  Fix: run a pass to move all strings through the localization system.

- [ ] **No unit tests for core logic**
  `Tests/` exists but has no coverage for `minimumDistance`, `updateNextPOI` ordering,
  elevation accumulation, or `bearing()`.
  Add `XCTestCase` tests for these as a baseline.

- [ ] **Two `.onAppear` modifiers in `RideView`**
  Fragile ordering; both fire on appear.
  *(Already merged in current code — verify and close if done.)*

---

## ✅ Completed

| Item | Resolved |
|---|---|
| All routing uses `.cycling` via `CyclingRouteService` (iOS 26+) | Apr 26, 2026 |
| `nextPOI` uses on-route track index ordering | Apr 26, 2026 |
| `sendWatchUpdate()` throttled to 1 Hz | Apr 26, 2026 |
| Two `.onAppear` blocks merged into one | Apr 26, 2026 |
