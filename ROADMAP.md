# VeloGPXNeo — Roadmap
> Last updated: June 4, 2026 — Sprint 6 plan locked. Competitive expansion strategy added.
> Source of truth for sprint order. Each session: open this file first, pick the next item off the top, build it.
> For implementation details → `DEVLOG.md` (current sprint), `FEATURES.md` (feature specs), `TECH_DEBT.md` (debt catalogue).

---

## How This Works

- **Sprints are ordered.** Work top-to-bottom. Don't skip ahead unless explicitly noted as parallel-safe.
- **Each item has a `→ Spec` link** pointing to where the full implementation plan lives.
- **Checkboxes track completion.** Check an item off here + update DEVLOG when landing a commit.
- **iOS 26 minimum.** No availability gating for iOS 25 or below. Use iOS 26 APIs freely. Gate only for `MKMapItem.identifier` (iOS 18+) since it's a nice-to-have enhancement on top of the coordinate fallback.
- **God object splits (RideView, RideSessionStore) are incremental — not a dedicated sprint.** High-risk refactors with no test coverage as a safety net. Each split happens naturally when we're already in that file for a feature.

---

## ✅ Sprint 1 — Foundation & Debt Clearance
> **COMPLETE** as of May 13, 2026.

All MK-1 through MK-6, AC-1 through AC-3, and MISC-1 through MISC-6 items resolved.
See `TECH_DEBT.md` for full verified list.

---

## ✅ Sprint 2 — On-Device AI (FoundationModels, iOS 26)
> **COMPLETE** as of May 15, 2026.

- [x] **F-A1** Ride Summary Generation — `RideSummaryGenerator.swift`
- [x] **F-A2** Smart Route Naming — `RouteNameSuggester.swift` + `RouteRenameSheet`
- [x] **F-A3** POI Relevance Ranking — `POIRankingEngine.swift`

---

## ✅ Sprint 3 — RidePlanAssistant (FoundationModels + MKLocalSearch)
> **COMPLETE** as of May 16, 2026.

- [x] **F-C1** RidePlanAssistant Core — `PlanAssistantEngine.swift`, `RidePlanIntent+Generable.swift`, `RidePlanAssistantView.swift`
- [x] **F-C2** RidePlanAssistant Polish — stop icons, dwell chips, outing time stats, AI Planned card
- [x] **F-C3** Distance-matching layer — `PlanRouteEngine.matchTargetDistance` wired through

---

## ✅ Sprint 4 — Stability & Pre-1.5 Polish
> **COMPLETE** as of May 17, 2026.

- [x] Dead views deleted (`CyclingRouteOverlay`, `RouteNoticeView`, `NextPOIBanner`)
- [x] F-C3 distance matching + AI assistant routing fix
- [x] Canonical `bearing(to:)` / `midpoint(to:)` / `destination(bearing:distance:)` on `CLLocationCoordinate2D+Extensions`
- [x] Re-route button replacing redundant drag-to-reorder toggle in `WaypointListSheet`
- [ ] **MISC-5** Duplicate `bearing()` in `RideSessionStore` + `GPXCueEngine` — carry into Sprint 6
- [ ] **P2** `updateNextPOI` hot-path, `buildSnapIndexCache` O(N×M), `elevationSamples` lazy cache, empty `catch` blocks, POI sheet merge, elevation noise — carry into Sprint 6

---

## ✅ Sprint 5 — Draw Route (Strava Parity)
> **COMPLETE** as of May 23, 2026.

- [x] **F-D1** `DrawRouteEngine` — spatial + temporal debounce, MKDirections snap, undo, finalise
- [x] **F-D2** `DrawRouteView` — dual polyline, pan/draw toggle, cancel confirmation, Done → `RouteModel(.drawn)`
- [x] **F-D3** Entry point → Plan tab via `WaypointListSheet.emptyPrompt`
- [x] **F-D4** Pan / Draw mode toggle with haptic
- [ ] **F-D5** Inline route naming on Done — `commitRoute()` hardcodes `"Drawn Route"` → add `TextField` before commit or present `RouteRenameSheet` on dismiss ← **carry into Sprint 6**

---

## 🚧 Sprint 6 — Quality Lock + Spoken Navigation
> Goal: close all carry-overs from Sprint 4 & 5, then ship spoken cues — the #1 free-tier differentiator.
> Strava charges $80/yr for audio cues. This is a 3-day build on top of existing `GPXCueEngine`.

### Carry-overs (complete first)

- [ ] **F-D5** Inline route naming on Done (`DrawRouteView` → `RouteRenameSheet`)
- [ ] **MISC-5** Extract duplicate `bearing()` haversine; delete copies in `RideSessionStore` + `GPXCueEngine`

### Performance (P2 backlog)

- [ ] **P2-A** `updateNextPOI` pre-computed snap index — cache on POI list change; begin `POITrackingEngine` extraction from `RideSessionStore`
- [ ] **P2-B** `buildSnapIndexCache` O(N×M) — move to `Task { }` background; k-d tree or linear sweep (`PreRidePOISheet.swift:102–117`)
- [ ] **P2-C** `elevationSamples` lazy cache — computed once, invalidated only on `trackPoints` change (`RouteDetailView.swift:236–252`)
- [ ] **P2-D** Surface empty `catch` blocks with `lastError` toast — `RideSummaryView.swift:296`, `RideHistoryView.swift:231`, `RideHistoryDetailView.swift:266,346`
- [ ] **P2-E** Merge `POIDiscoverySheet` + `NearbySearchSheet` into `POISheet(mode:)` with `.preRide | .midRide`
- [ ] **P2-F** Elevation gain noise smoothing — `> 2 m` delta threshold in `RideSessionStore` altitude accumulation

### F-E — Spoken Turn-by-Turn Cues (`AVSpeechSynthesizer`)

**No new frameworks. No paywall. Zero API cost. Fully offline.**

- [ ] **F-E1** `SpeechCueService.swift` — `@Observable actor`; wraps `AVSpeechSynthesizer`; `speak(_:)` queues utterances; `AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: .duckOthers)`; `isSpeechEnabled: Bool` via `@AppStorage("speechCuesEnabled")`
- [ ] **F-E2** Wire into `RideSessionStore` — call `speak()` from existing `CueSheetEntry` trigger points; no changes to `GPXCueEngine`
- [ ] **F-E3** Anticipatory climb cues — when next `CueSheetEntry` within 500 m has cumulative elevation gain ≥ 20 m, speak `"Climb ahead — 1.1 km at 4%"`; compute from `trackPoints` elevation delta window
- [ ] **F-E4** Resume-route cue — after POI arrival (200 m gate fires), if stationary ≥ 30 s then user resumes movement, speak `"Resuming route — next turn in X km"`
- [ ] **F-E5** Settings — `SpeechCuesRow` with enable/disable + voice speed picker (`.default`, `.slow`); uses `AVSpeechSynthesisVoice(language: Locale.current.identifier)`

**Watch target:** `SpeechCueService.swift` is iPhone only — `AVAudioSession` not available on watchOS.

---

## Sprint 7 — WeatherKit Ride Window
> Goal: pre-ride weather intelligence inline in route planning. Zero third-party dependencies.
> WeatherKit is Apple-first, private, free up to 500k calls/month. No user API key.
> **Prerequisite:** add `com.apple.developer.weatherkit` entitlement to Debug + Release profiles before starting.

### F-F — WeatherKit Integration

- [ ] **F-F1** `WeatherService.swift` — `@Observable actor`; fetches `HourlyForecast<HourWeather>` for route start coordinate + estimated finish time; 30-min fetch cache via `lastFetchDate` gate; exposes `rideWindow: RideWindow?`
  ```swift
  struct RideWindow {
      let bestStartHour: Date
      let temperatureCelsius: Double
      let precipProbability: Double      // 0–1
      let windSpeedKph: Double
      let windBearing: Double            // degrees
      let tailwindLabel: String          // "Tailwind", "Headwind", "Crosswind"
  }
  ```
- [ ] **F-F2** Tailwind/headwind computation — compare `windBearing` vs. `route.bearing(firstPoint → lastPoint)` using existing `bearing(to:)` extension; ±30° = tailwind, ±150° = headwind, else crosswind
- [ ] **F-F3** `RideWindowCard` — shown in `WaypointListSheet` header when route has ≥ 2 waypoints; best start time, temp, precip %, wind label; tap to expand hourly strip
- [ ] **F-F4** HUD weather capsule — `WeatherCapsule` in `RideHUDPanel`; current temp + next-hour precip %; fetches on ride start; refreshes every 20 min via `Task.sleep`
- [ ] **F-F5** Settings — `WeatherRow` toggle (`weatherEnabled: @AppStorage`); only shown when `WeatherService.isAvailable`

---

## Sprint 8 — Offline Navigation (Option B)
> Goal: GPS navigation with no cellular signal. Map tiles go blank; route + cues stay live.
> Zero new SDKs. Option A (MapLibre full tiles) is deferred to Backlog.

### F-G — Offline Navigation Mode

- [ ] **F-G1** `NetworkMonitor.swift` — `NWPathMonitor` wrapper; `@Observable`; publishes `isOnline: Bool`; inject via `.environment`
- [ ] **F-G2** `RideSessionStore` network-awareness — when `isOnline` → `false` during active ride, pause `CyclingRouteService` reroute attempts silently; do not surface as error (offline nav is expected behaviour)
- [ ] **F-G3** Offline HUD banner — `OfflineBanner` in `RideHUDPanel` when `!isOnline`; `"Offline — GPS navigation active"`; teal background, dismissible; reappears on next connectivity drop
- [ ] **F-G4** Map style fallback — when `!isOnline`, switch `mapStyle` to `.standard` (vector tiles cache better than satellite); suppress reroute button in off-route alert sheet
- [ ] **F-G5** Pre-ride offline alert — if `!isOnline` at ride start, show one-time `Alert`: `"You're offline. Navigation will work but the map may appear blank in areas you haven't visited."` + `"Got it"` dismiss
- [ ] **F-G6** Route pre-cache — on route save, write JSON snapshot of `trackPoints` + `cueSheet` to `Application Support/OfflineCache/`; ensures cues available without re-parsing on next launch

---

## Sprint 9 — Ride Replay + Speed Map
> Goal: post-ride emotional recap. Strava charges $80/yr for this. Built entirely on existing `RideHistoryStore` + `trackPoints`.

### F-H — Ride Replay & Segment Colouring

- [ ] **F-H1** Speed-band polylines — partition `trackPoints` into speed quartiles; render 4 `MapPolyline` overlays (green / yellow / orange / red); legend chip; toggle via `"Speed Map"` button in `RideHistoryDetailView`
- [ ] **F-H2** `ReplayEngine.swift` — `@Observable`; steps through `trackPoints` at configurable speed (1×, 4×, 10×); publishes `currentCoordinate: CLLocationCoordinate2D`; `RideHistoryDetailView` animates `MapCamera` following point
- [ ] **F-H3** Replay controls — play/pause, speed selector, scrub slider mapped to `trackPoints` index; floating pill at bottom of map
- [ ] **F-H4** `PersonalRecordsEngine.swift` — on `RideHistoryStore` write, compare sub-segment times across history using `trackPoints` timestamps + `bearing(to:)` distance; flag PRs in `RideHistoryDetailView` with trophy chip

**Note:** Fix `RideHistoryStore` pagination (Backlog item) before F-H4 to avoid full-scan on every ride save.

---

## Sprint 10 — Elevation-Aware AI Planning
> Goal: deepen the AI moat. No competitor offers natural-language elevation-preference route planning.

### F-I — Elevation Preference in RidePlanAssistant

- [ ] **F-I1** `ElevationPreference` enum — `.flat`, `.rolling`, `.hilly`, `.mountainous`, `.endEasy`; add as `@Generable` field to `RidePlanIntent`; update `PlanAssistantEngine` prompt schema description
- [ ] **F-I2** `PlanRouteEngine.matchTargetGain(targetGainM:)` — after waypoint resolution, score candidate `MKRoute` segments by elevation gain from `steps` altitude data; prefer segments matching `ElevationPreference` profile
- [ ] **F-I3** Elevation profile sparkline — `ElevationSparklineView` in `WaypointListSheet` header; updates live as waypoints change; reuses `elevationSamples` cache from P2-C
- [ ] **F-I4** Climb summary chip — `"↑ 820 m · 3 climbs"` in `WaypointListSheet` stats row; derived from `RouteModel.totalElevationGain` + climb-segment counter (consecutive track points with gain > 10 m)

---

## Sprint 11 — GPX Import Expansion
> Goal: make VeloGPXNeo the best GPX destination on iOS. No route hosting required.

### F-J — Universal GPX Import

- [ ] **F-J1** `ImportFromURLSheet.swift` — `TextField` for any direct `.gpx` URL; `URLSession.data(from:)` download → existing `GPXParser` pipeline; differentiated error messages (corrupt, unsupported schema, duplicate, I/O)
- [ ] **F-J2** `UIDocumentPickerViewController` prominence — surface existing file picker as primary empty-state action in `RouteLibraryView`; also in `+` toolbar sheet; replaces buried secondary menu item
- [ ] **F-J3** iCloud Drive GPX sync — `NSFileCoordinator` + `NSMetadataQuery` watches `~/Documents` iCloud container for `.gpx` files; auto-import with duplicate detection via route name + distance hash
- [ ] **F-J4** Import error quality — replace `RouteStore.swift:79` generic `"Import failed"` with: corrupt file / unsupported GPX schema / duplicate route / I/O failure — four distinct messages with recovery suggestions

---

## Backlog — Deferred / Future

| Item | Where | Notes |
|---|---|---|
| `RideHistoryStore` pagination | `RideHistoryStore.swift` | SwiftData migration or paginated JSON reads; required before 200+ ride users hit perf wall. Unblock before Sprint 9 F-H4. |
| Full localization pass | Whole app | Route all user-visible strings through `LocalizationManager`; fix fragile `AppleLanguages` key |
| Unit tests for core logic | `Tests/` | `minimumDistance`, `updateNextPOI`, elevation accumulation, `bearing()` — zero coverage today |
| `RouteStore+POI.swift` consolidation | `Shared/` | 866 B stub; POI persistence scattered across `RideView` call sites |
| IUO `CLLocationManager` | `RideSessionStore.swift:37` | Replace with `private let manager = CLLocationManager()` |
| Force-unwrap on coordinate `min()`/`max()` | `RideSummaryView`, `RideHistoryView`, `RideHistoryDetailView` | Wrap in Optional binding |
| `RideSessionStore+Spurs.swift` internal access | — | Use `private(set)` or extract dedicated spur service |
| Draw Route waypoint-tap mode | F-D future | Drop pins + auto-connect; accessibility fallback for VoiceOver users |
| Option A full offline tiles (MapLibre) | Post-Sprint 11 | MapLibre GL Native via SPM; bounding-box tile pack download; replaces `MKMapView` in offline context; OSRM for routing while online |
| Road surface annotation | Parked | MapKit exposes no `surface=` API. All third-party implementations use OSM Overpass. Not viable for Apple-only stack. Revisit only if Apple adds surface metadata to a future MapKit release. |
| Multi-sport / `ActivityProfile` | Post-Sprint 11 | `ActivityProfile` enum (cycling, hiking, running, trail running); parameterises `MKDirectionsTransportType`, speed defaults, `RouteDifficulty` thresholds, AI prompt noun; inject via `.environment(\.activityProfile)` |

---

## Dependency Graph

```
Sprint 1:   ✅ COMPLETE
Sprint 2:   ✅ COMPLETE
Sprint 3:   ✅ COMPLETE
Sprint 4:   ✅ COMPLETE
Sprint 5:   ✅ COMPLETE

Sprint 6:   F-D5 carry ──► F-E spoken cues
            P2 debt carry ── parallel with F-E

Sprint 7:   bearing(to:) ✅ ──► F-F WeatherKit tailwind/headwind

Sprint 8:   F-G offline nav — no upstream dependency; can start after Sprint 6

Sprint 9:   RideHistoryStore (existing) ──► F-H replay + speed map
            Fix pagination (Backlog) before F-H4 PersonalRecordsEngine

Sprint 10:  F-C RidePlanAssistant ✅ ──► F-I elevation-aware AI planning
            P2-C elevationSamples cache (Sprint 6) ──► F-I3 sparkline

Sprint 11:  RouteStore GPX pipeline ✅ ──► F-J import expansion
```

---

## Watch Target Rules

The following must **never** be added to the Watch target in Build Phases:

- `POIModel+MapKit.swift` — uses `MKMapItem.identifier` (iOS only)
- `VeloAI.swift` — `FoundationModels` is iOS only
- `RouteNameSuggester.swift` — `FoundationModels` + `MKReverseGeocodingRequest`
- `RideSummaryGenerator.swift` — `FoundationModels`
- `POIRankingEngine.swift` — `FoundationModels`
- `PlanAssistantEngine.swift` — `FoundationModels`
- `RidePlanIntent+Generable.swift` — `FoundationModels`
- `RidePlanAssistantView.swift` — `FoundationModels`
- `DrawRouteEngine.swift` — iPhone only
- `DrawRouteView.swift` — iPhone only
- `SpeechCueService.swift` — iPhone only (`AVAudioSession` unavailable on watchOS)
- `WeatherService.swift` — iPhone only (WeatherKit entitlement scope)
- Any file with `import FoundationModels`
