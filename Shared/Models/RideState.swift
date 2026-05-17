import Foundation
import CoreLocation
import MapKit
import SwiftUI

// MARK: - Climb Category

public enum ClimbCategory: Int, Codable, Comparable, Sendable {
    case four = 4
    case three = 3
    case two = 2
    case one = 1
    case hc = 0

    public static func < (lhs: ClimbCategory, rhs: ClimbCategory) -> Bool {
        lhs.rawValue > rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .four:  return "Cat 4"
        case .three: return "Cat 3"
        case .two:   return "Cat 2"
        case .one:   return "Cat 1"
        case .hc:    return "HC"
        }
    }

    public var color: Color {
        switch self {
        case .four:  return .green
        case .three: return .blue
        case .two:   return .orange
        case .one:   return .red
        case .hc:    return .purple
        }
    }

}

public struct ClimbSegment: Codable, Equatable, Sendable {
    public let startIndex: Int
    public let endIndex: Int
    public let totalDistance: Double
    public let elevationGain: Double
    public let avgGrade: Double
    public let category: ClimbCategory

    public init(startIndex: Int, endIndex: Int, totalDistance: Double, elevationGain: Double, avgGrade: Double, category: ClimbCategory) {
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.totalDistance = totalDistance
        self.elevationGain = elevationGain
        self.avgGrade = avgGrade
        self.category = category
    }
}

// MARK: - Coordinate
public struct Coordinate: Codable, Hashable, Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

public extension CLLocationCoordinate2D {
    var asCoordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }
}

public struct RerouteStep: Codable, Hashable, Sendable, Equatable {
    public var instructions: String
    public var distanceMeters: Double
}

public struct RideState: Codable, Sendable {
    public var isActive: Bool
    public var isPaused: Bool
    public var pausedDuration: TimeInterval
    public var speed: Double
    public var maxSpeed: Double
    public var totalDistance: Double
    public var elapsedTime: TimeInterval
    public var currentCoordinate: Coordinate?
    public var currentHeading: Double
    public var nextPOI: POIModel?
    public var nextPOIDistance: Double?
    public var isOffRoute: Bool
    public var offRouteDistance: Double
    public var heartRate: Double?
    public var elevationGain: Double
    public var elevationLoss: Double
    public var bearingToRoute: Double?
    public var rerouteSteps: [RerouteStep]
    public var isRerouting: Bool
    public var activeClimb: ClimbSegment?
    public var activeClimbRemaining: Double?

    public init(
        isActive: Bool = false,
        isPaused: Bool = false,
        pausedDuration: TimeInterval = 0,
        speed: Double = 0,
        maxSpeed: Double = 0,
        totalDistance: Double = 0,
        elapsedTime: TimeInterval = 0,
        currentCoordinate: Coordinate? = nil,
        currentHeading: Double = 0,
        nextPOI: POIModel? = nil,
        nextPOIDistance: Double? = nil,
        isOffRoute: Bool = false,
        offRouteDistance: Double = 0,
        heartRate: Double? = nil,
        elevationGain: Double = 0,
        elevationLoss: Double = 0,
        bearingToRoute: Double? = nil,
        rerouteSteps: [RerouteStep] = [],
        isRerouting: Bool = false,
        activeClimb: ClimbSegment? = nil,
        activeClimbRemaining: Double? = nil
    ) {
        self.isActive = isActive
        self.isPaused = isPaused
        self.pausedDuration = pausedDuration
        self.speed = speed
        self.maxSpeed = maxSpeed
        self.totalDistance = totalDistance
        self.elapsedTime = elapsedTime
        self.currentCoordinate = currentCoordinate
        self.currentHeading = currentHeading
        self.nextPOI = nextPOI
        self.nextPOIDistance = nextPOIDistance
        self.isOffRoute = isOffRoute
        self.offRouteDistance = offRouteDistance
        self.heartRate = heartRate
        self.elevationGain = elevationGain
        self.elevationLoss = elevationLoss
        self.bearingToRoute = bearingToRoute
        self.rerouteSteps = rerouteSteps
        self.isRerouting = isRerouting
        self.activeClimb = activeClimb
        self.activeClimbRemaining = activeClimbRemaining
    }

    nonisolated public var speedKmh: Double { speed * 3.6 }
    nonisolated public var distanceKm: Double { totalDistance / 1000 }

    /// Moving time excludes all paused segments — use this for avg speed.
    nonisolated public var movingTime: TimeInterval { max(elapsedTime - pausedDuration, 0) }

    nonisolated public var avgSpeedKmh: Double {
        guard movingTime > 0 else { return 0 }
        return (totalDistance / movingTime) * 3.6
    }
}
