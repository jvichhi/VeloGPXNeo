import Foundation
import CoreLocation

/// Builds a GPX 1.1 string from a RideSummary.
///
/// Export options:
///  - `includeActualTrack`  — the recorded GPS breadcrumb (always recommended)
///  - `includePlannedRoute` — the original imported GPX route as a <rte>
///  - `includePOIs`         — all POIs as <wpt> elements with name + category symbol
public struct GPXExporter {

    public struct Options {
        public var includeActualTrack: Bool
        public var includePlannedRoute: Bool
        public var includePOIs: Bool

        public init(
            includeActualTrack: Bool = true,
            includePlannedRoute: Bool = false,
            includePOIs: Bool = true
        ) {
            self.includeActualTrack = includeActualTrack
            self.includePlannedRoute = includePlannedRoute
            self.includePOIs = includePOIs
        }
    }

    public static func export(_ summary: RideSummary, options: Options = Options()) -> String {
        let iso = ISO8601DateFormatter()
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1"
             creator="VeloGPX"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.topografix.com/GPX/1/1
               http://www.topografix.com/GPX/1/1/gpx.xsd">
          <metadata>
            <name>\(escape(summary.routeName))</name>
            <time>\(iso.string(from: summary.startDate))</time>
            <desc>Actual ride — \(String(format: "%.1f", summary.distanceKm)) km, \(formatDuration(summary.elapsedTime))</desc>
          </metadata>
        
        """

        // ── Waypoints (POIs) ─────────────────────────────────────────────
        if options.includePOIs {
            for poi in summary.pois {
                // FIX (locale): use String(format:"%f") to force C-locale decimal point.
                // Raw Double interpolation produces "46,5" on French/German devices,
                // which is invalid GPX XML and rejected by every downstream tool.
                let lat = String(format: "%f", poi.coordinate.latitude)
                let lon = String(format: "%f", poi.coordinate.longitude)
                gpx += "  <wpt lat=\"\(lat)\" lon=\"\(lon)\">\n"
                gpx += "    <name>\(escape(poi.name))</name>\n"
                gpx += "    <desc>\(escape(poi.category.displayName))</desc>\n"
                gpx += "    <sym>\(gpxSymbol(for: poi.category))</sym>\n"
                gpx += "  </wpt>\n"
            }
        }

        // ── Planned route (original GPX) ─────────────────────────────────
        if options.includePlannedRoute && !summary.plannedTrack.isEmpty {
            gpx += "  <rte>\n"
            gpx += "    <name>\(escape(summary.routeName)) — Planned</name>\n"
            for coord in summary.plannedTrack {
                let lat = String(format: "%f", coord.latitude)
                let lon = String(format: "%f", coord.longitude)
                gpx += "    <rtept lat=\"\(lat)\" lon=\"\(lon)\" />\n"
            }
            gpx += "  </rte>\n"
        }

        // ── Actual track ─────────────────────────────────────────────────
        if options.includeActualTrack && !summary.actualTrack.isEmpty {
            gpx += "  <trk>\n"
            gpx += "    <name>\(escape(summary.routeName)) — Actual Ride</name>\n"
            gpx += "    <desc>\(iso.string(from: summary.startDate)) → \(iso.string(from: summary.endDate))</desc>\n"
            gpx += "    <trkseg>\n"
            for coord in summary.actualTrack {
                let lat = String(format: "%f", coord.latitude)
                let lon = String(format: "%f", coord.longitude)
                gpx += "      <trkpt lat=\"\(lat)\" lon=\"\(lon)\" />\n"
            }
            gpx += "    </trkseg>\n"
            gpx += "  </trk>\n"
        }

        gpx += "</gpx>\n"
        return gpx
    }

    // MARK: - Helpers

    private static func escape(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&",  with: "&amp;")
            .replacingOccurrences(of: "<",  with: "&lt;")
            .replacingOccurrences(of: ">",  with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        return h > 0
            ? String(format: "%dh %02dm %02ds", h, m, s)
            : String(format: "%dm %02ds", m, s)
    }

    /// Maps POICategory to a standard GPX symbol name recognised by
    /// Garmin BaseCamp, Komoot, and other major tools.
    private static func gpxSymbol(for category: POICategory) -> String {
        switch category {
        case .cafe:          return "Restaurant"
        case .restaurant:    return "Restaurant"
        case .water:         return "Drinking Water"
        case .bikeRepair:    return "Car Repair"
        case .bikeRental:    return "Parking Area"
        case .accommodation: return "Lodge"
        case .viewpoint:     return "Scenic Area"
        case .campsite:      return "Campground"
        case .pharmacy:      return "Medical Facility"
        case .custom:        return "Waypoint"
        }
    }
}
