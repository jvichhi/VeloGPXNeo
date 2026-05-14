# VeloGPXNeo — Dev Log
> Active work tracker. Updated each session so the next session can onboard instantly.
> For longer-lived tech debt, see `TECH_DEBT.md`.

---

## Current State — May 13, 2026 (late night)

**Build:** ✅ Clean (iOS 26+, SwiftUI / MapKit / CoreLocation / Supabase / WatchConnectivity)

**iOS target:** iOS 26+ only. No backward-compatibility shims required.

---

## Recently Landed (this session — May 13 late)

| Commit | What |
|---|---|
| `a77af46` | **DOCS** `ROADMAP.md` created — 4-sprint prioritised work order pulling from DEVLOG + FEATURES + TECH_DEBT |
| `cc8f2fc` | **MISC-2** Removed spurious `await` on synchronous `plan.loadFrom(route:)` in `PlanView.swift:62,72` — clears two Xcode warnings. Zero behaviour change (`loadFrom` was and remains `@MainActor` sync; the `await` was a no-op hop on an already-MainActor context). |

---

## Recently Landed (May 12–13 evening)

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

### MK-6 / F-B — `mapItemIdentifier` + `mapsURL` on `POIModel`

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

**Gotcha:** `MKMapItem.identifier` is iOS 18+. Gate with `#available(iOS 18, *)`. The coordinate-based `deterministicID` remains the universal fallback so Watch builds are unaffected. Since we target iOS 26+, the `#available` gate will always be true on device — it exists purely to keep the Watch target clean.

---

## Open Bugs

*(None — all P0/P1 bugs resolved)*

---

## Open Features

| # | Feature | Notes |
|---|---|---|
| MK-6 / F-B | `POIModel` Place IDs + `mapsURL` | **Next to code** — see In Progress above |
| F-3 | `RideView` God View split | Extract `RideMapLayer`, `RideHUDPanel`, `RideBirdsEyePanel` — see TECH_DEBT P1 |
| F-4 | `RideSessionStore` God Object split | `RideLocationEngine` + `POITrackingEngine` + `WatchSyncManager` — see TECH_DEBT P1 |
| F-A | On-device AI — `VeloAISession` wrapper (FoundationModels) | Shared session wrapper, Sprint 3 |
| F-A1 | Ride Summary Generation | On-device AI, iOS 26+, depends on F-A |
| F-A2 | Smart Route Naming | On import or rename, depends on F-A |
| F-A3 | POI Relevance Ranking | Context-aware "Suggested" sort, depends on F-A |
| F-C1 | RidePlanAssistant core | Natural language → multi-stop route, depends on F-A |
| F-C2 | RidePlanAssistant polish | Stop icons, dwell time, Save/Discard UX |

---

## Remaining Warnings (Xcode)

| ID | File | Warning | Priority |
|---|---|---|---|
| MISC-1 | `RideView.swift:232` | `onChange(of:perform:)` deprecated iOS 17 | Low |
| MISC-3 | `iPhone/Assets.xcassets` | Missing `AccentColor` color set | Low |
| MISC-4 | `RouteModel.swift:190` | Unused `windowMeters` immutable value | Low |
| MISC-5 | `RideSessionStore.swift` / `GPXCueEngine` | Duplicate `bearing()` haversine function | Low |
| MISC-6 | `RideSessionStore.swift:92` | Notification permission result silently ignored | Medium |
| AC-1 | `CyclingRouteService.swift` (14 sites) | Swift 6 actor isolation: `clCoordinate`/`route`/`distance(to:)` on wrong actor | Medium |
| AC-2 | `CyclingRouteService.swift:245,257,273` | Swift 6: `TurnInstruction.init` in nonisolated context | Medium |
| AC-3 | `WatchRideStore.swift:23` | Swift 6: `WatchRideSummary` `Decodable` on wrong actor | Medium |

---

## Notes / Watch-outs

- **iOS 26+ only.** No backward-compatibility shims or `#available(iOS X, *)` guards needed except where the Watch target also compiles the same file.
- **`MKMapItem.identifier` availability** — iOS 18+ only. Always gate with `#available(iOS 18, *)` to keep the Watch target clean. On our iOS 26+ phone target this is always true.
- **Water fountain POI category** — `POISearchService` maps "Water" to `.nationalPark` as a proxy. No `MKPointOfInterestCategory` constant for drinking fountains exists yet in the iOS 26 SDK. Watch WWDC / SDK release notes.
- `RideSessionStore.swift` is ~30 KB. F-4 God Object split is overdue — do before adding more ride features.
- `POIDiscoverySheet` vs `NearbySearchSheet` still overlap in purpose. Worth merging into one sheet with `mode: .preRide | .midRide` before 1.0.
- `RouteStore+POI.swift` still thin (866 B) — POI persistence scattered. Consolidate before 1.0.
- **`POIModel` is `Codable`** — adding optional fields is backwards-compatible (old JSON without them decodes fine). No migration needed for existing persisted POI files.
