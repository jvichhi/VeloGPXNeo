//
//  POIModel+MapKit.swift
//  VeloGPX (iPhone only — uses MapKit APIs not available on watchOS)
//
//  Factory that builds a POIModel from an MKMapItem, capturing the stable
//  place identifier and Maps deep-link URL at the moment of search so both
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
        // We target iOS 26 so this branch is always taken, but the guard
        // keeps the compiler happy without a deployment target annotation.
        let identifier: String?
        if #available(iOS 18, *) {
            identifier = self.identifier?.rawValue
        } else {
            identifier = nil
        }

        // Apple Maps deep-link — openInMapsActionURL() is iOS 17+, always
        // present on our iOS 26 minimum target.
        let mapsURL = self.openInMapsActionURL()

        return POIModel(
            id: deterministicPOIID,
            name: name ?? "POI",
            category: category,
            coordinate: poiCoordinate,
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
