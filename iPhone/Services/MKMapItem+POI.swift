//
//  MKMapItem+POI.swift
//  VeloGPX
//
//  Shared helpers for converting MKMapItem → POI primitives.
//  Deployment target is iOS 26 — all #available branches removed per PROJECT.md.
//  Uses iOS 26 APIs exclusively: item.location, item.address (MKAddress).
//  MKMapItem.placemark is deprecated iOS 26.
//

import MapKit
import CoreLocation

extension MKMapItem {

    // MARK: - Coordinate

    /// The item's coordinate via item.location (non-optional on iOS 26).
    var poiCoordinate: CLLocationCoordinate2D {
        location.coordinate
    }

    // MARK: - Address

    /// Short single-line address from MKAddress (iOS 26+).
    var shortAddress: String? {
        address?.formattedAddress
    }

    // MARK: - Deterministic UUID

    /// Stable UUID derived from coordinate (6 decimal places).
    /// Same physical place always yields the same ID across searches.
    var deterministicPOIID: UUID {
        let coord = poiCoordinate
        let lat = (coord.latitude  * 1_000_000).rounded() / 1_000_000
        let lon = (coord.longitude * 1_000_000).rounded() / 1_000_000
        let seed = "\(lat),\(lon)"

        var hash = seed.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { acc, byte in
            (acc ^ UInt64(byte)) &* 1_099_511_628_211
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(hash & 0xFF)
            hash >>= 8
        }

        var hash2 = seed.reversed().description.utf8
            .reduce(UInt64(14_695_981_039_346_656_037)) { acc, byte in
                (acc ^ UInt64(byte)) &* 1_099_511_628_211
            }
        for i in 8..<16 {
            bytes[i] = UInt8(hash2 & 0xFF)
            hash2 >>= 8
        }

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2],  bytes[3],
            bytes[4], bytes[5], bytes[6],  bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
