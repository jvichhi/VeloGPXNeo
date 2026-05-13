# VeloGPXNeo — Dev Log
> Active work tracker. Updated each session so the next session can onboard instantly.
> For longer-lived tech debt, see `TECH_DEBT.md`.

---

## Current State — May 13, 2026 (late night)

**Build:** ✅ Clean (iOS 26+, SwiftUI / MapKit / CoreLocation / Supabase / WatchConnectivity)

---

## Recently Landed (this session — May 12 evening)

| Commit | What |
|---|---|
| `c299bc1` | **P0** GPX locale crash — `String(format: "%f", ...)` for all lat/lon in `GPXExporter.swift` |
| `c299bc1` | **P1** `RideSessionStore` `deinit` added — cancels `errorClearTask`, invalidates `elapsedTimer` |
| `c299bc1` | **P1** `[weak self]` in `showError` Task closure — prevents retain cycle |
| `c299bc1` | **P1** Heading guard — `didUpdateHeading` now guards `heading != 0 \|\| trueHeading >= 0` |
| `c299bc1` | **P1** `RouteLibraryView` `.constant()` alert replaced with `@State var showImportAlert` + `.onChange` |
| `c299bc1` | **P1** `RouteStore` force-unwrap crash — `storageDirectory()` + `poisStorageURL()` now throw instead of `first!` |
| `842fb65` | **MK-5** `POISearchService` — typed `MKPointOfInterestFilter` for category searches (iOS 18+/26) |
| `842fb65` | **P0** `POIDiscoverySheet` — POI ID collision fixed with `deterministicID(for:)` |
| `842fb65` | **P0** `POIDiscoverySheet` — category detection upgraded to `item.pointOfInterestCategory` |
| `842fb65` | **P1** Watch haptic loop fixed — `didAlertOffRoute: Bool` flag in `WatchRideStore`; resets on `isOffRoute → false` |

---

## In Progress — Next to Code

### F-5 — Foundational Models: `mapItemIdentifier` + `mapsURL` on `POIModel`

**Goal:** Every POI created from an `MKMapItem` search result carries a stable Apple Maps Place ID and a deep-link `maps://` URL. Enables:
- Correct deduplication (replaces coordinate-based `deterministicID` as primary key for search-derived POIs)
- "Open in Maps" one-tap action from any POI detail view
- Future: share route POI list as tappable Maps deep links

**Plan:**
1. Add two optional fields to `POIModel`:
   ```swift
   public var mapItemIdentifier: String?   // MKMapItem.identifier.rawValue (iOS 18+)
   public var mapsURL: URL?                // maps://?auid=<identifier> deep link
   ```
2. In `POIModel.init(from mapItem:)` factory (new static func in `POIModel+MapKit.swift`):
   ```swift
   // iOS 18+
   if #available(iOS 18, *) {
       model.mapItemIdentifier = mapItem.identifier?.rawValue
       model.mapsURL = mapItem.identifier.flatMap {
           URL(string: "maps://?auid=\($0.rawValue)")
       }
   }
   ```
3. Update `deterministicID(for:)` fallback: still used for custom/manual POIs and any POI without a `mapItemIdentifier`.
4. Update `isAdded` checks in `NearbySearchSheet` + `POIDiscoverySheet`: prefer `mapItemIdentifier` equality when both sides have one; fall back to coordinate hash.
5. Add `"Open in Maps"` button to `NearbyResultCard` / POI detail row — `UIApplication.shared.open(poi.mapsURL)`.

**Files to touch:**
- `Shared/Models/POIModel.swift` — add two optional fields + new `init` params
- `Shared/Models/POIModel+MapKit.swift` — NEW file: `static func from(_ mapItem: MKMapItem) -> POIModel`
- `iPhone/Views/NearbySearchSheet.swift` — update `isAdded` + add Open in Maps button
- `iPhone/Views/POIDiscoverySheet.swift` — same
- `iPhone/Views/PreRidePOISheet.swift` — same
- `iPhone/Views/NearbyResultCard.swift` (if it exists) or inline card row

**Gotcha:** `MKMapItem.identifier` is iOS 18+. Gate with `#available(iOS 18, *)`. The coordinate-based `deterministicID` remains the universal fallback so Watch + older-device builds are unaffected.

---

## Open Bugs

*(None — all P0/P1 bugs from May 12 resolved)*

---

## Open Features

| # | Feature | Notes |
|---|---|---|
| F-3 | `RideView` God View split | Extract `RideMapLayer`, `RideHUDPanel`, `RideBirdsEyePanel` — see TECH_DEBT P1 |
| F-4 | `RideSessionStore` God Object split | `RideLocationEngine` + `POITrackingEngine` + `WatchSyncManager` — see TECH_DEBT P1 |
| F-5 | Foundational Models: `mapItemIdentifier` + `mapsURL` on `POIModel` | See In Progress above |
| F-6 | Unified Maps URLs + Place IDs — "Open in Maps" from POI detail | Depends on F-5 |

---

## Notes / Watch-outs

- **MK-2 placemark reads** — `NearbySearchSheet`, `POIDiscoverySheet`, `ReverseGeocodingService`, `PlaceDescriptorService` all still read `mapItem.placemark.coordinate` / `.title` (deprecated iOS 26). These are warnings now; will be errors when min deployment target passes iOS 26. Track as MK-2 in TECH_DEBT.
- **`MKMapItem.identifier` availability** — iOS 18+ only. Always gate with `#available(iOS 18, *)` and keep the coordinate-based `deterministicID` as the universal fallback.
- **Water fountain POI category** — `POISearchService` maps "Water" to `.nationalPark` as a proxy. No `MKPointOfInterestCategory` constant for drinking fountains exists yet in the iOS 26 SDK. Watch WWDC / SDK release notes.
- `RideSessionStore.swift` is ~30 KB. F-4 God Object split is overdue — do before adding more ride features.
- `POIDiscoverySheet` vs `NearbySearchSheet` still overlap in purpose. Worth merging into one sheet with `mode: .preRide | .midRide` before 1.0.
- `RouteStore+POI.swift` still thin (866 B) — POI persistence scattered. Consolidate before 1.0.
- **`POIModel` is `Codable`** — adding optional fields is backwards-compatible (old JSON without them decodes fine). No migration needed for existing persisted POI files.
