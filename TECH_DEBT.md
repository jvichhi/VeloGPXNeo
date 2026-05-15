# VeloGPXNeo — Tech Debt Checkpoint
> Last reviewed: May 15, 2026 (synced to Sprint 2 completions)

---

## 🔴 P0 — Fix Immediately

- [x] **Duplicate `POISearchService.swift`** — ✅ Resolved May 2, 2026
  Root-level copy (`iPhone/POISearchService.swift`, 1040 B) removed from project and Build Phases.
  Only `iPhone/Services/POISearchService.swift` remains.

- [x] **POI `×` button in `nextPOIChip` is broken / unreachable** — ✅ Resolved May 2, 2026
  Chip `×` removed entirely. `nextPOIChip` is now display-only (icon + distance).
  Deletion replaced by long-press on map annotation (see F-2b).

- [x] **POI toggle uses name-matching instead of ID** — ✅ Resolved May 12, 2026
  `POIDiscoverySheet.swift:133` — `addPOI(from:)` and `isAdded` check both use `deterministicID(for:)`.

- [x] **GPX export produces invalid files on non-US locales** — ✅ Resolved May 12, 2026
  `GPXExporter.swift` lat/lon values now use `String(format: "%f", ...)` forcing C locale.

- [x] **Orphan `Shared/Localization/` directory deleted** — ✅ Resolved May 3, 2026

---

## 🟠 iOS 26 Modernization — Warnings Resolved

### MK-1 — `MKPlacemark` / `init(placemark:)` → `MKMapItem.init(location:address:)` — ✅ Resolved May 13, 2026

`CyclingRouteService.swift` and `PlaceDescriptorService.swift` both fully use `MKMapItem(location:address:)`. No `MKPlacemark` or deprecated `init(placemark:)` remain. Discovered in code review — was already done before this session.

---

### MK-2 — `MKMapItem.placemark` reads → `.location` / `.address` — ✅ Resolved May 13, 2026

`NearbySearchSheet`, `POIDiscoverySheet`, `PlaceDescriptorService`, and `ReverseGeocodingService` all use `mapItem.location?.coordinate` and `mapItem.name`. No `.placemark` reads remain. Discovered in code review.

---

### MK-3 — `CLGeocoder` → `MKReverseGeocodingRequest` — ✅ Resolved May 13, 2026

`ReverseGeocodingService` uses `MKReverseGeocodingRequest` as the iOS 26+ primary path.
`CLGeocoder` retained as a properly `@available(iOS, deprecated: 26.0)` gated fallback only.
`PlaceDescriptorService` uses `MKReverseGeocodingRequest` exclusively (no `CLGeocoder` at all).
Discovered in code review.

---

### MK-4 — `UIScreen.main` → context-based screen — ✅ Resolved May 13, 2026

`RideSummaryView`, `RideHistoryDetailView`, `RideHistoryView` — all `UIScreen.main.scale` and
`UIScreen.main.bounds.width` references replaced:
- Scale: `@Environment(\.displayScale) private var displayScale` captured before async boundary
- Width: `GeometryReader` passes `geo.size.width` as a parameter
Discovered in code review.

---

### MK-5 — `POISearchService` typed `MKPointOfInterestFilter` — ✅ Resolved May 12, 2026

Now uses `MKPointOfInterestFilter(including:)` with typed `MKPointOfInterestCategory` constants.
Natural language retained as fallback for free-text / unknown queries.
> **Note:** No `MKPointOfInterestCategory` constant for drinking water/fountains yet.
> "Water" maps to `.nationalPark` as proxy. Track for future SDK update.

---

### MK-6 — `POIModel` missing `mapItemIdentifier` + `mapsURL` (Place IDs) [ 🔲 Open ]

**Affects:** `POIModel.swift`, `NearbySearchSheet.swift`, `POIDiscoverySheet.swift`, `PreRidePOISheet.swift`

`POIModel` currently uses a coordinate-based `deterministicID`. Adding stable Apple Maps Place IDs enables:
- Correct deduplication when a POI moves slightly
- "Open in Maps" deep-link action
- Future: shareable POI lists as tappable Maps links

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
               coordinate: mapItem.location?.coordinate ?? .init(),
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
3. Update `isAdded` in all three sheets: prefer `mapItemIdentifier` match; fall back to coordinate hash.
4. Add "Open in Maps" button to POI detail row.
5. `POIModel` is `Codable` — adding optional fields is backwards-compatible. No migration needed.

> **Availability gate:** `MKMapItem.identifier` is iOS 18+. Gate with `#available(iOS 18, *)` for Watch target cleanliness. Always true on iOS 26+ phone target.
> **Full spec:** `FEATURES.md § F-B`

---

### AC-1 — Swift 6: `clCoordinate` / `route` / `distance(to:)` on wrong actor — ✅ Resolved May 13, 2026

`CyclingRouteService` passes raw `Double` lat/lon values across async boundaries and constructs
`CLLocationCoordinate2D` inside `MainActor.run {}` blocks. No `@MainActor`-isolated coordinate
constructions leak into nonisolated contexts. `GPXCueEngine` uses the same pattern throughout.
Discovered in code review — was already done before this session.

---

### AC-2 — Swift 6: `TurnInstruction.init(...)` from nonisolated context — ✅ Resolved May 13, 2026

`GPXCueEngine` uses `CueSheetEntry(lat:lon:)` nonisolated init throughout — confirmed by file-level
comment. No `TurnInstruction`/`CueSheetEntry` inits cross actor boundaries.
Discovered in code review — was already done before this session.

---

### AC-3 — Swift 6: `WatchRideSummary` `Decodable` on wrong actor — ✅ Resolved May 13, 2026 (commit `a587b44`)

`Codable` split into a `nonisolated extension WatchRideSummary: Codable {}` so the conformance
has no actor isolation. Safe to call from the `nonisolated` `WCSession` callback in `WatchRideStore`.

---

### MISC-1 — `onChange(of:perform:)` deprecated iOS 17 [ 🔲 Open ]

**Affects:** `RideView.swift:232`

```swift
// Before (iOS 16 API, deprecated in 17)
.onChange(of: someValue) { newValue in ... }

// After
.onChange(of: someValue) { _, newValue in ... }
```

---

### MISC-2 — `PlanView` spurious `await` on sync calls — ✅ Resolved May 13, 2026 (commit `cc8f2fc`)

`await plan.loadFrom(route:)` removed from `PlanView.swift:62,72`. `loadFrom` is `@MainActor` sync.

---

### MISC-3 — Missing `AccentColor` in Assets catalog — ✅ Resolved May 13, 2026 (commit `a587b44`)

`AccentColor.colorset` added to `iPhone/Assets.xcassets` with green light/dark variants matching app palette.

---

### MISC-4 — Unused `windowMeters` immutable value [ 🔲 Open ]

**Affects:** `RouteModel.swift:190` (both VeloGPX and Watch targets)

```swift
let windowMeters = ...  // never read after assignment
```
Either use it or replace with `_`.

---

### MISC-5 — Duplicated `bearing()` haversine function [ 🔲 Open ]

**Affects:** `RideSessionStore.swift` · `RideView.swift` (confirmed via source search May 15, 2026)

> ⚠️ **Was incorrectly marked resolved in ROADMAP.md** — reopened after source search confirmed `bearing()` present in both files.

Extract to:
```swift
// Shared/Extensions/CLLocationCoordinate2D+Bearing.swift
extension CLLocationCoordinate2D {
    func bearing(to destination: CLLocationCoordinate2D) -> Double {
        // single canonical implementation
    }
}
```
`GPXCueEngine` already has a `nonisolated` version — use that as the canonical one.
Delete the duplicate from `RideSessionStore` and `RideView`.
Scheduled for Sprint 4 alongside `RideSessionStore` F-4 split.

---

### MISC-6 — Notification permission result silently ignored [ 🔲 Open ]

**Affects:** `RideSessionStore.swift:92`

```swift
// Current — granted result discarded
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

// Fix
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
    DispatchQueue.main.async { self.notificationsGranted = granted }
}
```
Add `private var notificationsGranted = false` and gate all `UNUserNotificationCenter.add(...)` calls on it.

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
- `POIDiscoverySheet` vs `NearbySearchSheet` — merge into one sheet with `mode: .preRide | .midRide` before 1.0.
- `RouteStore+POI.swift` is thin (866 B) — POI persistence scattered. Consolidate before 1.0.

---

### Route Line Visibility — ✅ Landed May 2, 2026

| Polyline | Outline | Fill |
|---|---|---|
| Remaining route | white 18 pt | blue 12 pt |
| Ridden route | white 14 pt | blue/0.45 8 pt |
| Reroute | white 16 pt | orange 10 pt |
| POI spur inbound (next) | — | green 8 pt dashed |
| POI spur outbound (next) | — | red 7 pt dashed |

---

- [x] **Replace `.walking`/`.automobile` routing with `.cycling` (WWDC25)** — ✅ Done

- [ ] **Extract `RideView` into sub-views** (`RideView.swift` ~37 KB — God View)
  Do incrementally during Sprint 3 F-C2, not as a standalone refactor.
  Candidates: `RideMapLayer`, `RideHUDPanel`, `RideBirdsEyePanel`

- [ ] **Split `RideSessionStore` (~30 KB God Object)**
  Do incrementally during Sprint 4 perf work.
  Proposed split: `RideLocationEngine`, `POITrackingEngine`, `WatchSyncManager`

- [ ] **MK-6 / F-B — `POIModel` Place IDs + Unified Maps URLs** — see MK-6 above

- [x] **Fix `nextPOI` to use on-route ordering, not raw distance** — ✅ Done
- [x] **Replace manual `Annotation("You", ...)` with `UserAnnotation()`** — ✅ Done
- [x] **`hudHeight` uses `DispatchQueue.asyncAfter` timing hack** — ✅ Done
- [x] **`.constant()` binding breaks alert dismissal** — ✅ Resolved May 12, 2026
- [x] **Watch haptic fires every second while off-route** — ✅ Resolved May 13, 2026
- [x] **`errorClearTask` not cancelled on deinit** — ✅ Resolved May 12, 2026
- [x] **Off-route bearing uses potentially invalid heading** — ✅ Resolved May 12, 2026

---

## 🟢 P2 — Backlog

- [ ] **Elevation gain has no noise smoothing**
  Threshold gate (only accumulate deltas > 2 m) or Kalman filter on altitude stream.

- [x] **`PlaceDescriptorService` wired to `WaypointListSheet`** — ✅ Resolved May 13, 2026

- [x] **`NextPOIBanner.swift` stub deleted** — ✅ Resolved May 13, 2026

- [ ] **`RouteNoticeView.swift` — kept but unconnected**
  Wire into `CyclingRouteService` result + `topBanners`, or delete before 1.0.

- [ ] **`CyclingRouteOverlay.swift` — removed from `RouteDetailView`**
  Consider surfacing in `PlanView`. `RouteNoticeView` should be wired alongside.

- [ ] **`MapStyle` — expose cycling overlay toggle**
  Add setting: `.standard` / `.hybrid(elevation: .realistic)` / cycling lane style.

- [ ] **`buildSnapIndexCache` O(N×M) on main thread** — `PreRidePOISheet.swift:102-117`

- [ ] **`updateNextPOI` scans all POIs on every location update** — `RideSessionStore.swift:491-551`

- [ ] **`elevationSamples` recomputed on every body evaluation** — `RouteDetailView.swift:236-252`

- [ ] **Empty `catch` blocks swallow errors silently**
  `RideSummaryView.swift:296`, `RideHistoryView.swift:231`, `RideHistoryDetailView.swift:266,346`

- [ ] **Notification auth result silently ignored** — see MISC-6 above

- [x] **`FileManager` URL force-unwrap** — ✅ Resolved May 12, 2026

- [ ] **Generic "Import failed" message** — `RouteStore.swift:79`

---

## 🔵 P3 — Nice to Have

- [x] **Throttle `sendWatchUpdate()` to 1 Hz** — ✅ Done
- [x] **Surface routing/rerouting errors to the user** — ✅ Done
- [x] **`MapCameraAnimation` for smooth heading transitions (WWDC25)** — ✅ Done

- [ ] **`RideHistoryStore` has no pagination**
- [ ] **Hardcoded English strings — not using `LocalizationManager`**
- [ ] **No unit tests for core logic**
- [ ] **Dead views (`CyclingRouteOverlay`, `RouteNoticeView`)** — use or delete before 1.0
- [ ] **`RideSessionStore+Spurs.swift` accesses internal properties** — use `private(set)` or extract
- [ ] **`AppleLanguages` UserDefaults key is fragile** — `LocalizationManager.swift:126`
- [ ] **Implicitly unwrapped optional `CLLocationManager`** — `RideSessionStore.swift:37`
- [ ] **Force-unwrap of `min()`/`max()` on coordinate arrays** — `RideSummaryView`, `RideHistoryView`, `RideHistoryDetailView`

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
| CoreMotion re-linked; version synced to 1.2/3 across all 3 targets | May 12, 2026 |
| Stale `RideSessionStore.swift (corrected section)` removed from Watch Resources | May 12, 2026 |
| **P0** GPX export locale crash fixed | May 12, 2026 |
| **P0** POI ID collision fixed in `POIDiscoverySheet` | May 12, 2026 |
| **P1** `RouteLibraryView` `.constant()` alert binding replaced | May 12, 2026 |
| **P1** `errorClearTask` memory leak fixed | May 12, 2026 |
| **P1** Off-route heading guard added | May 12, 2026 |
| **P1** `RouteStore` force-unwrap crash fixed | May 12, 2026 |
| **MK-5** `POISearchService` typed `MKPointOfInterestFilter` | May 12, 2026 |
| **P0** `POIDiscoverySheet` category detection upgraded | May 12, 2026 |
| **P1** Watch haptic loop fixed (`didAlertOffRoute` flag) | May 13, 2026 |
| **P2** `PlaceDescriptorService` wired to `WaypointListSheet` | May 13, 2026 |
| **P2** `NextPOIBanner.swift` deleted | May 13, 2026 |
| **MK-1** `MKPlacemark/init(placemark:)` → `MKMapItem(location:address:)` | May 13, 2026 |
| **MK-2** `MKMapItem.placemark` reads → `.location`/`.address` | May 13, 2026 |
| **MK-3** `CLGeocoder` → `MKReverseGeocodingRequest` | May 13, 2026 |
| **MK-4** `UIScreen.main` → `@Environment(\.displayScale)` + `GeometryReader` | May 13, 2026 |
| **AC-1** Swift 6 `clCoordinate`/`route` across async boundary | May 13, 2026 |
| **AC-2** Swift 6 `TurnInstruction.init` nonisolated | May 13, 2026 |
| **AC-3** `WatchRideSummary` `Decodable` wrong actor | May 13, 2026 |
| **MISC-2** Spurious `await` on `plan.loadFrom(route:)` | May 13, 2026 |
| **MISC-3** `AccentColor` added to Assets catalog | May 13, 2026 |
| **DOCS** `ROADMAP.md` created — 4-sprint prioritised work order | May 13, 2026 |
| **F-A Shared** `VeloAI.swift` — `isAvailable` gate + `enabledKey` AppStorage key | May 15, 2026 |
| **F-A1** `RideSummaryGenerator.swift` — `respond(to:)` pattern, caption persistence | May 15, 2026 |
| **F-A2** `RouteNameSuggester.swift` — `MKReverseGeocodingRequest`, 3 pill suggestions | May 15, 2026 |
| **F-A3** `POIRankingEngine.swift` — actor-isolated, multi-signal scoring | May 15, 2026 |
| **F-A2** `RouteLibraryView.swift` rewrite — rename swipe + context menu + `RouteRenameSheet` + `FlowLayout` | May 15, 2026 |
| **Bug** FlowLayout regression fixed — `_FlowLayout: Layout` must never hold `@ViewBuilder` storage | May 15, 2026 |
| **Sprint 2** All F-A items complete, clean build confirmed (zero warnings, zero errors) | May 15, 2026 |
