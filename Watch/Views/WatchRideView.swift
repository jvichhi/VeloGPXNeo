import SwiftUI
import WatchKit

struct WatchRideView: View {
    @ObservedObject var store: WatchRideStore

    var body: some View {
        if let s = store.summary, s.isActive {
            activeRideView(s)
        } else {
            idleView
        }
    }

    private func activeRideView(_ s: WatchRideSummary) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", s.speedKmh))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                        .minimumScaleFactor(0.5)
                    Text("km/h")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    watchMetric("DIST", String(format: "%.2f km", s.distanceKm))
                    Divider().frame(height: 32)
                    watchMetric("OFF", String(format: "%.0fm", s.offRouteDistance))
                }

                if s.isOffRoute {
                    Label("Off Route", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.red, in: Capsule())
                }

                if let name = s.nextPOIName, let dist = s.nextPOIDistance {
                    VStack(spacing: 2) {
                        Text(name).font(.caption).lineLimit(1)
                        Text(String(format: "%.0fm ahead", dist))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Riding")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func watchMetric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            Image(systemName: "bicycle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Start a ride\non your iPhone")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}
