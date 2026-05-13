# VeloGPXNeo — Future Features Backlog
> Created: May 13, 2026 | Status: Not started — planned for future sprints

---

## Overview

This document tracks significant new features that are scoped, technically validated, and ready to be picked up in a future sprint. Items here are distinct from tech debt — they represent net-new user-facing capability, not fixes to existing code.

---

## F-A — Foundation Models: On-Device AI

**Priority:** High  
**API:** `FoundationModels` (iOS 26+, Apple Intelligence)  
**Requires:** iOS 26 minimum deployment target (already set)  
**Status:** Not started

### Why This Matters

`FoundationModels` runs fully on-device, fully offline — no API keys, no server costs, no network dependency. This is critical for a cycling app used on remote routes where connectivity is unreliable or absent. Unlike cloud LLMs, it respects user privacy (ride data never leaves the device) and works in airplane mode.

The framework uses Apple's on-device Apple Intelligence model, which is small enough to run at low latency and supports structured generation via `@Generable` macros.

---

### F-A1 — Ride Summary Generation

**What it does:** After a ride completes, feed the `RideSummary` data into a `FoundationModels` session to generate a natural-language summary the user can share directly (Messages, Instagram caption, Strava description, etc.).

**Input data available in `RideSummary`:**
- `routeName`, `totalDistance`, `elevationGain`, `elevationLoss`
- `maxSpeed`, `elapsedTime`, `movingTime`, `startDate`
- `actualTrack` (array of coordinates for geography context)
- `pois` (visited POIs can be mentioned by name)

**Implementation plan:**

1. Add `FoundationModels` import to `RideSummaryView.swift`
2. Create `RideSummaryGenerator.swift` in `iPhone/Services/`:
   ```swift
   import FoundationModels

   @available(iOS 26, *)
   struct RideSummaryGenerator {
       private let session = LanguageModelSession()

       func generate(from summary: RideSummary) async throws -> String {
           let distKm  = String(format: "%.1f", summary.totalDistance / 1000)
           let gainM   = Int(summary.elevationGain)
           let elapsed = formatDuration(summary.elapsedTime)
           let pois    = summary.pois.prefix(3).map { $0.name }.joined(separator: ", ")

           let prompt = """
           Write a 2-3 sentence summary for a cycling ride.
           Route: \(summary.routeName)
           Distance: \(distKm) km  |  Elevation gain: \(gainM) m  |  Time: \(elapsed)
           Notable stops: \(pois.isEmpty ? "none" : pois)
           Tone: enthusiastic but factual. No hashtags. No emojis.
           """
           let response = try await session.respond(to: prompt)
           return response.content
       }
   }
   ```
3. Surface in `RideSummaryView` as a "Generate Summary" button → inline text field pre-filled with result, editable before sharing.
4. Gate with `#available(iOS 26, *)` and `ModelAvailability.isAvailable` check; show a static template fallback on unsupported devices.

**UX placement:** `RideSummaryView` — below the stats grid, above the Share button. One tap generates; user can regenerate or edit inline before sharing.

---

### F-A2 — Smart Route Naming

**What it does:** When a user imports a GPX file with a generic filename (e.g., `track_2026-05-13.gpx`) or taps "Rename", suggest a human-readable name based on the route's geography.

**Input:** Start/end coordinates + key waypoint coordinates from `RouteModel.trackPoints`

**Implementation plan:**

1. Create `RouteNameSuggester.swift` in `iPhone/Services/`:
   ```swift
   import FoundationModels
   import CoreLocation

   @available(iOS 26, *)
   struct RouteNameSuggester {
       private let session = LanguageModelSession()
       private let geocoder = CLGeocoder()   // fallback until MK-3 migration

       func suggest(for route: RouteModel) async throws -> [String] {
           // Sample 5 evenly spaced points for geographic context
           let points = stride(from: 0, to: route.trackPoints.count,
                               by: max(1, route.trackPoints.count / 5))
               .map { route.trackPoints[$0].coordinate }

           // Reverse geocode the start and midpoint
           let startName  = try await geocodeName(points.first)
           let middleName = try await geocodeName(points[points.count / 2])

           let distKm = String(format: "%.0f", route.totalDistance / 1000)
           let gainM  = Int(route.elevationGain)

           let prompt = """
           Suggest 3 short, evocative route names for a cycling ride.
           Start area: \(startName ?? "unknown")
           Midpoint area: \(middleName ?? "unknown")
           Distance: \(distKm) km  |  Elevation gain: \(gainM) m
           Style: specific place names, loop/circuit/climb if applicable, 3-6 words max.
           Return exactly 3 names, one per line, no numbering.
           """
           let response = try await session.respond(to: prompt)
           return response.content
               .split(separator: "\n")
               .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
               .filter { !$0.isEmpty }
       }

       private func geocodeName(_ coord: Coordinate?) async throws -> String? {
           guard let coord else { return nil }
           let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
           let placemarks = try await geocoder.reverseGeocodeLocation(loc)
           return placemarks.first?.locality ?? placemarks.first?.subLocality
       }
   }
   ```
2. Show suggestions as a pill picker in the rename sheet in `RouteLibraryView`.
3. Gate with `#available(iOS 26, *)` — show a plain text field on earlier OS.

> **Note:** Replace `CLGeocoder` with `MKReverseGeocodingRequest` once MK-3 migration is complete (see TECH_DEBT.md).

---

### F-A3 — POI Relevance Ranking

**What it does:** When the user opens `POIDiscoverySheet` or `NearbySearchSheet`, rank the returned POIs by predicted relevance to the current ride context — all on-device, no server.

**Context signals available:**
- `RouteModel.difficulty` (easy/moderate/hard/epic)
- `RouteModel.elevationGain` (high gain → water sources ranked higher)
- `RideHistoryStore` — categories of POIs the user has interacted with on past rides
- `rideState.totalDistance` / elapsed time (late in long ride → food/accommodation ranked higher)

**Implementation plan:**

1. Create `POIRankingEngine.swift` in `iPhone/Services/`:
   ```swift
   import FoundationModels

   @available(iOS 26, *)
   @Generable
   struct RankedPOI: Identifiable {
       let id: UUID
       let relevanceScore: Double   // 0.0–1.0
       let reason: String           // short justification shown on hover
   }

   @available(iOS 26, *)
   actor POIRankingEngine {
       static let shared = POIRankingEngine()
       private let session = LanguageModelSession()

       func rank(_ pois: [POIModel],
                 context: RideContext) async -> [POIModel] {
           // Build a structured prompt with ride context + POI list
           // Use @Generable to get back a typed [RankedPOI] response
           // Sort pois by relevanceScore and return
       }
   }
   ```
2. `RideContext` struct captures: difficulty, elevationGain, distanceSoFar, timeOfDay, pastCategoryFrequency (from `RideHistoryStore`).
3. Integrate into `POIDiscoverySheet` — add a "Suggested" sort option alongside "Nearest" and "By Category". Default to "Suggested" when at least 3 rides of history exist.
4. Show `reason` as a subtitle under the POI name (`"Good stop for a long climb route"`).

**Fallback:** When `FoundationModels` is unavailable, keep current distance-sorted order.

---

### F-A — Shared Implementation Notes

- Add `FoundationModels` framework to the VeloGPX target in Build Phases
- All three features should check `ModelAvailability.isAvailable` before showing AI-powered UI
- Use a shared `VeloAISession` wrapper to avoid spinning up multiple concurrent `LanguageModelSession` instances
- Consider adding a user toggle in `SettingsView` — "AI Features (Apple Intelligence)" — with a clear explanation that all processing is on-device
- Language: Apple Intelligence respects the device locale; no extra localization needed for generated text in the short term

---

## F-B — Unified Maps URLs + Apple Place IDs (MK-6)

**Priority:** High (blocks shareable POI lists and stable POI identity)  
**API:** `MKMapItem.identifier` (iOS 18+)  
**Status:** Not started — full spec already in TECH_DEBT.md MK-6

### Why This Matters

`POIModel` currently uses a coordinate-based `deterministicID` for stable identity. This works but misses the **Apple Maps Place ID** (`MKMapItem.identifier`, iOS 18+), which:
- Survives business renames and minor address changes
- Enables deep-link URLs that open directly in Apple Maps (`maps://?auid=<identifier>`)
- Lays the foundation for shareable POI lists (share a route + its POIs as tappable Maps links)
- Prevents collisions when two businesses share nearly identical coordinates (café that moved 5m)

### Implementation Plan

**Step 1 — Extend `POIModel`** (`Shared/Models/POIModel.swift`):
```swift
public struct POIModel: Codable, Identifiable, Sendable, Equatable {
    // ... existing fields ...

    // New optional fields — backwards-compatible (Codable handles missing keys)
    public var mapItemIdentifier: String?   // MKMapItem.identifier.rawValue (iOS 18+)
    public var mapsURL: URL?               // maps://?auid=<identifier>
}
```

**Step 2 — Factory extension** (new file: `Shared/Models/POIModel+MapKit.swift`):
```swift
import MapKit

extension POIModel {
    static func from(_ mapItem: MKMapItem, distanceFromRoute: Double = 0) -> POIModel {
        var poi = POIModel(
            id: UUID(),
            name: mapItem.name ?? "",
            category: POICategory.from(mapItem.pointOfInterestCategory),
            coordinate: (mapItem.location?.coordinate
                         ?? mapItem.placemark.coordinate).asCoordinate,
            distanceFromRoute: distanceFromRoute
        )
        if #available(iOS 18, *) {
            poi.mapItemIdentifier = mapItem.identifier?.rawValue
            poi.mapsURL = mapItem.identifier.flatMap {
                URL(string: "maps://?auid=\($0.rawValue)")
            }
        }
        return poi
    }
}
```
> Replace `mapItem.placemark.coordinate` fallback with `mapItem.location?.coordinate` once MK-2 migration is complete.

**Step 3 — Update `isAdded` logic** in `NearbySearchSheet`, `POIDiscoverySheet`, `PreRidePOISheet`:
```swift
// Prefer identifier-based match; fall back to coordinate hash
func isAdded(_ mapItem: MKMapItem, in pois: [POIModel]) -> Bool {
    if #available(iOS 18, *),
       let id = mapItem.identifier?.rawValue {
        return pois.contains { $0.mapItemIdentifier == id }
    }
    return pois.contains { $0.id == deterministicID(for: mapItem) }
}
```

**Step 4 — "Open in Maps" button** in `NearbyResultCard` and POI detail rows:
```swift
if let url = poi.mapsURL {
    Button {
        UIApplication.shared.open(url)
    } label: {
        Label("Open in Maps", systemImage: "map")
    }
    .buttonStyle(.bordered)
}
```

**Step 5 — Shareable POI list (stretch goal)**
Once Place IDs are stable, generate a shareable text or URL containing POI identifiers. The receiver opens Maps and sees the exact same places. Implementation deferred until F-B steps 1–4 are stable.

### Backward Compatibility
- `POIModel` is `Codable` — adding optional fields with `nil` defaults is fully backwards-compatible
- Existing JSON files in `RideHistoryStore` decode without errors; new fields default to `nil`
- `deterministicID(for:)` coordinate fallback preserved for Watch builds and custom waypoints which will never have a Place ID

---

## Feature Comparison

| Feature | API | iOS Min | Offline | Net-New UX |
|---|---|---|---|---|
| F-A1 Ride summary generation | `FoundationModels` | iOS 26 | ✅ Yes | Shareable natural language summary post-ride |
| F-A2 Smart route naming | `FoundationModels` + `CLGeocoder`/`MKReverseGeocodingRequest` | iOS 26 | ✅ Yes (geocoding cached) | Auto-named routes on import |
| F-A3 POI relevance ranking | `FoundationModels` | iOS 26 | ✅ Yes | "Suggested" POI sort based on ride context |
| F-B Place IDs + Maps URLs | `MKMapItem.identifier` | iOS 18 | N/A | Stable POI identity + "Open in Maps" deep link |

---

## Dependencies & Sequencing

```
MK-2 migration (TECH_DEBT) ──► F-B (POIModel+MapKit factory uses .location instead of .placemark)
MK-3 migration (TECH_DEBT) ──► F-A2 (replace CLGeocoder with MKReverseGeocodingRequest)
F-B (Place IDs stable) ──────► Stretch: shareable POI lists
F-A1 (summary gen) ──────────► Can ship independently, no other F-A prerequisites
F-A2, F-A3 ──────────────────► Can ship in any order after F-A1 validates the AI session pattern
```

---

## Open Questions

- **F-A3 training signal:** Should `RideHistoryStore` track which POI categories the user actually visits (stops at) vs. just passes near? Requires adding a `visitedPOICategories` field to `PersistedRideSummary`.
- **F-A language:** Should generated text (ride summaries, route names) respect `LocalizationManager` language override, or always use device locale? Device locale is simpler and likely correct for v1.
- **F-B Watch compatibility:** `MKMapItem.identifier` is iOS 18+ only and not available on watchOS. The Watch target must always use the coordinate `deterministicID` fallback — ensure `POIModel+MapKit.swift` is excluded from the Watch target in Build Phases.
