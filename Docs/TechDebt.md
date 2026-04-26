# VeloGPX Neo — Tech Debt Tracker

> Last updated: 2026-04-26  
> Session: Post feature-burst checkpoint

This doc tracks all identified tech debt items, their status, and the rationale for each fix. Update the status column when work is merged.

---

## Legend

| Symbol | Meaning |
|---|---|
| ✅ | Done — merged to main |
| 🔄 | In progress |
| ⬜ | Queued — not started |

---

## P0 — Blockers / Correctness

| # | Item | File(s) | Status | Notes |
|---|---|---|---|---|
| P0-1 | ~~Duplicate `POISearchService.swift` at root `iPhone/`~~ | `iPhone/POISearchService.swift` | ✅ | Deleted root-level copy. `iPhone/Services/POISearchService.swift` is canonical. Root copy was `ObservableObject` (wrong pattern); Services copy is `final actor`-safe singleton. |
| P0-2 | POI toggle used name-matching instead of UUID | `iPhone/Views/NearbySearchSheet.swift` | ✅ | `isAdded(_:)` and `toggle(_:)` now match on `coordinate` fingerprint at creation and `UUID` from `routeStore.selectedPOIs`. See fix notes below. |

### P0-2 Fix Notes
The root problem: `MKMapItem` has no stable ID. The fix seeds the `POIModel.id` from a deterministic UUID derived from the coordinate (lat+lon rounded to 6dp, hashed). This means the same real-world location always gets the same UUID regardless of which sheet creates it, so `isAdded` can use UUID comparison safely.

---

## P1 — Important Correctness / UX

| # | Item | File(s) | Status | Notes |
|---|---|---|---|---|
| P1-1 | All routing used `.walking` transport type | `iPhone/Views/RideView.swift`, `iPhone/Stores/RideSessionStore.swift` | ✅ | All `MKDirections` calls replaced with `CyclingRouteService.shared`. iOS 26+ gets `.cycling`, older gets `.walking` fallback. The service already existed but was unused. |
| P1-2 | `nextPOI` picked nearest by raw distance, not on-route order | `iPhone/Stores/RideSessionStore.swift` | ✅ | `updateNextPOI` now projects each POI onto the GPX track using nearest track index, then filters to POIs whose projected index is ≥ `nearestTrackIndex`. Sorts by projected distance remaining. |

### P1-1 Fix Notes
`CyclingRouteService` in `iPhone/Services/` already had the `#available(iOS 26)` guard for `.cycling`. It was never called — `RideView` and `RideSessionStore` were each rolling their own `MKDirections.Request` inline. Both now delegate to `CyclingRouteService.shared.calculateRoute(from:to:)`.

### P1-2 Fix Notes
Previous logic: sort all POIs by `coordinate.distance(to: currentLocation)`, take minimum within 5km.  
New logic:
1. For each POI, find the nearest track index (capped search window ±100 from current `nearestTrackIndex`).
2. Filter to POIs whose track index ≥ `nearestTrackIndex` (i.e., still ahead).
3. Sort by track index ascending — the POI closest ahead on the route wins.
4. `nextPOIDistance` is still straight-line for display (accurate enough for the chip).

---

## P2 — Architecture / Improvements

| # | Item | File(s) | Status | Notes |
|---|---|---|---|---|
| P2-1 | `PlaceDescriptorService` unwired — dead code risk | `iPhone/Services/PlaceDescriptorService.swift`, `iPhone/Views/RouteDetailView.swift` | ✅ | Wired to `RouteDetailView`: waypoints now call `PlaceDescriptorService.shared.resolve()` on appear to enrich their display name and address. No new UI — enriched name replaces raw GPX name in the waypoint list. |

---

## P3 — Nice to Have / Performance

| # | Item | File(s) | Status | Notes |
|---|---|---|---|---|
| P3-1 | `sendWatchUpdate()` called on every GPS ping | `iPhone/Stores/RideSessionStore.swift` | ✅ | Throttled to 1 Hz using a `Date`-based gate. WCSession messages were firing at ~5m GPS filter rate (~1–3/sec at cycling speed), wasting encode cycles. |

---

## Remaining Backlog (not in this session)

| # | Item | Priority | Notes |
|---|---|---|---|
| B-1 | Extract `RideView` into sub-views (God View) | 🟡 P1 | `RideView.swift` is 35KB. Extract: `RideMapLayer`, `RideHUDPanel`, `RideBirdsEyePanel`. Move spur logic to `POISpurService`. |
| B-2 | Split `RideSessionStore` responsibilities | 🟡 P1 | 7 concerns in one class. Split into `RideLocationEngine`, `POITrackingEngine`, `WatchSyncManager`. |
| B-3 | `hudHeight` uses `DispatchQueue.asyncAfter` timing hack | 🟡 P2 | Replace with `PreferenceKey`-based height propagation. |
| B-4 | Elevation gain/loss uses raw GPS altitude, no smoothing | 🟡 P2 | Apply 2m threshold gate minimum. Kalman filter stretch goal. |
| B-5 | Two `.onAppear` blocks in `RideView` | 🟢 P3 | Merge into one. |
| B-6 | No unit tests for core logic | 🟢 P3 | Add `XCTestCase` for `minimumDistance`, POI ordering, `bearing()`. |
| B-7 | `LocalizationManager` unused in views | 🟢 P3 | Harden all user-visible strings through localization system. |
| B-8 | `RideHistoryStore` loads all history at once | 🟢 P3 | Paginate or migrate to SwiftData. |
| B-9 | Silent `catch {}` blocks everywhere | 🟢 P3 | Add `@Published var lastError: String?` to `RideSessionStore`, surface in HUD. |
| B-10 | `NextPOIBanner.swift` is an orphaned stub | 🟢 P3 | Delete or promote to replace inlined chip in `RideView`. |
| B-11 | `RouteNoticeView.swift` appears vestigial | 🟢 P3 | Audit usages, delete if unused. |
| B-12 | Manual `Annotation("You")` should use `UserAnnotation()` | 🟢 P2 | System pulsing dot + accuracy ring is better UX. |
| B-13 | `MapCameraAnimation` not used for riding camera updates | 🟢 P2 | Wrap `updateRidingCamera` in `MapCameraAnimation` for smoother heading changes. |
