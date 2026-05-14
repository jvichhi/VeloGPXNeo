# VeloGPXNeo — Roadmap
> Last updated: May 13, 2026  
> Source of truth for sprint order. Each session: open this file first, pick the next item off the top, build it.  
> For implementation details → `DEVLOG.md` (current sprint), `FEATURES.md` (feature specs), `TECH_DEBT.md` (debt catalogue).

---

## How This Works

- **Sprints are ordered.** Work top-to-bottom. Don't skip ahead unless explicitly noted as parallel-safe.
- **Each item has a `→ Spec` link** pointing to where the full implementation plan lives.
- **Checkboxes track completion.** Check an item off here + update DEVLOG when landing a commit.
- **iOS 26 minimum.** No availability gating for iOS 25 or below. Use iOS 26 APIs freely. Gate only for `MKMapItem.identifier` (iOS 18+) since it's a Nice-to-Have enhancement, not a required baseline.

---

## Sprint 1 — Foundation & Debt Clearance
> Goal: clean build with zero warnings, stable POI identity, and God View/Object splits started.

- [ ] **MK-6 / F-B · POIModel Place IDs + "Open in Maps"**  
  Add `mapItemIdentifier` + `mapsURL` to `POIModel`. New `POIModel+MapKit.swift` factory. Update `isAdded` in all three POI sheets. Add "Open in Maps" button to POI detail rows.  
  → `TECH_DEBT.md § MK-6` · `FEATURES.md § F-B` · `DEVLOG.md § In Progress (F-5)`  
  **Files:** `Shared/Models/POIModel.swift`, `Shared/Models/POIModel+MapKit.swift` (new), `NearbySearchSheet.swift`, `POIDiscoverySheet.swift`, `PreRidePOISheet.swift`

- [ ] **MK-1 · `MKPlacemark` / `init(placemark:)` → `MKMapItem.init(location:address:)`**  
  4 sites in `CyclingRouteService.swift`, 4 sites in `PlaceDescriptorService.swift`.  
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

## Sprint 2 — Architecture Splits
> Goal: break apart the two God objects before adding any more features on top of them.

- [ ] **F-3 · `RideView` God View split** (~37 KB → three focused views)  
  Extract `RideMapLayer` (map, camera, polylines, annotations), `RideHUDPanel` (metric tiles, buttons, elevation strip), `RideBirdsEyePanel` (aerial layout branch).  
  → `TECH_DEBT.md § P1` · `DEVLOG.md § Open Features F-3`

- [ ] **F-4 · `RideSessionStore` God Object split** (~30 KB → thin coordinator + three engines)  
  `RideLocationEngine` (CLLocation, heading, breadcrumbs), `POITrackingEngine` (proximity, nextPOI, spur requests), `WatchSyncManager` (WCSession framing + throttle). `RideSessionStore` becomes the coordinator.  
  → `TECH_DEBT.md § P1` · `DEVLOG.md § Open Features F-4`

- [ ] **AC-1 · Swift 6 actor isolation — `clCoordinate` / `route` / `distance(to:)`**  
  14 sites in `CyclingRouteService.swift`, 3 in `PlaceDescriptorService.swift`. Snapshot values before async boundary or mark struct `Sendable`.  
  → `TECH_DEBT.md § AC-1`

- [ ] **AC-2 · Swift 6 — `TurnInstruction.init` from nonisolated context**  
  `CyclingRouteService.swift:245,257,273`. Mark `TurnInstruction` as `Sendable` or build array inside `MainActor.run {}`.  
  → `TECH_DEBT.md § AC-2`

- [ ] **AC-3 · Swift 6 — `WatchRideSummary` `Decodable` on wrong actor**  
  `WatchRideStore.swift:23`. Remove `@MainActor` from the data struct.  
  → `TECH_DEBT.md § AC-3`

- [ ] **P2 · Merge `POIDiscoverySheet` + `NearbySearchSheet` into one sheet with `mode: .preRide | .midRide`**  
  Two sheets with overlapping purpose. Merge before 1.0.  
  → `TECH_DEBT.md § P1 (POI Overhaul follow-ups)`

---

## Sprint 3 — On-Device AI (FoundationModels, iOS 26)
> Goal: ship the three standalone AI features that don't depend on each other.  
> Add `FoundationModels` to Build Phases + `VeloAISession` shared wrapper first.

- [ ] **F-A Shared · Add `FoundationModels` framework + `VeloAISession` wrapper**  
  Single shared session wrapper to avoid multiple concurrent `LanguageModelSession` instances. Add user toggle in `SettingsView` — "AI Features (Apple Intelligence)" — with on-device explanation. Gate all AI UI on `ModelAvailability.isAvailable`.  
  → `FEATURES.md § F-A (Shared Implementation Notes)`

- [ ] **F-A1 · Ride Summary Generation**  
  Post-ride natural language summary from `RideSummary` data. "Generate Summary" button in `RideSummaryView` below stats grid. Editable before sharing.  
  → `FEATURES.md § F-A1`  
  **New file:** `iPhone/Services/RideSummaryGenerator.swift`

- [ ] **F-A2 · Smart Route Naming**  
  On GPX import or rename tap, suggest 3 names via reverse geocode + model. Pill picker in rename sheet in `RouteLibraryView`.  
  → `FEATURES.md § F-A2`  
  **New file:** `iPhone/Services/RouteNameSuggester.swift`  
  **Dependency:** Replace `CLGeocoder` with `MKReverseGeocodingRequest` once MK-3 (Sprint 1) is landed.

- [ ] **F-A3 · POI Relevance Ranking**  
  Context-aware "Suggested" sort in `POIDiscoverySheet` / `NearbySearchSheet`. Uses ride difficulty, elevation gain, elapsed distance, time-of-day, and `RideHistoryStore` category frequency.  
  → `FEATURES.md § F-A3`  
  **New file:** `iPhone/Services/POIRankingEngine.swift`

---

## Sprint 4 — RidePlanAssistant (FoundationModels + MKLocalSearch, iOS 26)
> Goal: natural language → multi-stop route in the Routes tab.  
> Requires F-A shared session wrapper from Sprint 3.

- [ ] **F-C1 · RidePlanAssistant — Core**  
  `PlanAssistantEngine` orchestrates: model parses `RidePlanIntent` → `MKLocalSearch` resolves stops → `PlanState` + `PlanRouteEngine` computes geometry. `RidePlanAssistantView` inline expandable input in Routes tab. `DisambiguationSheet` for ambiguous place names.  
  → `FEATURES.md § F-C1`  
  **New files:** `iPhone/Services/PlanAssistantEngine.swift`, `iPhone/Services/RidePlanIntent+Generable.swift`, `iPhone/Views/RidePlanAssistantView.swift`, `iPhone/Views/DisambiguationSheet.swift`  
  **Modified:** `RouteLibraryView.swift`, `RouteStore.swift`

- [ ] **F-C2 · RidePlanAssistant — Polish**  
  Stop-type icons in `WaypointListSheet`. Dwell time estimation per stop intent. Total outing time (ride + stops) in `WaypointListSheet` header. "AI Planned" temp section in Routes tab with Save / Discard / Start actions.  
  → `FEATURES.md § F-C2`  
  **Modified:** `WaypointListSheet.swift`, `PlanState.swift`, `RouteStore.swift`

---

## Backlog — No Sprint Assigned Yet

These are valid but not time-sensitive. Pick up after Sprint 4 or slot in opportunistically.

| Item | Where | Notes |
|---|---|---|
| Elevation gain noise smoothing | `RideSessionStore` | Threshold gate (>2m) or Kalman filter on altitude stream |
| `MapStyle` cycling overlay toggle | `SettingsView` | Expose `.standard` / `.hybrid(elevation:)` / cycling lane style |
| `buildSnapIndexCache` O(N×M) offload | `PreRidePOISheet.swift:102` | Background task or k-d tree spatial index |
| `updateNextPOI` hot-path scan | `RideSessionStore.swift:491` | Pre-compute snap indices; use indexed lookup |
| `elevationSamples` recompute on every body eval | `RouteDetailView.swift:236` | Lazy cache, invalidate on `trackPoints` change |
| Empty `catch` blocks silently swallowing errors | `RideSummaryView`, `RideHistoryView`, `RideHistoryDetailView` | Log + surface via toast |
| `RouteNoticeView` — wire or delete | — | Wire into `CyclingRouteService` result + `topBanners`, or delete before 1.0 |
| `CyclingRouteOverlay` — surface in `PlanView` pre-ride | — | Currently orphaned; pair with `RouteNoticeView` decision |
| `RideHistoryStore` pagination | — | SwiftData or paginated JSON reads |
| Localization pass | Whole app | Route all user-visible strings through `LocalizationManager` |
| Unit tests for core logic | `Tests/` | `minimumDistance`, `updateNextPOI`, elevation accumulation, `bearing()` |
| `RouteStore+POI.swift` consolidation | `Shared/` | 866 B stub; POI persistence scattered across `RideView` call sites |
| `AppleLanguages` UserDefaults key | `LocalizationManager.swift:126` | Fragile internal key + deprecated `synchronize()`; use Bundle `.lproj` approach |
| IUO `CLLocationManager` | `RideSessionStore.swift:37` | `private let manager = CLLocationManager()` |
| Force-unwrap on coordinate array `min()`/`max()` | `RideSummaryView`, `RideHistoryView`, `RideHistoryDetailView` | Optional binding |
| `RideSessionStore+Spurs.swift` internal property access | — | `private(set)` or dedicated spur service |

---

## Dependency Graph

```
Sprint 1: MK-1, MK-2, MK-3, MK-4, MISC-* (all parallel-safe)
          └── MK-6 / F-B (POIModel Place IDs) ──► Sprint 3 F-A2 (replace CLGeocoder)
                                                ──► Stretch: shareable POI lists

Sprint 2: F-3, F-4 God splits (parallel-safe with each other)
          AC-1, AC-2, AC-3 (Swift 6 — can batch in one pass)

Sprint 3: F-A Shared wrapper  ──► F-A1, F-A2, F-A3 (then any order)
          F-A1 validates the VeloAISession pattern ──► Sprint 4 reuses it

Sprint 4: F-A (Sprint 3 complete) ──► F-C1 ──► F-C2
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
