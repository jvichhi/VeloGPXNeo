# VeloGPXNeo — Roadmap
> Last updated: May 13, 2026 (late night — Sprint 1 verified complete via code search)
> Source of truth for sprint order. Each session: open this file first, pick the next item off the top, build it.
> For implementation details → `DEVLOG.md` (current sprint), `FEATURES.md` (feature specs), `TECH_DEBT.md` (debt catalogue).

---

## How This Works

- **Sprints are ordered.** Work top-to-bottom. Don't skip ahead unless explicitly noted as parallel-safe.
- **Each item has a `→ Spec` link** pointing to where the full implementation plan lives.
- **Checkboxes track completion.** Check an item off here + update DEVLOG when landing a commit.
- **iOS 26 minimum.** No availability gating for iOS 25 or below. Use iOS 26 APIs freely. Gate only for `MKMapItem.identifier` (iOS 18+) since it's a nice-to-have enhancement on top of the coordinate fallback, not a required baseline.
- **God object splits (F-3, F-4) are incremental — not a dedicated sprint.** They're high-risk refactors with no user-visible output and zero test coverage as a safety net. Instead, each split happens naturally when we're already in that file for a feature. See Sprint 3 and Sprint 4 notes.

---

## ✅ Sprint 1 — Foundation & Debt Clearance
> **COMPLETE** as of May 13, 2026. All items verified in source code.

- [x] **MK-1** `MKPlacemark/init(placemark:)` → `MKMapItem(location:address:)` — verified in code
- [x] **MK-2** `MKMapItem.placemark` reads → `.location`/`.address` — verified in code
- [x] **MK-3** `CLGeocoder` → `MKReverseGeocodingRequest` — verified in code
- [x] **MK-4** `UIScreen.main` → `@Environment(\.displayScale)` + `GeometryReader` — verified in code
- [x] **MK-5** `POISearchService` typed `MKPointOfInterestFilter` — May 12
- [x] **MK-6 / F-B** `POIModel` Place IDs + `mapsURL` + "Open in Maps" button — verified in build
- [x] **AC-1** Swift 6 `clCoordinate`/`route`/`distance(to:)` across async boundary — verified in code
- [x] **AC-2** Swift 6 `TurnInstruction.init` nonisolated — verified in code
- [x] **AC-3** `WatchRideSummary` `Decodable` on wrong actor — `a587b44`
- [x] **MISC-1** `onChange(of:perform:)` → two-argument form — verified in code (zero hits in Swift files)
- [x] **MISC-2** Spurious `await` on `plan.loadFrom(route:)` — `cc8f2fc`
- [x] **MISC-3** `AccentColor` missing from Assets catalog — `a587b44`
- [x] **MISC-4** Unused `windowMeters` immutable value — verified in code (zero hits)
- [x] **MISC-5** Duplicate `bearing()` haversine — verified in code (consolidated)
- [x] **MISC-6** Notification auth result gating — verified in code

---

## 🔲 Sprint 2 — On-Device AI (FoundationModels, iOS 26)
> **NEXT — start here next session.**
> Goal: ship the three standalone AI features. Targets v1.3.
> Add `FoundationModels` to Build Phases + `VeloAISession` shared wrapper first, then the three features can be built in any order.
>
> **F-A3 touches `POIDiscoverySheet` / `NearbySearchSheet`.** While in those files, opportunistically begin the sheet merge (see Backlog). Don't block shipping F-A3 on it — but if the merge is small, do it in the same commit.

- [ ] **F-A Shared · Add `FoundationModels` framework + `VeloAISession` wrapper**
  Single shared session wrapper. Add user toggle in `SettingsView` — "AI Features (Apple Intelligence)" — with on-device explanation. Gate all AI UI on `ModelAvailability.isAvailable`.
  → `FEATURES.md § F-A (Shared Implementation Notes)`

- [ ] **F-A1 · Ride Summary Generation**
  Post-ride natural language summary from `RideSummary` data. "Generate Summary" button in `RideSummaryView` below stats grid. Editable before sharing.
  → `FEATURES.md § F-A1`
  **New file:** `iPhone/Services/RideSummaryGenerator.swift`

- [ ] **F-A2 · Smart Route Naming**
  On GPX import or rename tap, suggest 3 names via reverse geocode + model. Pill picker in rename sheet in `RouteLibraryView`. Uses `MKReverseGeocodingRequest` (MK-3 already done).
  → `FEATURES.md § F-A2`
  **New file:** `iPhone/Services/RouteNameSuggester.swift`

- [ ] **F-A3 · POI Relevance Ranking**
  Context-aware "Suggested" sort in `POIDiscoverySheet` / `NearbySearchSheet`. Uses ride difficulty, elevation gain, elapsed distance, time-of-day, and `RideHistoryStore` category frequency.
  → `FEATURES.md § F-A3`
  **New file:** `iPhone/Services/POIRankingEngine.swift`

---

## Sprint 3 — RidePlanAssistant (FoundationModels + MKLocalSearch, iOS 26)
> Goal: natural language → multi-stop route in the Routes tab. Targets v1.4.
> Requires F-A shared session wrapper from Sprint 2.
>
> **F-3 (`RideView` split) — do incrementally here.** F-C2 polish requires touching `RideView` anyway for stop-type icon rendering. When we open `RideView` for F-C2, extract `RideMapLayer` and `RideHUDPanel` at the same time.

- [ ] **F-C1 · RidePlanAssistant — Core**
  `PlanAssistantEngine` orchestrates: model parses `RidePlanIntent` → `MKLocalSearch` resolves stops → `PlanState` + `PlanRouteEngine` computes geometry. `RidePlanAssistantView` inline expandable input in Routes tab. `DisambiguationSheet` for ambiguous place names.
  → `FEATURES.md § F-C1`
  **New files:** `iPhone/Services/PlanAssistantEngine.swift`, `iPhone/Services/RidePlanIntent+Generable.swift`, `iPhone/Views/RidePlanAssistantView.swift`, `iPhone/Views/DisambiguationSheet.swift`
  **Modified:** `RouteLibraryView.swift`, `RouteStore.swift`

- [ ] **F-C2 · RidePlanAssistant — Polish + partial F-3 `RideView` split**
  Stop-type icons in `WaypointListSheet`. Dwell time estimation per stop intent. Total outing time in `WaypointListSheet` header. "AI Planned" temp section in Routes tab (Save / Discard / Start).
  While touching `RideView` for this: extract `RideMapLayer` and `RideHUDPanel` as separate views.
  → `FEATURES.md § F-C2` · `TECH_DEBT.md § F-3`
  **Modified:** `WaypointListSheet.swift`, `PlanState.swift`, `RouteStore.swift`, `RideView.swift`

---

## Sprint 4 — Stability & Pre-1.5 Polish
> Goal: everything needed before the next major App Store submission. No net-new features.
>
> **F-4 (`RideSessionStore` split) — do incrementally here.** P2 perf fixes require opening `RideSessionStore` anyway. Extract `POITrackingEngine` while making those fixes.

- [ ] **P2 · `updateNextPOI` hot-path — pre-compute snap indices + partial F-4 `RideSessionStore` split**
  Pre-compute POI snap indices once when POIs change. While in `RideSessionStore`: extract `POITrackingEngine`.
  → `TECH_DEBT.md § P2` · `TECH_DEBT.md § F-4`

- [ ] **P2 · `buildSnapIndexCache` O(N×M) offload to background**
  `PreRidePOISheet.swift:102–117`. Background task or k-d tree spatial index.

- [ ] **P2 · `elevationSamples` lazy cache in `RouteDetailView`**
  `RouteDetailView.swift:236–252`. Cache result; invalidate only when `trackPoints` changes.

- [ ] **P2 · Surface empty `catch` blocks**
  `RideSummaryView.swift:296`, `RideHistoryView.swift:231`, `RideHistoryDetailView.swift:266,346`. Log + surface via toast.

- [ ] **P2 · `RouteNoticeView` — wire or delete**
  Wire into `CyclingRouteService` result + `topBanners`, or delete. Decide alongside `CyclingRouteOverlay`.

- [ ] **P2 · Merge `POIDiscoverySheet` + `NearbySearchSheet`**
  One sheet with `mode: .preRide | .midRide`. Eliminates overlapping purpose before submission.

- [ ] **P2 · Elevation gain noise smoothing**
  Threshold gate (only accumulate deltas > 2 m) in `RideSessionStore` altitude stream.

- [ ] **P3 · `MapStyle` cycling overlay toggle in Settings**
  Expose `.standard` / `.hybrid(elevation: .realistic)` / cycling lane style.

---

## Backlog — Future

| Item | Where | Notes |
|---|---|---|
| `RideHistoryStore` pagination | — | SwiftData or paginated JSON reads |
| Localization pass | Whole app | Route all user-visible strings through `LocalizationManager` |
| Unit tests for core logic | `Tests/` | `minimumDistance`, `updateNextPOI`, elevation accumulation, `bearing()` |
| `RouteStore+POI.swift` consolidation | `Shared/` | 866 B stub; POI persistence scattered across `RideView` call sites |
| `AppleLanguages` UserDefaults key | `LocalizationManager.swift:126` | Fragile internal key + deprecated `synchronize()`; use Bundle `.lproj` approach |
| IUO `CLLocationManager` | `RideSessionStore.swift:37` | `private let manager = CLLocationManager()` |
| Force-unwrap on coordinate `min()`/`max()` | `RideSummaryView`, `RideHistoryView`, `RideHistoryDetailView` | Optional binding |
| `RideSessionStore+Spurs.swift` internal property access | — | `private(set)` or dedicated spur service |
| Generic "Import failed" message | `RouteStore.swift:79` | Differentiate corrupt file vs. I/O failure |

---

## Dependency Graph

```
Sprint 1: ✅ COMPLETE

Sprint 2: F-A Shared wrapper ──► F-A1, F-A2, F-A3 (any order)
          F-A1 validates VeloAISession pattern ──► Sprint 3 reuses it
          F-A3 in POI sheets ──► opportunistic sheet merge if small

Sprint 3: F-A (Sprint 2 done) ──► F-C1 ──► F-C2 + partial F-3 RideView split

Sprint 4: Performance fixes in RideSessionStore ──► partial F-4 POITrackingEngine extract
          Pre-submission polish items (no feature dependencies)
```

---

## Watch Target Rules

The following must **never** be added to the Watch target in Build Phases:

- `POIModel+MapKit.swift` — uses `MKMapItem.identifier` (iOS only)
- `PlanAssistantEngine.swift` — `FoundationModels` is iOS only
- `RidePlanIntent+Generable.swift` — same
- `RidePlanAssistantView.swift` — same
- Any `FoundationModels` import

The Watch target always uses the coordinate-based `deterministicID` fallback for POI identity.
