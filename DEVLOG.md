# VeloGPXNeo — Dev Log
> Active work tracker. Updated each session so the next session can onboard instantly.
> For longer-lived tech debt, see `TECH_DEBT.md`.

---

## Current State — May 17, 2026 (end of night)

**Build:** ✅ Clean — zero warnings, zero errors (iOS 26+, SwiftUI / MapKit / CoreLocation / FoundationModels)

**Sprint 1:** ✅ Complete
**Sprint 2:** ✅ Complete
**Sprint 3:** ✅ Complete
**Sprint 4:** In progress — dead code cleared, F-C3 distance matching landed, straight-line bugs fixed.

**Next session starts at:** Sprint 4 · P2 perf fixes — `updateNextPOI` hot-path, `buildSnapIndexCache` offload, `elevationSamples` cache.
(Sprint 5 F-D DrawRoute also unblocked — all prerequisites in place.)

---

## Session Summary — May 17, 2026 (continued)

| Item | Status | Notes |
|---|---|---|
| **F-C3** Distance-matching layer | ✅ | LLM's `targetDistanceKm` + `suggestedName` now wired. Loop extension algorithm pushes return-segment midpoint perpendicular when too short. ±15% tolerance, max 2 attempts, 20 km push cap. |
| `CLLocationCoordinate2D` helpers | Added | `bearing(to:)`, `midpoint(to:)`, `destination(bearing:distance:)` — partial MISC-5 (canonical bearing now in extension; duplicates remain) |
| PlanState fields | Added | `suggestedName`, `targetDistanceKm`, `distanceWarning` |
| **Bug fix** AI assistant not triggering routing | ✅ | `PlanAssistantEngine` now calls `PlanRouteEngine.recomputeAll` after waypoint population. Fixes map showing pins without route polylines after AI plan. |
| **Bug fix** POI spur straight-line fallback | ✅ | `RideSessionStore+Spurs.fetchLeg` returns nil on MKDirections failure instead of straight-line stub. Caller skips cache entry. |
| Reorder → Re-route button | ✅ | WaypointListSheet Reorder button replaced with Re-route (triggers `recomputeAll`). |
| README.md | Rewritten | Full rewrite for public GitHub: features, architecture, build steps, commit conventions. |
| TECH_DEBT.md, ROADMAP.md | Updated | F-C3 entries added; dead code items checked off. |

## Session Summary — May 17, 2026

| Item | Status | Notes |
|---|---|---|
| Dead code audit | ✅ | Full scan of all Swift files — 15 dead items identified |
| `CyclingRouteOverlay.swift` | Deleted | 260 loc, zero callers since removed from RouteDetailView |
| `RouteNoticeView.swift` | Deleted | 38 loc, never wired |
| `NextPOIBanner.swift` | Deleted | 29 loc, zero callers (TECH_DEBT claimed deleted but was on disk) |
| `ReverseGeocodingService.swift` | Deleted | 37 loc, superseded by PlaceDescriptorService |
| Root `MKMapItem+POI.swift` | Deleted | 73 loc, not compiled (stale #available copy) |
| `POISearchService.searchAlongRoute()` | Removed | Zero callers + orphan `Array.middle` helper |
| `CyclingRouteService.calculateAlternativeRoutes()` | Removed | Zero callers |
| `RouteStore.importRoute(data:filename:)` | Removed | Only URL overload used |
| `RideSessionStore.stop()` + `clearError()` | Removed | Zero callers each |
| `TimeInterval.formattedDuration` | Removed | Zero callers (use `.hhmm` instead) |
| `ClimbCategory.minGrade/minDistance/minElevation` | Removed | Zero callers (RouteModel.classifyClimb hardcodes) |
| `POICategory.CaseIterable` | Removed | allCases never called |
| pbxproj cleanup | ✅ | 16 references to deleted files removed |
| TECH_DEBT.md, ROADMAP.md | Updated | Dead views/items checked off |

**581 lines deleted across 14 files.** Zero risk — all items confirmed zero external references before deletion.

---
## Session Summary — May 14–15, 2026 (late night)

| Item | Status | Commit | Notes |
|---|---|---|---|
| F-A Shared: `VeloAI.swift` | ✅ | `77cfdcb` | `isAvailable` gate, `enabledKey` AppStorage key |
| F-A1: `RideSummaryGenerator.swift` | ✅ | `77cfdcb` | `respond(to:)` pattern, caption persistence |
| F-A2: `RouteNameSuggester.swift` | ✅ | `77cfdcb` | `MKReverseGeocodingRequest`, 3 pill suggestions |
| F-A3: `POIRankingEngine.swift` | ✅ | `77cfdcb` | Actor-isolated, multi-signal scoring |
| `RouteLibraryView.swift` F-A2 rewrite | ✅ | `6004119` | Rename swipe + context menu + `RouteRenameSheet` + `FlowLayout` |
| `RideHistoryStore.swift` import fix | ✅ | `9cfaa93` | Added missing `import Combine` + `import SwiftUI` |
| ROADMAP Sprint 2 marked complete | ✅ | `6004119` | All F-A checkboxes checked off |
| Post-review fixes (5 items) | ✅ | `2f426ba` | `nonisolated`, `MKReverseGeocodingRequest`, `@available` cleanup |
| **🐛 FlowLayout regression introduced** | ⚠️ | `2f426ba` | `@ViewBuilder var content` accidentally added to `_FlowLayout: Layout` — caused 3 build errors |
| **🔧 FlowLayout regression fixed** | ✅ | `aa6c614` | Removed generic type + `@ViewBuilder` from `_FlowLayout`; Layout types must never hold view storage |
| End-of-session doc + comment pass | ✅ | this commit | DEVLOG, ROADMAP updated; verbose comments added to all 4 service files |

### Key Lesson — The FlowLayout Bug
The `_FlowLayout` regression is a good example of a class of bugs that can sneak in:
- `FlowLayout<Content: View>: View` is correct — it **is** a View and **owns** the `@ViewBuilder` content.
- `_FlowLayout: Layout` is the SwiftUI `Layout` protocol implementation — it must **never** hold `@ViewBuilder` storage. The engine calls `sizeThatFits` and `placeSubviews` passing subviews automatically.
- A `Layout` type has no `body`. It is not a `View`. Adding `@ViewBuilder var content` to it causes Swift to fail to infer the generic `Content` because `Layout` conformance doesn't participate in `ViewBuilder.buildExpression`.
- Rule: **if it conforms to `Layout`, it cannot have `@ViewBuilder` properties.**

---

## Previously Landed (May 14, 2026 — Sprint 2 mid-session)

| Commit | What |
|---|---|
| `3baba7c` | fix(Bug-3): wire `persistedID` + `historyStore` into `RideSummaryView` callsite |
| `abb02ee` | fix(Bug-3): persist AI caption on generation, restore on re-open |
| `f377f7c` | fix(Bug-3): `aiCaption` on `PersistedRideSummary` + `saveCaption` |
| `1dc540d` | fix(concurrency): `VeloAI.isAvailable` and `makeSession` `nonisolated` |
| `054851e` | fix(ai): use `respond(to:)` not `generate(from:)` for plain-string prompts |
| `2e9e39e` | fix(ai): replace `streamResponse` with `respond(to:)` |
| `2ec05c6` | dead code removal |

## Previously Landed (May 12–13, 2026 — Sprint 1)

| Commit | What |
|---|---|
| `c299bc1` | **P0** GPX locale crash — `String(format: "%f", ...)` for all lat/lon |
| `c299bc1` | **P1** `RideSessionStore` `deinit` — cancels `errorClearTask`, invalidates `elapsedTimer` |
| `c299bc1` | **P1** Heading guard — `heading != 0 \|\| trueHeading >= 0` |
| `c299bc1` | **P1** `RouteLibraryView` `.constant()` alert → `@State var showImportAlert` |
| `c299bc1` | **P1** `RouteStore` force-unwrap crash — `storageDirectory()` + `poisStorageURL()` now throw |
| `842fb65` | **MK-5** `POISearchService` typed `MKPointOfInterestFilter` |
| `842fb65` | **P0** `POIDiscoverySheet` POI ID collision fixed with `deterministicID(for:)` |
| `842fb65` | **P0** `POIDiscoverySheet` category → `item.pointOfInterestCategory` |
| `842fb65` | **P1** Watch haptic loop fixed — `didAlertOffRoute` flag |
| `a587b44` | **AC-3** `WatchRideSummary` `Codable` split into `nonisolated extension` |
| `a587b44` | **MISC-3** `AccentColor.colorset` added to `iPhone/Assets.xcassets` |
| `cc8f2fc` | **MISC-2** Removed spurious `await` on sync `plan.loadFrom(route:)` |

---

## Open Bugs

*(None — all P0/P1 bugs resolved. FlowLayout regression fixed in `aa6c614`.)*

---

## Open Features

| # | Feature | Sprint | Notes |
|---|---|---|---|
| F-C1 | RidePlanAssistant core | **3 — next** | `PlanAssistantEngine`, `RidePlanIntent+Generable`, `RidePlanAssistantView`, `DisambiguationSheet` |
| F-C2 | RidePlanAssistant polish + partial F-3 | 3 | Stop icons, dwell time, Save/Discard UX; extract `RideMapLayer` + `RideHUDPanel` while in `RideView` |
| F-3 | `RideView` god view split | 3 (incremental) | Extract `RideMapLayer` + `RideHUDPanel` during F-C2 |
| F-4 | `RideSessionStore` god object split | 4 (incremental) | Extract `POITrackingEngine` during P2 perf fixes |

---

## Remaining Warnings (Xcode) — End of May 15

**None.** Zero warnings, zero errors. Clean build confirmed.

---

## Architecture Notes — FoundationModels (iOS 26)

This section exists so the next session doesn't re-learn these rules.

### API surface we use
- **`SystemLanguageModel.default`** — the on-device model. Never instantiate your own model.
- **`LanguageModelSession(model:)`** — create a new session per request (they're lightweight). Do NOT hold a session as a long-lived `@State` or stored property on an actor.
- **`session.respond(to: prompt)`** — use for plain `String` prompts where you want a plain `String` back. This is what `RideSummaryGenerator` and `RouteNameSuggester` use.
- **`session.generate(from: schema)`** — use for `@Generable` structured output. This is what `RidePlanIntent+Generable` will use in Sprint 3.
- **DO NOT use** `session.stream(from:onPartial:)` — removed in iOS 26 beta. The replacement is `respond(to:)` for strings and `generate(from:)` for structured types.

### Availability pattern
- **`SystemLanguageModel.default.availability == .available`** — the single gate. Check this before creating any session.
- **`nonisolated`** — any property that reads `SystemLanguageModel.default.availability` must be `nonisolated` if it might be called from a non-main-actor context (e.g., inside `.task {}` blocks, background actors).
- **`@AppStorage(VeloAI.enabledKey)`** — user toggle. Always check `VeloAI.isAvailable && aiEnabled` together before showing AI UI or calling any service.
- **Do NOT add `@available(iOS 26, *)`** to service structs — the deployment target is iOS 26. That annotation is redundant and was removed in `2f426ba`.

### Watch target exclusion
`FoundationModels` is an **iPhone-only framework**. The following files must **never** be added to the Watch target in Build Phases:
- `VeloAI.swift`
- `RouteNameSuggester.swift`
- `RideSummaryGenerator.swift`
- `POIRankingEngine.swift`
- (Sprint 3) `PlanAssistantEngine.swift`, `RidePlanIntent+Generable.swift`

### MKReverseGeocodingRequest (iOS 26)
- **`CLGeocoder` is deprecated on iOS 18+.** Never use it. PROJECT.md flags this explicitly.
- Use `MKReverseGeocodingRequest(coordinate:)` → `req.response` (async/await, no completion handler).
- Returns `MKReverseGeocodingResponse` with a `.placemark: MKPlacemark`. Read `.locality` or `.subLocality` for city/neighbourhood names.

---

## Notes / Watch-outs

- **iOS 26+ only.** No backward-compatibility shims. Gate with `#available` only for Watch-target-safe files (e.g., `MKMapItem.identifier`).
- **`FoundationModels` is iOS only** — never add AI service files to the Watch target (see above).
- **`_FlowLayout` must never hold `@ViewBuilder` storage** — it conforms to `Layout`, not `View`. The `FlowLayout` View wrapper owns the content; `_FlowLayout` receives subviews from the engine.
- **`CLGeocoder` is deprecated** — use `MKReverseGeocodingRequest` everywhere.
- **`session.respond(to:)`** for plain string I/O, **`session.generate(from:)`** for `@Generable` structured output.
- `RideSessionStore.swift` is ~30 KB. F-4 split is overdue — do incrementally during Sprint 4.
- `POIDiscoverySheet` vs `NearbySearchSheet` overlap — merge into `mode: .preRide | .midRide` before 1.0.
