//
//  ReverseGeocodingService.swift
//  VeloGPX
//
//  iOS 26+ only. Uses MKReverseGeocodingRequest exclusively.
//  CLGeocoder and #available branches removed — deployment target is iOS 26 (PROJECT.md).
//  MKAddress only has shortAddress / fullAddress — no locality member.
//

import Foundation
import MapKit
import CoreLocation

actor ReverseGeocodingService {

    static let shared = ReverseGeocodingService()
    private init() {}

    private var cache: [String: String] = [:]

    func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let key = String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
        if let cached = cache[key] { return cached }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        do {
            let items = try await request.mapItems
            // MKAddress only exposes shortAddress/fullAddress; item.name gives the place name
            let result = items.first?.name ?? items.first?.address?.shortAddress
            if let result { cache[key] = result }
            return result
        } catch {
            return nil
        }
    }
}
