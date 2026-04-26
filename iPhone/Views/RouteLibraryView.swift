import SwiftUI
import UniformTypeIdentifiers

struct RouteLibraryView: View {
    @EnvironmentObject private var routeStore: RouteStore
    @State private var isImporterPresented = false
    @State private var pendingSelectRoute: RouteModel? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(routeStore.routes) { route in
                        let isSelected = routeStore.selectedRoute?.id == route.id
                        let isPending  = pendingSelectRoute?.id == route.id

                        VStack(spacing: 0) {
                            NavigationLink {
                                RouteDetailView(route: route)
                            } label: {
                                RouteCard(route: route, isActive: isSelected)
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                // Tapping an already-active card just navigates — no re-select needed
                                if !isSelected {
                                    withAnimation(.spring(duration: 0.25)) {
                                        pendingSelectRoute = route
                                    }
                                }
                            })

                            // Inline "Ride This Route" CTA — slides in when card is tapped
                            if isPending && !isSelected {
                                HStack(spacing: 10) {
                                    Button {
                                        withAnimation(.spring(duration: 0.3)) {
                                            routeStore.selectedRoute = route
                                            pendingSelectRoute = nil
                                        }
                                    } label: {
                                        Label("Ride This Route", systemImage: "bicycle")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                                            .foregroundStyle(.white)
                                    }

                                    Button {
                                        withAnimation(.spring(duration: 0.2)) {
                                            pendingSelectRoute = nil
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 40, height: 40)
                                            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.bottom, 12)
                                .padding(.top, -4)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .shadow(color: .black.opacity(isSelected ? 0.10 : 0.06), radius: isSelected ? 8 : 6, y: isSelected ? 3 : 2)
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
    let isActive: Bool

    var body: some View {
        HStack(spacing: 14) {

            // Left icon — blue tint when active
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? Color.blue.opacity(0.18) : Color.blue.opacity(0.10))
                    .frame(width: 52, height: 52)
                Image(systemName: "figure.outdoor.cycle")
                    .font(.system(size: 22))
                    .foregroundStyle(isActive ? .blue : .blue.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(route.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    StatBadge(icon: "arrow.left.and.right", value: String(format: "%.1f km", route.totalDistance / 1000))
                    StatBadge(icon: "mountain.2",           value: String(format: "%.0f m ↑", route.elevationGain))
                    StatBadge(icon: "doc",                  value: route.sourceFormat.rawValue.uppercased())
                }
            }

            Spacer()

            // Active checkmark badge OR chevron
            if isActive {
                ZStack {
                    Circle()
                        .fill(.blue)
                        .frame(width: 26, height: 26)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(
            isActive
                ? AnyShapeStyle(.regularMaterial)
                : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            // Blue left edge accent on active card
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isActive ? Color.blue.opacity(0.45) : Color.clear, lineWidth: 1.5)
        )
        .animation(.spring(duration: 0.25), value: isActive)
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
