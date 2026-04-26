//
//  ReverseGeocodingService.swift
//  VeloGPX
//
//  Modern replacement for CLGeocoder using MKReverseGeocodingRequest (iOS 26+).
//  Falls back to CLGeocoder on iOS 18 so both paths return a plain String address.
//
//  Usage:
//    let address = await ReverseGeocodingService.shared.reverseGeocode(coordinate)
//

import Foundation
import MapKit
import CoreLocation

actor ReverseGeocodingService {

    static let shared = ReverseGeocodingService()
    private init() {}

    // Simple in-memory cache to avoid hammering the API for the same coords.
    private var cache: [String: String] = [:]

    /// Returns a human-readable address string for the given coordinate.
    /// Returns nil if geocoding fails or produces no results.
    func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let key = String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
        if let cached = cache[key] { return cached }

        let result: String?

        if #available(iOS 26.0, *) {
            result = await reverseGeocodeModern(coordinate)
        } else {
            result = await reverseGeocodeLegacy(coordinate)
        }

        if let result {
            cache[key] = result
        }
        return result
    }

    // MARK: - iOS 26+ path

    @available(iOS 26.0, *)
    private func reverseGeocodeModern(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        do {
            let mapItems = try await request.mapItems
            // Prefer the item's name; fall back to placemark address.
            return mapItems.first?.name
                ?? mapItems.first?.placemark.title
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
            // Build a compact "Name, City" string.
            let parts = [p.name, p.locality].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.joined(separator: ", ")
        } catch {
            return nil
        }
    }
}
