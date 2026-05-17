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
    /// Stable place identifier captured from MKMapItem at search time.
    /// Nil for POIs persisted before this field was introduced — safe via explicit CodingKeys below.
    public var mapItemIdentifier: String?
    /// Deep-link URL that opens this place in Apple Maps.
    /// Nil for legacy POIs.
    public var mapsURL: URL?

    public init(
        id: UUID = UUID(),
        name: String,
        category: POICategory,
        coordinate: CLLocationCoordinate2D,
        distanceFromRoute: Double = 0,
        address: String? = nil,
        phone: String? = nil,
        website: String? = nil,
        mapItemIdentifier: String? = nil,
        mapsURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.coordinate = coordinate.asCoordinate
        self.distanceFromRoute = distanceFromRoute
        self.address = address
        self.phone = phone
        self.website = website
        self.mapItemIdentifier = mapItemIdentifier
        self.mapsURL = mapsURL
    }

    // MARK: - Codable
    // Explicit keys so existing JSON that lacks the new fields decodes without crashing.

    enum CodingKeys: String, CodingKey {
        case id, name, category, coordinate, distanceFromRoute
        case address, phone, website
        case mapItemIdentifier, mapsURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try c.decode(UUID.self,        forKey: .id)
        name              = try c.decode(String.self,      forKey: .name)
        category          = try c.decode(POICategory.self, forKey: .category)
        coordinate        = try c.decode(Coordinate.self,  forKey: .coordinate)
        distanceFromRoute = try c.decode(Double.self,      forKey: .distanceFromRoute)
        address           = try c.decodeIfPresent(String.self, forKey: .address)
        phone             = try c.decodeIfPresent(String.self, forKey: .phone)
        website           = try c.decodeIfPresent(String.self, forKey: .website)
        mapItemIdentifier = try c.decodeIfPresent(String.self, forKey: .mapItemIdentifier)
        mapsURL           = try c.decodeIfPresent(URL.self,    forKey: .mapsURL)
    }
}

public enum POICategory: String, Codable, Sendable {
    case cafe
    case restaurant
    case water
    case bikeRepair    = "bike_repair"
    case bikeRental    = "bike_rental"
    case accommodation
    case viewpoint
    case campsite
    case pharmacy
    case custom
    // Added to match POIRankingEngine usage
    case restroom      = "restroom"
    case bikeshop      = "bike_shop"
    case scenic        = "scenic"

    public var displayName: String {
        switch self {
        case .cafe:          return "Café"
        case .restaurant:    return "Restaurant"
        case .water:         return "Water"
        case .bikeRepair:    return "Bike Repair"
        case .bikeRental:    return "Bike Rental"
        case .accommodation: return "Accommodation"
        case .viewpoint:     return "Viewpoint"
        case .campsite:      return "Campsite"
        case .pharmacy:      return "Pharmacy"
        case .custom:        return "Waypoint"
        case .restroom:      return "Restroom"
        case .bikeshop:      return "Bike Shop"
        case .scenic:        return "Scenic"
        }
    }

    public var systemImage: String {
        switch self {
        case .cafe:          return "cup.and.saucer.fill"
        case .restaurant:    return "fork.knife"
        case .water:         return "drop.fill"
        case .bikeRepair:    return "wrench.and.screwdriver.fill"
        case .bikeRental:    return "bicycle"
        case .accommodation: return "bed.double.fill"
        case .viewpoint:     return "binoculars.fill"
        case .campsite:      return "tent.fill"
        case .pharmacy:      return "cross.fill"
        case .custom:        return "mappin.circle.fill"
        case .restroom:      return "figure.walk"
        case .bikeshop:      return "storefront.fill"
        case .scenic:        return "photo.on.rectangle"
        }
    }
}
