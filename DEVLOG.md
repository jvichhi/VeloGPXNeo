# VeloGPXNeo — Dev Log
> Active work tracker. Updated each session so the next session can onboard instantly.
> For longer-lived tech debt, see `TECH_DEBT.md`.

---

## Current State — May 13, 2026 (end of night)

**Build:** ✅ Clean — zero warnings, zero bugs (iOS 26+, SwiftUI / MapKit / CoreLocation / Supabase / WatchConnectivity)

**iOS target:** iOS 26+ only. No backward-compatibility shims required.

---

## Session Summary — May 13, 2026 (late night)

| Commit | What |
|---|---|
| `a77af46` | **DOCS** `ROADMAP.md` created — 4-sprint prioritised work order pulling from DEVLOG + FEATURES + TECH_DEBT |
| `cc8f2fc` | **MISC-2** Removed spurious `await` on sync `plan.loadFrom(route:)` in `PlanView.swift:62,72` |
| `a587b44` | **AC-3** `WatchRideSummary` — split `Codable` into a `nonisolated extension` to fix Swift 6 actor isolation warning in `WatchRideStore` |
| `a587b44` | **MISC-3** Added `AccentColor.colorset` to `iPhone/Assets.xcassets` (green light/dark, matches app palette) |
| (pre-session) | **MK-1** `MKPlacemark/init(placemark:)` → `MKMapItem(location:address:)` — already done in code, now marked resolved |
| (pre-session) | **MK-2** `MKMapItem.placemark` reads → `.location`/`.address` — already done in code, now marked resolved |
| (pre-session) | **MK-3** `CLGeocoder` → `MKReverseGeocodingRequest` — already done in code, now marked resolved |
| (pre-session) | **MK-4** `UIScreen.main` → `@Environment(\.displayScale)` + `GeometryReader` — already done in code, now marked resolved |
| (pre-session) | **AC-1** Swift 6 `clCoordinate`/`route`/`distance(to:)` — already fixed via raw Double lat/lon across async boundaries |
| (pre-session) | **AC-2** Swift 6 `TurnInstruction.init` nonisolated — already fixed via `CueSheetEntry(lat:lon:)` nonisolated init |

**Key discovery this session:** Code was significantly ahead of docs. MK-1 through MK-4 and AC-1/2 were all already resolved in source — ROADMAP and TECH_DEBT updated to reflect reality.

---

## Previously Landed (May 12–13 evening)

| Commit | What |
|---|---|
| `c299bc1` | **P0** GPX locale crash — `String(format: "%f", ...)` for all lat/lon in `GPXExporter.swift` |
| `c299bc1` | **P1** `RideSessionStore` `deinit` added — cancels `errorClearTask`, invalidates `elapsedTimer` |
| `c299bc1` | **P1** `[weak self]` in `showError` Task closure — prevents retain cycle |
| `c299bc1` | **P1** Heading guard — `didUpdateHeading` guards `heading != 0 \|\| trueHeading >= 0` |
| `c299bc1` | **P1** `RouteLibraryView` `.constant()` alert replaced with `@State var showImportAlert` + `.onChange` |
| `c299bc1` | **P1** `RouteStore` force-unwrap crash — `storageDirectory()` + `poisStorageURL()` now throw |
| `842fb65` | **MK-5** `POISearchService` — typed `MKPointOfInterestFilter` for category searches |
| `842fb65` | **P0** `POIDiscoverySheet` — POI ID collision fixed with `deterministicID(for:)` |
| `842fb65` | **P0** `POIDiscoverySheet` — category detection upgraded to `item.pointOfInterestCategory` |
| `842fb65` | **P1** Watch haptic loop fixed — `didAlertOffRoute` flag in `WatchRideStore` |

---

## Next to Code — Sprint 1 Remaining

Sprint 1 is nearly done. Five small items left — all low-risk, no architecture changes.

| ID | File | What | Effort |
|---|---|---|---|
| **MISC-1** | `RideView.swift:232` | `onChange(of:perform:)` → two-argument form | 1 line |
| **MISC-4** | `RouteModel.swift:190` | Remove unused `let windowMeters` | 1 line |
| **MISC-5** | `RideSessionStore.swift` + `GPXCueEngine` | Extract duplicate `bearing()` to `CLLocationCoordinate2D+Bearing.swift` | New file |
| **MISC-6** | `RideSessionStore.swift:92` | Store `notificationsGranted` flag; gate all notification calls | ~10 lines |
| **MK-6 / F-B** | `POIModel`, 3 sheets | `mapItemIdentifier` + `mapsURL` + "Open in Maps" button | Medium |

After those five, Sprint 1 is complete and Sprint 2 (on-device AI / FoundationModels) begins.

---

## Open Bugs

*(None — all P0/P1 bugs resolved)*

---

## Open Features

| # | Feature | Sprint | Notes |
|---|---|---|---|
| MK-6 / F-B | `POIModel` Place IDs + `mapsURL` | 1 | Last Sprint 1 feature item — see Next to Code above |
| F-A | On-device AI — `VeloAISession` wrapper (FoundationModels) | 2 | Shared session wrapper, must land first |
| F-A1 | Ride Summary Generation | 2 | Depends on F-A |
| F-A2 | Smart Route Naming | 2 | Depends on F-A + MK-3 (done) |
| F-A3 | POI Relevance Ranking | 2 | Depends on F-A |
| F-C1 | RidePlanAssistant core | 3 | Natural language → multi-stop route, depends on F-A |
| F-C2 | RidePlanAssistant polish | 3 | Stop icons, dwell time, Save/Discard UX |
| F-3 | `RideView` God View split | 3 | Extract `RideMapLayer`, `RideHUDPanel` — do during F-C2 |
| F-4 | `RideSessionStore` God Object split | 4 | Extract `POITrackingEngine` — do during P2 perf fixes |

---

## Remaining Warnings (Xcode) — End of May 13

| ID | File | Warning | Priority |
|---|---|---|---|
| MISC-1 | `RideView.swift:232` | `onChange(of:perform:)` deprecated | Low |
| MISC-4 | `RouteModel.swift:190` | Unused `windowMeters` immutable value | Low |
| MISC-5 | `RideSessionStore.swift` / `GPXCueEngine` | Duplicate `bearing()` haversine | Low |
| MISC-6 | `RideSessionStore.swift:92` | Notification auth result silently ignored | Medium |

> All AC-* warnings (AC-1, AC-2, AC-3), all MK-* deprecations (MK-1 through MK-4), and MISC-2/3 are resolved.

---

## Notes / Watch-outs

- **iOS 26+ only.** No backward-compatibility shims needed. Gate with `#available` only for Watch-target-safe files.
- **`MKMapItem.identifier`** — iOS 18+. Gate with `#available(iOS 18, *)` to keep Watch target clean. Always true on iOS 26+ phone target.
- **Water fountain POI** — `POISearchService` maps "Water" to `.nationalPark` proxy. No SDK constant yet. Watch WWDC / SDK notes.
- `RideSessionStore.swift` is ~30 KB. F-4 split is overdue — do incrementally during Sprint 4 perf work, not as a standalone refactor.
- `POIDiscoverySheet` vs `NearbySearchSheet` still overlap. Merge into one sheet (`mode: .preRide | .midRide`) before 1.0.
- `RouteStore+POI.swift` is thin (866 B) — POI persistence scattered. Consolidate before 1.0.
- **`POIModel` is `Codable`** — adding optional fields is backwards-compatible. No migration needed for existing persisted POI files.
- **`GPXCueEngine` `bearing()` vs `RideSessionStore` `bearing()`** — both are identical haversines. MISC-5 consolidates them into `CLLocationCoordinate2D+Bearing.swift`. `GPXCueEngine` already has a `nonisolated` copy which can become the canonical one.
