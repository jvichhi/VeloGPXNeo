# VeloGPXNeo — Project Rules

Rules for AI-assisted development on this repo. Both the human developer and the AI architect must follow these. When in conflict, these rules win.

---

## Deployment Target

- **iOS 26 minimum. No lower version support.** Use iOS 26 APIs freely.
- Only gate with `#available` when the feature is a nice-to-have enhancement on top of a working fallback (e.g. `MKMapItem.identifier` is iOS 18+, but the coordinate-based `deterministicPOIID` fallback still works below that).
- Do not add `@available(iOS 26, *)` or `#if available` scaffolding "just in case" — it creates dead code and noise.
- The Watch target targets watchOS 11+. Apply the same philosophy.

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
- `MKMapItem` has no `openInMapsActionURL()` — use `maps://` URL scheme instead: `URL(string: "maps://?ll=\(lat),\(lon)&q=\(encodedName)")`
- `MKMapItem` has no `.placemark.coordinate` shortcut on iOS 18+ — use `.location?.coordinate`
- `CLGeocoder` is deprecated on iOS 18+ — use `MKReverseGeocodingRequest`

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

Some documentation files in this repo are large and will cause AI coding tools to time out mid-write, potentially corrupting the file:

| File | Size | Risk |
|---|---|---|
| `FEATURES.md` | ~39 KB | ⚠️ High — do not full-rewrite |
| `TECH_DEBT.md` | ~16 KB | ⚠️ Medium |
| `ROADMAP.md` | ~10 KB | ⚠️ Medium |
| `DEVLOG.md` | ~9 KB | Low |

### Safe Update Pattern
Always make **targeted, section-specific edits** to large `.md` files:
- Tell the AI exactly which section to update (e.g. *"mark F-A1 as complete in FEATURES.md"*)
- Never ask an AI tool to "update the FEATURES.md file with the latest backlog and status notes" as a single instruction — this triggers a full file read + rewrite that times out after several minutes
- If a full rewrite is truly needed, split it into multiple focused passes (one section at a time)

### Recovery
If an AI tool errors mid-write on a `.md` file:
```bash
git status           # check if file was partially written
git diff <file>.md   # inspect the damage
git checkout HEAD -- <file>.md   # restore from last clean commit
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
