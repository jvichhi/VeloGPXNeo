import SwiftUI
import UniformTypeIdentifiers
import FoundationModels

struct RouteLibraryView: View {
    @EnvironmentObject private var routeStore: RouteStore
    @State private var isImporterPresented = false
    @State private var showImportAlert = false
    // F-A2: rename sheet
    @State private var routeToRename: RouteModel? = nil

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
            .onChange(of: routeStore.lastImportMessage) { _, newValue in
                showImportAlert = newValue != nil
            }
        }
        .alert("VeloGPX",
               isPresented: $showImportAlert,
               actions: {
                   Button("OK") {
                       showImportAlert = false
                       routeStore.lastImportMessage = nil
                   }
               },
               message: { Text(routeStore.lastImportMessage ?? "") })
        // F-A2: Rename sheet
        .sheet(item: $routeToRename) { route in
            RouteRenameSheet(route: route) { newName in
                routeStore.renameRoute(route, to: newName)
            }
            .environmentObject(routeStore)
        }
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
                    // F-A2: Rename swipe action
                    Button {
                        routeToRename = route
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.yellow)
                }

                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        routeStore.pendingRideRoute = route
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
                        routeStore.pendingRideRoute = route
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
                    // F-A2: Rename in contextMenu
                    Button {
                        routeToRename = route
                    } label: {
                        Label("Rename", systemImage: "pencil")
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

// MARK: - F-A2: Route Rename Sheet

private struct RouteRenameSheet: View {
    let route: RouteModel
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(VeloAI.enabledKey) private var aiEnabled = true

    @State private var draftName: String
    @State private var suggestionState: SuggestionState = .idle
    @State private var suggestions: [String] = []

    private enum SuggestionState {
        case idle, loading, done, failed(String)
    }

    init(route: RouteModel, onSave: @escaping (String) -> Void) {
        self.route  = route
        self.onSave = onSave
        _draftName  = State(initialValue: route.name)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // MARK: Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Route Name")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        TextField("Route name", text: $draftName)
                            .font(.body)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 12))
                            .autocorrectionDisabled()
                    }

                    // MARK: AI Suggestions (F-A2)
                    if VeloAI.isAvailable && aiEnabled {
                        VStack(spacing: 0) {
                            // Header
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.purple)
                                Text("Suggested Names")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                if case .done = suggestionState {
                                    Button {
                                        Task { await fetchSuggestions() }
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    .accessibilityLabel("Regenerate suggestions")
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6).opacity(0.6))

                            Divider()

                            // Body
                            Group {
                                switch suggestionState {
                                case .idle:
                                    Button {
                                        Task { await fetchSuggestions() }
                                    } label: {
                                        Label("Suggest Names from Route", systemImage: "sparkles")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 13)
                                            .background(.purple.opacity(0.12),
                                                        in: RoundedRectangle(cornerRadius: 12))
                                            .foregroundStyle(.purple)
                                    }
                                    .padding(14)

                                case .loading:
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(.purple)
                                        Text("Finding route names\u{2026}")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)

                                case .done:
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Tap a suggestion to use it — you can still edit before saving.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        FlowLayout(spacing: 8) {
                                            ForEach(suggestions, id: \.self) { name in
                                                Button {
                                                    draftName = name
                                                } label: {
                                                    Text(name)
                                                        .font(.subheadline.weight(.medium))
                                                        .padding(.horizontal, 14)
                                                        .padding(.vertical, 9)
                                                        .background(
                                                            draftName == name
                                                                ? Color.purple
                                                                : Color(.systemGray5),
                                                            in: Capsule()
                                                        )
                                                        .foregroundStyle(
                                                            draftName == name ? .white : .primary
                                                        )
                                                        .animation(.spring(duration: 0.2),
                                                                   value: draftName)
                                                }
                                            }
                                        }
                                    }
                                    .padding(14)

                                case .failed(let msg):
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle")
                                            .foregroundStyle(.orange)
                                        Text(msg)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button("Retry") {
                                            Task { await fetchSuggestions() }
                                        }
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.purple)
                                    }
                                    .padding(14)
                                }
                            }
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Rename Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            // Auto-fetch on appear when AI is available
            .task {
                guard VeloAI.isAvailable && aiEnabled else { return }
                await fetchSuggestions()
            }
        }
    }

    private func fetchSuggestions() async {
        suggestionState = .loading
        do {
            let names = try await RouteNameSuggester().suggest(for: route)
            suggestions = names
            suggestionState = .done
        } catch {
            suggestionState = .failed("Couldn't generate suggestions. Try again.")
        }
    }
}

// MARK: - FlowLayout (wrapping pill row)

/// A simple left-to-right wrapping layout for the suggestion pills.
private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        // iOS 16+ Layout protocol. Falls back gracefully to HStack wrap for older OS
        // but since we target iOS 26+ this is fine.
        _FlowLayout(spacing: spacing, content: content)
    }
}

private struct _FlowLayout<Content: View>: Layout {
    let spacing: CGFloat
    @ViewBuilder var content: Content

    // Required boilerplate — Layout expects a Body associatedtype
    struct Cache {}
    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxWidth = max(maxWidth, x)
        }
        y += rowHeight
        return CGSize(width: maxWidth, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
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
              text: "Search online for \"GPX cycling routes [your city]\" to find free files shared by local riders."),
        .init(icon: "square.and.arrow.down",
              text: "Tap + above or the Import button, then pick the file from Files, Mail, or AirDrop."),
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
