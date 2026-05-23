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
//  fix: resolve(coordinate:) overload doesn't exist — bridge via WaypointPoint stub (May 13 2026).
//
//  F-C1 (May 2026): "Plan with AI" button added to emptyPrompt.
//  Triggers showAssistant binding owned by PlanView, which presents
//  RidePlanAssistantView as a .sheet.
//
//  F-C2 (May 16 2026): stop-type SF Symbol icons per WaypointStopKind.
//  Dwell time chip shown under each AI-planned waypoint name.
//  Total outing time (ride time + total dwell) added to header stats row.
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
    /// Controls presentation of RidePlanAssistantView in PlanView.
    @Binding var showAssistant: Bool

    @EnvironmentObject private var routeStore: RouteStore

    @State private var showSaveAlert = false
    @State private var routeName = ""
    @State private var savedRouteName: String? = nil
    @State private var editMode: EditMode = .inactive
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
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan Route")
                        .font(.headline)
                    HStack(spacing: 10) {
                        Label(distanceString, systemImage: "arrow.left.and.right")
                        Label(elevationString, systemImage: "mountain.2")
                        if let outing = outingTimeString {
                            Label(outing, systemImage: "clock")
                        }
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

                if plan.waypoints.count >= 2 && !isCollapsed {
                    Button {
                        Task { await engine.recomputeAll(in: plan) }
                    } label: {
                        if plan.isRouting {
                            HStack(spacing: 4) {
                                ProgressView().scaleEffect(0.7)
                                Text("Routing")
                            }
                        } else {
                            Label("Re-route", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                    .disabled(plan.isRouting)
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
                if let warning = plan.distanceWarning {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    Divider()
                }
                if plan.waypoints.isEmpty { emptyPrompt } else { waypointList }
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
        let rowCount = min(plan.waypoints.count, 5)
        let listHeight = CGFloat(rowCount) * 52

        return List {
            ForEach(Array(plan.waypoints.enumerated()), id: \.element.id) { index, wp in
                let label = displayName(for: wp)
                HStack(spacing: 10) {
                    waypointBadge(index: index, total: plan.waypoints.count)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            // F-C2: stop-type icon for AI-planned waypoints
                            if let kind = wp.intentKind {
                                Image(systemName: symbolName(for: kind))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(tintColor(for: kind))
                            }
                            Text(label)
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            Text(coordinateLabel(wp.coordinate))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            // F-C2: dwell time chip
                            if let dwell = wp.dwellMinutes, dwell > 0 {
                                Text("\(dwell) min")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
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
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        withAnimation { deleteWaypoint(id: wp.id, index: index) }
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
        .onChange(of: plan.waypoints.count) { _, count in
            if count < 2 { editMode = .inactive }
        }
        .frame(maxHeight: listHeight)
    }

    private func displayName(for wp: PlanWaypoint) -> String {
        if let resolved = resolvedNames[wp.id] { return resolved }
        if let name = wp.name { return name }
        return coordinateLabel(wp.coordinate)
    }

    // MARK: - F-C2: Stop-Type Icon Helpers
    // Parameter type is WaypointStopKind (Watch-safe mirror of IntentStopKind).
    // WaypointListSheet must NOT import FoundationModels.

    /// SF Symbol name for each WaypointStopKind.
    private func symbolName(for kind: WaypointStopKind) -> String {
        switch kind {
        case .cafe:    return "cup.and.saucer.fill"
        case .park:    return "leaf.fill"
        case .town:    return "building.2.fill"
        case .service: return "wrench.and.screwdriver.fill"
        case .other:   return "mappin.circle.fill"
        }
    }

    /// Accent colour for each stop kind icon.
    private func tintColor(for kind: WaypointStopKind) -> Color {
        switch kind {
        case .cafe:    return .brown
        case .park:    return .green
        case .town:    return Color(.systemIndigo)
        case .service: return .orange
        case .other:   return .blue
        }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.secondary)
                Text("Tap the map to drop waypoints")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button {
                showAssistant = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("Plan with AI")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
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
                routeName = plan.suggestedName ?? PlanState.autoName()
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
                let route = plan.buildRouteModel(name: plan.suggestedName ?? PlanState.autoName())
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

    private func resolveNameIfNeeded(for wp: PlanWaypoint) async {
        guard resolvedNames[wp.id] == nil, wp.name == nil else { return }
        let stub = WaypointPoint(coordinate: wp.coordinate, name: nil)
        let result = await PlaceDescriptorService.shared.resolve(stub)
        guard plan.waypoints.contains(where: { $0.id == wp.id }) else { return }
        resolvedNames[wp.id] = result.name
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

    // F-C2: Total outing time = estimated ride time + total dwell across all waypoints.
    // Ride-time estimate: 15 km/h average cycling speed (conservative urban/mixed pace).
    // Only shown when there are waypoints and at least one dwell stop.
    private var outingTimeString: String? {
        guard !plan.waypoints.isEmpty else { return nil }
        let totalDwellMin = plan.waypoints.compactMap(\.dwellMinutes).reduce(0, +)
        guard totalDwellMin > 0 || plan.totalDistance > 0 else { return nil }
        let rideMinutes = Int((plan.totalDistance / 1000.0) / 15.0 * 60.0)
        let totalMinutes = rideMinutes + totalDwellMin
        if totalMinutes < 60 {
            return "~\(totalMinutes) min"
        } else {
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            return m == 0 ? "~\(h) h" : "~\(h) h \(m) min"
        }
    }
}
