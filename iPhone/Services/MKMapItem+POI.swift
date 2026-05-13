//
//  MKMapItem+POI.swift
//  VeloGPX
//
//  Shared helpers for converting MKMapItem → POI primitives.
//  Previously duplicated verbatim in NearbySearchSheet and POIDiscoverySheet.
//

import MapKit
import CoreLocation

extension MKMapItem {

    // MARK: - Coordinate (iOS 26 compat)

    /// Returns the item's coordinate in a backward-compatible way.
    /// iOS 26 made `CLLocation` non-optional on `MKMapItem`; older OS uses the placemark.
    var poiCoordinate: CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
            return location.coordinate
        } else {
            return placemark.coordinate
        }
    }

    // MARK: - Address

    /// Short single-line address, backward-compatible.
    var shortAddress: String? {
        if #available(iOS 26.0, *) {
            return address?.shortAddress
        } else {
            return placemark.thoroughfare
        }
    }

    // MARK: - Deterministic UUID

    /// Produces a stable UUID derived from the item's coordinate (6 decimal places).
    /// Two searches returning the same physical place always yield the same ID,
    /// eliminating name-collision bugs when checking `isAdded` across sheets.
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
