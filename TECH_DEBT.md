# VeloGPXNeo — Tech Debt
> Last reviewed: July 24, 2026 — open items only; resolved items removed to git history.

---

## 🔴 P0 — Fix Immediately

_None currently open._

---

## 🟠 Open Modernization

### MK-6 — `POIModel` missing `mapItemIdentifier` + `mapsURL` (Place IDs)

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
> **Full spec:** `Docs/Specs/F-B_PlaceIDs.md`

---

### MISC-1 — `onChange(of:perform:)` deprecated iOS 17 🔴 Elevate: iOS 26 min means this is a real warning

**Affects:** `RideView.swift:232`

```swift
// Before (iOS 16 API, deprecated in 17)
.onChange(of: someValue) { newValue in ... }

// After
.onChange(of: someValue) { _, newValue in ... }
```

---

### MISC-4 — Unused `windowMeters` immutable value

**Affects:** `RouteModel.swift:190` (both VeloGPX and Watch targets)

```swift
let windowMeters = ...  // never read after assignment
```
Either use it or replace with `_`.

---

### MISC-5 — Duplicated `bearing()` haversine function — Partial

**Affects:** `RideSessionStore.swift`, `GPXCueEngine.swift`

Canonical `bearing(to:)`, `midpoint(to:)`, `destination(bearing:distance:)` added to
`Shared/Extensions/CLLocationCoordinate2D+Extensions.swift` (May 17, 2026).
Duplicates in `RideSessionStore` and `GPXCueEngine` still remain — deferred to Sprint 6.

---

### MISC-6 — Notification permission result silently ignored

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

- [ ] **Extract `RideView` into sub-views** (`RideView.swift` ~37 KB — God View)
  Candidates: `RideMapLayer`, `RideHUDPanel`, `RideBirdsEyePanel`

- [ ] **Split `RideSessionStore` (~30 KB God Object)**
  Proposed split: `RideLocationEngine`, `POITrackingEngine`, `WatchSyncManager`

- [ ] **MK-6 / F-B — `POIModel` Place IDs + Unified Maps URLs** — see MK-6 above

- [ ] **`POIDiscoverySheet` vs `NearbySearchSheet`** — merge into `POISheet(mode:)` with `.preRide | .midRide` before 1.0

- [ ] **POI persistence** — consolidate scattered `RouteStore` call sites before 1.0

---

## 🟢 P2 — Backlog

- [ ] **`buildSnapIndexCache` O(N×M) on main thread** — `PreRidePOISheet.swift:102-117`
- [ ] **`updateNextPOI` scans all POIs on every location update** — `RideSessionStore.swift:491-551`
- [ ] **`elevationSamples` recomputed on every body evaluation** — `RouteDetailView.swift:236-252`
- [ ] **Empty `catch` blocks swallow errors silently** — `RideSummaryView.swift:296`, `RideHistoryView.swift:231`, `RideHistoryDetailView.swift:266,346`
- [ ] **Notification auth result silently ignored** — see MISC-6 above
- [ ] **Generic "Import failed" message** — `RouteStore.swift:79`
- [ ] **Elevation gain noise smoothing** — threshold gate (> 2 m delta) in `RideSessionStore` altitude accumulation
- [ ] **`MapStyle` — expose cycling overlay toggle** — `.standard` / `.hybrid(elevation: .realistic)`

---

## 🔵 P3 — Nice to Have

- [ ] **`RideHistoryStore` has no pagination** — SwiftData migration or paginated JSON reads; required before 200+ ride users
- [ ] **Hardcoded English strings** — route all user-visible strings through `LocalizationManager`
- [ ] **No unit tests for core logic** — `minimumDistance`, `updateNextPOI`, elevation accumulation, `bearing()`
- [ ] **`RideSessionStore+Spurs.swift` accesses internal properties** — use `private(set)` or extract
- [ ] **`AppleLanguages` UserDefaults key is fragile** — `LocalizationManager.swift:126`
- [ ] **Implicitly unwrapped optional `CLLocationManager`** — `RideSessionStore.swift:37`
- [ ] **Force-unwrap of `min()`/`max()` on coordinate arrays** — `RideSummaryView`, `RideHistoryView`, `RideHistoryDetailView`
