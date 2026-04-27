//
//  PlanView.swift
//  VeloGPX
//

import SwiftUI
import MapKit
import CoreLocation

private let kDrawerCollapsed: CGFloat = 120
private let kDrawerMedium: CGFloat = 340

struct PlanView: View {

    @StateObject private var plan = PlanState()
    private let engine = PlanRouteEngine()

    @EnvironmentObject private var routeStore: RouteStore

    var switchToRide: () -> Void = {}
    var switchToRoutes: () -> Void = {}

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var drawerHeight: CGFloat = kDrawerCollapsed
    @State private var showErrorBanner = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {

                // Map takes all space above the drawer — shrinks as drawer grows
                ZStack(alignment: .top) {
                    mapLayer
                    if showErrorBanner, let err = plan.routingError {
                        errorBanner(message: err)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: max(100, geo.size.height - drawerHeight))
                .clipped()

                // Drawer sits directly below map in normal flow
                // Tab bar is rendered by TabView outside this entire view
                drawerCard(maxDrawer: geo.size.height * 0.72)
            }
            .ignoresSafeArea(edges: .top)
        }
        .onChange(of: plan.routingError) { _, newVal in
            if newVal != nil {
                withAnimation { showErrorBanner = true }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { showErrorBanner = false }
                    plan.routingError = nil
                }
            }
        }
    }

    // MARK: - Drawer

    private func drawerCard(maxDrawer: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 2)

            WaypointListSheet(
                plan: plan,
                engine: engine,
                onRideNow: {
                    withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) {
                        drawerHeight = kDrawerCollapsed
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { switchToRide() }
                },
                onGoToRoutes: {
                    withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) {
                        drawerHeight = kDrawerCollapsed
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { switchToRoutes() }
                },
                onPlanAnother: {
                    plan.clearAll()
                    withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) {
                        drawerHeight = kDrawerCollapsed
                    }
                }
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: drawerHeight)
        .clipped()
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 0.5)
        }
        .gesture(
            DragGesture()
                .onChanged { val in
                    let proposed = drawerHeight - val.translation.height
                    drawerHeight = min(max(proposed, kDrawerCollapsed), maxDrawer)
                }
                .onEnded { val in
                    let velocity = val.predictedEndTranslation.height
                    let snaps: [CGFloat] = [kDrawerCollapsed, kDrawerMedium, maxDrawer]
                    withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) {
                        if velocity > 180 {
                            drawerHeight = kDrawerCollapsed
                        } else if velocity < -180 {
                            drawerHeight = drawerHeight < kDrawerMedium ? kDrawerMedium : maxDrawer
                        } else {
                            drawerHeight = snaps.min(by: { abs($0 - drawerHeight) < abs($1 - drawerHeight) }) ?? kDrawerCollapsed
                        }
                    }
                }
        )
        .onTapGesture {
            if drawerHeight <= kDrawerCollapsed {
                withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) {
                    drawerHeight = kDrawerMedium
                }
            }
        }
    }

    // MARK: - Map

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $position) {
                if !plan.routePolyline.isEmpty {
                    MapPolyline(coordinates: plan.routePolyline)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
                if plan.isLoopClosed && !plan.loopPolyline.isEmpty {
                    MapPolyline(coordinates: plan.loopPolyline)
                        .stroke(.blue.opacity(0.55),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6]))
                }
                ForEach(Array(plan.waypoints.enumerated()), id: \.element.id) { index, wp in
                    Annotation("", coordinate: wp.coordinate, anchor: .bottom) {
                        WaypointPin(
                            index: index,
                            total: plan.waypoints.count,
                            isLoopClosed: plan.isLoopClosed,
                            name: wp.name
                        )
                    }
                }
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapPitchToggle()
            }
            .onTapGesture { screenPoint in
                guard let coord = proxy.convert(screenPoint, from: .local) else { return }
                let waypointCount = plan.waypoints.count
                plan.addWaypoint(coord)
                if waypointCount >= 1 {
                    Task {
                        await engine.refreshSegments(
                            in: plan,
                            affectedWaypointIndices: [waypointCount]
                        )
                    }
                }
                if plan.waypoints.count == 1 {
                    withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) {
                        drawerHeight = kDrawerMedium
                    }
                }
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.primary)
            Spacer()
            Button {
                withAnimation { showErrorBanner = false; plan.routingError = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 52)
    }
}

// MARK: - Waypoint Pin

private struct WaypointPin: View {
    let index: Int
    let total: Int
    let isLoopClosed: Bool
    var name: String?

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            if let name, !name.isEmpty {
                Text(name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                    .fixedSize()
            }
        }
    }

    private var fillColor: Color {
        if index == 0 { return .green }
        if index == total - 1 && !isLoopClosed { return .red }
        return Color(.darkGray)
    }

    private var label: String {
        if index == 0 { return isLoopClosed && total > 1 ? "S/E" : "S" }
        if index == total - 1 && !isLoopClosed { return "E" }
        return "\(index + 1)"
    }
}
