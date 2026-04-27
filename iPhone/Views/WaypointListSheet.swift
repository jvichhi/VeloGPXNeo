//
//  WaypointListSheet.swift
//  VeloGPX
//

import SwiftUI
import CoreLocation

struct WaypointListSheet: View {

    @ObservedObject var plan: PlanState
    let engine: PlanRouteEngine
    let onRideNow: () -> Void
    let onSaved: () -> Void

    @EnvironmentObject private var routeStore: RouteStore

    @State private var showSaveAlert = false
    @State private var routeName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                Divider()

                if plan.waypoints.isEmpty {
                    emptyPrompt
                } else {
                    waypointList
                }

                Divider()

                closeLoopRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                Divider()

                actionRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .navigationTitle("Waypoints")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        plan.clearAll()
                    } label: {
                        Text("Clear")
                            .foregroundStyle(plan.waypoints.isEmpty ? Color.secondary : Color.red)
                    }
                    .disabled(plan.waypoints.isEmpty)
                }
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

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: 20) {
            Label(distanceString, systemImage: "arrow.left.and.right")
                .font(.subheadline.weight(.semibold))
            Label(elevationString, systemImage: "mountain.2")
                .font(.subheadline.weight(.semibold))
            if plan.isRouting {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.7)
                    Text("Routing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .foregroundStyle(plan.waypoints.isEmpty ? Color.secondary : Color.primary)
    }

    // MARK: - Waypoint List

    private var waypointList: some View {
        List {
            ForEach(Array(plan.waypoints.enumerated()), id: \.element.id) { index, wp in
                HStack(spacing: 12) {
                    waypointBadge(index: index, total: plan.waypoints.count)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wp.name ?? coordinateLabel(wp.coordinate))
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(coordinateLabel(wp.coordinate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .onDelete { offsets in
                let ids = offsets.map { plan.waypoints[$0].id }
                ids.forEach { plan.removeWaypoint(id: $0) }
                Task { await engine.recomputeAll(in: plan) }
            }
            .onMove { from, to in
                plan.moveWaypoint(fromOffsets: from, toOffset: to)
                Task { await engine.recomputeAll(in: plan) }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
    }

    // MARK: - Empty Prompt

    private var emptyPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Tap the map to place waypoints")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    // MARK: - Close Loop Row

    private var closeLoopRow: some View {
        HStack {
            Image(systemName: plan.isLoopClosed
                    ? "arrow.triangle.turn.up.right.circle.fill"
                    : "arrow.triangle.turn.up.right.circle")
                .foregroundStyle(plan.isLoopClosed ? Color.blue : Color.secondary)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 1) {
                Text("Close Loop")
                    .font(.subheadline.weight(.medium))
                if plan.isLoopClosed, let loopSeg = plan.segments.first(where: { $0.isLoop }) {
                    Text("Return leg: " + formatDistance(loopSeg.distance))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Add a return leg back to the start")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        HStack(spacing: 12) {
            Button {
                routeName = PlanState.autoName()
                showSaveAlert = true
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(plan.isRideable ? Color.primary : Color.secondary)
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
                        plan.isRideable ? Color.blue : Color(.systemGray4),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .foregroundStyle(Color.white)
            }
            .disabled(!plan.isRideable)
        }
    }

    // MARK: - Helpers

    private func saveToLibrary() {
        let name = routeName.trimmingCharacters(in: .whitespaces)
        let route = plan.buildRouteModel(name: name.isEmpty ? PlanState.autoName() : name)
        routeStore.addPlannedRoute(route, select: false)
        onSaved()
    }

    private func waypointBadge(index: Int, total: Int) -> some View {
        ZStack {
            Circle()
                .fill(badgeColor(index: index, total: total))
                .frame(width: 28, height: 28)
            Text(badgeLabel(index: index, total: total))
                .font(.system(size: 11, weight: .bold))
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
        String(format: "%.0f m gain", plan.totalElevationGain)
    }
}
