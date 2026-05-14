# VeloGPXNeo — Tech Debt Checkpoint
> Last reviewed: May 13, 2026 (v1.2 build 3 — iOS 26 deprecation + Swift 6 actor warnings pass)

---

## 🔴 P0 — Fix Immediately

- [x] **Duplicate `POISearchService.swift`** — ✅ Resolved May 2, 2026
  Root-level copy (`iPhone/POISearchService.swift`, 1040 B) removed from project and Build Phases.
  Only `iPhone/Services/POISearchService.swift` remains.

- [x] **POI `×` button in `nextPOIChip` is broken / unreachable** — ✅ Resolved May 2, 2026
  Chip `×` removed entirely. `nextPOIChip` is now display-only (icon + distance).
  Deletion replaced by long-press on map annotation (see F-2b).

- [x] **POI toggle uses name-matching instead of ID** — ✅ Resolved May 12, 2026
  `NearbySearchSheet` was already using `deterministicID(for:)`. `POIDiscoverySheet.swift:133`
  also fixed — `addPOI(from:)` and the `isAdded` check in `ForEach` now both use
  coordinate-based `deterministicID(for:)`. Two different "Starbucks" along a route no longer collide.

- [x] **GPX export produces invalid files on non-US locales** — ✅ Resolved May 12, 2026
  `GPXExporter.swift` lat/lon values now formatted with `String(format: "%f", ...)` forcing
  C locale. Eliminates `46,5` comma-decimal separator on French/German/etc. devices.

- [x] **Orphan `Shared/Localization/` directory deleted** — ✅ Resolved May 3, 2026
  Dead 16-file directory removed. Real localization lives in `Resources/*.lproj/`.

---

## 🟠 iOS 26 Modernization — Tackle Now (warnings → future errors)

These are all active Xcode warnings from the v1.2 b3 build. The MapKit and UIScreen items
are deprecated-in-iOS-26 APIs that Apple will harden in a future SDK. The Swift 6 actor items
are already errors in Swift 6 mode and will block a strict-concurrency build.

### MK-1 — `MKPlacemark` / `init(placemark:)` → `MKMapItem.init(location:address:)` — ✅ Resolved May 13, 2026

`CyclingRouteService.swift` and `PlaceDescriptorService.swift` were already fully migrated
to `MKMapItem(location:address:)`. No `MKPlacemark` or `init(placemark:)` references remain.

---

### MK-2 — `MKMapItem.placemark` property reads → `.location` / `.address` — ✅ Resolved May 13, 2026

`NearbySearchSheet`, `POIDiscoverySheet`, `PlaceDescriptorService`, and `ReverseGeocodingService`
all use `mapItem.location?.coordinate` and `mapItem.name`. No `.placemark` reads remain.

---

### MK-3 — `CLGeocoder` + `reverseGeocodeLocation` → `MKReverseGeocodingRequest` — ✅ Resolved May 13, 2026

`ReverseGeocodingService` and `PlaceDescriptorService` both use `MKReverseGeocodingRequest`
as the iOS 26+ primary path. `CLGeocoder` is retained only in `ReverseGeocodingService` as
a properly `@available(iOS, deprecated: 26.0)` gated fallback for the legacy code path.

---

### MK-4 — `UIScreen.main` → context-based screen — ✅ Resolved May 13, 2026

`RideSummaryView`, `RideHistoryDetailView`, `RideHistoryView` — all `UIScreen.main.scale`
and `UIScreen.main.bounds.width` references replaced:
- Scale: `@Environment(\.displayScale) private var displayScale` captured before async boundary
- Width: `GeometryReader` passes `geo.size.width` into snapshot functions as a parameter

---

### MK-5 — `POISearchService` typed `MKPointOfInterestFilter` — ✅ Resolved May 12, 2026

`POISearchService` previously sent plain `naturalLanguageQuery` strings only. Now uses
`MKPointOfInterestFilter(including:)` with typed `MKPointOfInterestCategory` constants
(`.cafe`, `.restaurant`, `.bicycle`, `.pharmacy`, etc.) for structured category searches.
Natural language retained as fallback for free-text / unknown queries.
> **Note:** No `MKPointOfInterestCategory` constant exists for drinking water/fountains yet.
> "Water" searches currently map to `.nationalPark` as a proxy. Track for future SDK update.

---

### MK-6 — `POIModel` missing `mapItemIdentifier` + `mapsURL` (Place IDs) [ NEW — May 13, 2026 ]

**Affects:** `POIModel.swift`, `NearbySearchSheet.swift`, `POIDiscoverySheet.swift`, `PreRidePOISheet.swift`

`POIModel` currently uses a coordinate-based `deterministicID` as its stable identity. While this
works, it misses the stable **Apple Maps Place ID** (`MKMapItem.identifier`, iOS 18+) that survives
business renames, address changes, and duplicate names. Without it:
- Two POIs at the same coordinate (e.g. a café that moved 5 m) collide
- No deep-link URL to open the place in Maps
- No foundation for sharing POI lists as tappable Maps links

**Plan:**
1. Add two optional fields to `POIModel`:
   ```swift
   public var mapItemIdentifier: String?   // MKMapItem.identifier.rawValue (iOS 18+)
   public var mapsURL: URL?                // maps://?auid=<identifier>
   ```
2. Create `Shared/Models/POIModel+MapKit.swift` with a factory:
   ```swift
   extension POIModel {
       static func from(_ mapItem: MKMapItem, distanceFromRoute: Double = 0) -> POIModel {
           var poi = POIModel(
               id: UUID(),
               name: mapItem.name ?? "",
               category: POICategory.from(mapItem.pointOfInterestCategory),
               coordinate: mapItem.location?.coordinate ?? mapItem.placemark.coordinate,
               distanceFromRoute: distanceFromRoute
           )
           if #available(iOS 18, *) {
               poi.mapItemIdentifier = mapItem.identifier?.rawValue
               poi.mapsURL = mapItem.identifier.flatMap {
                   URL(string: "maps://?auid=\($0.rawValue)")
               }
           }
           return poi
       }
   }
   ```
3. Update `isAdded` in all three sheets: prefer `mapItemIdentifier` match when both sides have one;
   fall back to `deterministicID(for:)` coordinate hash.
4. Add "Open in Maps" button to POI detail row / `NearbyResultCard`:
   ```swift
   if let url = poi.mapsURL {
       Button { UIApplication.shared.open(url) } label: {
           Label("Open in Maps", systemImage: "map")
       }
   }
   ```
5. `POIModel` is `Codable` — adding optional fields is backwards-compatible. No JSON migration needed.

> **Availability gate required:** `MKMapItem.identifier` is iOS 18+. Gate with `#available(iOS 18, *)` to keep the Watch target clean. On the iOS 26+ phone target this is always true.

> **Full feature spec** — see `FEATURES.md` § F-B for the complete implementation plan including
> the `POIModel+MapKit.swift` factory, `isAdded` update pattern, and Watch compatibility notes.

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
   let origin = await MainActor.run { origin.clCoordinate }
   let dest   = await MainActor.run { destination.clCoordinate }
   ```

2. **Mark the model struct `Sendable` and remove `@MainActor`** on pure value properties.

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
```

---

### MISC-2 — `PlanView` spurious `await` on sync calls — ✅ Resolved May 13, 2026

`await plan.loadFrom(route:)` removed from both call sites (`PlanView.swift:62,72`).
`loadFrom(route:)` is `@MainActor` synchronous — the `await` was a fossil from when the function
was previously `async` (likely when it performed a Supabase/MapKit call). Swift allowed it
because both call sites were already in async contexts (`Task {}` / `.task {}`), making it a
no-op actor hop. Zero behaviour change. Clears two Xcode warnings. Commit `cc8f2fc`.

---

### MISC-3 — Missing `AccentColor` in Assets catalog

**Affects:** `iPhone/Assets.xcassets`

Add an `AccentColor` color set matching VeloGPX brand teal (`#01696F` light / `#4F98A3` dark).

---

### MISC-4 — Unused `windowMeters` immutable value

**Affects:** `RouteModel.swift:190` (both VeloGPX and Watch targets)

```swift
let windowMeters = ...  // never read after assignment
```
Either use it or replace with `_`.

---

### MISC-5 — Duplicated `bearing()` haversine function [ NEW — May 13, 2026 ]

**Affects:** `RideSessionStore.swift` · `GPXCueEngine` (both implement independently)

Both files contain an identical haversine bearing calculation. Extract to a shared extension:
```swift
// Shared/Extensions/CLLocationCoordinate2D+Bearing.swift
extension CLLocationCoordinate2D {
    func bearing(to destination: CLLocationCoordinate2D) -> Double {
        // single canonical implementation
    }
}
```
Delete the duplicate from whichever file is the secondary copy.

---

### MISC-6 — Notification permission result silently ignored [ NEW — May 13, 2026 ]

**Affects:** `RideSessionStore.swift:92`

```swift
// Current — granted is discarded
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

// Fix — store and gate
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
    DispatchQueue.main.async { self.notificationsGranted = granted }
}
```
Add a `private var notificationsGranted = false` flag and guard all `UNUserNotificationCenter.add(...)` call sites with it.

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
- `POIDiscoverySheet` vs `NearbySearchSheet` — worth merging into one sheet with a `mode: .preRide | .midRide` parameter before 1.0.
- `RouteStore+POI.swift` is suspiciously thin (866 B) — POI persistence logic scattered across `RideView` call sites. Consolidate into `RouteStore` or a dedicated `POIPersistenceService`.

---

### Route Line Visibility — ✅ Landed May 2, 2026

| Polyline | Outline | Fill |
|---|---|---|
| Remaining route | white 18 pt | blue 12 pt |
| Ridden route | white 14 pt | blue/0.45 8 pt |
| Reroute | white 16 pt | orange 10 pt |
| POI spur inbound (next) | — | green 8 pt dashed |
| POI spur outbound (next) | — | red 7 pt dashed |
| Non-next spurs scale proportionally (5 pt green / 4 pt red) | | |

---

- [x] **Replace `.walking`/`.automobile` routing with `.cycling` (WWDC25)** — ✅ Done

- [ ] **Extract `RideView` into sub-views** (`RideView.swift` is ~37 KB — God View)
  Candidates:
  - `RideMapLayer` — map, camera, polylines, annotations
  - `RideHUDPanel` — metric tiles, buttons, elevation strip
  - `RideBirdsEyePanel` — aerial overview layout branch

- [ ] **Split `RideSessionStore` (~30 KB God Object)**
  Proposed split:
  - `RideLocationEngine` — CLLocation, heading, breadcrumbs
  - `POITrackingEngine` — proximity, nextPOI, spur requests
  - `WatchSyncManager` — WCSession framing and throttle
  `RideSessionStore` becomes a thin coordinator.

- [ ] **MK-6 / F-B — `POIModel` Place IDs + Unified Maps URLs** — see MK-6 above

- [x] **Fix `nextPOI` to use on-route ordering, not raw distance** — ✅ Done

- [x] **Replace manual `Annotation("You", ...)` with `UserAnnotation()`** — ✅ Done

- [x] **`hudHeight` uses `DispatchQueue.asyncAfter` timing hack** — ✅ Done
  Replaced with `HUDHeightKey: PreferenceKey`.

- [x] **`.constant()` binding breaks alert dismissal** — ✅ Resolved May 12, 2026
  `RouteLibraryView.swift:44` — replaced `.constant(routeStore.lastImportMessage != nil)` with
  a proper `@State var showImportAlert: Bool` synced via `.onChange(of: routeStore.lastImportMessage)`.

- [x] **Watch haptic fires every second while off-route** — ✅ Resolved May 13, 2026
  `WatchRideStore.swift:26` — added `didAlertOffRoute: Bool` flag; resets on `isOffRoute → false`
  transition. Watch now fires haptic once per off-route event.

- [x] **`errorClearTask` not cancelled on deinit** — ✅ Resolved May 12, 2026
  Added `deinit { errorClearTask?.cancel(); elapsedTimer?.invalidate() }` to `RideSessionStore`.
  Task closure also updated to `[weak self]`.

- [x] **Off-route bearing uses potentially invalid heading** — ✅ Resolved May 12, 2026
  `RideView.swift:369` — guarded on `currentHeading.isFinite && currentHeading != 0` before
  computing relative bearing arrow.

---

## 🟢 P2 — Backlog

- [ ] **Elevation gain has no noise smoothing**
  Fix: threshold gate (only accumulate deltas > 2 m) or simple Kalman filter on altitude stream.

- [x] **`PlaceDescriptorService` wired to `WaypointListSheet`** — ✅ Resolved May 13, 2026
  `WaypointListSheet` now resolves each waypoint coordinate to a human-readable place name via
  `PlaceDescriptorService.shared.resolve()` (iOS 26+ `MKReverseGeocodingRequest` primary,
  `MKLocalSearch` fallback). Resolution is lazy and async — a spinner appears in-flight, and
  results are cached in `resolvedNames: [UUID: String]` so re-renders don't re-fire network calls.
  The raw `lat, lon` label is still shown as a subtitle under the resolved name.
  Availability gated: iOS <26 shows raw coordinates (same as before).

- [x] **`NextPOIBanner.swift` stub deleted** — ✅ Resolved May 13, 2026
  File removed. `nextPOIChip` in `RideView` covers this entirely.

- [ ] **`RouteNoticeView.swift` — kept but unconnected**
  Wire into `CyclingRouteService` result and surface in `topBanners`, OR delete before 1.0.
  Currently retained alongside `CyclingRouteOverlay` as a pair — both need the same UX decision.

- [ ] **`CyclingRouteOverlay.swift` — deliberately removed from RouteDetailView**
  Kept for potential reuse. Consider surfacing in `PlanView` pre-ride rather than `RouteDetailView`.
  `RouteNoticeView` should be wired alongside this when it's reinstated.

- [ ] **`MapStyle` — expose cycling overlay option (WWDC25)**
  Add a user setting to toggle between `.standard`, `.hybrid(elevation: .realistic)`,
  and a cycling-focused style with lane overlays.

- [ ] **Two `.onAppear` blocks in `RideView`** *(re-verify — marked completed but may still be present)*

- [ ] **`buildSnapIndexCache` O(N×M) on main thread** — `PreRidePOISheet.swift:102-117`
  Fix: offload to background task or build a spatial index (k-d tree / grid).

- [ ] **`updateNextPOI` scans all POIs on every location update** — `RideSessionStore.swift:491-551`
  Fix: pre-compute POI snap indices once when POIs change; use indexed lookup in hot path.

- [ ] **`elevationSamples` recomputed on every body evaluation** — `RouteDetailView.swift:236-252`
  Fix: lazily cache, invalidate only when `route.trackPoints` changes.

- [ ] **Empty `catch` blocks swallow errors silently**
  `RideSummaryView.swift:296`, `RideHistoryView.swift:231`, `RideHistoryDetailView.swift:266,346`.
  Fix: at minimum log errors; ideally surface via published error string / toast.

- [ ] **Notification auth result silently ignored** — `RideSessionStore.swift:92`
  See MISC-6 above for full fix.

- [x] **`FileManager` URL force-unwrap** — ✅ Resolved May 12, 2026
  `RouteStore.swift:150,161` — both `storageDirectory()` and `poisStorageURL()` now
  `throw StorageError.unavailable` instead of force-unwrapping `.first!`. All call sites
  updated to use `try?` / `guard let`.

- [ ] **Generic "Import failed" message** — `RouteStore.swift:79`
  Differentiate corrupt file vs. I/O failure error messages.

---

## 🔵 P3 — Nice to Have

- [x] **Throttle `sendWatchUpdate()` to 1 Hz** — ✅ Done

- [x] **Surface routing/rerouting errors to the user** — ✅ Done

- [x] **`MapCameraAnimation` for smooth heading transitions (WWDC25)** — ✅ Done

- [ ] **`RideHistoryStore` has no pagination**
  Fix: lazy loading with `SwiftData` or paginated JSON file reads.

- [ ] **Hardcoded English strings — not using `LocalizationManager`**
  Run a pass to move all user-visible strings through the localization system.

- [ ] **No unit tests for core logic**
  Zero coverage for: `minimumDistance`, `updateNextPOI` ordering, elevation accumulation,
  `bearing()` function. Add `XCTestCase` tests for these highest-risk paths.

- [ ] **Dead views add maintenance overhead**
  - `CyclingRouteOverlay.swift` — retained for potential reuse; use or delete before 1.0.
  - `RouteNoticeView.swift` — never instantiated (tracked in P2 for wiring).

- [ ] **`RideSessionStore+Spurs.swift` accesses internal properties loosened from `private`**
  Fix: use `private(set)` or extract spur logic into a dedicated service.

- [ ] **`AppleLanguages` UserDefaults key is fragile / not documented public API**
  `LocalizationManager.swift:126` writes to `"AppleLanguages"` — system-internal key, not
  documented for app use on iOS 17+. Also calls deprecated `synchronize()`.
  Fix: use the Bundle-based `.lproj` loading approach.

- [ ] **Implicitly unwrapped optional `CLLocationManager`** — `RideSessionStore.swift:37`
  Fix: `private let manager = CLLocationManager()`.

- [ ] **Force-unwrap of `min()`/`max()` on coordinate arrays**
  `RideSummaryView.swift:256-259`, `RideHistoryView.swift:203-208`, `RideHistoryDetailView.swift:288-297`.
  Fix: use optional binding instead of `!`.

---

## ✅ Completed

| Item | Resolved |
|---|---|
| All routing uses `.cycling` via `CyclingRouteService` (iOS 26+) | Apr 26, 2026 |
| `nextPOI` uses on-route track index ordering | Apr 26, 2026 |
| `sendWatchUpdate()` throttled to 1 Hz | Apr 26, 2026 |
| Two `.onAppear` blocks merged into one | Apr 26, 2026 |
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
| **P0** GPX export locale crash fixed (`String(format: "%f", ...)`) | May 12, 2026 |
| **P0** POI ID collision fixed in `POIDiscoverySheet` (coordinate-based deterministicID) | May 12, 2026 |
| **P1** `RouteLibraryView` `.constant()` alert binding replaced with `@State` | May 12, 2026 |
| **P1** `errorClearTask` memory leak fixed (`deinit` + `[weak self]`) | May 12, 2026 |
| **P1** Off-route heading guard added (`RideView.swift:369`) | May 12, 2026 |
| **P1** `RouteStore` force-unwrap crash fixed (`throw StorageError.unavailable`) | May 12, 2026 |
| **MK-5** `POISearchService` upgraded to typed `MKPointOfInterestFilter` (iOS 18+/26) | May 12, 2026 |
| **P0** `POIDiscoverySheet` category detection upgraded to `item.pointOfInterestCategory` | May 12, 2026 |
| **P1** Watch haptic loop fixed (`didAlertOffRoute` flag in `WatchRideStore`) | May 13, 2026 |
| **P2** `PlaceDescriptorService` wired to `WaypointListSheet` (lazy async, iOS 26 gated) | May 13, 2026 |
| **P2** `NextPOIBanner.swift` deleted (superseded by `nextPOIChip` in `RideView`) | May 13, 2026 |
| **MK-1** `MKPlacemark`/`init(placemark:)` → `MKMapItem(location:address:)` | May 13, 2026 |
| **MK-2** `MKMapItem.placemark` reads → `.location`/`.address` | May 13, 2026 |
| **MK-3** `CLGeocoder` → `MKReverseGeocodingRequest` (iOS 26+ primary path) | May 13, 2026 |
| **MK-4** `UIScreen.main` → `@Environment(\.displayScale)` + `GeometryReader` width | May 13, 2026 |
| **MISC-2** Spurious `await` on `plan.loadFrom(route:)` removed (`PlanView.swift:62,72`) | May 13, 2026 |
| **DOCS** `ROADMAP.md` created — 4-sprint prioritised work order | May 13, 2026 |
