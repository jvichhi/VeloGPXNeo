import SwiftUI
import UniformTypeIdentifiers

struct RouteLibraryView: View {
    @EnvironmentObject private var routeStore: RouteStore
    @State private var isImporterPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(routeStore.routes) { route in
                        NavigationLink {
                            RouteDetailView(route: route)
                        } label: {
                            RouteCard(route: route)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            routeStore.selectedRoute = route
                        })
                        .contextMenu {
                            Button(role: .destructive) {
                                routeStore.deleteRoute(route)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Routes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.blue)
                                .frame(width: 32, height: 32)
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [UTType(filenameExtension: "gpx")!, UTType(filenameExtension: "geojson")!, .json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        Task { await routeStore.importRoute(from: url) }
                    }
                case .failure:
                    routeStore.lastImportMessage = "Import cancelled"
                }
            }
            .overlay {
                if routeStore.routes.isEmpty {
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color(.systemGray5))
                                .frame(width: 72, height: 72)
                            Image(systemName: "map")
                                .font(.system(size: 30))
                                .foregroundStyle(.secondary)
                        }
                        VStack(spacing: 6) {
                            Text("No routes yet")
                                .font(.title3.bold())
                            Text("Import a GPX or GeoJSON file from\nSafari, Files, or Mail.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Button {
                            isImporterPresented = true
                        } label: {
                            Label("Import a Route", systemImage: "square.and.arrow.down")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.blue, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    .padding()
                }
            }
        }
        .alert("VeloGPX", isPresented: .constant(routeStore.lastImportMessage != nil), actions: {
            Button("OK") { routeStore.lastImportMessage = nil }
        }, message: {
            Text(routeStore.lastImportMessage ?? "")
        })
    }
}

// MARK: - Route Card

private struct RouteCard: View {
    let route: RouteModel

    var body: some View {
        HStack(spacing: 14) {
            // Left accent icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: "figure.outdoor.cycle")
                    .font(.system(size: 22))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(route.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    StatBadge(
                        icon: "arrow.left.and.right",
                        value: String(format: "%.1f km", route.totalDistance / 1000)
                    )
                    StatBadge(
                        icon: "mountain.2",
                        value: String(format: "%.0f m ↑", route.elevationGain)
                    )
                    StatBadge(
                        icon: "doc",
                        value: route.sourceFormat.rawValue.uppercased()
                    )
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

// MARK: - Stat Badge

private struct StatBadge: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(value)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color(.systemGray5), in: Capsule())
    }
}
