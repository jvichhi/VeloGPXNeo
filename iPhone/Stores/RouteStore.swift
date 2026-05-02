import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Combine

@MainActor
final class RouteStore: ObservableObject {
    @Published private(set) var routes: [RouteModel] = []
    @Published var selectedRoute: RouteModel?
    @Published var selectedPOIs: [POIModel] = []
    @Published var lastImportMessage: String?

    // Tab navigation: set this to .plan (with routeToEditInPlan) to deep-link
    // from any view into the Plan tab without needing a NavigationStack push.
    @Published var selectedTab: AppTab = .routes
    // When non-nil, PlanView preloads this route on appear then clears it.
    @Published var routeToEditInPlan: RouteModel? = nil

    private let directoryName = "ImportedRoutes"
    // Bug 1 fix: sidecar directory for per-route POI persistence.
    private let poisDirectoryName = "RoutePOIs"

    func loadFromDisk() {
        let fm = FileManager.default
        let directory = storageDirectory()
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        routes = files.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(RouteModel.self, from: data)
        }.sorted { $0.createdAt > $1.createdAt }
        if selectedRoute == nil { selectedRoute = routes.first }
    }

    // Bug 1 fix: load persisted POIs for a given route from the sidecar file.
    // Call this whenever selectedRoute changes (wired in RootView).
    func loadPOIs(forRoute route: RouteModel) {
        let url = poisStorageURL(for: route.id)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([POIModel].self, from: data)
        else { return }
        selectedPOIs = decoded
    }

    // Bug 1 fix: persist selectedPOIs to a sidecar file keyed to the route UUID.
    // Called from RouteDetailView.onDisappear and POIDiscoverySheet.onDisappear.
    func savePOIs() {
        guard let route = selectedRoute else { return }
        let url = poisStorageURL(for: route.id)
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
                selectedPOIs = route.waypoints.map { wp in
                    POIModel(name: wp.name ?? "Waypoint", category: .custom, coordinate: wp.coordinate.clCoordinate)
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

    func importRoute(data: Data, filename: String) throws {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let route: RouteModel
        if ext == "gpx" {
            route = try GPXParser.parse(data: data, filename: filename)
            selectedPOIs = route.waypoints.map { wp in
                POIModel(name: wp.name ?? "Waypoint", category: .custom, coordinate: wp.coordinate.clCoordinate)
            }
        } else {
            let result = try GeoJSONParser.parse(data: data, filename: filename)
            guard let parsedRoute = result.route else { throw NSError(domain: "VeloGPX", code: 3) }
            route = parsedRoute
            selectedPOIs = result.pois
        }
        try save(route)
        loadFromDisk()
    }

    /// Saves a route built in the Plan tab and selects it.
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
        let url = storageDirectory().appendingPathComponent("\(route.id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
        // Also clean up the POI sidecar.
        try? FileManager.default.removeItem(at: poisStorageURL(for: route.id))
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
        let url = storageDirectory().appendingPathComponent("\(route.id.uuidString).json")
        let data = try JSONEncoder().encode(route)
        try data.write(to: url, options: .atomic)
    }

    private func storageDirectory() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent(directoryName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // Bug 1 fix: sidecar storage for POIs, keyed by route UUID.
    private func poisStorageURL(for routeID: UUID) -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent(poisDirectoryName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("\(routeID.uuidString).json")
    }
}
