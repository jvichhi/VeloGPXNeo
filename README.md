# VeloGPX

iPhone and Apple Watch cycling app. Import GPX/GeoJSON routes, get turn-by-turn directions with Apple Maps cycling routing, plan routes with on-device AI, and track rides with sensor data.

Requires iOS 26 and Xcode 26. Physical device needed for location, barometer, and on-device LLM features.

## Features

**Route management**
- Import GPX and GeoJSON files from Files, Safari, Mail, or AirDrop
- In-app route library with rename, reverse, and delete
- Document-based opening (.gpx, .geojson, .json)

**Ride tracking**
- Turn-by-turn cues with off-route detection and automatic rerouting
- Live Activity and Apple Watch sync (distance, speed, ETA, next cue)
- Elevation gain from barometric altimeter, climb detection and categorization
- POI tracking along route with proximity alerts
- Post-ride summary with stats, elevation profile, and map replay

**On-device AI (FoundationModels, iOS 26)**
- Natural-language route planning: describe a ride and the LLM parses stops, distance, and loop preference
- Deterministic distance matching extends loop routes to hit the requested distance
- AI-generated ride summaries for sharing
- Smart route naming with geocoded suggestions
- POI relevance ranking by ride difficulty, elevation, and time of day

**Sensors**
- Bluetooth power meters, heart rate monitors, and cadence sensors via CoreBluetooth
- Apple Watch heart rate as fallback

## Architecture

```
Shared/          Models, extensions, and services shared across targets
  Models/        Codable types (RouteModel, POIModel, RideSummary, etc.)
  Extensions/    CLLocationCoordinate2D, TimeInterval helpers
iPhone/          iPhone target
  Views/         SwiftUI views (RouteLibrary, RideView, PlanView, etc.)
  Services/      MapKit routing, FoundationModels AI, MKLocalSearch
  Models/        PlanState, POISpur
  Stores/        RouteStore, RideSessionStore, RideHistoryStore
Watch/           Apple Watch target
  Views/         Glanceable ride metrics
  Stores/        WatchRideStore (receives state via WCSession)
Docs/
  Specs/         Per-feature implementation specs
```

The Watch target only depends on `Shared/`. Files with FoundationModels, MapKit UI, or UIKit imports stay in `iPhone/`.

## Build

1. Open `VeloGPX.xcodeproj` in Xcode 26
2. Set your development team in Signing & Capabilities for all three targets (VeloGPX, VeloGPXWatch Watch App, VeloGPXLiveActivity)
3. Enable these capabilities on the iPhone target:
   - Background Modes: Location updates
   - HealthKit (heart rate from Apple Watch)
4. The Watch target needs HealthKit for heart rate
5. Build and run on a physical iPhone (simulator does not support location, barometer, or FoundationModels)

The project uses `GENERATE_INFOPLIST_FILE = YES` so Info.plist is handled by Xcode. The only manual plist is `VeloGPXLiveActivity/Info.plist`.

## Git

Commits follow `type(scope): description`:

| Prefix | Use |
|--------|-----|
| `feat` | New feature |
| `fix` | Bug fix |
| `refactor` | Code change, no behaviour change |
| `docs` | Markdown files only |
| `chore` | Roadmap, devlog, project upkeep |

Scope matches the roadmap item ID: `feat(ai)`, `fix(perf)`, `docs(readme)`.

## Relevant Apple APIs

- MapKit cycling directions (`MKDirectionsTransportType.cycling`)
- `MKLocalSearch` and `MKReverseGeocodingRequest` (CLGeocoder deprecated)
- FoundationModels `SystemLanguageModel` with `@Generable` structured output
- CoreBluetooth for cycling sensors
- WatchConnectivity for ride state sync
- ActivityKit for Live Activities
- CoreMotion barometric altimeter
