# VeloGPX 🚴

A native iPhone + Apple Watch cycling GPS companion app built for GPX and GeoJSON routes.

## V2 direction

This repository now targets a cleaner V2 architecture with:
- modern SwiftUI + newer MapKit APIs
- GPX / GeoJSON import into an in-app route library
- document-based opening so GPX files can open directly in VeloGPX from Files, Safari, Mail, or shared download flows
- Apple Watch companion views for ride metrics and alerts
- route-following, off-route detection, and POI display along the corridor

## Planned app capabilities

- Import GPX and GeoJSON from Files
- Open `.gpx`, `.geojson`, and `.json` directly in the app via document types
- Save imported files into a local route collection
- Show route line, rider position, POIs, and off-route warnings
- Sync simplified ride state to Apple Watch

## Architecture

- `Shared/` — route, POI, ride state, parsers
- `iPhone/` — route library, import flow, MapKit ride UI
- `Watch/` — glanceable ride metrics and haptics
- `Docs/` — implementation notes

## Next steps

1. Open in Xcode
2. Set signing/team
3. Enable Background Location and HealthKit
4. Add document types / URL handling capabilities
5. Test opening a GPX file directly into VeloGPX
