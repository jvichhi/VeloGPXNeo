# VeloGPXNeo — Tech Debt Checkpoint
> Last reviewed: May 3, 2026 (code review — new bugs, perf, error-handling findings added)

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
  Breaks when two POIs share a name (e.g., two "Café" locations).
  Fix: use `deterministicID(for:)` based on coordinate (6 d.p.) or assign a stable `UUID` at creation.
  *(Note: a previous entry marked this "already fixed" — re-verify in current build)*
  **May 3 review**: Confirmed still present. `POIDiscoverySheet.swift:133` also deduplicates by
  `$0.name == poi.name`. Two different "Starbucks" along a route silently collide.

- [ ] **GPX export produces invalid files on non-US locales**
  `GPXExporter.swift` builds XML via raw string interpolation of `Double` values.
  `poi.coordinate.latitude` uses default locale formatting — on German/French/etc. devices
  `46.5` becomes `46,5` (comma decimal separator), producing invalid GPX.
  Fix: force `en_US_POSIX` locale on the number formatter, or use `String(format: "%f", ...)`.
  Same risk in the `escape()` function — single quotes, carriage returns not handled.

- [ ] **Duplicate `LocalizationManager.swift` — will break builds if both compiled**
  Two independent implementations exist:
  - `Shared/Managers/LocalizationManager.swift` (full-featured, calls deprecated `synchronize()`)
  - `Shared/Localization/LocalizationManager.swift` (cleaner refactor, missing some features)
  Both define `AppLanguage`, `LocalizationManager`, and the `localized` extension on `String`.
  If both are included in the same target the compiler emits "invalid redeclaration" errors.
  Fix: consolidate into one file, pick the best of both, remove the deprecated `synchronize()` call.

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

- [ ] **`.constant()` binding breaks alert dismissal** — `RouteLibraryView.swift:44`
  ```swift
  .alert("VeloGPX", isPresented: .constant(routeStore.lastImportMessage != nil), ...)
  ```
  `.constant()` ignores writes. If the system dismisses the alert (tap outside on iPad, etc.),
  the binding write to `false` is lost and `lastImportMessage` remains non-nil, re-presenting
  the alert immediately. Fix: use a proper `@State` Bool synced bidirectionally.

- [ ] **Watch haptic fires every second while off-route** — `WatchRideStore.swift:26`
  `WKInterfaceDevice.current().play(.notification)` fires on every watch update (up to 1 Hz)
  while `isOffRoute == true`. No guard against repeated alerts — once off-route the watch
  vibrates continuously until the rider returns. Fix: track a `didAlertOffRoute` flag and
  reset it on `isOffRoute → false` transition.

- [ ] **`errorClearTask` not cancelled on deinit** — `RideSessionStore.swift:421`
  The `Task` closure captures `self` strongly via `lastError`. If the store were deallocated
  during the 6-second sleep, the task wakes and accesses a dangling `self`.
  Fix: add `deinit { errorClearTask?.cancel() }`. Same for `elapsedTimer`:
  `deinit { elapsedTimer?.invalidate() }`.

- [ ] **Off-route bearing uses potentially invalid heading** — `RideView.swift:369`
  `rideState.currentHeading` defaults to `0` when heading data is unavailable (device stationary).
  Combined with a non-zero bearing, this produces a misleading direction arrow.
  Fix: guard on heading validity before computing the relative bearing.

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

- [ ] **Two `.onAppear` blocks in `RideView`** *(note: marked completed below but still present — re-verify)*
  ```swift
  .onAppear { rideStore.prepare() ... }
  .onAppear { rideStore.setHistoryStore(historyStore) }
  ```
  Both fire but ordering is fragile. Merge into one `.onAppear` block.

- [ ] **`buildSnapIndexCache` O(N×M) on main thread** — `PreRidePOISheet.swift:102-117`
  For every POI, scans the entire track point array to find the nearest index. With 50 POIs
  and 10,000 track points, that's 500K iterations on the main thread on every appearance.
  Fix: offload scan to a background task, or build a spatial index (k-d tree / grid).

- [ ] **`updateNextPOI` scans all POIs on every location update** — `RideSessionStore.swift:491-551`
  Called from `locationManager(_:didUpdateLocations:)` (~5m granularity). For each POI it
  iterates a range of track points. With 5,000 track points and 20 POIs, each update does up
  to 100K distance calculations on the main actor.
  Fix: pre-compute POI snap indices once when POIs change, then only do indexed lookup.

- [ ] **`elevationSamples` recomputed on every body evaluation** — `RouteDetailView.swift:236-252`
  Computed property iterates all track points every render, including during text field editing
  for renaming. Fix: lazily cache the result, invalidating only when `route.trackPoints` changes.

- [ ] **Empty `catch` blocks swallow errors silently**
  `RideSummaryView.swift:296`, `RideHistoryView.swift:231`, `RideHistoryDetailView.swift:266,346`
  all use `} catch {}` — suppressing failures from `MKMapSnapshotter`, GPX file writing, and
  image rendering. User gets no feedback when export or snapshot fails.
  Fix: at minimum `print()` the error; ideally surface via a published error string / toast.

- [ ] **Notification auth result silently ignored** — `RideSessionStore.swift:92`
  ```swift
  UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
  ```
  If denied, `triggerApproachAlert()` still attempts to add notification requests which silently
  fail. Fix: check `granted` and skip notification attempts when denied.

- [ ] **`FileManager` URL force-unwrap** — `RouteStore.swift:150,161`
  ```swift
  let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
  ```
  In sandboxed, test, or unusual configurations this could return `[]` → crash.
  Fix: provide a fallback directory or use optional binding with a clear error.

- [ ] **Generic "Import failed" message** — `RouteStore.swift:79`
  Invalid file content and I/O failures both produce the same string. User can't tell whether
  their file is corrupt or the device is out of storage. Fix: differentiate error messages.

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

- [ ] **Dead views add maintenance overhead**
  - `CyclingRouteOverlay.swift` — commented as "retained for potential future reuse." Either use or delete.
  - `RouteNoticeView.swift` — defined but never instantiated (already tracked in P2 for wiring).
  Remove or wire up before 1.0.

- [ ] **`RideSessionStore+Spurs.swift` accesses internal properties loosened from `private`**
  `route`, `pois`, `nearestTrackIndex`, `rideState` were explicitly made `internal` (not `private`)
  so the file-separated extension could read them. Comment says "internal so file-separated
  extensions can read these." Fix: use `private(set)` or extract spur logic into a dedicated service.

- [ ] **`AppleLanguages` UserDefaults key is fragile / not documented public API**
  `Shared/Managers/LocalizationManager.swift:126` writes to `UserDefaults.standard.set(..., forKey: "AppleLanguages")`.
  This is a system-internal key, not documented for app use on iOS 17+. May break in future iOS releases.
  Also calls the deprecated `UserDefaults.standard.synchronize()` (deprecated since iOS 13).
  Fix: use the Bundle-based `.lproj` loading approach (already present in the `Shared/Localization/` copy).

- [ ] **Implicitly unwrapped optional `CLLocationManager`** — `RideSessionStore.swift:37`
  ```swift
  private var manager: CLLocationManager!
  ```
  Set in `init()`. Safe in practice but a code smell. Fix: `private let manager = CLLocationManager()`.

- [ ] **Force-unwrap of `min()`/`max()` on coordinate arrays** — multiple files
  `RideSummaryView.swift:256-259`, `RideHistoryView.swift:203-208`, `RideHistoryDetailView.swift:288-297`
  all use `coords.map(\.latitude).min()!` guarded by `count > 1`. Safe today but fragile —
  a refactor that changes the guard could introduce a crash. Use optional binding instead.

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
