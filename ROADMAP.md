# VeloGPXNeo — Roadmap
> Last updated: May 16, 2026 — Sprint 3 complete, F-C1 + F-C2 shipped
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
- [ ] **MISC-5** Duplicate `bearing()` haversine — ⚠️ **REOPENED** — `bearing()` confirmed present in both `RideSessionStore.swift` and `RideView.swift` as of May 15 source search. Was incorrectly marked complete. Extract to `Shared/Extensions/CLLocationCoordinate2D+Bearing.swift` before Sprint 4.
- [x] **MISC-6** Notification auth result gating — verified in code

---

## ✅ Sprint 2 — On-Device AI (FoundationModels, iOS 26)
> **COMPLETE** as of May 15, 2026. All items shipped, clean build confirmed.
> FlowLayout regression introduced in `2f426ba` and fixed in `aa6c614` — see DEVLOG for details.

- [x] **F-A Shared · Add `FoundationModels` framework + `VeloAI` wrapper**
  `VeloAI.swift` — `nonisolated static var isAvailable` gates the entire AI feature set.
  `static let enabledKey` is the `@AppStorage` key used by Settings toggle and all AI views.
  FoundationModels.framework must be added manually in Xcode: Build Phases → Link Binary With Libraries.
  → `FEATURES.md § F-A (Shared Implementation Notes)`
  **New file:** `iPhone/Services/VeloAI.swift`

- [x] **F-A1 · Ride Summary Generation**
  Post-ride natural language summary from `RideSummary` data. Full idle/generating/done/failed
  state machine in `RideSummaryView`. Editable before sharing. Caption persisted to `RideHistoryStore`
  via `saveCaption(id:caption:)`. Uses `session.respond(to: prompt)` — plain string I/O, not `@Generable`.
  → `FEATURES.md § F-A1`
  **New file:** `iPhone/Services/RideSummaryGenerator.swift`

- [x] **F-A2 · Smart Route Naming**
  Rename swipe action (yellow, trailing) + "Rename" context menu item in `RouteLibraryView`.
  `RouteRenameSheet` auto-fetches 3 pill suggestions via `RouteNameSuggester`. Tapping a pill
  fills the text field; user can edit freely before saving. `FlowLayout` (View wrapper) +
  `_FlowLayout` (pure `Layout` — no `@ViewBuilder` storage) implements the pill wrapping.
  Geocodes route start coordinate with `MKReverseGeocodingRequest` — **not** `CLGeocoder` (deprecated iOS 18+).
  → `FEATURES.md § F-A2`
  **New file:** `iPhone/Services/RouteNameSuggester.swift`

- [x] **F-A3 · POI Relevance Ranking**
  Context-aware "Suggested" / "Nearest" / "Category" segmented sort in `POIDiscoverySheet`.
  `POIRankingEngine` (`actor`) scores each POI by ride difficulty, elevation gain, distance,
  and time-of-day. Reason subtitle shown per card. Auto-ranks when AI enabled on search.
  → `FEATURES.md § F-A3`
  **New file:** `iPhone/Services/POIRankingEngine.swift`

---

## ✅ Sprint 3 — RidePlanAssistant (FoundationModels + MKLocalSearch, iOS 26)
> **COMPLETE** as of May 16, 2026. F-C1 + F-C2 shipped.
> F-3 RideView split deferred — will happen incrementally in Sprint 4 when RideView is opened for perf fixes.
> Bugs fixed: civic address resolution uses `MKLocalSearch resultTypes=[.address]`;
> `placardSubtitle` reads address fields via `item.placemark` (CLPlacemark), not directly on MKMapItem.

- [x] **F-C1 · RidePlanAssistant — Core**
  `PlanAssistantEngine` orchestrates: model parses `RidePlanIntent` via `session.respond(to:generating:)`
  (structured `@Generable` output) → `MKLocalSearch` resolves stops → `PlanState` + `PlanRouteEngine`
  computes geometry. `RidePlanAssistantView` sheet with inline disambiguation card.
  Note: `DisambiguationSheet.swift` was folded inline into `RidePlanAssistantView` — no separate file needed.
  → `FEATURES.md § F-C1`
  **New files:** `iPhone/Services/PlanAssistantEngine.swift`, `iPhone/Services/RidePlanIntent+Generable.swift`,
  `iPhone/Views/RidePlanAssistantView.swift`
  **Modified:** `RouteLibraryView.swift`, `RouteStore.swift`, `WaypointListSheet.swift`
  **Watch target:** None of these files may be added to the Watch target — `FoundationModels` is iPhone-only.

- [x] **F-C2 · RidePlanAssistant — Polish**
  Stop-type SF Symbol icons + tint colour per `WaypointStopKind` in `WaypointListSheet`.
  Dwell time chip ("`X min`" capsule) rendered under each AI-planned waypoint name.
  Total outing time (ride time @ 15 km/h + total dwell) in `WaypointListSheet` header stats row.
  "AI Planned" temporary section in Routes tab with Save / Discard / Start actions; one plan at a time.
  → `FEATURES.md § F-C2`
  **Modified:** `WaypointListSheet.swift`, `PlanState.swift`, `RouteStore.swift`
  **F-3 RideView split:** deferred to Sprint 4.

---

## Sprint 4 — Stability & Pre-1.5 Polish
> Goal: everything needed before the next major App Store submission. No net-new features.
>
> **F-4 (`RideSessionStore` split) — do incrementally here.** P2 perf fixes require opening
> `RideSessionStore` anyway. Extract `POITrackingEngine` while making those fixes.
>
> **F-3 (`RideView` split) — pick up here.** Deferred from Sprint 3. Extract `RideMapLayer`
> and `RideHUDPanel` when first opening `RideView` for any Sprint 4 item.

- [ ] **P2 · `updateNextPOI` hot-path — pre-compute snap indices + partial F-4 `RideSessionStore` split**
  Pre-compute POI snap indices once when POIs change. While in `RideSessionStore`: extract `POITrackingEngine`.
  → `TECH_DEBT.md § P2` · `TECH_DEBT.md § F-4`

- [ ] **P2 · `buildSnapIndexCache` O(N×M) offload to background**
  `PreRidePOISheet.swift:102–117`. Background task or k-d tree spatial index.

- [ ] **P2 · `elevationSamples` lazy cache in `RouteDetailView`**
  `RouteDetailView.swift:236–252`. Cache result; invalidate only when `trackPoints` changes.

- [ ] **P2 · Surface empty `catch` blocks**
  `RideSummaryView.swift:296`, `RideHistoryView.swift:231`, `RideHistoryDetailView.swift:266,346`.
  Log + surface via toast.

- [ ] **P2 · `RouteNoticeView` — wire or delete**
  Wire into `CyclingRouteService` result + `topBanners`, or delete.
  Decide alongside `CyclingRouteOverlay`.

- [ ] **P2 · Merge `POIDiscoverySheet` + `NearbySearchSheet`**
  One sheet with `mode: .preRide | .midRide`. Eliminates overlapping purpose before submission.

- [ ] **P2 · Elevation gain noise smoothing**
  Threshold gate (only accumulate deltas > 2 m) in `RideSessionStore` altitude stream.

- [ ] **MISC-5 · Extract duplicate `bearing()` haversine**
  `bearing()` confirmed still present in both `RideSessionStore.swift` and `RideView.swift` (May 15 source search).
  Extract to `Shared/Extensions/CLLocationCoordinate2D+Bearing.swift`. Use `GPXCueEngine`'s `nonisolated` version as the canonical one; delete the duplicate from `RideSessionStore`.
  → `TECH_DEBT.md § MISC-5`

- [ ] **P3 · `MapStyle` cycling overlay toggle in Settings**
  Expose `.standard` / `.hybrid(elevation: .realistic)` / cycling lane style.

---

## Sprint 5 — Draw Route (Strava Parity)
> Goal: finger-draw road-snapped route creation. User draws on the map; `MKDirections` snaps
> gesture segments to the cycling road network in real time. Result feeds the existing
> `AIPendingRouteCard` (Save / Discard / Start) with a green "DRAWN" badge.
> Requires Sprint 3 `RouteStore.addAIPlannedRoute` ✅ (landed F-C2)

- [ ] **F-D1 · `DrawRouteEngine` actor**
  Segment stack, spatial + temporal debounce, in-flight guard, `MKDirections` snap,
  snap failure handling, `undoLastSegment()`, `finaliseTrace()`, `reset()`.
  → `Docs/Specs/F-D_DrawRoute.md`
  **New file:** `iPhone/Services/DrawRouteEngine.swift`

- [ ] **F-D2 · `DrawRouteView` full-screen canvas**
  Map canvas, dual polyline overlay (snapped solid + pending dashed + pulse animation),
  top bar (Cancel / Undo), bottom bar (stats pill + Done), cancel confirmation dialog,
  Done → `RouteModel(.drawn)` → `routeStore.addAIPlannedRoute`.
  → `Docs/Specs/F-D_DrawRoute.md`
  **New file:** `iPhone/Views/DrawRouteView.swift`

- [ ] **F-D3 · Wire into `RouteLibraryView` + `.drawn` source format**
  Add `pencil.and.map` toolbar button, `.fullScreenCover` sheet presentation.
  Add `.drawn` case to `sourceFormat` enum; update `RouteRow` pill to green "DRAWN".
  → `Docs/Specs/F-D_DrawRoute.md`
  **Modified:** `RouteLibraryView.swift`, `RouteModel.swift` (or enum source file)

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
| Draw Route waypoint-tap mode | F-D2 future | Drop pins, auto-connect — accessibility fallback for VoiceOver users |

---

## Dependency Graph

```
Sprint 1: ✅ COMPLETE
Sprint 2: ✅ COMPLETE
Sprint 3: ✅ COMPLETE

Sprint 4: Performance fixes in RideSessionStore ──► partial F-4 POITrackingEngine extract
          F-3 RideView split (deferred from Sprint 3) ──► extract RideMapLayer + RideHUDPanel
          Pre-submission polish items (no feature dependencies)
          MISC-5 bearing() consolidation (do while in RideSessionStore for F-4)

Sprint 5: RouteStore.addAIPlannedRoute (Sprint 3 ✅) ──► F-D DrawRoute
          F-D1 DrawRouteEngine ──► F-D2 DrawRouteView ──► F-D3 wire + .drawn sourceFormat
```

---

## Watch Target Rules

The following must **never** be added to the Watch target in Build Phases:

- `POIModel+MapKit.swift` — uses `MKMapItem.identifier` (iOS only)
- `VeloAI.swift` — `FoundationModels` is iOS only
- `RouteNameSuggester.swift` — `FoundationModels` + `MKReverseGeocodingRequest` (iOS only)
- `RideSummaryGenerator.swift` — `FoundationModels` (iOS only)
- `POIRankingEngine.swift` — `FoundationModels` (iOS only)
- `PlanAssistantEngine.swift` — `FoundationModels` (iOS only, Sprint 3)
- `RidePlanIntent+Generable.swift` — same (Sprint 3)
- `RidePlanAssistantView.swift` — same (Sprint 3)
- `DrawRouteEngine.swift` — iPhone only (Sprint 5)
- `DrawRouteView.swift` — iPhone only (Sprint 5)
- Any file with `import FoundationModels`
