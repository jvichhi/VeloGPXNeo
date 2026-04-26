import SwiftUI

/// A styled card rendered to UIImage via ImageRenderer for sharing
/// to iMessage, Instagram Stories, etc.
struct ShareableRideCard: View {
    let ride: PersistedRideSummary
    let snapshot: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            // Map
            if let img = snapshot {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: 390, height: 200)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: 390, height: 200)
            }

            // Stats
            VStack(spacing: 16) {
                // Route name + date
                VStack(spacing: 4) {
                    Text(ride.routeName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(ride.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Hero distance
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(String(format: "%.2f", ride.distanceKm))
                        .font(.system(size: 56, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.blue)
                    Text("km")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                // 4-stat row
                HStack(spacing: 0) {
                    CardStat(icon: "clock.fill",         value: ride.durationFormatted,                             label: "Time",    color: .purple)
                    Divider().frame(height: 40)
                    CardStat(icon: "speedometer",        value: String(format: "%.1f", ride.avgSpeedKmh) + " km/h", label: "Avg Speed", color: .blue)
                    Divider().frame(height: 40)
                    CardStat(icon: "mountain.2.fill",    value: String(format: "%.0f m", ride.elevationGain),       label: "Gain",    color: .green)
                    Divider().frame(height: 40)
                    CardStat(icon: "bolt.fill",          value: String(format: "%.1f", ride.maxSpeedKmh) + " km/h", label: "Top Speed", color: .orange)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))

                // Branding
                HStack(spacing: 6) {
                    Image(systemName: "bicycle")
                        .font(.caption.weight(.semibold))
                    Text("VeloGPX")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(Color(.systemBackground))
        }
        .frame(width: 390)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
    }
}

private struct CardStat: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
