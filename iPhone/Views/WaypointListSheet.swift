//
//  WaypointListSheet.swift
//  VeloGPX
//
//  Embedded in PlanView's bottom drawer — NOT a .sheet presentation.
//  Height is controlled by PlanView's drawerHeight state; this view
//  must NOT stretch beyond its given space.
//

import SwiftUI
import CoreLocation

struct WaypointListSheet: View {

    @ObservedObject var plan: PlanState
    let engine: PlanRouteEngine
    /// True when the drawer is at peek (collapsed) height.
    /// Hides the waypoint list, Close Loop row, and action buttons so
    /// nothing gets clipped inside the short drawer frame.
    var isCollapsed: Bool = false
    let onRideNow: () -> Void
    let onGoToRoutes: () -> Void
    let onPlanAnother: () -> Void

    @EnvironmentObject private var routeStore: RouteStore

    @State private var showSaveAlert = false
    @State private var routeName = ""
    @State private var savedRouteName: String? = nil
    @State private var editMode: EditMode = .active

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
        VStack(spacing: 0) {

            // ── Header row: always visible at every drawer height ──
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
                Button {
                    plan.clearAll()
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

            // ── Everything below hidden when drawer is at peek height ──
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
                        Text(wp.name ?? coordinateLabel(wp.coordinate))
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(coordinateLabel(wp.coordinate))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Color(UIColor.separator).opacity(0.5))
            }
            .onDelete { offsets in
                let sortedOffsets = offsets.sorted()
                let ids = sortedOffsets.map { plan.waypoints[$0].id }
                let bridgeIndex = sortedOffsets.first.map { max(0, $0 - 1) }
                ids.forEach { plan.removeWaypoint(id: $0) }
                Task {
                    if plan.waypoints.count >= 2, let idx = bridgeIndex {
                        await engine.refreshSegments(in: plan, affectedWaypointIndices: [idx])
                    }
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
        .frame(maxHeight: CGFloat(min(plan.waypoints.count, 5)) * 52)
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
