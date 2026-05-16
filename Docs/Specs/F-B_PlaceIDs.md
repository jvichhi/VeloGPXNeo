# F-B — Unified Maps URLs + Apple Place IDs

**Priority:** High
**API:** `MKMapItem.identifier` (iOS 18+)
**Status:** Backlog

---

## Goal

Improve POI identity stability and enable Apple Maps deep links via Place IDs.

## Why

`POIModel` currently uses a coordinate-based `deterministicID`. This works but misses `MKMapItem.identifier` (iOS 18+) which:
- Survives business renames and minor address changes
- Enables `maps://?auid=<identifier>` deep links
- Prevents collisions when two businesses share nearly identical coordinates

## Implementation Plan

**Step 1 — Extend `POIModel`** (`Shared/Models/POIModel.swift`):
```swift
public var mapItemIdentifier: String?   // MKMapItem.identifier.rawValue (iOS 18+)
public var mapsURL: URL?               // maps://?auid=<identifier>
```
These are optional — fully backwards-compatible with existing JSON in `RideHistoryStore`.

**Step 2 — Factory** (`Shared/Models/POIModel+MapKit.swift`):
Gate identifier reads with `if #available(iOS 18, *)`.

**Step 3 — Update `isAdded` logic** in `POIDiscoverySheet`, `NearbySearchSheet`, `PreRidePOISheet` to prefer identifier matching.

**Step 4 — Add "Open in Maps" button** in POI detail rows using `mapsURL`.

## Notes

- Watch target always uses the coordinate `deterministicID` fallback.
- `POIModel+MapKit.swift` must never be added to the Watch target.
