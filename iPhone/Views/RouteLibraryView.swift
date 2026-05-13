import SwiftUI
import UniformTypeIdentifiers

struct RouteLibraryView: View {
    @EnvironmentObject private var routeStore: RouteStore
    @State private var isImporterPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if routeStore.routes.isEmpty {
                    emptyState
                } else {
                    routeList
                }
            }
            .navigationTitle("Routes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isImporterPresented = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(.tint.opacity(0.12), in: Circle())
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [
                    UTType(filenameExtension: "gpx")!,
                    UTType(filenameExtension: "geojson")!,
                    .json
                ],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await routeStore.importRoute(from: url) }
                }
            }
        }
        .alert("VeloGPX",
               isPresented: .constant(routeStore.lastImportMessage != nil),
               actions: { Button("OK") { routeStore.lastImportMessage = nil } },
               message: { Text(routeStore.lastImportMessage ?? "") })
    }

    // MARK: - Route List

    private var routeList: some View {
        List {
            ForEach(routeStore.routes) { route in
                let isSelected = routeStore.selectedRoute?.id == route.id
                let isPlanned  = route.sourceFormat == .planned

                NavigationLink {
                    RouteDetailView(route: route)
                } label: {
                    RouteRow(route: route, isActive: isSelected)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                .listRowSeparator(.hidden)

                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        routeStore.deleteRoute(route)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            routeStore.selectedRoute = route
                        }
                    } label: {
                        Label("Ride", systemImage: "bicycle")
                    }
                    .tint(.blue)

                    if isPlanned {
                        Button {
                            routeStore.routeToEditInPlan = route
                        } label: {
                            Label("Plan", systemImage: "pencil.and.map")
                        }
                        .tint(.purple)
                    }
                }

                .contextMenu {
                    Button {
                        withAnimation { routeStore.selectedRoute = route }
                    } label: {
                        Label("Ride This Route", systemImage: "bicycle")
                    }
                    if isPlanned {
                        Button {
                            routeStore.routeToEditInPlan = route
                        } label: {
                            Label("Edit in Plan", systemImage: "pencil.and.map")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        routeStore.deleteRoute(route)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 20) {
                    ZStack {
                        Circle().fill(Color(.systemGray5)).frame(width: 72, height: 72)
                        Image(systemName: "list.bullet.below.rectangle")
                            .font(.system(size: 30)).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 6) {
                        Text("No routes yet").font(.title3.bold())
                        Text("Import a GPX or GeoJSON, or use the Plan tab to build one.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Button { isImporterPresented = true } label: {
                        Label("Import a Route", systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .background(.blue, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 60)

                ImportTipCard()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Import Tip Card

private struct ImportTipCard: View {
    private struct TipRow: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
    }

    private let rows: [TipRow] = [
        .init(icon: "doc.badge.arrow.up",
              text: "Export a GPX or GeoJSON file from any route planning app."),
        .init(icon: "globe",
              text: "Search the web for \u201cGPX routes [your city]\u201d \u2014 many cycling communities share free files online."),
        .init(icon: "square.and.arrow.down",
              text: "Tap \u2b above or the Import button, then pick the file from Files, Mail, or AirDrop."),
        .init(icon: "map",
              text: "Prefer to build your own? Head to the Plan tab to draw a route from scratch."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("How to add routes")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: row.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(row.text)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(.systemGray4), lineWidth: 0.5)
        }
    }
}

// MARK: - Route Row

private struct RouteRow: View {
    let route: RouteModel
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconTint.opacity(isActive ? 0.18 : 0.10))
                    .frame(width: 44, height: 44)
                Image(systemName: routeIcon)
                    .font(.system(size: 19))
                    .foregroundStyle(isActive ? iconTint : iconTint.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(route.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    PillBadge(icon: "arrow.left.and.right",
                              label: String(format: "%.1f km", route.totalDistance / 1000))
                    PillBadge(icon: "mountain.2",
                              label: String(format: "%.0f m", route.elevationGain))
                    if isPlanned {
                        PillBadge(icon: "map.fill", label: "PLANNED",
                                  color: .purple, filled: true)
                    } else {
                        PillBadge(icon: "doc",
                                  label: route.sourceFormat.rawValue.uppercased())
                    }
                }
            }

            Spacer()

            if isActive {
                ZStack {
                    Circle().fill(Color.blue).frame(width: 22, height: 22)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isActive ? Color.blue.opacity(0.4) : Color.clear,
                    lineWidth: 1.5
                )
        }
        .animation(.spring(duration: 0.25), value: isActive)
    }

    private var isPlanned: Bool   { route.sourceFormat == .planned }
    private var routeIcon: String { isPlanned ? "map.fill" : "figure.outdoor.cycle" }
    private var iconTint: Color   { isPlanned ? .purple : .blue }
}

// MARK: - Pill Badge

private struct PillBadge: View {
    let icon: String
    let label: String
    var color: Color = .blue
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(label).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(filled ? Color.white : Color.secondary)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(filled ? color : Color(.systemGray5), in: Capsule())
    }
}
