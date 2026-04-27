import SwiftUI
import MapKit
import Charts

// MARK: - View Mode

enum RideViewMode {
    case birdsEye   // pre-ride overview — full route visible, no HUD
    case riding     // active ride — camera follows rider, HUD visible
}

struct RideView: View {

    @EnvironmentObject private var routeStore:   RouteStore
    @EnvironmentObject private var rideStore:    RideSessionStore
    @EnvironmentObject private var historyStore: RideHistoryStore

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var poiSpurs: [POISpur] = []
    @State private var suppressNextCameraChange = false
    @State private var hudHeight: CGFloat = 0
    @State private var showNearbySheet   = false
    @State private var showDiscoverySheet = false
    @State private var scenePhase = ScenePhase.active

    @Environment(\.scenePhase) private var envScenePhase

    var body: some View {
        Group {
            if let route = routeStore.selectedRoute {
                if rideStore.rideState.isActive {
                    ridingLayout(route: route)
                } else {
                    birdsEyeLayout(route: route)
                }
            } else {
                noRouteState
            }
        }
        .onAppear {
            rideStore.prepare()
            rideStore.setHistoryStore(historyStore)
        }
        .onChange(of: rideStore.rideState.isActive) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.4)) {
                    if let coord = rideStore.rideState.currentCoordinate {
                        position = .camera(MapCamera(
                            centerCoordinate: coord,
                            distance: 400,
                            heading: rideStore.rideState.currentHeading,
                            pitch: 60
                        ))
                    }
                }
            }
        }
        .onChange(of: envScenePhase) { _, newPhase in
            if newPhase == .active && rideStore.rideState.isActive {
                updateRidingCamera()
            }
        }
        .onChange(of: rideStore.rideState.currentCoordinate) { _, newValue in
            guard rideStore.rideState.isActive, let coord = newValue else { return }
            updateRidingCamera(to: coord)
            Task { poiSpurs = await rideStore.computeSpurs() }
        }
        .onChange(of: rideStore.rideState.nextPOI?.id) { _, _ in
            Task { poiSpurs = await rideStore.computeSpurs() }
        }
    }

    // MARK: - No Route State

    private var noRouteState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(Color(.systemGray5)).frame(width: 72, height: 72)
                Image(systemName: "map")
                    .font(.system(size: 30)).foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                Text("No Route Selected").font(.title3.bold())
                Text("Go to Routes and pick a route to ride.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Birds Eye Layout

    private func birdsEyeLayout(route: RouteModel) -> some View {
        ZStack(alignment: .bottom) {
            mapLayer(route: route, topControlInset: 0)
                .ignoresSafeArea()

            // Pre-ride bottom card
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(route.name)
                                .font(.headline)
                                .lineLimit(1)
                            HStack(spacing: 10) {
                                Label(String(format: "%.1f km", route.totalDistance / 1000),
                                      systemImage: "arrow.left.and.right")
                                Label(String(format: "%.0f m", route.elevationGain),
                                      systemImage: "mountain.2")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            showDiscoverySheet = true
                        } label: {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 36, height: 36)
                                .background(.tint.opacity(0.12), in: Circle())
                        }
                    }

                    Button {
                        rideStore.startRide(route: route)
                    } label: {
                        Text("Start Ride")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(Color.white)
                    }
                    .disabled(rideStore.rideState.currentCoordinate == nil)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .onAppear {
            fitCameraToRoute(route)
        }
        .sheet(isPresented: $showDiscoverySheet) {
            POIDiscoverySheet()
                .environmentObject(routeStore)
        }
    }

    // MARK: - Riding Layout

    private func ridingLayout(route: RouteModel) -> some View {
        ZStack(alignment: .bottom) {
            mapLayer(route: route, topControlInset: 62)
                .ignoresSafeArea()

            // HUD
            VStack(spacing: 0) {
                // Chips
                chipsRow
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                // Reroute steps
                if !rideStore.rideState.rerouteSteps.isEmpty {
                    rerouteStepsList
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }

                // Metrics
                metricsHUD(route: route)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            hudHeight = geo.size.height
                        }
                    }
                }
            )
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showNearbySheet) {
            NearbySearchSheet()
                .environmentObject(routeStore)
                .environmentObject(rideStore)
        }
    }

    // MARK: - Chips Row

    private var chipsRow: some View {
        HStack(spacing: 8) {
            offRouteChip
            nextPOIChip
            Spacer()
            nearbyButton
            endRideButton
        }
    }

    private var offRouteChip: some View {
        Group {
            if rideStore.rideState.isOffRoute {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Off Route")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(Int(rideStore.rideState.offRouteDistance))m from route")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    if let bearing = rideStore.rideState.bearingToRoute,
                       rideStore.rideState.offRouteDistance <= 200 {
                        let relativeBearing = (bearing - rideStore.rideState.currentHeading + 360)
                            .truncatingRemainder(dividingBy: 360)
                        Image(systemName: "arrow.up")
                            .rotationEffect(.degrees(relativeBearing))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                    if rideStore.rideState.isRerouting {
                        ProgressView().scaleEffect(0.6)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var nextPOIChip: some View {
        Group {
            if let poi = rideStore.rideState.nextPOI,
               let dist = rideStore.rideState.nextPOIDistance,
               dist < 2000 {
                HStack(spacing: 4) {
                    Image(systemName: poi.category.systemImage)
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text(dist < 1000
                         ? "\(Int(dist))m"
                         : String(format: "%.1fkm", dist / 1000))
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var nearbyButton: some View {
        Button { showNearbySheet = true } label: {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(.regularMaterial, in: Circle())
        }
    }

    private var endRideButton: some View {
        Button {
            rideStore.endRide()
        } label: {
            Text("End")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.red, in: Capsule())
        }
    }

    // MARK: - Reroute Steps

    private var rerouteStepsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(
                Array(rideStore.rideState.rerouteSteps.prefix(3).enumerated()),
                id: \.offset
            ) { idx, step in
                HStack(spacing: 6) {
                    Image(systemName: idx == 0 ? "arrow.turn.up.right" : "arrow.right")
                        .font(.system(size: 11))
                        .foregroundStyle(idx == 0 ? .primary : .secondary)
                    Text(step)
                        .font(.system(size: 11))
                        .foregroundStyle(idx == 0 ? .primary : .secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Metrics HUD

    private func metricsHUD(route: RouteModel) -> some View {
        let s = rideStore.rideState
        return HStack(spacing: 0) {
            metricCell(value: formatDistance(s.distanceTravelled),  label: "Distance")
            Divider().frame(height: 32)
            metricCell(value: formatSpeed(s.currentSpeed),          label: "Speed")
            Divider().frame(height: 32)
            metricCell(value: formatDuration(s.elapsedTime),        label: "Time")
            Divider().frame(height: 32)
            metricCell(value: formatDistance(remainingDistance(route: route)), label: "Remain")
        }
    }

    private func metricCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Map
    // topControlInset: pushes the MapKit system controls (MapCompass, MapPitchToggle,
    // MapUserLocationButton) below the status bar when the map is edge-to-edge.
    // riding layout passes 62 pt (status bar ~54 pt + 8 pt gap).
    // birdseye layout passes 0 (map is not full-bleed in that context).

    @ViewBuilder
    private func mapLayer(route: RouteModel, topControlInset: CGFloat) -> some View {
        Map(position: $position) {
            if let progress = rideStore.routeProgress {
                MapPolyline(coordinates: progress.ridden)
                    .stroke(.blue.opacity(0.3), lineWidth: 4)
                MapPolyline(coordinates: progress.remaining)
                    .stroke(.blue, lineWidth: 5)
            } else {
                MapPolyline(coordinates: route.trackPoints.map { $0.coordinate.clCoordinate })
                    .stroke(.blue, lineWidth: 5)
            }

            if !rideStore.reroutePolyline.isEmpty {
                MapPolyline(coordinates: rideStore.reroutePolyline)
                    .stroke(.orange, lineWidth: 4)
            }

            ForEach(poiSpurs) { spur in
                MapPolyline(coordinates: spur.inbound)
                    .stroke(
                        spur.isNext ? Color.green : Color.green.opacity(0.65),
                        style: StrokeStyle(lineWidth: spur.isNext ? 4 : 2.5, dash: [7, 5])
                    )
                MapPolyline(coordinates: spur.outbound)
                    .stroke(
                        spur.isNext ? Color.red : Color.red.opacity(0.5),
                        style: StrokeStyle(lineWidth: spur.isNext ? 3.5 : 2, dash: [7, 5])
                    )
            }

            // Waypoint pins: only show on the pre-ride route preview screen,
            // never during an active ride or in Birds Eye mode.
            // The route polyline is the rider's guide — pin clutter adds nothing.
            if !rideStore.rideState.isActive {
                ForEach(route.waypoints) { waypoint in
                    Annotation(waypoint.name ?? "Waypoint", coordinate: waypoint.coordinate.clCoordinate) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                    }
                }
            }

            ForEach(routeStore.selectedPOIs) { poi in
                let isNext = poi.id == rideStore.rideState.nextPOI?.id
                Annotation(poi.name, coordinate: poi.coordinate.clCoordinate) {
                    ZStack {
                        Circle()
                            .fill(isNext ? Color.green : Color.white)
                            .frame(width: 32, height: 32)
                            .shadow(radius: isNext ? 4 : 2)
                        Image(systemName: poi.category.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isNext ? .white : .orange)
                    }
                }
            }

            // WWDC25: UserAnnotation replaces the manual blue dot Annotation.
            // Provides system pulsing blue dot, accuracy ring, and participates
            // in the improved iOS 26 location rendering pipeline.
            UserAnnotation()
        }
        .onMapCameraChange(frequency: .onEnd) { _ in
            if suppressNextCameraChange {
                suppressNextCameraChange = false
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
                .mapControlVisibility(.visible)
            MapPitchToggle()
        }
        .safeAreaPadding(.top, topControlInset)
    }

    // MARK: - Camera Helpers

    private func fitCameraToRoute(_ route: RouteModel) {
        let coords = route.trackPoints.map { $0.coordinate.clCoordinate }
        guard !coords.isEmpty else { return }
        let region = MKCoordinateRegion(
            center: coords.reduce(CLLocationCoordinate2D(latitude: 0, longitude: 0)) {
                CLLocationCoordinate2D(
                    latitude: $0.latitude + $1.latitude / Double(coords.count),
                    longitude: $0.longitude + $1.longitude / Double(coords.count)
                )
            },
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        suppressNextCameraChange = true
        position = .region(region)
    }

    private func updateRidingCamera(to coord: CLLocationCoordinate2D? = nil) {
        let target = coord ?? rideStore.rideState.currentCoordinate
        guard let c = target else { return }
        suppressNextCameraChange = true
        withAnimation(.linear(duration: 1.0)) {
            position = .camera(MapCamera(
                centerCoordinate: c,
                distance: 400,
                heading: rideStore.rideState.currentHeading,
                pitch: 60
            ))
        }
    }

    // MARK: - Formatters

    private func remainingDistance(route: RouteModel) -> CLLocationDistance {
        guard let progress = rideStore.routeProgress else { return route.totalDistance }
        return progress.remaining.isEmpty ? 0 :
            zip(progress.remaining, progress.remaining.dropFirst())
                .reduce(0) { $0 + $1.0.distance(from: $1.1) }
    }

    private func formatDistance(_ metres: CLLocationDistance) -> String {
        metres >= 1000
            ? String(format: "%.1f km", metres / 1000)
            : String(format: "%.0f m", metres)
    }

    private func formatSpeed(_ mps: CLLocationSpeed) -> String {
        let kmh = max(mps * 3.6, 0)
        return String(format: "%.1f", kmh)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
