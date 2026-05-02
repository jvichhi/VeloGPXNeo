//
//  PlanView.swift
//  VeloGPX
//

import SwiftUI
import MapKit
import CoreLocation

private let kDrawerPeek:   CGFloat = 72
private let kDrawerMedium: CGFloat = 320

struct PlanView: View {

    @StateObject private var plan = PlanState()
    private let engine = PlanRouteEngine()

    @EnvironmentObject private var routeStore: RouteStore

    var switchToRide: () -> Void = {}
    var switchToRoutes: () -> Void = {}
    // preloadRoute is kept for direct instantiation (e.g. tests, previews).
    // In production the tab flow uses routeStore.routeToEditInPlan instead.
    var preloadRoute: RouteModel? = nil

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var drawerHeight: CGFloat = kDrawerMedium
    @State private var showErrorBanner = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {

                // Map fills entire screen — bleeds behind status bar AND tab bar.
                // .ignoresSafeArea() is on the map layer only so the ZStack
                // still respects the tab bar safe area; the drawer therefore
                // stops naturally above the tab bar without extra math.
                mapLayer
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Floating error banner
                if showErrorBanner, let err = plan.routingError {
                    errorBanner(message: err)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 56)
                        .zIndex(20)
                }

                // Floating drawer — .regularMaterial = semi-transparent
                drawerCard(geo: geo)
                    .zIndex(10)
            }
            // ZStack intentionally does NOT have .ignoresSafeArea(edges: .bottom).
            // Removing it is what keeps the drawer above the tab bar.
        }
        .task {
            // Prefer the store-driven deep-link route; fall back to the
            // direct preloadRoute param (tests / previews).
            let routeToLoad = routeStore.routeToEditInPlan ?? preloadRoute
            if let route = routeToLoad {
                await plan.loadFrom(route: route)
                // Clear the pending edit request so re-appearing the tab
                // later doesn't reload the same route unexpectedly.
                routeStore.routeToEditInPlan = nil
                withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) {
                    drawerHeight = kDrawerMedium
                }
            }
        }
        // Respond to a new routeToEditInPlan set while PlanView is already
        // on screen (tab was already active, user swipes Plan on a second route).
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

    // MARK: - Drawer

    private func drawerCard(geo: GeometryProxy) -> some View {
        // After removing .ignoresSafeArea from the ZStack, geo.size.height
        // is the safe-area height (tab bar excluded), so maxDrawer no longer
        // needs a safeBottom offset — just subtract 60 to leave a map peek.
        let maxDrawer = geo.size.height - 60

        // safeBottom is now 0 inside the safe area; the existing conditional
        // falls through to the 16pt content margin automatically.
        let safeBottom = geo.safeAreaInsets.bottom

        return VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 2)

            WaypointListSheet(
                plan: plan,
                engine: engine,
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
        .background(.regularMaterial, in: RoundedCorners(tl: 20, tr: 20, bl: 0, br: 0))
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

                // Once the route line is computed, suppress intermediate waypoint pins.
                // Only keep Start (index 0) and End (last) so the map stays uncluttered.
                // When no route exists yet (just dropped pins), show all pins to aid placement.
                let routeExists = !plan.routePolyline.isEmpty
                ForEach(Array(plan.waypoints.enumerated()), id: \.element.id) { index, wp in
                    let isStartOrEnd = index == 0 || index == plan.waypoints.count - 1
                    if !routeExists || isStartOrEnd {
                        Annotation("", coordinate: wp.coordinate, anchor: .bottom) {
                            WaypointPin(index: index, total: plan.waypoints.count,
                                        isLoopClosed: plan.isLoopClosed, name: wp.name)
                        }
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
                let before = plan.waypoints.count
                plan.addWaypoint(coord)
                if before >= 1 {
                    Task { await engine.refreshSegments(in: plan, affectedWaypointIndices: [before]) }
                }
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

// MARK: - Top-only rounded corners

private struct RoundedCorners: Shape {
    var tl: CGFloat; var tr: CGFloat; var bl: CGFloat; var br: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tl, y: rect.minY),
                       control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tr),
                       control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - br, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
