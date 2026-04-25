import Foundation
import CoreLocation

public enum GeoJSONError: Error {
    case invalidJSON
    case missingRoute
}

public struct GeoJSONParseResult: Sendable {
    public var route: RouteModel?
    public var pois: [POIModel]

    public init(route: RouteModel? = nil, pois: [POIModel] = []) {
        self.route = route
        self.pois = pois
    }
}

public enum GeoJSONParser {
    public static func parse(data: Data, filename: String? = nil) throws -> GeoJSONParseResult {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeoJSONError.invalidJSON
        }

        let type = object["type"] as? String
        if type == "FeatureCollection" {
            return try parseFeatureCollection(object, filename: filename)
        }
        if type == "Feature" {
            return try parseFeature(object, filename: filename)
        }
        throw GeoJSONError.invalidJSON
    }

    private static func parseFeatureCollection(_ object: [String: Any], filename: String?) throws -> GeoJSONParseResult {
        let features = object["features"] as? [[String: Any]] ?? []
        var route: RouteModel?
        var pois: [POIModel] = []

        for feature in features {
            guard let geometry = feature["geometry"] as? [String: Any],
                  let geometryType = geometry["type"] as? String else { continue }
            let properties = feature["properties"] as? [String: Any] ?? [:]

            if geometryType == "LineString" {
                let coordinates = geometry["coordinates"] as? [[Double]] ?? []
                let trackPoints = coordinates.compactMap { coord -> TrackPoint? in
                    guard coord.count >= 2 else { return nil }
                    return TrackPoint(coordinate: .init(latitude: coord[1], longitude: coord[0]), elevation: coord.count > 2 ? coord[2] : nil)
                }
                if !trackPoints.isEmpty {
                    route = RouteModel(
                        name: properties["name"] as? String ?? filename ?? "Imported GeoJSON",
                        sourceFormat: .geojson,
                        trackPoints: trackPoints,
                        originalFilename: filename
                    )
                }
            } else if geometryType == "Point" {
                let coordinates = geometry["coordinates"] as? [Double] ?? []
                if coordinates.count >= 2 {
                    let categoryRaw = (properties["category"] as? String) ?? (properties["amenity"] as? String) ?? "custom"
                    let category = POICategory(rawValue: categoryRaw) ?? .custom
                    let poi = POIModel(
                        name: properties["name"] as? String ?? "POI",
                        category: category,
                        coordinate: .init(latitude: coordinates[1], longitude: coordinates[0]),
                        address: properties["address"] as? String,
                        phone: properties["phone"] as? String,
                        website: properties["website"] as? String
                    )
                    pois.append(poi)
                }
            }
        }
        return GeoJSONParseResult(route: route, pois: pois)
    }

    private static func parseFeature(_ object: [String: Any], filename: String?) throws -> GeoJSONParseResult {
        try parseFeatureCollection(["type": "FeatureCollection", "features": [object]], filename: filename)
    }
}
