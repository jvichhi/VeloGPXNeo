import Foundation
import CoreLocation

public struct POIModel: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let category: POICategory
    public let coordinate: Coordinate
    public let distanceFromRoute: Double
    public var address: String?
    public var phone: String?
    public var website: String?

    public init(
        id: UUID = UUID(),
        name: String,
        category: POICategory,
        coordinate: CLLocationCoordinate2D,
        distanceFromRoute: Double = 0,
        address: String? = nil,
        phone: String? = nil,
        website: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.coordinate = coordinate.asCoordinate
        self.distanceFromRoute = distanceFromRoute
        self.address = address
        self.phone = phone
        self.website = website
    }
}

public enum POICategory: String, Codable, CaseIterable, Sendable {
    case cafe
    case restaurant
    case water
    case bikeRepair = "bike_repair"
    case bikeRental = "bike_rental"
    case accommodation
    case viewpoint
    case campsite
    case pharmacy
    case custom

    public var displayName: String {
        switch self {
        case .cafe: return "Café"
        case .restaurant: return "Restaurant"
        case .water: return "Water"
        case .bikeRepair: return "Bike Repair"
        case .bikeRental: return "Bike Rental"
        case .accommodation: return "Accommodation"
        case .viewpoint: return "Viewpoint"
        case .campsite: return "Campsite"
        case .pharmacy: return "Pharmacy"
        case .custom: return "Waypoint"
        }
    }

    public var systemImage: String {
        switch self {
        case .cafe: return "cup.and.saucer.fill"
        case .restaurant: return "fork.knife"
        case .water: return "drop.fill"
        case .bikeRepair: return "wrench.and.screwdriver.fill"
        case .bikeRental: return "bicycle"
        case .accommodation: return "bed.double.fill"
        case .viewpoint: return "binoculars.fill"
        case .campsite: return "tent.fill"
        case .pharmacy: return "cross.fill"
        case .custom: return "mappin.circle.fill"
        }
    }
}
