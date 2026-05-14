# VeloGPXNeo — Project Context
> Read this first at the start of every session. Keep it current.

---

## App Identity

| Field | Value |
|---|---|
| **App name** | VeloGPX |
| **Display name** | VeloGPX |
| **Repo** | `jvichhi/VeloGPXNeo` (public) |
| **Platform** | iOS + Apple Watch (paired) |
| **Category** | `public.app-category.navigation` |
| **Bundle ID** | `jvic.VeloGPX` |
| **Team ID** | `DCMGV2B253` |
| **Tagline** | Native iOS + Apple Watch cycling GPS companion. Import GPX/GeoJSON routes, get POI alerts along your route, never get lost on the bike. |

---

## Versions

| Version | Status | Notes |
|---|---|---|
| **1.1** | ✅ Shipped — App Store | Last public release |
| **1.2** | 🔨 In development | `MARKETING_VERSION = 1.2`, `CURRENT_PROJECT_VERSION = 3` (build 3) |
| **1.3** | 📋 Planned | Sprint 1 + 2 work (debt clearance + AI features) |

---

## Xcode Project Settings

| Setting | Value |
|---|---|
| **Xcode version** | 26.4.1 (all targets created on `26.4.1`) |
| **objectVersion / preferredProjectObjectVersion** | 77 |
| **Swift version** | `SWIFT_VERSION = 5.0` (Swift 6 mode via `SWIFT_APPROACHABLE_CONCURRENCY = YES`) |
| **Default actor isolation** | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (iPhone + Watch targets) |
| **Upcoming feature flag** | `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` |
| **String catalogs** | `STRING_CATALOG_GENERATE_SYMBOLS = YES` |
| **Asset symbol extensions** | `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES` |
| **Accent color asset name** | `AccentColor` (all targets) |
| **App icon asset name** | `AppIcon` |
| **Mac Catalyst** | `SUPPORTS_MACCATALYST = NO` |
| **Parallel builds** | `BuildIndependentTargetsInParallel = YES` |

---

## Targets

### VeloGPX (iPhone)

| Setting | Value |
|---|---|
| **Bundle ID** | `jvic.VeloGPX` |
| **Deployment target** | `IPHONEOS_DEPLOYMENT_TARGET = 26.0` |
| **macOS deployment** | `MACOSX_DEPLOYMENT_TARGET = 26.4` |
| **xrOS deployment** | `XROS_DEPLOYMENT_TARGET = 26.4` |
| **Supported platforms** | `iphoneos iphonesimulator` |
| **Device family** | `1` (iPhone only) |
| **Orientations (iPhone)** | Portrait, LandscapeLeft, LandscapeRight |
| **Orientations (iPad)** | All four |
| **Frameworks linked** | `CoreMotion.framework` (explicit); MapKit, SwiftUI, CoreLocation implicit via SDK |
| **App groups** | `REGISTER_APP_GROUPS = YES` |
| **Location usage (always)** | "VeloGPX uses your location to track rides in the background" |
| **Location usage (when-in-use)** | "VeloGPX uses your location to track your ride" |

### VeloGPXWatch Watch App

| Setting | Value |
|---|---|
| **Bundle ID** | `jvic.VeloGPX.watchkitapp` |
| **Deployment target** | `WATCHOS_DEPLOYMENT_TARGET = 26.0` |
| **Device family** | `4` (Apple Watch) |
| **Companion app** | `jvic.VeloGPX` (`WKRunsIndependentlyOfCompanionApp = NO`) |
| **Orientations** | Portrait + PortraitUpsideDown |

### VeloGPXLiveActivityExtension

| Setting | Value |
|---|---|
| **Bundle ID** | `jvic.VeloGPX.VeloGPXLiveActivity` |
| **Deployment target** | `IPHONEOS_DEPLOYMENT_TARGET = 26.0` |
| **Live Activities** | `NSSupportsLiveActivities = YES` |
| **Frameworks linked** | `WidgetKit.framework`, `SwiftUI.framework` |

---

## Tech Stack

| Layer | Technology |
|---|---|
| **Language** | Swift 6 (`SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) |
| **UI** | SwiftUI |
| **Maps** | MapKit (iOS 26 APIs — `MKMapItem.init(location:)`, `MKReverseGeocodingRequest`, typed `MKPointOfInterestFilter`) |
| **Location** | CoreLocation |
| **Motion** | CoreMotion (explicit framework link on iPhone target) |
| **Live Activities** | WidgetKit + ActivityKit |
| **AI** | FoundationModels (iOS 26+, Apple Intelligence — Sprint 2+, not yet linked) |
| **Watch sync** | WatchConnectivity |
| **Backend** | Supabase |
| **Localization** | `Localizable.strings` — 15 languages (see below) |
| **Min deployment** | iOS 26.0, watchOS 26.0 — no legacy API gating below this |
| **Exception** | `MKMapItem.identifier` gates at `#available(iOS 18, *)` — nice-to-have on top of coordinate fallback |

### Localized Languages
`en`, `de`, `ar`, `zh-Hans`, `ja`, `nb`, `es`, `da`, `it`, `sv`, `ko`, `pl`, `fr`, `nl`, `pt`

---

## File Inventory by Target

### iPhone target sources
`VeloGPXApp.swift`, `RootView.swift`, `RideView.swift`, `RouteLibraryView.swift`, `RouteDetailView.swift`, `SettingsView.swift`, `RideSummaryView.swift`, `RideHistoryView.swift`, `RideHistoryDetailView.swift`, `ShareableRideCard.swift`, `NearbySearchSheet.swift`, `POIDiscoverySheet.swift`, `PreRidePOISheet.swift`, `NextPOIBanner.swift`, `PlanView.swift`, `WaypointListSheet.swift`, `CyclingRouteOverlay.swift`, `RouteNoticeView.swift`, `RideSessionStore.swift`, `RideSessionStore+Spurs.swift`, `RouteStore.swift`, `RideHistoryStore.swift`, `CyclingRouteService.swift`, `PlaceDescriptorService.swift`, `POISearchService.swift`, `ReverseGeocodingService.swift`, `MKMapItem+POI.swift`, `PlanRouteEngine.swift`, `PlanState.swift`, `POISpur.swift`, `LocalizationManager.swift`

**Shared files also compiled into iPhone target:**
`POIModel.swift`, `RouteModel.swift`, `RideState.swift`, `RideSummary.swift`, `PersistedRideSummary.swift`, `WatchRideSummary.swift`, `GPXParser.swift`, `GeoJSONParser.swift`, `GPXExporter.swift`, `RideActivityAttributes.swift`, `CLLocationCoordinate2D+Extensions.swift`, `TimeInterval+Formatting.swift`

### Watch target sources
`VeloGPXWatchApp.swift`, `WatchRideView.swift`, `WatchRideStore.swift`

**Shared files also compiled into Watch target:**
`POIModel.swift`, `RouteModel.swift`, `RideState.swift`, `RideSummary.swift`, `WatchRideSummary.swift`, `GPXParser.swift`, `GeoJSONParser.swift`, `GPXExporter.swift`, `LocalizationManager.swift`, `CLLocationCoordinate2D+Extensions.swift`, `TimeInterval+Formatting.swift`

### LiveActivity target sources
`RideActivityAttributes.swift`

### ⚠️ Watch target — never add these files
`MKMapItem+POI.swift` · any `FoundationModels` import · `PlanAssistantEngine.swift` · `RidePlanAssistantView.swift` · `RidePlanIntent+Generable.swift`

---

## Repo Structure

```
VeloGPXNeo/
├── PROJECT.md                        ← you are here — read first every session
├── ROADMAP.md                        ← sprint order and current work queue
├── DEVLOG.md                         ← active session tracker (current state, next task, open bugs)
├── FEATURES.md                       ← future feature specs with full Swift implementation plans
├── TECH_DEBT.md                      ← debt catalogue (P0 → P3, with file + line refs)
├── VeloGPX.xcodeproj/
├── VeloGPX-Info.plist                ← iPhone target plist (generated, INFOPLIST_FILE)
├── VeloGPXWatch-Watch-App-Info.plist ← Watch target plist
├── Package.swift                     ← SPM manifest
├── iPhone/
│   ├── Views/                        ← SwiftUI views (iPhone target only)
│   ├── Services/                     ← CyclingRouteService, POISearchService, etc.
│   ├── Stores/                       ← RideSessionStore, RouteStore, RideHistoryStore
│   ├── Models/                       ← PlanState, POISpur (iPhone-only models)
│   ├── Managers/                     ← LocalizationManager
│   ├── Assets.xcassets
│   └── VeloGPXApp.swift
├── Shared/
│   ├── Models/                       ← POIModel, RouteModel, RideState, RideSummary, etc.
│   ├── Extensions/                   ← CLLocationCoordinate2D+Extensions, TimeInterval+Formatting
│   └── Parsers/                      ← GPXParser, GeoJSONParser
├── Watch/
│   ├── Views/                        ← WatchRideView
│   ├── WatchRideStore.swift
│   └── VeloGPXWatchApp.swift
├── VeloGPXWatch Watch App/           ← Watch target root (filesystem-synchronized group)
├── VeloGPXLiveActivity/              ← LiveActivity extension (filesystem-synchronized group)
├── Resources/                        ← Localizable.strings (15 locales)
├── Samples/                          ← sample GPX/GeoJSON files for testing
└── Docs/                             ← architecture docs
```

---

## Key Models & Services (quick reference)

| Name | Location | Role |
|---|---|---|
| `POIModel` | `Shared/Models/POIModel.swift` | Point of interest — coordinate, category, name, optional Place ID |
| `RouteModel` | `Shared/Models/RouteModel.swift` | GPX/GeoJSON parsed route with track points and elevation |
| `RideSummary` | `Shared/Models/RideSummary.swift` | Post-ride stats struct |
| `RideActivityAttributes` | `Shared/` | Live Activity content state |
| `RideSessionStore` | `iPhone/Stores/` | God object — location engine, POI tracking, Watch sync (~30 KB, split planned Sprint 4) |
| `RideSessionStore+Spurs` | `iPhone/Stores/` | POI spur off-route logic (extension) |
| `RideView` | `iPhone/Views/` | God view — map, HUD, birdseye (~37 KB, split planned Sprint 3) |
| `POISearchService` | `iPhone/Services/` | Typed `MKPointOfInterestFilter` category searches |
| `CyclingRouteService` | `iPhone/Services/` | `.cycling` route requests (iOS 26 API) |
| `PlaceDescriptorService` | `iPhone/Services/` | Reverse geocoding for waypoint display names |
| `ReverseGeocodingService` | `iPhone/Services/` | Coordinate → place name |
| `MKMapItem+POI.swift` | `iPhone/Services/` | MapKit POI extension (iPhone only — not in Watch target) |
| `RouteStore` | `iPhone/Stores/` | GPX/GeoJSON import, route persistence |
| `RideHistoryStore` | `iPhone/Stores/` | Persisted past rides |
| `PlanState` + `PlanRouteEngine` | `iPhone/` | Manual route planning (waypoint drop + geometry) |
| `WatchRideStore` | `Watch/` | Watch-side ride state, receives updates via WatchConnectivity |
| `LocalizationManager` | `Shared/Managers/` | Language override (fragile `AppleLanguages` key — tracked as P3 debt) |
| `GPXParser` / `GeoJSONParser` | `Shared/Parsers/` | Route file parsing (shared between iPhone + Watch) |
| `GPXExporter` | `Shared/` | Export ride track as GPX |

---

## Coding Conventions

- **iOS 26 minimum — use new APIs freely.** No `#available(iOS 25, *)` guards.
- **Exception:** Gate `MKMapItem.identifier` with `#available(iOS 18, *)` — additive enhancement on top of coordinate `deterministicID` fallback.
- **Swift 6 strict concurrency** — `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. New code must be actor-safe. Legacy violations tracked in `TECH_DEBT.md § AC-1/2/3`.
- **No force-unwraps** in new code. Existing ones tracked in TECH_DEBT.
- **`POIModel` is `Codable`** — adding optional fields is backwards-compatible (`nil` on decode if key missing). No migration needed for additive changes.
- **Watch target exclusions** — see File Inventory above.
- **Commit message format:** `type(scope): description` — e.g. `feat(poi): add mapItemIdentifier + mapsURL to POIModel`

---

## Session Startup Checklist

At the start of every coding session:

1. Read `PROJECT.md` (this file) — confirm version, bundle IDs, deployment targets
2. Read `ROADMAP.md` — find the next unchecked item in the current sprint
3. Read `DEVLOG.md` — check current build status and any open bugs before touching code
4. Pull latest `main`
5. Build in Xcode — confirm clean before starting
