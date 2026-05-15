import Foundation
import FoundationModels

/// F-A2 — Generates 3 short, evocative names for a route using on-device AI.
///
/// Returns an empty array (not an error) when the model is unavailable or
/// the response can't be parsed, so callers don't need error handling.
struct RouteNameSuggester {

    // MARK: - Public API

    /// Returns up to 3 name suggestions, or `[]` on failure.
    func suggest(for route: RouteModel) async throws -> [String] {
        let session = try VeloAI.makeSession(instructions: systemInstruction)
        let prompt  = buildPrompt(for: route)

        let response = try await session.respond(to: prompt)
        return parse(response.content)
    }

    // MARK: - Prompt

    private let systemInstruction = """
        You are a creative route-naming assistant for cyclists.
        Reply with exactly 3 short route names, one per line, no numbering, no extra text.
        Each name should be 2–5 words. Evocative, poetic, or local-landmark-inspired.
        """

    private func buildPrompt(for route: RouteModel) -> String {
        var parts: [String] = []
        parts.append("Distance: \(String(format: "%.1f", route.totalDistance / 1000)) km")
        parts.append("Elevation gain: \(String(format: "%.0f", route.elevationGain)) m")
        parts.append("Elevation loss: \(String(format: "%.0f", route.elevationLoss)) m")
        if route.trackPoints.count > 0 {
            let start = route.trackPoints.first!
            parts.append("Start: \(String(format: "%.4f", start.coordinate.latitude)), \(String(format: "%.4f", start.coordinate.longitude))")
        }
        if let filename = route.originalFilename {
            let hint = (filename as NSString).deletingPathExtension
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            parts.append("Original filename hint: \(hint)")
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Parse

    private func parse(_ raw: String) -> [String] {
        raw
            .components(separatedBy: .newlines)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                  .trimmingCharacters(in: CharacterSet(charactersIn: "1234567890.-) "))
            }
            .filter { !$0.isEmpty && $0.count >= 3 }
            .prefix(3)
            .map { String($0) }
    }
}
