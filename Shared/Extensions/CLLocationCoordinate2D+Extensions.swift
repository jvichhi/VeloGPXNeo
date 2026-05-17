import Foundation
import CoreLocation

public extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> Double {
        let a = CLLocation(latitude: latitude, longitude: longitude)
        let b = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return a.distance(from: b)
    }

    func perpendicularDistance(toSegment start: CLLocationCoordinate2D, end: CLLocationCoordinate2D) -> Double {
        let ax = start.longitude
        let ay = start.latitude
        let bx = end.longitude
        let by = end.latitude
        let px = longitude
        let py = latitude

        let abx = bx - ax
        let aby = by - ay
        let apx = px - ax
        let apy = py - ay
        let ab2 = abx * abx + aby * aby

        guard ab2 > 0 else { return distance(to: start) }

        let t = max(0, min(1, (apx * abx + apy * aby) / ab2))
        let closest = CLLocationCoordinate2D(latitude: ay + aby * t, longitude: ax + abx * t)
        return distance(to: closest)
    }

    /// Bearing from this coordinate to another, in degrees (0 = north, 90 = east).
    func bearing(to destination: CLLocationCoordinate2D) -> Double {
        let lat1 = latitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let dLon = (destination.longitude - longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return ((atan2(y, x) * 180 / .pi) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Midpoint between this coordinate and another.
    func midpoint(to other: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let lon2 = other.longitude * .pi / 180

        let bx = cos(lat2) * cos(lon2 - lon1)
        let by = cos(lat2) * sin(lon2 - lon1)
        let lat3 = atan2(sin(lat1) + sin(lat2), sqrt((cos(lat1) + bx) * (cos(lat1) + bx) + by * by))
        let lon3 = lon1 + atan2(by, cos(lat1) + bx)

        return CLLocationCoordinate2D(latitude: lat3 * 180 / .pi, longitude: lon3 * 180 / .pi)
    }

    /// Destination coordinate at a given bearing and distance (metres) from this one.
    func destination(bearing: Double, distance: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let angularDistance = distance / earthRadius
        let bearingRad = bearing * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180

        let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearingRad))
        let lon2 = lon1 + atan2(sin(bearingRad) * sin(angularDistance) * cos(lat1), cos(angularDistance) - sin(lat1) * sin(lat2))

        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}
