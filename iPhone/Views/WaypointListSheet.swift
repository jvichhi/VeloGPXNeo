//
//  WaypointListSheet.swift
//  VeloGPX
//
//  Embedded in PlanView's bottom drawer — NOT a .sheet presentation.
//  Height is controlled by PlanView's drawerHeight state; this view
//  must NOT stretch beyond its given space.
//
//  Bug 1 fix (May 13 2026): swipe-to-delete was silently swallowed
//  by the always-active editMode reorder chrome. EditMode is now
//  OFF by default and toggled by a toolbar-style button that appears
//  only when there are 2+ waypoints (the minimum needed for reorder
//  to be meaningful). Swipe-to-delete works in both normal and edit mode.
//
//  PlaceDescriptorService wired May 13, 2026.
//

import SwiftUI
import CoreLocation
import MapKit

struct WaypointListSheet: View {

    @ObservedObject var plan: PlanState
    let engine: PlanRouteEngine
    /// True when the drawer is at peek (collapsed) height.
    var isCollapsed: Bool = false
    let onRideNow: () -> Void
    let onGoToRoutes: () -> Void
    let onPlanAnother: () -> Void

    @EnvironmentObject private var routeStore: RouteStore

    @State private var showSaveAlert = false
    @State private var routeName = ""
    @State private var savedRouteName: String? = nil
    // Bug 1 fix: editMode is OFF by default. Swipe-to-delete works without
    // entering edit mode. The "Reorder" button appears only when count >= 2.
    @State private var editMode: EditMode = .inactive
    // PlaceDescriptorService results — keyed by waypoint UUID.
    @State private var resolvedNames: [UUID: String] = [:]

    var body: some View {
        Group {
            if let name = savedRouteName {
                savedConfirmation(name: name)
            } else {
                planningContent
            }
        }
        .alert("Save Route", isPresented: $showSaveAlert) {
            TextField("Route name", text: $routeName)
            Button("Save") { saveToLibrary() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for your planned route.")
        }
    }

    // MARK: - Planning Content

    private var planningContent: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header row ──────────────────────────────────────────────────
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan Route")
                        .font(.headline)
                    HStack(spacing: 10) {
                        Label(distanceString, systemImage: "arrow.left.and.right")
                        Label(elevationString, systemImage: "mountain.2")
                        if plan.isRouting {
                            HStack(spacing: 3) {
                                ProgressView().scaleEffect(0.65)
                                Text("Routing").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(plan.waypoints.isEmpty ? .tertiary : .secondary)
                }
                Spacer()

                // Bug 1: Reorder button only appears with 2+ waypoints and
                // when the drawer is not collapsed. Tapping toggles editMode
                // so drag handles appear on each row.
                if plan.waypoints.count >= 2 && !isCollapsed {
                    Button {
                        editMode = editMode == .active ? .inactive : .active
                    } label: {
                        Text(editMode == .active ? "Done" : "Reorder")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                    .padding(.trailing, 8)
                }

                Button {
                    plan.clearAll()
                    resolvedNames.removeAll()
                    editMode = .inactive
                } label: {
                    Text("Clear")
                        .font(.subheadline)
                        .foregroundStyle(plan.waypoints.isEmpty ? Color.secondary : Color.red)
                }
                .disabled(plan.waypoints.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)

            if !isCollapsed {
                Divider()

                if plan.waypoints.isEmpty {
                    emptyPrompt
                } else {
                    waypointList
                }

                Divider()

                closeLoopRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                Divider()

                actionRow
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }
        }
    }

    // MARK: - Waypoint List

    private var waypointList: some View {
        List {
            ForEach(Array(plan.waypoints.enumerated()), id: \.element.id) { index, wp in
                HStack(spacing: 10) {
                    waypointBadge(index: index, total: plan.waypoints.count)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(resolvedNames[wp.id] ?? (wp.name ?? coordinateLabel(wp.coordinate)))
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(coordinateLabel(wp.coordinate))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if resolvedNames[wp.id] == nil && wp.name == nil {
                        ProgressView()
                            .scaleEffect(0.6)
                            .transition(.opacity)
                    }
                }
                .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Color(UIColor.separator).opacity(0.5))
                // Bug 1 fix: swipeActions now work reliably because editMode
                // is inactive by default. Swipe delete is available in BOTH
                // inactive (normal swipe) and active (drag-handle) modes.
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        withAnimation {
                            deleteWaypoint(id: wp.id, index: index)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .task(id: wp.id) {
                    await resolveNameIfNeeded(for: wp)
                }
            }
            .onMove { from, to in
                plan.moveWaypoint(fromOffsets: from, toOffset: to)
                Task { await engine.recomputeAll(in: plan) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        // Bug 1: when the last waypoint is removed by swipe, exit edit mode
        // so the empty-prompt can display without a dangling reorder chrome.
        .onChange(of: plan.waypoints.count) { _, count in
            if count < 2 { editMode = .inactive }
        }
        .frame(maxHeight: CGFloat(min(plan.waypoints.count, 5)) * 52)
    }

    // MARK: - Delete Helper

    private func deleteWaypoint(id: UUID, index: Int) {
        let bridgeIndex = max(0, index - 1)
        resolvedNames.removeValue(forKey: id)
        plan.removeWaypoint(id: id)
        Task {
            if plan.waypoints.count >= 2 {
                await engine.refreshSegments(in: plan, affectedWaypointIndices: [bridgeIndex])
            }
        }
    }

    // MARK: - Empty Prompt

    private var emptyPrompt: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(.secondary)
            Text("Tap the map to drop waypoints")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - Close Loop Row

    private var closeLoopRow: some View {
        HStack(spacing: 10) {
            Image(systemName: plan.isLoopClosed
                    ? "arrow.triangle.turn.up.right.circle.fill"
                    : "arrow.triangle.turn.up.right.circle")
                .foregroundStyle(plan.isLoopClosed ? Color.blue : Color.secondary)
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 1) {
                Text("Close Loop")
                    .font(.subheadline.weight(.medium))
                Group {
                    if plan.isLoopClosed, let loopSeg = plan.segments.first(where: { $0.isLoop }) {
                        Text("Return: " + formatDistance(loopSeg.distance))
                    } else {
                        Text("Return leg back to start")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { plan.isLoopClosed },
                set: { _ in
                    plan.toggleLoop()
                    Task { await engine.refreshLoopSegment(in: plan) }
                }
            ))
            .labelsHidden()
            .disabled(!plan.canCloseLoop)
        }
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                routeName = PlanState.autoName()
                showSaveAlert = true
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(plan.isRideable ? .primary : .secondary)
            }
            .disabled(!plan.isRideable)

            Button {
                let route = plan.buildRouteModel(name: PlanState.autoName())
                routeStore.addPlannedRoute(route, select: true)
                onRideNow()
            } label: {
                Label("Ride Now", systemImage: "bicycle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        plan.isRideable ? AnyShapeStyle(Color.blue) : AnyShapeStyle(Color(.systemGray4)),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .foregroundStyle(Color.white)
            }
            .disabled(!plan.isRideable)
        }
    }

    // MARK: - Post-Save Confirmation

    private func savedConfirmation(name: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            VStack(spacing: 4) {
                Text("\"\(name)\"")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Saved to your library")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                Button {
                    onGoToRoutes()
                } label: {
                    Label("View in Routes", systemImage: "list.bullet")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Color.white)
                }
                Button {
                    savedRouteName = nil
                    onPlanAnother()
                } label: {
                    Label("Plan Another", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    // MARK: - PlaceDescriptorService Integration

    @available(iOS 26, *)
    private func resolveNameIfNeeded(for wp: WaypointPoint) async {
        guard resolvedNames[wp.id] == nil, wp.name == nil else { return }
        let resolved = await PlaceDescriptorService.shared.resolve(wp)
        guard plan.waypoints.contains(where: { $0.id == wp.id }) else { return }
        resolvedNames[wp.id] = resolved.name
    }

    private func resolveNameIfNeeded(for wp: WaypointPoint) async {
        // PlaceDescriptorService requires iOS 26+.
    }

    // MARK: - Helpers

    private func saveToLibrary() {
        let name = routeName.trimmingCharacters(in: .whitespaces)
        let finalName = name.isEmpty ? PlanState.autoName() : name
        let route = plan.buildRouteModel(name: finalName)
        routeStore.addPlannedRoute(route, select: false)
        withAnimation { savedRouteName = finalName }
    }

    private func waypointBadge(index: Int, total: Int) -> some View {
        ZStack {
            Circle()
                .fill(badgeColor(index: index, total: total))
                .frame(width: 26, height: 26)
            Text(badgeLabel(index: index, total: total))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white)
        }
    }

    private func badgeColor(index: Int, total: Int) -> Color {
        if index == 0 { return .green }
        if index == total - 1 && !plan.isLoopClosed { return .red }
        return Color(.darkGray)
    }

    private func badgeLabel(index: Int, total: Int) -> String {
        if index == 0 { return "S" }
        if index == total - 1 && !plan.isLoopClosed { return "E" }
        return "\(index + 1)"
    }

    private func coordinateLabel(_ coord: CLLocationCoordinate2D) -> String {
        String(format: "%.4f, %.4f", coord.latitude, coord.longitude)
    }

    private func formatDistance(_ metres: CLLocationDistance) -> String {
        metres >= 1000
            ? String(format: "%.1f km", metres / 1000)
            : String(format: "%.0f m", metres)
    }

    private var distanceString: String {
        plan.waypoints.isEmpty ? "0.0 km" : formatDistance(plan.totalDistance)
    }

    private var elevationString: String {
        String(format: "%.0f m\u{2191}", plan.totalElevationGain)
    }
}
