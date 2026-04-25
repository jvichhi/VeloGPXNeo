import Foundation

/// Info.plist snippets and notes for direct GPX/GeoJSON opening in VeloGPX.
/// Add these keys to the iPhone app target Info.plist if Xcode does not generate them from the target editor.
///
/// CFBundleDocumentTypes:
/// - GPX Route
///   - LSItemContentTypes: public.xml, com.topografix.gpx
///   - CFBundleTypeExtensions: gpx
///   - CFBundleTypeRole: Viewer
/// - GeoJSON Route
///   - LSItemContentTypes: public.json
///   - CFBundleTypeExtensions: geojson, json
///   - CFBundleTypeRole: Viewer
///
/// In SwiftUI App lifecycle, use `.onOpenURL { url in ... }` to import the file.
///
/// Desired UX:
/// 1. User downloads GPX from Le Québec à vélo.
/// 2. User taps Share / Open in… / Files.
/// 3. VeloGPX appears as an available app for `.gpx` and `.geojson`.
/// 4. Opening the file launches VeloGPX and imports it into RouteStore automatically.

enum DocumentTypeNotes {}
