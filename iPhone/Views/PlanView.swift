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
    @State private var showAssistant = false
    /// Last known map centre — updated via onMapCameraChange.
    @State private var mapCentre: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 45.5017, longitude: -73.5673)

    // MARK: Inline draw mode (F-D overhaul)
    @State private var drawEngine = DrawRouteEngine()
    @State private var isDrawModeActive: Bool = false
    @State private var isDrawDone: Bool = false
    private let drawHaptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {

                mapLayer(geo: geo)
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                mapControlsOverlay(geo: geo)
                    .zIndex(5)

                if showErrorBanner, let err = plan.routingError {
                    errorBanner(message: err)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 56)
                        .zIndex(20)
                }

                // Draw mode snap-error toast
                if let snapErr = drawEngine.lastSnapError {
                    snapErrorToast(snapErr)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 56)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(20)
                        .onAppear {
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                drawEngine.clearSnapError()
                            }
                        }
                }

                if isDrawModeActive {
                    drawBottomBar(geo: geo)
                        .zIndex(10)
                } else {
                    drawerCard(geo: geo)
                        .padding(.bottom, 8)
                        .zIndex(10)
                }
            }
        }
        .animation(.spring(duration: 0.28), value: isDrawModeActive)
        .animation(.spring(duration: 0.3), value: drawEngine.lastSnapError)
        .task {
            let routeToLoad = routeStore.routeToEditInPlan ?? preloadRoute
            if let route = routeToLoad {
                plan.loadFrom(route: route)
                routeStore.routeToEditInPlan = nil
                await engine.recomputeAll(in: plan)
                withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) {
                    drawerHeight = kDrawerMedium
                }
            }
        }
        .onChange(of: routeStore.routeToEditInPlan) { _, route in
            guard let route else { return }
            Task {
                plan.loadFrom(route: route)
                routeStore.routeToEditInPlan = nil
                await engine.recomputeAll(in: plan)
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
        .sheet(isPresented: $showAssistant) {
            RidePlanAssistantView(
                plan: plan,
                nearLat: mapCentre.latitude,
                nearLon: mapCentre.longitude
            )
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

            // F-D inline draw toggle
            Button {
                withAnimation(.spring(duration: 0.25)) {
                    isDrawModeActive.toggle()
                    if !isDrawModeActive { drawEngine.reset() }
                }
                drawHaptic.impactOccurred()
            } label: {
                Image(systemName: isDrawModeActive ? "pencil.circle.fill" : "pencil.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isDrawModeActive ? Color.blue : Color.primary)
                    .frame(width: 42, height: 42)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            }
            .accessibilityLabel(isDrawModeActive ? "Exit draw mode" : "Enter draw mode")
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
                // Waypoint planning polyline
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

                // F-D inline draw polylines
                if drawEngine.allSnappedCoordinates.count >= 2 {
                    MapPolyline(coordinates: drawEngine.allSnappedCoordinates)
                        .stroke(.teal, lineWidth: 4)
                }
                if drawEngine.pendingCoordinates.count >= 2 {
                    MapPolyline(coordinates: drawEngine.pendingCoordinates)
                        .stroke(
                            .teal.opacity(drawEngine.isSnapping ? 0.4 : 0.65),
                            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                        )
                }

                UserAnnotation()
            }
            .mapStyle(isPitchEnabled
                ? .standard(elevation: .realistic)
                : .standard(elevation: .flat)
            )
            .mapControlVisibility(.hidden)
            .onMapCameraChange { context in
                mapCentre = context.camera.centerCoordinate
            }
            // Tap-to-waypoint: disabled in draw mode
            .onTapGesture { screenPoint in
                guard !isDrawModeActive else { return }
                guard let coord = proxy.convert(screenPoint, from: .local) else { return }
                let before = plan.waypoints.count
                plan.addWaypoint(coord)
                if before >= 1 {
                    Task { await engine.refreshSegments(in: plan, affectedWaypointIndices: [before]) }
                }
            }
            // F-D: draw gesture overlay — only active in draw mode
            .overlay {
                if isDrawModeActive {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 2, coordinateSpace: .local)
                                .onChanged { value in
                                    guard let coord = proxy.convert(value.location, from: .local) else { return }
                                    drawEngine.addGesturePoint(lat: coord.latitude, lon: coord.longitude)
                                }
                                .onEnded { _ in
                                    Task { await drawEngine.finaliseStroke() }
                                }
                        )
                }
            }
        }
    }

    // MARK: - Draw mode bottom bar

    private func drawBottomBar(geo: GeometryProxy) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .bold))
                Text("Draw Mode — drag to trace your route")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.teal.opacity(0.88), in: Capsule())

            HStack(spacing: 12) {
                if drawEngine.hasContent {
                    Label(
                        String(format: "%.1f km", drawEngine.totalDistance / 1000),
                        systemImage: "arrow.left.and.right"
                    )
                    .font(.subheadline.weight(.semibold))

                    Divider().frame(height: 14)

                    Label(
                        String(format: "%.0f m", drawEngine.totalElevationGain),
                        systemImage: "mountain.2"
                    )
                    .font(.subheadline.weight(.semibold))

                    if drawEngine.isSnapping {
                        Divider().frame(height: 14)
                        ProgressView().controlSize(.mini).tint(.secondary)
                    }

                    Spacer()
                } else {
                    Text("Lift finger to snap each stroke")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Button {
                    drawEngine.undoLastSegment()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(.regularMaterial, in: Circle())
                }
                .disabled(!drawEngine.canUndo)
                .accessibilityLabel("Undo last segment")

                Button {
                    guard !isDrawDone else { return }
                    isDrawDone = true
                    Task {
                        await drawEngine.finaliseStroke()
                        await commitDrawnRoute()
                        isDrawDone = false
                    }
                } label: {
                    ZStack {
                        if isDrawDone {
                            ProgressView().tint(.white)
                        } else {
                            Text("Done")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .frame(width: 72)
                    .padding(.vertical, 10)
                    .background(
                        drawEngine.segments.isEmpty ? Color(.systemGray4) : Color.teal,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .foregroundStyle(.white)
                }
                .disabled(drawEngine.segments.isEmpty || isDrawDone)
                .accessibilityLabel("Finish and save drawn route")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
            .padding(.horizontal, 16)
        }
        .padding(.bottom, geo.safeAreaInsets.bottom > 0 ? geo.safeAreaInsets.bottom : 16)
    }

    // MARK: - Commit drawn route

    @MainActor
    private func commitDrawnRoute() async {
        let coords = drawEngine.allSnappedCoordinates
        guard coords.count >= 2 else { return }
        let trackPoints = coords.map { TrackPoint(coordinate: $0, elevation: nil, timestamp: nil) }
        let route = RouteModel(
            name: "Drawn Route",
            sourceFormat: .drawn,
            trackPoints: trackPoints
        )
        routeStore.addAIPlannedRoute(route)
        drawEngine.reset()
        withAnimation(.spring(duration: 0.25)) { isDrawModeActive = false }
    }

    // MARK: - Snap error toast

    private func snapErrorToast(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }

    // MARK: - Drawer

    private func drawerCard(geo: GeometryProxy) -> some View {
        let maxDrawer = geo.size.height - 60
        let safeBottom = geo.safeAreaInsets.bottom
        let isCollapsed = drawerHeight <= kDrawerPeek

        return VStack(spacing: 0) {
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
                },
                showAssistant: $showAssistant,
                onDrawRoute: {
                    withAnimation(.spring(duration: 0.25)) { isDrawModeActive = true }
                    drawHaptic.impactOccurred()
                }
            )
            .padding(.bottom, safeBottom > 0 ? safeBottom : 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: min(drawerHeight, maxDrawer))
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
