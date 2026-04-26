import SwiftUI
import MapKit

struct RideHistoryView: View {
    @EnvironmentObject private var historyStore: RideHistoryStore

    @State private var selectedRide: PersistedRideSummary?
    @State private var showDetail = false

    var body: some View {
        NavigationStack {
            Group {
                if historyStore.rides.isEmpty {
                    emptyState
                } else {
                    rideList
                }
            }
            .navigationTitle("My Rides")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $showDetail) {
                if let ride = selectedRide {
                    RideHistoryDetailView(ride: ride)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bicycle.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No rides yet")
                .font(.title2.weight(.semibold))
            Text("Your completed rides will appear here.\nHop on and start pedalling!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Records Banner

    private var recordsBanner: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if let ride = historyStore.longestRide {
                    RecordChip(
                        icon: "arrow.left.and.right",
                        label: "Longest",
                        value: String(format: "%.1f km", ride.distanceKm),
                        color: .blue
                    )
                }
                if let ride = historyStore.fastestRide {
                    RecordChip(
                        icon: "bolt.fill",
                        label: "Fastest avg",
                        value: String(format: "%.1f km/h", ride.avgSpeedKmh),
                        color: .orange
                    )
                }
                if let ride = historyStore.climbingRide {
                    RecordChip(
                        icon: "mountain.2.fill",
                        label: "Most climb",
                        value: String(format: "%.0f m", ride.elevationGain),
                        color: .green
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Ride List

    private var rideList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                // Personal records
                recordsBanner
                    .padding(.vertical, 12)

                // Monthly sections
                ForEach(historyStore.monthlySections) { section in
                    Section {
                        ForEach(section.rides) { ride in
                            RideRowCard(ride: ride)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedRide = ride
                                    showDetail = true
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        withAnimation { historyStore.delete(id: ride.id) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                        }
                    } header: {
                        MonthSectionHeader(section: section)
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Month Section Header

private struct MonthSectionHeader: View {
    let section: RideHistoryStore.MonthSection

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.id)
                    .font(.headline)
                Text("\(section.rideCount) ride\(section.rideCount == 1 ? "" : "s")  ·  \(String(format: "%.0f", section.totalDistance / 1000)) km  ·  \(String(format: "%.0f", section.totalElevation)) m gain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

// MARK: - Ride Row Card

struct RideRowCard: View {
    let ride: PersistedRideSummary
    @State private var snapshot: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            // Map thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray5))
                    .frame(width: 72, height: 72)
                if let img = snapshot {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "map.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
            }

            // Stats
            VStack(alignment: .leading, spacing: 4) {
                Text(ride.routeName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(ride.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Label(String(format: "%.1f km", ride.distanceKm), systemImage: "arrow.left.and.right")
                    Label(ride.durationFormatted, systemImage: "clock")
                    Label(String(format: "%.0f m", ride.elevationGain), systemImage: "mountain.2")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .task { await generateThumbnail() }
    }

    private func generateThumbnail() async {
        let coords = ride.actualTrack
        guard coords.count > 1 else { return }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta:  max((lats.max()! - lats.min()!) * 1.5, 0.004),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.5, 0.004)
        )
        let opts = MKMapSnapshotter.Options()
        opts.region = MKCoordinateRegion(center: center, span: span)
        opts.size   = CGSize(width: 144, height: 144)
        opts.scale  = UIScreen.main.scale
        opts.mapType = .standard
        opts.showsBuildings = false
        do {
            let snap = try await MKMapSnapshotter(options: opts).start()
            let img = UIGraphicsImageRenderer(size: opts.size).image { _ in
                snap.image.draw(at: .zero)
                let path = UIBezierPath()
                for (i, c) in coords.enumerated() {
                    let pt = snap.point(for: c)
                    i == 0 ? path.move(to: pt) : path.addLine(to: pt)
                }
                UIColor.systemBlue.withAlphaComponent(0.9).setStroke()
                path.lineWidth = 2.5
                path.lineCapStyle = .round
                path.stroke()
            }
            snapshot = img
        } catch {}
    }
}

// MARK: - Personal Record Chip

private struct RecordChip: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }
}
