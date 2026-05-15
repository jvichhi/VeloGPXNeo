# VeloGPX Neo — Tech Debt Tracker

> Last updated: 2026-05-15  
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
| P0-3 | Deleting a middle waypoint in Plan Route leaves a diagonal / broken blue line | `iPhone/Services/PlanRouteEngine.swift`, `iPhone/Views/WaypointListSheet.swift` | ⬜ | See fix notes below. |
| P0-4 | Compiler errors in `POIRankingEngine` and `RouteNameSuggester` | `iPhone/Services/POIRankingEngine.swift`, `iPhone/Services/RouteNameSuggester.swift` | ⬜ | See fix notes below. |

### P0-2 Fix Notes
The root problem: `MKMapItem` has no stable ID. The fix seeds the `POIModel.id` from a deterministic UUID derived from the coordinate (lat+lon rounded to 6dp, hashed). This means the same real-world location always gets the same UUID regardless of which sheet creates it, so `isAdded` can use UUID comparison safely.

### P0-3 Fix Notes — Waypoint Delete Reroute

**Symptom:** Deleting a middle waypoint (e.g. B from [A, B, C]) leaves a diagonal straight line or a gap on the map instead of routing A→C via cycling roads.

**Root cause — two compounding issues:**

1. **Actor isolation race.** `deleteWaypoint` in `WaypointListSheet` fires `Task { await engine.refreshSegments(...) }` without `@MainActor`. `PlanRouteEngine` is `@MainActor` but the anonymous `Task` closure hops off the main actor. `state.segments` reads inside `dirtyPairs` therefore race against main-actor mutations, and a prior in-flight `computeSegment` response (for the now-deleted pair) can still call `upsertSegment` after cancellation, inserting a stale straight-line fallback that overwrites the clean state.

2. **Visual gap during routing.** `removeWaypoint` strips both orphaned segments synchronously, so the map briefly shows no line at all between the remaining waypoints. If the MapKit response is slow (~0.5–1 s), the gap is visible; if a stale task wins the race, a diagonal appears instead.

**Fix — two targeted changes:**

**`WaypointListSheet.swift` — mark the delete `Task` `@MainActor`:**
```swift
// BEFORE:
Task {
    if plan.waypoints.count >= 2 {
        await engine.refreshSegments(in: plan, affectedWaypointIndices: [bridgeIndex])
    }
}

// AFTER:
Task { @MainActor in
    if plan.waypoints.count >= 2 {
        await engine.refreshSegments(in: plan, affectedWaypointIndices: [bridgeIndex])
    }
}
```

**`PlanRouteEngine.swift` — insert a straight-line placeholder before the async routing call** so the map stays visually connected while waiting for the MapKit response. `upsertSegment` will overwrite it with the real routed line when it arrives:
```swift
func refreshSegments(in state: PlanState, affectedWaypointIndices: [Int]) async {
    currentTask?.cancel()
    currentTask = Task {
        state.pruneOrphanedSegments()
        let pairs = dirtyPairs(
            for: affectedWaypointIndices,
            waypoints: state.waypoints,
            existingSegments: state.segments,
            isLoop: state.isLoopClosed
        )
        // Insert straight-line placeholders immediately so the map stays
        // connected during the async routing call. The real routed segment
        // replaces each placeholder via upsertSegment once routing completes.
        for pair in pairs where !pair.isLoop {
            let dist = pair.from.coordinate.planDistance(to: pair.to.coordinate)
            let placeholder = PlanSegment(
                fromWaypointID: pair.from.id,
                toWaypointID: pair.to.id,
                coordinates: [pair.from.coordinate, pair.to.coordinate],
                distance: dist,
                isLoop: false
            )
            state.upsertSegment(placeholder)
        }
        await computeAndApply(pairs: pairs, state: state)
    }
    await currentTask?.value
}
```

**Expected result:** On delete, the map instantly shows a thin straight connector (placeholder), then snaps to the proper cycling route within ~0.5–1 s. No diagonal, no gap, no data race.

---

### P0-4 Fix Notes — Compiler Errors (May 15 2026 session)

**`POIRankingEngine.swift`**

| Line | Error | Fix |
|---|---|---|
| 108 | `Initializer for conditional binding must have Optional type, not 'Double'` | `poi.distanceFromRoute` is a non-optional `Double`. Replace `if let dist = poi.distanceFromRoute` with `let dist = poi.distanceFromRoute`. |
| 135, 138, 139, 153, 212, 215, 216 | `Type 'POICategory' has no member 'restroom' / 'bikeshop' / 'scenic'` | Add the three missing cases to the `POICategory` enum in `POIModel.swift`: `.restroom`, `.bikeshop` (raw value `"bike_shop"`), `.scenic`. Add corresponding `displayName` and `symbolName` switch arms. |
| 194 | `Value of type 'Double' has no member 'map'` | `sp.poi.distanceFromRoute` is a plain `Double`, not `Optional<Double>`. Replace `.map { String(format: "%.0f m away", $0) } ?? "nearby"` with `String(format: "%.0f m away", sp.poi.distanceFromRoute)`. |

**`RouteNameSuggester.swift`**

| Line | Error | Fix |
|---|---|---|
| 100 | `Value of type 'TrackPoint' has no member 'latitude' / 'longitude'` | `TrackPoint` stores coordinates as a nested `Coordinate` struct. Replace `first.latitude` / `first.longitude` with `first.coordinate.latitude` / `first.coordinate.longitude`. |
| 106 | `Incorrect argument label in call (have 'coordinate:', expected 'location:')` | `MKReverseGeocodingRequest` takes a `CLLocation`, not a `CLLocationCoordinate2D`. Wrap: `let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)` then `MKReverseGeocodingRequest(location: location)`. |
| 107 | `No calls to throwing functions occur within 'try'` / `No 'async' operations occur within 'await'` | Check the SDK signature of `MKReverseGeocodingRequest.response`. If it is a non-throwing, non-async property, drop `try?` and `await`. Use `guard let result = request.response else { return nil }`. |

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
