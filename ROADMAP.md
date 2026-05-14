# VeloGPXNeo — Roadmap
> Last updated: May 13, 2026  
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

## Sprint 1 — Foundation & Debt Clearance
> Goal: clean build with zero warnings and stable POI identity. Targets v1.3.
> All items are parallel-safe — they can be batched in any order within the sprint.

- [x] **MK-6 / F-B · POIModel Place IDs + "Open in Maps"**  
  Add `mapItemIdentifier` + `mapsURL` to `POIModel`. New `POIModel+MapKit.swift` factory. Update `isAdded` in all three POI sheets. Add "Open in Maps" button to POI detail rows.  
  → `TECH_DEBT.md § MK-6` · `FEATURES.md § F-B` · `DEVLOG.md § In Progress (F-5)`  
  **Files:** `Shared/Models/POIModel.swift`, `Shared/Models/POIModel+MapKit.swift` (new), `NearbySearchSheet.swift`, `POIDiscoverySheet.swift`, `PreRidePOISheet.swift`

- [ ] **MK-1 · `MKPlacemark` / `init(placemark:)` → `MKMapItem.init(location:address:)`**  
  4 sites in `CyclingRouteService.swift`, 4 in `PlaceDescriptorService.swift`.  
  → `TECH_DEBT.md § MK-1`

- [ ] **MK-2 · `MKMapItem.placemark` property reads → `.location` / `.address`**  
  7 sites in `NearbySearchSheet.swift`, 3 in `POIDiscoverySheet.swift`, 2 in `PlaceDescriptorService.swift`, 1 in `ReverseGeocodingService.swift`.  
  → `TECH_DEBT.md § MK-2`

- [ ] **MK-3 · `CLGeocoder` → `MKReverseGeocodingRequest`**  
  `ReverseGeocodingService.swift:63,66` · `PlaceDescriptorService.swift:57,60`.  
  → `TECH_DEBT.md § MK-3`

- [ ] **MK-4 · `UIScreen.main` → `@Environment(\.displayScale)`**  
  `RideHistoryDetailView.swift`, `RideHistoryView.swift`, `RideSummaryView.swift` — 5 sites.  
  → `TECH_DEBT.md § MK-4`

- [ ] **AC-1 · Swift 6 actor isolation — `clCoordinate` / `route` / `distance(to:)`**  
  14 sites in `CyclingRouteService.swift`, 3 in `PlaceDescriptorService.swift`. Snapshot values before async boundary or mark struct `Sendable`.  
  → `TECH_DEBT.md § AC-1`

- [ ] **AC-2 · Swift 6 — `TurnInstruction.init` from nonisolated context**  
  `CyclingRouteService.swift:245,257,273`. Mark `TurnInstruction` as `Sendable` or build array in `MainActor.run {}`.  
  → `TECH_DEBT.md § AC-2`

- [ ] **AC-3 · Swift 6 — `WatchRideSummary` `Decodable` on wrong actor**  
  `WatchRideStore.swift:23`. Remove `@MainActor` from the data struct.  
  → `TECH_DEBT.md § AC-3`

- [ ] **MISC-1 · `onChange(of:perform:)` → two-argument form**  
  `RideView.swift:232`.  
  → `TECH_DEBT.md § MISC-1`

- [ ] **MISC-2 · Remove spurious `await` on sync calls**  
  `PlanView.swift:62,72`.  
  → `TECH_DEBT.md § MISC-2`

- [ ] **MISC-3 · Add `AccentColor` to Assets catalog**  
  `#01696F` light / `#4F98A3` dark in `iPhone/Assets.xcassets`.  
  → `TECH_DEBT.md § MISC-3`

- [ ] **MISC-4 · Remove unused `windowMeters` immutable value**  
  `RouteModel.swift:190` (both targets).  
  → `TECH_DEBT.md § MISC-4`

- [ ] **MISC-5 · Extract duplicate `bearing()` haversine to `CLLocationCoordinate2D+Bearing.swift`**  
  `RideSessionStore.swift` + `GPXCueEngine` both implement independently.  
  → `TECH_DEBT.md § MISC-5`

- [ ] **MISC-6 · Gate notification calls on `notificationsGranted` flag**  
  `RideSessionStore.swift:92` — store result of `requestAuthorization`.  
  → `TECH_DEBT.md § MISC-6`

---

## Sprint 2 — On-Device AI (FoundationModels, iOS 26)
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
  On GPX import or rename tap, suggest 3 names via reverse geocode + model. Pill picker in rename sheet in `RouteLibraryView`. Uses `MKReverseGeocodingRequest` (MK-3 already done in Sprint 1).  
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
> **F-3 (`RideView` split) — do incrementally here.** F-C2 polish requires touching `RideView` anyway for stop-type icon rendering. When we open `RideView` for F-C2, extract `RideMapLayer` and `RideHUDPanel` at the same time. This spreads the risk across real feature work rather than a standalone refactor, and keeps the split grounded in a concrete reason to be in the file.

- [ ] **F-C1 · RidePlanAssistant — Core**  
  `PlanAssistantEngine` orchestrates: model parses `RidePlanIntent` → `MKLocalSearch` resolves stops → `PlanState` + `PlanRouteEngine` computes geometry. `RidePlanAssistantView` inline expandable input in Routes tab. `DisambiguationSheet` for ambiguous place names.  
  → `FEATURES.md § F-C1`  
  **New files:** `iPhone/Services/PlanAssistantEngine.swift`, `iPhone/Services/RidePlanIntent+Generable.swift`, `iPhone/Views/RidePlanAssistantView.swift`, `iPhone/Views/DisambiguationSheet.swift`  
  **Modified:** `RouteLibraryView.swift`, `RouteStore.swift`

- [ ] **F-C2 · RidePlanAssistant — Polish + partial F-3 `RideView` split**  
  Stop-type icons in `WaypointListSheet`. Dwell time estimation per stop intent. Total outing time in `WaypointListSheet` header. "AI Planned" temp section in Routes tab (Save / Discard / Start).  
  While touching `RideView` for this: extract `RideMapLayer` (map, camera, polylines, annotations) and `RideHUDPanel` (metric tiles, buttons, elevation strip) as separate views. Leave `RideBirdsEyePanel` for later if scope is too large.  
  → `FEATURES.md § F-C2` · `TECH_DEBT.md § F-3`  
  **Modified:** `WaypointListSheet.swift`, `PlanState.swift`, `RouteStore.swift`, `RideView.swift`

---

## Sprint 4 — Stability & Pre-1.5 Polish
> Goal: everything needed before the next major App Store submission. No net-new features — just making what exists solid.
>
> **F-4 (`RideSessionStore` split) — do incrementally here.** The P2 performance fixes (`updateNextPOI` hot-path, `buildSnapIndexCache`) require opening `RideSessionStore` anyway. Extract `POITrackingEngine` while making those fixes. Do `RideLocationEngine` and `WatchSyncManager` only if the scope stays manageable — don't force the full split in one go.

- [ ] **P2 · `updateNextPOI` hot-path — pre-compute snap indices + partial F-4 `RideSessionStore` split**  
  Pre-compute POI snap indices once when POIs change; use indexed lookup in hot path instead of scanning all POIs on every location update. While in `RideSessionStore` for this: extract `POITrackingEngine` (proximity, nextPOI, spur requests).  
  → `TECH_DEBT.md § P2` · `TECH_DEBT.md § F-4`  

- [ ] **P2 · `buildSnapIndexCache` O(N×M) offload to background**  
  `PreRidePOISheet.swift:102–117`. Background task or k-d tree spatial index.  
  → `TECH_DEBT.md § P2`

- [ ] **P2 · `elevationSamples` lazy cache in `RouteDetailView`**  
  `RouteDetailView.swift:236–252`. Cache result; invalidate only when `trackPoints` changes.  
  → `TECH_DEBT.md § P2`

- [ ] **P2 · Surface empty `catch` blocks**  
  `RideSummaryView.swift:296`, `RideHistoryView.swift:231`, `RideHistoryDetailView.swift:266,346`. Log + surface via toast.  
  → `TECH_DEBT.md § P2`

- [ ] **P2 · `RouteNoticeView` — wire or delete**  
  Wire into `CyclingRouteService` result + `topBanners`, or delete. Decide alongside `CyclingRouteOverlay`.  
  → `TECH_DEBT.md § P2`

- [ ] **P2 · Merge `POIDiscoverySheet` + `NearbySearchSheet`**  
  One sheet with `mode: .preRide | .midRide`. Eliminates overlapping purpose before submission.  
  → `TECH_DEBT.md § P1 (POI Overhaul follow-ups)`

- [ ] **P2 · Elevation gain noise smoothing**  
  Threshold gate (only accumulate deltas > 2 m) in `RideSessionStore` altitude stream.  
  → `TECH_DEBT.md § P2`

- [ ] **P3 · `MapStyle` cycling overlay toggle in Settings**  
  Expose `.standard` / `.hybrid(elevation: .realistic)` / cycling lane style.  
  → `TECH_DEBT.md § P3`

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
Sprint 1: MK-1, MK-2, MK-3, MK-4, MISC-*, AC-1/2/3 (all parallel-safe)
          └── MK-6 / F-B (POIModel Place IDs) ──► Sprint 2 F-A2 (MKReverseGeocodingRequest ready)
                                                ──► Stretch: shareable POI lists

Sprint 2: F-A Shared wrapper  ──► F-A1, F-A2, F-A3 (any order)
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
