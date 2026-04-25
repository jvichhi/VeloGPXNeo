# Info.plist — Document Type & UTI Registration

Add the following to `Info.plist` inside your iPhone target (or via Xcode → Target → Info → Document Types).

## CFBundleDocumentTypes

```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>GPX Route</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>com.topografix.gpx</string>
        </array>
    </dict>
    <dict>
        <key>CFBundleTypeName</key>
        <string>GeoJSON Route</string>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
        <key>LSHandlerRank</key>
        <string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>public.geojson</string>
            <string>public.json</string>
        </array>
    </dict>
</array>
```

## UTImportedTypeDeclarations (GPX only — GeoJSON & JSON are system UTIs)

```xml
<key>UTImportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>com.topografix.gpx</string>
        <key>UTTypeDescription</key>
        <string>GPS Exchange Format</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.xml</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>gpx</string>
            </array>
            <key>public.mime-type</key>
            <array>
                <string>application/gpx+xml</string>
            </array>
        </dict>
    </dict>
</array>
```

## Notes

- `LSHandlerRank` of `Alternate` means VeloGPX appears in the share sheet but doesn't claim to be the default opener.
- The `onOpenURL` handler in `VeloGPXApp.swift` already routes the file into `RouteStore.importRoute(from:)` — no additional code needed once the Info.plist is set.
- `fileImporter` in `RouteLibraryView.swift` uses `UTType(filenameExtension: "gpx")` as a fallback for when the system UTI isn't registered yet during development.
