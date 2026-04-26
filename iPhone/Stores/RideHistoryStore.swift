import Foundation
import Combine

/// Persists completed rides to Documents/ride-history.json.
/// Exposes sorted history, monthly grouped sections, and personal records.
@MainActor
final class RideHistoryStore: ObservableObject {
    @Published private(set) var rides: [PersistedRideSummary] = []

    // MARK: - Personal Records
    var longestRide: PersistedRideSummary?  { rides.max(by: { $0.totalDistance < $1.totalDistance }) }
    var fastestRide: PersistedRideSummary?  { rides.max(by: { $0.avgSpeedKmh   < $1.avgSpeedKmh   }) }
    var climbingRide: PersistedRideSummary? { rides.max(by: { $0.elevationGain  < $1.elevationGain  }) }

    // MARK: - Monthly Sections
    struct MonthSection: Identifiable {
        let id: String           // "April 2026"
        let rides: [PersistedRideSummary]
        var totalDistance: Double { rides.reduce(0) { $0 + $1.totalDistance } }
        var totalElevation: Double { rides.reduce(0) { $0 + $1.elevationGain } }
        var rideCount: Int { rides.count }
    }

    var monthlySections: [MonthSection] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let grouped = Dictionary(grouping: rides) { formatter.string(from: $0.startDate) }
        return grouped
            .map { MonthSection(id: $0.key, rides: $0.value.sorted { $0.startDate > $1.startDate }) }
            .sorted { section1, section2 in
                guard let d1 = section1.rides.first?.startDate,
                      let d2 = section2.rides.first?.startDate else { return false }
                return d1 > d2
            }
    }

    // MARK: - Persistence URL
    private var storageURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ride-history.json")
    }

    // MARK: - Init
    init() { load() }

    // MARK: - CRUD
    func save(_ summary: RideSummary) {
        let persisted = PersistedRideSummary(from: summary)
        rides.insert(persisted, at: 0)
        persist()
    }

    func delete(id: UUID) {
        rides.removeAll { $0.id == id }
        persist()
    }

    func delete(at offsets: IndexSet, in section: MonthSection) {
        let idsToDelete = offsets.map { section.rides[$0].id }
        rides.removeAll { idsToDelete.contains($0.id) }
        persist()
    }

    func rename(id: UUID, to newName: String) {
        guard let idx = rides.firstIndex(where: { $0.id == id }) else { return }
        rides[idx].routeName = newName
        persist()
    }

    // MARK: - Private helpers
    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            rides = try JSONDecoder().decode([PersistedRideSummary].self, from: data)
                .sorted { $0.startDate > $1.startDate }
        } catch {
            print("[RideHistoryStore] load error: \(error)")
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(rides)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[RideHistoryStore] persist error: \(error)")
        }
    }
}
