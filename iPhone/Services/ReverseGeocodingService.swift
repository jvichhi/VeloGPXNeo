//
//  ReverseGeocodingService.swift
//  VeloGPX
//
//  iOS 26+: MKReverseGeocodingRequest via MapKit.
//  iOS 18 fallback: CLGeocoder.
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

        let result: String?
        if #available(iOS 26.0, *) {
            result = await reverseGeocodeModern(coordinate)
        } else {
            result = await reverseGeocodeLegacy(coordinate)
        }

        if let result { cache[key] = result }
        return result
    }

    // MARK: - iOS 26+ path

    @available(iOS 26.0, *)
    private func reverseGeocodeModern(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        do {
            let items = try await request.mapItems
            // Use item.name; avoid deprecated .placemark property
            return items.first?.name
        } catch {
            return nil
        }
    }

    // MARK: - iOS 18 fallback path

    private func reverseGeocodeLegacy(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let p = placemarks.first else { return nil }
            let parts = [p.name, p.locality].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.joined(separator: ", ")
        } catch {
            return nil
        }
    }
}
