# VeloGPXNeo — Project Rules

Rules for AI-assisted development on this repo. Both the human developer and the AI architect must follow these. When in conflict, these rules win.

---

## Deployment Target

- **iOS 26 minimum. No lower version support.** Use iOS 26 APIs freely.
- Only gate with `#available` when the feature is a nice-to-have enhancement on top of a working fallback (e.g. `MKMapItem.identifier` is iOS 18+, but the coordinate-based `deterministicPOIID` fallback still works below that).
- Do not add `@available(iOS 26, *)` or `#if available` scaffolding "just in case" — it creates dead code and noise.
- The Watch target targets watchOS 11+. Apply the same philosophy.

---

## Verified Platform Capabilities

> This section exists so AI coding sessions don't re-learn or dispute known platform facts. These are verified.

### MapKit Cycling Directions (Developer Access)
- `MKDirectionsTransportType.cycling` is a real, supported value for `MKDirections.Request.transportType`.
  — `developer.apple.com/documentation/mapkit/mkdirectionstransporttype/cycling`
- Use `.cycling` for all bike-route requests. Apple Maps applies cycling-aware routing: bike lanes, quiet roads, hill avoidance. **Do not assume a third-party routing engine is required for pathfinding.**
- Apple Maps cycling coverage includes Canada (including Québec / Montréal / Laval area) and is broadly available in all major markets.
- Apple Maps does **not** expose a native "generate a N km loop" API. Loop planning is app-level logic on top of Apple's point-to-point cycling directions.

### FoundationModels API Surface (iOS 26)
- `session.respond(to: prompt)` → plain `String` output.
- `session.respond(to: prompt, generating: SomeType.self)` → typed `@Generable` structured output.
  — `developer.apple.com/documentation/foundationmodels/languagemodelsession/respond(to:generating:includeschemaInprompt:options:)`
- Do **not** use `session.stream(from:onPartial:)` — removed in iOS 26.
- Do **not** use `session.generate(from:)` for plain strings — that's for `@Generable` schema only.
- The model is for **intent parsing and natural language understanding only**. It does not produce route geometry, coordinates, or spatial data.

### FoundationModels Availability Gate
- `SystemLanguageModel.default.availability == .available` is the single gate.
- `VeloAI.isAvailable` wraps this — always use the wrapper, not the framework directly in views.
- `@AppStorage(VeloAI.enabledKey)` is the user toggle. Check both `VeloAI.isAvailable && aiEnabled` before showing AI UI.

### MKReverseGeocodingRequest (iOS 26)
- `CLGeocoder` is deprecated on iOS 18+. **Never use it.**
- Initialiser takes a `CLLocation`: `MKReverseGeocodingRequest(location: clLocation)`.
- Await `.mapItems` (returns `[MKMapItem]`) — **not** `.response`:

  ```swift
  let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
  guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
  let items = try await request.mapItems
  let item = items.first
  ```

- Read address fields via `item.placemark.locality`, `.administrativeArea`, etc. (see MKMapItem section below).

### MKPlacemark / MKMapItem — Deprecated Properties (iOS 26)
- **`MKPlacemark.title` is deprecated in iOS 26.** Do not use it for display strings.
- To build a human-readable subtitle from a placemark, compose from the still-valid individual fields:

  ```swift
  let parts = [placemark.locality, placemark.administrativeArea, placemark.country]
      .compactMap { $0 }.filter { !$0.isEmpty }
  let subtitle = parts.joined(separator: ", ")
  ```

- Other still-valid `MKPlacemark` fields: `name`, `locality`, `subLocality`, `administrativeArea`, `postalCode`, `country`, `isoCountryCode`.
- If you need a full formatted address, use `MKMapItem.placemark.formattedAddress` (available iOS 26+) in preference to manually assembling fields.

### MKMapItem — Address Fields Live on the Placemark
- `MKMapItem` itself has **no** address properties (`locality`, `administrativeArea`, `country`, etc.).
- All address fields are on `MKMapItem.placemark` (`MKPlacemark`, a subclass of `CLPlacemark`).
- **Always go via `.placemark`:**

  ```swift
  // WRONG — MKMapItem has no address properties
  let city = item.locality

  // CORRECT
  let city = item.placemark.locality
  let region = item.placemark.administrativeArea
  let country = item.placemark.country
  ```

### MKLocalSearch
- Correct API for resolving named stops (cafés, parks, boroughs, cities).
- Requires network connectivity. If offline, surface a friendly fallback.

---

## Swift File Authoring Rules

### No Unicode Escape Sequences
**Never use `\uXXXX` unicode escape sequences in Swift source files.** Swift source is UTF-8; write the literal character directly.

```swift
// WRONG — \u00e9 is a JSON/Java escape, not valid Swift
let label = "Caf\u00e9"
let ellipsis = "Searching\u2026"

// CORRECT — write the character as-is
let label = "Café"
let ellipsis = "Searching…"
```

This applies everywhere: string literals, comments, identifiers. The GitHub API transmits files as UTF-8 so the literal characters survive perfectly.

### No Invented API Calls
Before writing a call to any framework method not already used in the codebase, verify it exists in Apple's documentation or a trusted source. Common traps:
- `MKMapItem` has no `openInMapsActionURL()` — use `maps://` URL scheme: `URL(string: "maps://?ll=\(lat),\(lon)&q=\(encodedName)")`
- `MKMapItem` has no `.placemark.coordinate` shortcut on iOS 18+ — use `.location?.coordinate`
- `CLGeocoder` is deprecated on iOS 18+ — use `MKReverseGeocodingRequest`
- `MKPlacemark.title` is deprecated in iOS 26 — compose a subtitle from `.locality`, `.administrativeArea`, `.country` instead (see Verified Platform Capabilities above)
- `MKMapItem` has no address properties directly — always go via `item.placemark` (see MKMapItem — Address Fields Live on the Placemark above)

### No Force-Unwraps in New Code
Use `guard let` or `if let`. If a value is truly guaranteed, add a comment explaining why.

### No `UIScreen.main`
Use `@Environment(\.displayScale)` or `@Environment(\.horizontalSizeClass)` in SwiftUI. `UIScreen.main` is deprecated.

---

## API Verification Policy

When the AI generates a call to a method or property not already present in the codebase:
1. Check Apple Developer Documentation or search the web before writing the call.
2. If unsure, implement the equivalent manually (URL construction, custom extension, etc.) rather than calling a method that might not exist.
3. Note the verification source in a comment on the same line, e.g.: `// maps:// URL scheme — developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference`

---

## AI Tool File Size Warning

> ⚠️ **Do not ask an AI tool to read and rewrite large `.md` files in a single operation.**

`FEATURES.md` is now an index file — keep it under 5 KB. Full feature specs live in `Docs/Specs/`.

| File | Risk |
|---|---|
| `FEATURES.md` | ✅ Safe — index only, keep small |
| `TECH_DEBT.md` | ⚠️ Medium (~16 KB) |
| `ROADMAP.md` | ⚠️ Medium (~10 KB) |
| `DEVLOG.md` | Low (~9 KB) |
| `Docs/Specs/*.md` | ✅ Safe — scoped per feature |

### Safe Update Pattern
- Tell the AI exactly which section to update.
- Never ask an AI tool to "update FEATURES.md with the latest backlog" as a single instruction.
- If a full rewrite is truly needed, split into one section at a time.

### Recovery
If an AI tool errors mid-write on a `.md` file:
```bash
git status
git diff <file>.md
git checkout HEAD -- <file>.md
```

---

## File Organisation

```
Shared/          — models, extensions, services used by both iPhone and Watch targets
  Models/        — Codable data types (POIModel, RouteModel, etc.)
  Extensions/    — Swift/Foundation/CoreLocation extensions
  Services/      — pure logic services shared across targets
iPhone/          — iPhone target only
  Views/         — SwiftUI views
  Services/      — iPhone-only services (MapKit, FoundationModels, etc.)
Watch/           — Watch target only
  Views/
  Services/
Docs/
  Specs/         — one .md per feature spec; linked from FEATURES.md
```

### Watch Target Exclusion List
These files must **never** be added to the Watch target in Build Phases:
- `POIModel+MapKit.swift` — uses `MKMapItem` (iOS only)
- `PlanAssistantEngine.swift` — `FoundationModels` is iOS only
- `RidePlanIntent+Generable.swift` — same
- `RidePlanAssistantView.swift` — same
- Any file with `import FoundationModels`
- Any file with `#if canImport(UIKit)` guard wrapping the entire content

---

## Git Commit Conventions

Format: `type(scope): short description`

| Type | When |
|---|---|
| `feat` | New feature or user-visible behaviour |
| `fix` | Bug fix |
| `refactor` | Code change with no behaviour change |
| `chore` | ROADMAP, DEVLOG, project file updates |
| `perf` | Performance improvement |
| `docs` | .md files only |

Scope matches the ROADMAP item ID where applicable: `feat(MK-6)`, `fix(F-A1)`, `refactor(F-3)`.

---

## ROADMAP Discipline

- Work top-to-bottom in ROADMAP.md. Don't skip ahead unless the item is explicitly marked parallel-safe.
- When a commit lands that completes an item, check it off in ROADMAP.md in the same push.
- Update DEVLOG.md at the end of each session with: last commit SHA, what was done, what's next.
