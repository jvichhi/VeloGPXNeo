# VeloGPXNeo — Dev Log
> Active work tracker. Updated each session so the next session can onboard instantly.
> For longer-lived tech debt, see `TECH_DEBT.md`.

---

## Current State — July 24, 2026

**Build:** ✅ Clean — zero warnings, zero errors (iOS 26+, SwiftUI / MapKit / CoreLocation / FoundationModels)

**Sprint 1:** ✅ Complete
**Sprint 2:** ✅ Complete
**Sprint 3:** ✅ Complete
**Sprint 4:** ✅ Complete
**Sprint 5 (F-D Draw Route):** ✅ Core shipped
**Sprint 6:** 🚧 In progress — see ROADMAP.md for open items

**Next session starts at:** Sprint 6 — F-D5 inline route naming, then MISC-5 bearing dedup, then F-E spoken cues.

---

## Session Summary — May 23, 2026

| Item | Status | Notes |
|---|---|---|
| **Share-1: Share card blank on first tap** | ✅ Fixed | Nil-guard added after `await generateSnapshot()` in `renderShareCard()`. Root cause: `containerWidth` was `390` (default) when `generateSnapshot()` first ran; `GeometryReader.onAppear` hadn't fired yet. Fix in `RideHistoryDetailView.swift` — see `// FIX:` comment. |
| **F-D3: Draw Route entry point moved** | ✅ | Moved to `WaypointListSheet.emptyPrompt` in Plan tab. `RouteLibraryView` toolbar restored to single `+` import button. |
| **F-D4: Pan/Draw mode toggle** | ✅ | `DrawRouteView` defaults to pan mode. `pencil.circle` toolbar button toggles draw mode. `Color.clear` overlay intercepts touches in draw mode only. Haptic on toggle. |
| **F-D spec updated** | ✅ | `Docs/Specs/F-D_DrawRoute.md` updated to reflect shipped implementation. |

### Key Design Decisions — May 23

**Why pan mode is the default:** Users need to navigate the map to find their area before drawing. Default pan so they orient first, then switch to draw.

**Why `Color.clear` overlay instead of `simultaneousGesture`:** `simultaneousGesture` on `Map` fires both the map pan and `DragGesture` simultaneously — the map pans while you draw, producing garbage coordinates. A `Color.clear` overlay with `.contentShape(Rectangle())` intercepts touches entirely when present; `Map` gets all touches normally when absent.

**Share bug root cause:** On first Share tap, `containerWidth` is `390` (hardcoded `@State` default) because `GeometryReader.onAppear` fires asynchronously. `generateSnapshot()` used the wrong width → `MKMapSnapshotter` produced a misaligned or nil image → blank card. Fix: nil-guard after `await generateSnapshot()` prevents `ImageRenderer` running with a nil snapshot.

---

## Session Summary — May 17, 2026

| Item | Status | Notes |
|---|---|---|
| **F-C3** Distance-matching layer | ✅ | `targetDistanceKm` + `suggestedName` wired. Loop extension algorithm pushes return-segment midpoint perpendicular when too short. ±15% tolerance, max 2 attempts, 20 km push cap. |
| `CLLocationCoordinate2D` helpers | ✅ | `bearing(to:)`, `midpoint(to:)`, `destination(bearing:distance:)` added to `Shared/Extensions/`. |
| **Bug fix** AI assistant not triggering routing | ✅ | `PlanAssistantEngine` now calls `PlanRouteEngine.recomputeAll` after waypoint population. |
| **Bug fix** POI spur straight-line fallback | ✅ | `RideSessionStore+Spurs.fetchLeg` returns nil on MKDirections failure. |
| Reorder → Re-route button | ✅ | `WaypointListSheet` reorder replaced with re-route (triggers `recomputeAll`). |
| Dead code audit | ✅ | 581 lines deleted across 14 files. |
| README.md | ✅ | Full rewrite for public GitHub. |

---

## Session Summary — May 14–15, 2026

| Item | Status | Commit |
|---|---|---|
| F-A Shared: `VeloAI.swift` | ✅ | `77cfdcb` |
| F-A1: `RideSummaryGenerator.swift` | ✅ | `77cfdcb` |
| F-A2: `RouteNameSuggester.swift` | ✅ | `77cfdcb` |
| F-A3: `POIRankingEngine.swift` | ✅ | `77cfdcb` |
| `RouteLibraryView.swift` F-A2 rewrite | ✅ | `6004119` |
| Post-review fixes | ✅ | `2f426ba` |
| FlowLayout regression fixed | ✅ | `aa6c614` |

### Key Lesson — The FlowLayout Bug
- `FlowLayout<Content: View>: View` is correct — it **is** a View and **owns** the `@ViewBuilder` content.
- `_FlowLayout: Layout` must **never** hold `@ViewBuilder` storage. The `Layout` protocol has no `body`; it is not a `View`. Adding `@ViewBuilder var content` to a `Layout` type causes Swift to fail to infer the generic `Content`.
- **Rule:** if it conforms to `Layout`, it cannot have `@ViewBuilder` properties.

---

## Open Bugs

**None.** All known bugs resolved.

---

## Open Features

| # | Feature | Sprint | Notes |
|---|---|---|---|
| F-D5 | Draw Route — inline naming | 6 | `commitRoute()` currently hardcodes `"Drawn Route"`. Add `TextField` before commit or present `RouteRenameSheet` on dismiss. |
| F-E | Spoken Turn-by-Turn Cues | 6 | See ROADMAP.md § Sprint 6 for full task list. |

---

## Remaining Warnings (Xcode)

**None.** Zero warnings, zero errors. Clean build confirmed.

---

## Architecture Notes — FoundationModels (iOS 26)

This section exists so the next session doesn't re-learn these rules.

### API surface we use
- **`SystemLanguageModel.default`** — the on-device model. Never instantiate your own model.
- **`LanguageModelSession(model:)`** — create a new session per request (lightweight). Do NOT hold a session as a long-lived `@State` or stored property.
- **`session.respond(to: prompt)`** → plain `String` output. Used by `RideSummaryGenerator` and `RouteNameSuggester`.
- **`session.respond(to: prompt, generating: SomeType.self)`** → typed `@Generable` structured output. Used by `RidePlanIntent+Generable`.
- **DO NOT use** `session.stream(from:onPartial:)` — removed in iOS 26. Use `respond(to:)` for strings and `respond(to:generating:)` for structured types.

### Availability pattern
- **`SystemLanguageModel.default.availability == .available`** — the single gate.
- **`VeloAI.isAvailable`** wraps this — always use the wrapper, not the framework directly in views.
- **`@AppStorage(VeloAI.enabledKey)`** — user toggle. Always check `VeloAI.isAvailable && aiEnabled` together before showing AI UI.
- **Do NOT add `@available(iOS 26, *)`** to service structs — the deployment target is iOS 26.

### Watch target exclusion
`FoundationModels` is iPhone-only. Never add these files to the Watch target:
- `VeloAI.swift`, `RouteNameSuggester.swift`, `RideSummaryGenerator.swift`
- `POIRankingEngine.swift`, `PlanAssistantEngine.swift`, `RidePlanIntent+Generable.swift`
- `SpeechCueService.swift` — `AVAudioSession` unavailable on watchOS
- `WeatherService.swift` — WeatherKit entitlement scope is iPhone only

### MKReverseGeocodingRequest (iOS 26)
- **`CLGeocoder` is deprecated on iOS 18+.** Never use it.
- Initialiser takes a `CLLocation`:
  ```swift
  let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
  guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
  let items = try await request.mapItems
  let item = items.first
  ```
- Read address fields via `item.placemark.locality`, `.administrativeArea`, etc.

---

## Notes / Watch-outs

- **iOS 26+ only.** No backward-compatibility shims.
- **`FoundationModels` is iOS only** — never add AI service files to the Watch target.
- **`_FlowLayout` must never hold `@ViewBuilder` storage** — conforms to `Layout`, not `View`.
- **`CLGeocoder` is deprecated** — use `MKReverseGeocodingRequest(location:)` everywhere.
- **`session.respond(to:)`** for plain string I/O; **`session.respond(to:generating:)`** for `@Generable` structured output.
- **`DrawRouteView` `Color.clear` overlay pattern** — DragGesture lives inside `Color.clear`, not `.simultaneousGesture`. Intentional: see design decision above.
- **`DrawRouteEngine` stores raw `Double` lat/lon** — `CLLocationCoordinate2D` is `@MainActor` on iOS 26+, non-Sendable across actor boundaries.
- **`renderShareCard()` nil-guard** — after `await generateSnapshot()`, if `mapSnapshot` is still nil, `ImageRenderer` is NOT run. See `// FIX:` comment in `RideHistoryDetailView.swift`.
- `RideSessionStore.swift` is ~30 KB — F-4 split overdue; do incrementally during Sprint 6.
- `POIDiscoverySheet` vs `NearbySearchSheet` overlap — merge into `mode: .preRide | .midRide` before 1.0.
