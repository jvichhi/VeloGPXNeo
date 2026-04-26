# iOS 26 Cycling Routes — Implementation Notes

## Branch: `feature/ios26-cycling-routes`

This branch adds full support for the WWDC 2025 MapKit cycling directions APIs,
with safe `#available` guards so the app continues to work on iOS 18.

---

## New Files

| File | Purpose |
|---|---|
| `iPhone/Services/CyclingRouteService.swift` | Computes cycling routes via `MKDirections` with `.cycling` on iOS 26+ and `.walking` fallback on iOS 18 |
| `iPhone/Views/CyclingRouteOverlay.swift` | Drop-in card for `RouteDetailView` — shows route stats, inline map, route name, and notices |
| `iPhone/Views/RouteNoticeView.swift` | Renders road closure/restriction notices from `MKDirections.Response` |
| `iPhone/Services/ReverseGeocodingService.swift` | Replaces `CLGeocoder` with `MKReverseGeocodingRequest` on iOS 26+; falls back to `CLGeocoder` on iOS 18 |
| `iPhone/Services/PlaceDescriptorService.swift` | Resolves GPX waypoint coordinates to named `MKMapItem` using `MKMapItemRequest` on iOS 26+; `MKLocalSearch` fallback on iOS 18 |

---

## Integration Steps

### 1. Add `CyclingRouteOverlay` to `RouteDetailView`

Inside the `VStack(spacing: 16)` in `RouteDetailView.swift`, add:

```swift
// After the Waypoints Card
CyclingRouteOverlay(route: route)
```

### 2. Replace `CLGeocoder` calls

Anywhere you call `CLGeocoder().reverseGeocodeLocation(...)`, replace with:

```swift
let address = await ReverseGeocodingService.shared.reverseGeocode(coordinate)
```

### 3. Resolve waypoints to named places (optional)

In `RouteDetailView` or anywhere you display waypoints:

```swift
let resolved = await PlaceDescriptorService.shared.resolveAll(route.waypoints)
```

---

## iOS Version Behaviour

| Feature | iOS 26+ | iOS 18 fallback |
|---|---|---|
| Transport type | `.cycling` | `.walking` |
| Route name | ✅ `route.name` | ❌ nil |
| Road notices | ✅ `response.notices` | ❌ empty |
| Matched source/dest | ✅ `response.source/destination` | ❌ nil |
| Reverse geocoding | `MKReverseGeocodingRequest` | `CLGeocoder` |
| Waypoint resolution | `MKMapItemRequest` | `MKLocalSearch` |

---

## Deployment Target

No change needed to minimum deployment target — all iOS 26 APIs are guarded.
Requires **Xcode 26** to compile (`.cycling` enum case is new in the SDK).
