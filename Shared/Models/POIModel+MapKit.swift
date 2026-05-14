//
//  POIModel+MapKit.swift
//  VeloGPX (iPhone only — uses MapKit APIs not available on watchOS)
//
//  Factory that builds a POIModel from an MKMapItem, capturing the stable
//  place identifier and a Maps deep-link URL at the moment of search so both
//  survive serialisation to disk.
//

#if canImport(UIKit)  // iOS / iPadOS only
import MapKit
import CoreLocation

public extension MKMapItem {
    /// Builds a `POIModel` from this map item.
    /// - Parameters:
    ///   - category:           The `POICategory` to assign.
    ///   - distanceFromRoute:  Pre-computed distance from the GPX route (metres). Defaults to 0.
    func toPOIModel(
        category: POICategory,
        distanceFromRoute: Double = 0
    ) -> POIModel {
        // Stable identifier — available on iOS 18+.
        // We target iOS 26 so this branch is always taken.
        let identifier: String?
        if #available(iOS 18, *) {
            identifier = self.identifier?.rawValue
        } else {
            identifier = nil
        }

        // Build a maps:// deep-link from the item's coordinate.
        // MKMapItem has no openInMapsActionURL() method — construct the URL manually.
        let coord = poiCoordinate
        let encodedName = (name ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let mapsURL = URL(string: "maps://?ll=\(coord.latitude),\(coord.longitude)&q=\(encodedName)")

        return POIModel(
            id: deterministicPOIID,
            name: name ?? "POI",
            category: category,
            coordinate: coord,
            distanceFromRoute: distanceFromRoute,
            address: shortAddress,
            phone: phoneNumber,
            website: url?.absoluteString,
            mapItemIdentifier: identifier,
            mapsURL: mapsURL
        )
    }
}
#endif
