# VeloGPXNeo — Dev Log
> Active work tracker. Updated each session so the next session can onboard instantly.
> For longer-lived tech debt, see `TECH_DEBT.md`.

---

## Current State — May 12, 2026 (late evening)

**Build:** ✅ Clean (iOS 26+, SwiftUI / MapKit / CoreLocation / Supabase / WatchConnectivity)

---

## Recently Landed (this session)

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

---

## In Progress — Next to Code

Nothing currently in flight. Build is clean.

---

## Open Bugs

- **Watch haptic loop** — `WatchRideStore.swift`: haptic fires every second while off-route. Add `didAlertOffRoute` flag. *(Quick fix, ~15 min)*

---

## Open Features

| # | Feature | Notes |
|---|---|---|
| F-3 | `RideView` God View split | Extract `RideMapLayer`, `RideHUDPanel`, `RideBirdsEyePanel` — see TECH_DEBT P1 |
| F-4 | `RideSessionStore` God Object split | `RideLocationEngine` + `POITrackingEngine` + `WatchSyncManager` — see TECH_DEBT P1 |

---

## Notes / Watch-outs

- **MK-2 placemark reads** — `NearbySearchSheet`, `POIDiscoverySheet`, `ReverseGeocodingService`, `PlaceDescriptorService` all still read `mapItem.placemark.coordinate` / `.title` (deprecated iOS 26). These are warnings now; will be errors when min deployment target passes iOS 26. Track as MK-2 in TECH_DEBT.
- **Water fountain POI category** — `POISearchService` maps "Water" to `.nationalPark` as a proxy. No `MKPointOfInterestCategory` constant for drinking fountains exists yet in the iOS 26 SDK. Watch WWDC / SDK release notes.
- `RideSessionStore.swift` is ~30 KB. F-4 God Object split is overdue — do before adding more ride features.
- `POIDiscoverySheet` vs `NearbySearchSheet` still overlap in purpose. Worth merging into one sheet with `mode: .preRide | .midRide` before 1.0.
- `RouteStore+POI.swift` still thin (866 B) — POI persistence scattered. Consolidate before 1.0.
