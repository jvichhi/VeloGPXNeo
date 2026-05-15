//
//  RideHistoryStore.swift
//  VeloGPX
//

import Foundation

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
