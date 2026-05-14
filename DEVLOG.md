# VeloGPXNeo — Dev Log
> Active work tracker. Updated each session so the next session can onboard instantly.
> For longer-lived tech debt, see `TECH_DEBT.md`.

---

## Current State — May 13, 2026 (end of night)

**Build:** ✅ Clean — zero warnings, zero errors (iOS 26+, SwiftUI / MapKit / CoreLocation / Supabase / WatchConnectivity)

**Sprint 1:** ✅ Complete — verified via code search. All 15 items done.

**Next session starts at:** Sprint 2 · F-A Shared — `FoundationModels` framework + `VeloAISession` wrapper.

---

## Session Summary — May 13, 2026 (late night)

| Item | Status | Notes |
|---|---|---|
| `ROADMAP.md` created | ✅ | `a77af46` — 4-sprint prioritised work order |
| End-of-session doc cleanup | ✅ | `4bdbc9b` — DEVLOG, TECH_DEBT, ROADMAP synced |
| Sprint 1 code verification | ✅ | Code search confirmed all 5 "remaining" items already done in source |
| ROADMAP Sprint 1 marked complete | ✅ | This commit |

**Key discovery:** Code was consistently ahead of docs all session. MK-1/2/3/4, AC-1/2, and all MISC items were resolved in source before we even started documenting them. Sprint 1 is fully complete.

---

## Previously Landed (May 12–13)

| Commit | What |
|---|---|
| `c299bc1` | **P0** GPX locale crash — `String(format: "%f", ...)` for all lat/lon in `GPXExporter.swift` |
| `c299bc1` | **P1** `RideSessionStore` `deinit` — cancels `errorClearTask`, invalidates `elapsedTimer` |
| `c299bc1` | **P1** `[weak self]` in `showError` Task closure |
| `c299bc1` | **P1** Heading guard — `didUpdateHeading` guards `heading != 0 \|\| trueHeading >= 0` |
| `c299bc1` | **P1** `RouteLibraryView` `.constant()` alert replaced with `@State var showImportAlert` |
| `c299bc1` | **P1** `RouteStore` force-unwrap crash — `storageDirectory()` + `poisStorageURL()` now throw |
| `842fb65` | **MK-5** `POISearchService` — typed `MKPointOfInterestFilter` |
| `842fb65` | **P0** `POIDiscoverySheet` — POI ID collision fixed with `deterministicID(for:)` |
| `842fb65` | **P0** `POIDiscoverySheet` — category detection upgraded to `item.pointOfInterestCategory` |
| `842fb65` | **P1** Watch haptic loop fixed — `didAlertOffRoute` flag in `WatchRideStore` |
| `a587b44` | **AC-3** `WatchRideSummary` — `Codable` split into `nonisolated extension` |
| `a587b44` | **MISC-3** `AccentColor.colorset` added to `iPhone/Assets.xcassets` |
| `cc8f2fc` | **MISC-2** Removed spurious `await` on sync `plan.loadFrom(route:)` |

---

## Next to Code — Sprint 2

Order matters: **F-A Shared wrapper must land first** — F-A1/A2/A3 all depend on it.
After the wrapper, F-A1/A2/A3 can be built in any order.

| ID | What | New Files | Effort |
|---|---|---|---|
| **F-A Shared** | Add `FoundationModels` to Build Phases + `VeloAISession` wrapper + Settings toggle | `iPhone/Services/VeloAISession.swift` | Small |
| **F-A1** | Ride Summary Generation — "Generate Summary" in `RideSummaryView` | `iPhone/Services/RideSummaryGenerator.swift` | Medium |
| **F-A2** | Smart Route Naming — 3 AI name suggestions on import/rename | `iPhone/Services/RouteNameSuggester.swift` | Medium |
| **F-A3** | POI Relevance Ranking — "Suggested" sort in POI sheets | `iPhone/Services/POIRankingEngine.swift` | Medium |

Full specs for all four in `FEATURES.md § F-A`.

---

## Open Bugs

*(None — all P0/P1 bugs resolved)*

---

## Open Features

| # | Feature | Sprint | Notes |
|---|---|---|---|
| F-A Shared | `FoundationModels` + `VeloAISession` wrapper | **2 — next** | Must land before F-A1/A2/A3 |
| F-A1 | Ride Summary Generation | 2 | Depends on F-A |
| F-A2 | Smart Route Naming | 2 | Depends on F-A |
| F-A3 | POI Relevance Ranking | 2 | Depends on F-A |
| F-C1 | RidePlanAssistant core | 3 | Natural language → multi-stop route |
| F-C2 | RidePlanAssistant polish | 3 | Stop icons, dwell time, Save/Discard UX |
| F-3 | `RideView` God View split | 3 | Incremental during F-C2 |
| F-4 | `RideSessionStore` God Object split | 4 | Incremental during Sprint 4 perf fixes |

---

## Remaining Warnings (Xcode) — End of May 13

**None.** Zero warnings, zero errors. Clean build.

---

## Notes / Watch-outs

- **iOS 26+ only.** No backward-compatibility shims. Gate with `#available` only for Watch-target-safe files.
- **`FoundationModels` is iOS only** — never add AI service files to the Watch target.
- **`MKMapItem.identifier`** — iOS 18+. Gate with `#available(iOS 18, *)` for Watch target. Always true on iOS 26+ phone target.
- **Water fountain POI** — `POISearchService` maps "Water" to `.nationalPark` as proxy. No SDK constant yet.
- `RideSessionStore.swift` is ~30 KB. F-4 split is overdue — do incrementally during Sprint 4, not standalone.
- `POIDiscoverySheet` vs `NearbySearchSheet` overlap — merge into `mode: .preRide | .midRide` before 1.0.
- `RouteStore+POI.swift` is thin (866 B) — POI persistence scattered. Consolidate before 1.0.
- **`POIModel` is `Codable`** — adding optional fields is backwards-compatible. No migration needed.
