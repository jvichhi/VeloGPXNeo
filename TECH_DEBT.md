# VeloGPXNeo — Tech Debt Checkpoint
> Last reviewed: May 12, 2026 (v1.2 build 3 — iOS 26 deprecation + Swift 6 actor warnings pass)

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

- [x] **Orphan `Shared/Localization/` directory deleted** — ✅ Resolved May 3, 2026
  Code review flagged a "duplicate" `LocalizationManager.swift` — actually the second copy at
  `Shared/Localization/LocalizationManager.swift` was never in any Xcode target. Further
  inspection showed the entire `Shared/Localization/` directory was dead: the `.swift` file
  wasn't compiled, and the 15 `.lproj` bundles used structured keys (`"tab.ride"`) that don't
  match the code's direct-English key pattern (`"Routes".localized`), so they never resolved
  at runtime. Removed 16 dead files. Real localization lives in `Resources/*.lproj/`.

---

## 🟠 iOS 26 Modernization — Tackle Now (warnings → future errors)

These are all active Xcode warnings from the v1.2 b3 build. The MapKit and UIScreen items
are deprecated-in-iOS-26 APIs that Apple will harden in a future SDK. The Swift 6 actor items
are already errors in Swift 6 mode and will block a strict-concurrency build.

### MK-1 — `MKPlacemark` / `init(placemark:)` → `MKMapItem.init(location:address:)` [iOS 26]

**Affects:** `CyclingRouteService.swift:47,48,87,88` · `PlaceDescriptorService.swift:63,64,104,105`

Every `MKMapItem(placemark: MKPlacemark(coordinate: coord))` pair must become:
```swift
// Before (deprecated iOS 26)
MKMapItem(placemark: MKPlacemark(coordinate: coord))

// After
MKMapItem(location: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
```
For address strings, use `MKAddressRepresentations` instead of `MKPlacemark.title`.

---

### MK-2 — `MKMapItem.placemark` property reads → `.location` / `.address` [iOS 26]

**Affects:**
- `NearbySearchSheet.swift:108,109,148,150,199,200,224`
- `POIDiscoverySheet.swift:125,130,176`
- `PlaceDescriptorService.swift:94,95`
- `ReverseGeocodingService.swift:54`

All reads of `mapItem.placemark.coordinate`, `mapItem.placemark.name`, etc. must migrate to
`mapItem.location?.coordinate` and `mapItem.address` / `mapItem.addressRepresentations`.
Example pattern across all affected files:
```swift
// Before
let coord = mapItem.placemark.coordinate
let name  = mapItem.placemark.name ?? mapItem.name

// After
let coord = mapItem.location?.coordinate ?? mapItem.placemark.coordinate
let name  = mapItem.name
```

---

### MK-3 — `CLGeocoder` + `reverseGeocodeLocation` → `MKReverseGeocodingRequest` [iOS 26]

**Affects:** `ReverseGeocodingService.swift:63,66` · `PlaceDescriptorService.swift:57,60`

`CLGeocoder` is deprecated wholesale in iOS 26 in favour of MapKit's new geocoding API.
```swift
// Before
let geocoder = CLGeocoder()
geocoder.reverseGeocodeLocation(loc) { placemarks, error in ... }

// After (iOS 26+)
let request = MKReverseGeocodingRequest(location: loc)
let result  = try await request.result   // MKMapItem, no CLPlacemark needed
```
Gate with `#available(iOS 26, *)` and keep the `CLGeocoder` path as a fallback for iOS 17–25
until the min deployment target is raised above 26.

---

### MK-4 — `UIScreen.main` → context-based screen [iOS 26]

**Affects:**
- `RideHistoryDetailView.swift:273,298,299`
- `RideHistoryView.swift:213`
- `RideSummaryView.swift:262,263`

`UIScreen.main` is deprecated; the replacement is to access the screen through the view hierarchy:
```swift
// Before
let scale = UIScreen.main.scale

// After — in a SwiftUI view body or UIView subclass
// Option A: via @Environment (SwiftUI)
@Environment(\.displayScale) var displayScale  // use for scale

// Option B: via UIWindowScene (UIKit context in snapshot callbacks)
// Pass the windowScene into the snapshot helper, then:
// windowScene.screen.scale
```
`RideSummaryView` and `RideHistoryDetailView` use `UIScreen.main.scale` inside
`MKMapSnapshotter` completion handlers — extract `displayScale` from the view's environment
and capture it before the async callback.

---

### AC-1 — Swift 6 actor isolation: `clCoordinate` / `route` / `distance(to:)` on wrong actor

**Affects:** `CyclingRouteService.swift:153,175,176,189,194,195,211,212,216,219,245,257,259,273`
· `PlaceDescriptorService.swift:31,94,95`

`clCoordinate`, `route`, and the `distance(to:)` helper are `@MainActor`-isolated but called
from `nonisolated` async contexts in route-building closures. This is currently a warning;
it is **an error in Swift 6 mode**.

Fix strategy — choose one per property:

1. **Snapshot values before the async boundary** (preferred for coords):
   ```swift
   // Capture on MainActor before entering the Task/async closure
   let origin = await MainActor.run { origin.clCoordinate }
   let dest   = await MainActor.run { destination.clCoordinate }
   ```

2. **Mark the model struct `Sendable` and remove `@MainActor`** on pure value properties
   (`clCoordinate` on a coordinate struct should be actor-agnostic — it's a value type).

3. **Propagate `@MainActor` to the calling function** if the whole call-site is already on main.

---

### AC-2 — Swift 6: `TurnInstruction.init(...)` called from nonisolated context

**Affects:** `CyclingRouteService.swift:245,257,273`

`TurnInstruction` initializer is `@MainActor`-isolated but invoked inside a nonisolated async
closure building the step array. Fix: mark `TurnInstruction` as `Sendable` struct with no
actor isolation, or build the array in a `MainActor.run { }` block.

---

### AC-3 — Swift 6: `WatchRideSummary` `Decodable` conformance on wrong actor

**Affects:** `WatchRideStore.swift:23`

```
Main actor-isolated conformance of 'WatchRideSummary' to 'Decodable' cannot be used
in nonisolated context; this is an error in Swift 6 mode
```

`WatchRideSummary` is `@MainActor` but `Decodable` decoding happens on a background `JSONDecoder`
thread. Fix: remove `@MainActor` from `WatchRideSummary` (it's a plain data struct — no UI
state), or decode into a nonisolated intermediate and then assign on main.

---

### MISC-1 — `onChange(of:perform:)` deprecated iOS 17 [still a warning]

**Affects:** `RideView.swift:232`

```swift
// Before (iOS 16 API, deprecated in 17)
.onChange(of: someValue) { newValue in ... }

// After
.onChange(of: someValue) { _, newValue in ... }
// or zero-parameter form if old value not needed:
.onChange(of: someValue) { ... }
```

---

### MISC-2 — `PlanView` spurious `await` on sync calls

**Affects:** `PlanView.swift:62,72`

`await` wraps a call that contains no async operations — Xcode warns "No async operations
occur within await expression." Remove the `await` keyword from those two call sites.

---

### MISC-3 — Missing `AccentColor` in Assets catalog

**Affects:** `iPhone/Assets.xcassets`

The app-level accent color is not defined in any asset catalog. Xcode falls back to the
system blue. Add an `AccentColor` color set to `Assets.xcassets` matching VeloGPX's brand
teal (`#01696F` light / `#4F98A3` dark).

---

### MISC-4 — Unused `windowMeters` immutable value

**Affects:** `RouteModel.swift:190` (both VeloGPX and Watch targets)

```swift
let windowMeters = ...  // never read after assignment
```
Either use it or replace with `_`. Quick cleanup, zero risk.

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

- [ ] **Extract `RideView` into sub-views** (`RideView.swift` is ~37 KB — God View)
  Candidates:
  - `RideMapLayer` — map, camera, polylines, annotations
  - `RideHUDPanel` — metric tiles, buttons, elevation strip
  - `RideBirdsEyePanel` — aerial overview layout branch
  Move all MKDirections spur calls into a dedicated `POISpurService`.

- [ ] **Split `RideSessionStore` (~30 KB God Object)**
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
  *(Note: also needs the MK-1/MK-2/MK-3 iOS 26 modernization fixes regardless.)*

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
| Orphan `Shared/Localization/` directory (17 dead files) removed | May 3, 2026 |
| CoreMotion re-linked to VeloGPX target; version synced to 1.2/3 across all 3 targets | May 12, 2026 |
| Stale `RideSessionStore.swift (corrected section)` removed from Watch Resources phase | May 12, 2026 |
