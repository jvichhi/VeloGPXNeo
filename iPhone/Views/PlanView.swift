//
//  PlanView.swift
//  VeloGPX
//

import SwiftUI
import MapKit
import CoreLocation

private let kDrawerPeek:   CGFloat = 88
private let kDrawerMedium: CGFloat = 320

struct PlanView: View {

    @StateObject private var plan = PlanState()
    private let engine = PlanRouteEngine()

    @EnvironmentObject private var routeStore: RouteStore

    var switchToRide: () -> Void = {}
    var switchToRoutes: () -> Void = {}
    var preloadRoute: RouteModel? = nil

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var isPitchEnabled: Bool = true
    @State private var drawerHeight: CGFloat = kDrawerMedium
    @State private var showErrorBanner = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {

                // Map fills entire screen — bleeds behind status bar AND tab bar.
                // .ignoresSafeArea() scoped to mapLayer only; ZStack still respects
                // the tab bar safe area so the drawer stops above it naturally.
                mapLayer(geo: geo)
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Map control buttons — plain SwiftUI overlay, safe-area-aware.
                mapControlsOverlay(geo: geo)
                    .zIndex(5)

                // Floating error banner
                if showErrorBanner, let err = plan.routingError {
                    errorBanner(message: err)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 56)
                        .zIndex(20)
                }

                // Floating drawer — floats 8 pt above tab bar, fully rounded
                drawerCard(geo: geo)
                    .padding(.bottom, 8)
                    .zIndex(10)
            }
        }
        .task {
            let routeToLoad = routeStore.routeToEditInPlan ?? preloadRoute
            if let route = routeToLoad {
                await plan.loadFrom(route: route)
                routeStore.routeToEditInPlan = nil
                withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) {
                    drawerHeight = kDrawerMedium
                }
            }
        }
        .onChange(of: routeStore.routeToEditInPlan) { _, route in
            guard let route else { return }
            Task {
                await plan.loadFrom(route: route)
                routeStore.routeToEditInPlan = nil
                withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) {
                    drawerHeight = kDrawerMedium
                }
            }
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

    // MARK: - Map Controls Overlay

    private func mapControlsOverlay(geo: GeometryProxy) -> some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.4)) {
                    position = .userLocation(fallback: .automatic)
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            }
            .accessibilityLabel("Re-centre map on my location")

            Button {
                isPitchEnabled.toggle()
            } label: {
                Image(systemName: isPitchEnabled ? "view.3d" : "map")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            }
            .accessibilityLabel(isPitchEnabled ? "Switch to flat map" : "Switch to 3D map")
        }
        .padding(.top, geo.safeAreaInsets.top + 8)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(true)
    }

    // MARK: - Map

    private func mapLayer(geo: GeometryProxy) -> some View {
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

                let routeExists = !plan.routePolyline.isEmpty
                ForEach(Array(plan.waypoints.enumerated()), id: \.element.id) { index, wp in
                    let isStartOrEnd = index == 0 || index == plan.waypoints.count - 1
                    if !routeExists || isStartOrEnd {
                        Annotation("", coordinate: wp.coordinate, anchor: .center) {
                            WaypointPin(index: index, total: plan.waypoints.count,
                                        isLoopClosed: plan.isLoopClosed, name: wp.name)
                        }
                    }
                }

                UserAnnotation()
            }
            .mapStyle(isPitchEnabled
                ? .standard(elevation: .realistic)
                : .standard(elevation: .flat)
            )
            .mapControlVisibility(.hidden)
            .onTapGesture { screenPoint in
                guard let coord = proxy.convert(screenPoint, from: .local) else { return }
                let before = plan.waypoints.count
                plan.addWaypoint(coord)
                if before >= 1 {
                    Task { await engine.refreshSegments(in: plan, affectedWaypointIndices: [before]) }
                }
            }
        }
    }

    // MARK: - Drawer

    private func drawerCard(geo: GeometryProxy) -> some View {
        let maxDrawer = geo.size.height - 60
        let safeBottom = geo.safeAreaInsets.bottom
        let isCollapsed = drawerHeight <= kDrawerPeek

        return VStack(spacing: 0) {
            // Grab handle
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 2)

            WaypointListSheet(
                plan: plan,
                engine: engine,
                isCollapsed: isCollapsed,
                onRideNow: {
                    withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) { drawerHeight = kDrawerPeek }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { switchToRide() }
                },
                onGoToRoutes: {
                    withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) { drawerHeight = kDrawerPeek }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { switchToRoutes() }
                },
                onPlanAnother: {
                    plan.clearAll()
                    withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) { drawerHeight = kDrawerMedium }
                }
            )
            .padding(.bottom, safeBottom > 0 ? safeBottom : 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: min(drawerHeight, maxDrawer))
        // All four corners rounded — drawer floats above tab bar via .padding(.bottom, 8) in body
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 16, y: -3)
        .gesture(
            DragGesture()
                .onChanged { val in
                    let proposed = drawerHeight - val.translation.height
                    drawerHeight = min(max(proposed, kDrawerPeek), maxDrawer)
                }
                .onEnded { val in
                    let v = val.predictedEndTranslation.height
                    let snaps: [CGFloat] = [kDrawerPeek, kDrawerMedium, maxDrawer]
                    withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) {
                        if v > 180 {
                            drawerHeight = drawerHeight > kDrawerMedium ? kDrawerMedium : kDrawerPeek
                        } else if v < -180 {
                            drawerHeight = drawerHeight < kDrawerMedium ? kDrawerMedium : maxDrawer
                        } else {
                            drawerHeight = snaps.min(by: { abs($0 - drawerHeight) < abs($1 - drawerHeight) }) ?? kDrawerMedium
                        }
                    }
                }
        )
        .onTapGesture {
            if drawerHeight <= kDrawerPeek {
                withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) { drawerHeight = kDrawerMedium }
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption.weight(.medium))
            Spacer()
            Button { withAnimation { showErrorBanner = false; plan.routingError = nil } } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 52)
    }
}

// MARK: - Waypoint Pin

private struct WaypointPin: View {
    let index: Int; let total: Int; let isLoopClosed: Bool; var name: String?
    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(fillColor).frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.white)
            }
            if let name, !name.isEmpty {
                Text(name).font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5)).fixedSize()
            }
        }
    }
    private var fillColor: Color {
        index == 0 ? .green : (index == total - 1 && !isLoopClosed ? .red : Color(.darkGray))
    }
    private var label: String {
        if index == 0 { return isLoopClosed && total > 1 ? "S/E" : "S" }
        if index == total - 1 && !isLoopClosed { return "E" }
        return "\(index + 1)"
    }
}
