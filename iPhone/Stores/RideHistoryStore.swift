//
//  RideHistoryStore.swift
//  VeloGPX
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class RideHistoryStore: ObservableObject {
    @Published private(set) var summaries: [PersistedRideSummary] = []

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("ride_history.json")
    }()

    init() {
        load()
    }

    // MARK: - Alias

    /// Convenience alias used by RideHistoryView and other callsites.
    var rides: [PersistedRideSummary] { summaries }

    // MARK: - Personal Records

    var longestRide: PersistedRideSummary? {
        summaries.max(by: { $0.totalDistance < $1.totalDistance })
    }

    var fastestRide: PersistedRideSummary? {
        summaries.max(by: { $0.avgSpeedKmh < $1.avgSpeedKmh })
    }

    var climbingRide: PersistedRideSummary? {
        summaries.max(by: { $0.elevationGain < $1.elevationGain })
    }

    // MARK: - Monthly Sections

    struct MonthSection: Identifiable {
        /// Human-readable month label, e.g. "May 2026". Used as section ID.
        let id: String
        let rides: [PersistedRideSummary]

        var rideCount: Int { rides.count }
        var totalDistance: Double { rides.reduce(0) { $0 + $1.totalDistance } }
        var totalElevation: Double { rides.reduce(0) { $0 + $1.elevationGain } }
    }

    var monthlySections: [MonthSection] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        // Group by "Month YYYY" string, preserving insertion order (summaries
        // are already newest-first so groups naturally appear newest-first too).
        var seen: [String: Int] = [:]        // label → index into `sections`
        var sections: [MonthSection] = []

        for ride in summaries {
            let label = formatter.string(from: ride.startDate)
            if let idx = seen[label] {
                let existing = sections[idx]
                sections[idx] = MonthSection(id: existing.id, rides: existing.rides + [ride])
            } else {
                seen[label] = sections.count
                sections.append(MonthSection(id: label, rides: [ride]))
            }
        }
        return sections
    }

    // MARK: - Save new ride

    func save(_ summary: RideSummary) {
        let persisted = PersistedRideSummary(from: summary)
        summaries.insert(persisted, at: 0)
        persist()
    }

    // MARK: - Persist AI caption

    /// Updates the `aiCaption` field for the entry with the given id and re-writes to disk.
    func saveCaption(id: UUID, caption: String) {
        guard let idx = summaries.firstIndex(where: { $0.id == id }) else { return }
        summaries[idx].aiCaption = caption
        persist()
    }

    // MARK: - Delete

    func delete(id: UUID) {
        summaries.removeAll { $0.id == id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        summaries.remove(atOffsets: offsets)
        persist()
    }

    // MARK: - Rename

    func rename(id: UUID, to newName: String) {
        guard let idx = summaries.firstIndex(where: { $0.id == id }) else { return }
        summaries[idx].routeName = newName
        persist()
    }

    // MARK: - Private helpers

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            summaries = try JSONDecoder().decode([PersistedRideSummary].self, from: data)
        } catch {
            print("[RideHistoryStore] load error: \(error)")
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(summaries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[RideHistoryStore] persist error: \(error)")
        }
    }
}
