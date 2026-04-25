import Foundation
import CoreLocation

public enum GPXError: Error {
    case parseFailure
    case noTrackPoints
}

public final class GPXParser: NSObject, XMLParserDelegate {
    private var routeName = "Imported GPX"
    private var trackPoints: [TrackPoint] = []
    private var waypoints: [WaypointPoint] = []
    private var currentElement = ""
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: Double?
    private var currentTime: Date?
    private var currentWaypointName: String?
    private var currentWaypointSymbol: String?
    private var inTrackPoint = false
    private var inWaypoint = false
    private let isoFormatter = ISO8601DateFormatter()

    public static func parse(data: Data, filename: String? = nil) throws -> RouteModel {
        let delegate = GPXParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw GPXError.parseFailure }
        guard !delegate.trackPoints.isEmpty else { throw GPXError.noTrackPoints }
        return RouteModel(
            name: delegate.routeName,
            sourceFormat: .gpx,
            trackPoints: delegate.trackPoints,
            waypoints: delegate.waypoints,
            originalFilename: filename
        )
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "trkpt" {
            inTrackPoint = true
            currentLat = Double(attributeDict["lat"] ?? "")
            currentLon = Double(attributeDict["lon"] ?? "")
            currentEle = nil
            currentTime = nil
        } else if elementName == "wpt" {
            inWaypoint = true
            currentLat = Double(attributeDict["lat"] ?? "")
            currentLon = Double(attributeDict["lon"] ?? "")
            currentWaypointName = nil
            currentWaypointSymbol = nil
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch currentElement {
        case "name" where !inTrackPoint && !inWaypoint:
            routeName = trimmed
        case "name" where inWaypoint:
            currentWaypointName = trimmed
        case "sym" where inWaypoint:
            currentWaypointSymbol = trimmed
        case "ele":
            currentEle = Double(trimmed)
        case "time":
            currentTime = isoFormatter.date(from: trimmed)
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        defer { currentElement = "" }
        if elementName == "trkpt", inTrackPoint {
            if let lat = currentLat, let lon = currentLon {
                trackPoints.append(.init(coordinate: .init(latitude: lat, longitude: lon), elevation: currentEle, timestamp: currentTime))
            }
            inTrackPoint = false
        } else if elementName == "wpt", inWaypoint {
            if let lat = currentLat, let lon = currentLon {
                waypoints.append(.init(coordinate: .init(latitude: lat, longitude: lon), name: currentWaypointName, symbol: currentWaypointSymbol))
            }
            inWaypoint = false
        }
    }
}
