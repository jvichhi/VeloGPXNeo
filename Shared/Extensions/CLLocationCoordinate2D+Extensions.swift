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
}
