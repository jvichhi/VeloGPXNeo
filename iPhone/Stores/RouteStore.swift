import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Combine

// FIX (force-unwrap): typed error for storage failures so callers
// get a meaningful throw instead of a crash on unavailable sandbox.
enum StorageError: Error {
    case unavailable
}

@MainActor
final class RouteStore: ObservableObject {
    @Published private(set) var routes: [RouteModel] = []
    @Published var selectedRoute: RouteModel?
    @Published var selectedPOIs: [POIModel] = []
    @Published var lastImportMessage: String?

    @Published var selectedTab: AppTab = .routes
    @Published var routeToEditInPlan: RouteModel? = nil

    /// Set this to trigger the "ride this route" flow from anywhere.
    /// RootView observes it, selects the route, loads POIs, switches to
    /// the Ride tab, then clears it — identical to routeToEditInPlan pattern.
    @Published var pendingRideRoute: RouteModel? = nil

    // MARK: - F-C2: AI Planned Route
    //
    // Holds the single in-memory AI-planned route pending a Save / Discard / Start
    // decision in RouteLibraryView. Only one plan lives here at a time.
    // A new addAIPlannedRoute call replaces any previous value.
    //
    // Intentionally NOT persisted to disk: the user must explicitly save
    // (saveAIPlannedRoute) for the plan to appear in the permanent route list.
    // Discarding (discardAIPlannedRoute) or replacing with a new plan are the
    // only other paths. The value is cleared in all three cases.
    //
    // RouteLibraryView shows an "AI Planned" section header card at the top of
    // the list when this is non-nil, with Save / Discard / Start actions.

    @Published private(set) var aiPlannedRoute: RouteModel? = nil

    /// Store an AI-generated plan for the user to review.
    /// Replaces any existing pending plan without saving the previous one.
    func addAIPlannedRoute(_ route: RouteModel) {
        aiPlannedRoute = route
    }

    /// Rename the in-memory pending AI/drawn plan without persisting.
    /// Called from RouteRenameSheet's onSave closure (F-D5).
    /// The new name will be persisted when saveAIPlannedRoute() is called.
    func renameAIPlannedRoute(to newName: String) {
        guard var route = aiPlannedRoute else { return }
        route.name = newName
        aiPlannedRoute = route
    }

    /// Persist the pending AI plan into the permanent route library and clear it.
    /// Equivalent to calling addPlannedRoute then discarding the in-memory copy.
    func saveAIPlannedRoute() {
        guard let route = aiPlannedRoute else { return }
        aiPlannedRoute = nil
        addPlannedRoute(route, select: false)
    }

    /// Discard the pending AI plan without saving. Clears the card in RouteLibraryView.
    func discardAIPlannedRoute() {
        aiPlannedRoute = nil
    }

    // MARK: - Disk

    private let directoryName = "ImportedRoutes"
    private let poisDirectoryName = "RoutePOIs"

    func loadFromDisk() {
        let fm = FileManager.default
        guard let directory = try? storageDirectory() else { return }
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        routes = files.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(RouteModel.self, from: data)
        }.sorted { $0.createdAt > $1.createdAt }
        if selectedRoute == nil { selectedRoute = routes.first }
    }

    func loadPOIs(forRoute route: RouteModel) {
        guard let url = try? poisStorageURL(for: route.id) else { return }
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([POIModel].self, from: data)
        else { return }
        selectedPOIs = decoded
    }

    func savePOIs() {
        guard let route = selectedRoute else { return }
        guard let url = try? poisStorageURL(for: route.id) else { return }
        guard let data = try? JSONEncoder().encode(selectedPOIs) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func importRoute(from url: URL) async {
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let ext = url.pathExtension.lowercased()
            let route: RouteModel
            if ext == "gpx" {
                route = try GPXParser.parse(data: data, filename: url.lastPathComponent)
                // Resolve waypoint coordinates to canonical place names via
                // PlaceDescriptorService (iOS 26+ MKReverseGeocodingRequest,
                // CLGeocoder fallback, then MKLocalSearch fallback).
                let resolved = await PlaceDescriptorService.shared.resolveAll(route.waypoints)
                selectedPOIs = resolved.map { rw in
                    POIModel(name: rw.name, category: .custom, coordinate: rw.coordinate)
                }
            } else if ext == "geojson" || ext == "json" {
                let result = try GeoJSONParser.parse(data: data, filename: url.lastPathComponent)
                guard let parsedRoute = result.route else { throw NSError(domain: "VeloGPX", code: 1) }
                route = parsedRoute
                selectedPOIs = result.pois
            } else {
                throw NSError(domain: "VeloGPX", code: 2)
            }
            try save(route)
            loadFromDisk()
            selectedRoute = routes.first(where: { $0.id == route.id })
            lastImportMessage = "Imported \(route.name)"
        } catch {
            lastImportMessage = "Import failed"
        }
    }

    func addPlannedRoute(_ route: RouteModel, select: Bool = true) {
        do {
            try save(route)
            loadFromDisk()
            if select {
                selectedRoute = routes.first(where: { $0.id == route.id })
            }
        } catch {
            lastImportMessage = "Could not save planned route."
        }
    }

    func deleteRoute(_ route: RouteModel) {
        if let dir = try? storageDirectory() {
            let url = dir.appendingPathComponent("\(route.id.uuidString).json")
            try? FileManager.default.removeItem(at: url)
        }
        if let poisURL = try? poisStorageURL(for: route.id) {
            try? FileManager.default.removeItem(at: poisURL)
        }
        if selectedRoute?.id == route.id {
            selectedRoute = nil
            selectedPOIs = []
        }
        loadFromDisk()
    }

    func renameRoute(_ route: RouteModel, to newName: String) {
        guard var updated = routes.first(where: { $0.id == route.id }) else { return }
        updated.name = newName
        try? save(updated)
        loadFromDisk()
        if selectedRoute?.id == route.id { selectedRoute = updated }
    }

    func reverseRoute(_ route: RouteModel) {
        guard var updated = routes.first(where: { $0.id == route.id }) else { return }
        updated.trackPoints = updated.trackPoints.reversed()
        try? save(updated)
        loadFromDisk()
        if selectedRoute?.id == route.id { selectedRoute = updated }
    }

    private func save(_ route: RouteModel) throws {
        let dir = try storageDirectory()
        let url = dir.appendingPathComponent("\(route.id.uuidString).json")
        let data = try JSONEncoder().encode(route)
        try data.write(to: url, options: .atomic)
    }

    // FIX (force-unwrap): guard-let instead of first! so a missing
    // applicationSupportDirectory (e.g. during unit tests or a corrupted sandbox)
    // throws StorageError.unavailable rather than crashing.
    private func storageDirectory() throws -> URL {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StorageError.unavailable
        }
        let dir = base.appendingPathComponent(directoryName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func poisStorageURL(for routeID: UUID) throws -> URL {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StorageError.unavailable
        }
        let dir = base.appendingPathComponent(poisDirectoryName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("\(routeID.uuidString).json")
    }
}
