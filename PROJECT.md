# VeloGPXNeo — Project Context
> Read this first at the start of every session. Keep it current.

---

## App Identity

| Field | Value |
|---|---|
| **App name** | VeloGPX |
| **Repo** | `jvichhi/VeloGPXNeo` (public) |
| **Platform** | iOS + Apple Watch (paired) |
| **Category** | Cycling GPS / Route Navigation |
| **Tagline** | Native iOS + Apple Watch cycling GPS companion. Import GPX/GeoJSON routes, get POI alerts along your route, never get lost on the bike. |

---

## Versions

| Version | Status | Notes |
|---|---|---|
| **1.1** | ✅ Shipped — App Store | Last public release |
| **1.2** | 🔨 In development | Current build — iOS 26+, build 3 |
| **1.3** | 📋 Planned | Sprint 1 + 2 work (debt clearance + AI features) |

---

## Tech Stack

| Layer | Technology |
|---|---|
| **Language** | Swift 6 (strict concurrency target) |
| **UI** | SwiftUI |
| **Maps** | MapKit (iOS 26 APIs — `MKMapItem.init(location:)`, `MKReverseGeocodingRequest`, typed `MKPointOfInterestFilter`) |
| **Location** | CoreLocation |
| **AI** | FoundationModels (iOS 26+, Apple Intelligence — Sprint 2+) |
| **Watch sync** | WatchConnectivity |
| **Backend** | Supabase |
| **Min deployment** | iOS 26 — no legacy API gating below this |
| **Exception** | `MKMapItem.identifier` gates at iOS 18+ (nice-to-have enhancement, coordinate fallback always present) |

---

## Repo Structure

```
VeloGPXNeo/
├── PROJECT.md                  ← you are here — read first every session
├── ROADMAP.md                  ← sprint order and current work queue
├── DEVLOG.md                   ← active session tracker (current state, next task, open bugs)
├── FEATURES.md                 ← future feature specs with full Swift implementation plans
├── TECH_DEBT.md                ← debt catalogue (P0 → P3, with file + line refs)
├── iPhone/
│   ├── Views/                  ← SwiftUI views (iOS target only)
│   └── Services/               ← business logic, search, routing, AI services
├── Shared/
│   ├── Models/                 ← POIModel, RouteModel, RideSummary, etc.
│   └── Extensions/             ← shared Swift extensions
├── Watch/                      ← watchOS views
├── VeloGPXWatch Watch App/     ← Watch app target
├── VeloGPXLiveActivity/        ← Live Activity extension
├── Samples/                    ← sample GPX/GeoJSON files for testing
└── Docs/                       ← architecture docs
```

---

## Targets

| Target | Notes |
|---|---|
| **VeloGPX** (iOS) | Main app target — all iPhone views + services |
| **VeloGPXWatch Watch App** | Paired Watch target — subset of Shared models only, no FoundationModels, no MKMapItem.identifier |
| **VeloGPXLiveActivity** | Live Activity extension for in-progress ride metrics |

**Watch target rule:** Never add iOS-only files (`POIModel+MapKit.swift`, any `FoundationModels` import, `PlanAssistantEngine`, `RidePlanAssistantView`) to the Watch target in Build Phases.

---

## Key Models & Services (quick reference)

| Name | Location | Role |
|---|---|
| `POIModel` | `Shared/Models/POIModel.swift` | Point of interest — coordinate, category, name, optional Place ID |
| `RouteModel` | `Shared/Models/RouteModel.swift` | GPX/GeoJSON parsed route with track points and elevation |
| `RideSummary` | `Shared/Models/` | Post-ride stats struct |
| `RideSessionStore` | `iPhone/` | God object — location engine, POI tracking, Watch sync (~30 KB, split planned Sprint 4) |
| `RideView` | `iPhone/Views/` | God view — map, HUD, birdseye (~37 KB, split planned Sprint 3) |
| `POISearchService` | `iPhone/Services/` | Typed `MKPointOfInterestFilter` category searches |
| `CyclingRouteService` | `iPhone/Services/` | `.cycling` route requests (WWDC25 API) |
| `PlaceDescriptorService` | `iPhone/Services/` | Reverse geocoding for waypoint display names |
| `RouteStore` | `iPhone/` | GPX import, route persistence |
| `RideHistoryStore` | `iPhone/` | Persisted past rides |
| `PlanState` + `PlanRouteEngine` | `iPhone/` | Manual route planning (waypoint drop + geometry) |
| `WatchRideStore` | `Watch/` | Watch-side ride state, receives updates via WatchConnectivity |
| `LocalizationManager` | `Shared/` | Language override (fragile `AppleLanguages` key — tracked as P3 debt) |

---

## Coding Conventions

- **iOS 26 minimum — use new APIs freely.** No `#available(iOS 25, *)` guards.
- **Exception:** Gate `MKMapItem.identifier` with `#available(iOS 18, *)` — it's an additive enhancement on top of the always-present coordinate `deterministicID` fallback.
- **Swift 6 strict concurrency** is the target. New code must be actor-safe. Legacy violations are tracked in `TECH_DEBT.md § AC-1/2/3`.
- **No force-unwraps** in new code. Existing ones tracked in TECH_DEBT.
- **`POIModel` is `Codable`** — adding optional fields is backwards-compatible (missing keys decode as `nil`). No JSON migration needed for additive changes.
- **Watch target exclusions** — see Targets section above.
- **Commit message format:** `type(scope): description` — e.g. `feat(poi): add mapItemIdentifier + mapsURL to POIModel`

---

## Session Startup Checklist

At the start of every coding session:

1. Read `PROJECT.md` (this file) — confirm version and stack
2. Read `ROADMAP.md` — find the next unchecked item in the current sprint
3. Read `DEVLOG.md` — check current build status and any open bugs before touching code
4. Pull latest `main`
5. Build in Xcode — confirm clean before starting
