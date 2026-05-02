//
//  RideView.swift
//  VeloGPX
//

import SwiftUI
import MapKit
import Charts

// MARK: - View Mode

enum RideViewMode {
    case birdsEye
    case riding
}

struct RideView: View {

    @EnvironmentObject private var routeStore:   RouteStore
    @EnvironmentObject private var rideStore:    RideSessionStore
    @EnvironmentObject private var historyStore: RideHistoryStore

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var poiSpurs: [POISpur] = []
    @State private var suppressNextCameraChange = false
    @State private var hudHeight: CGFloat = 0
    @State private var showNearbySheet    = false
    @State private var showDiscoverySheet = false
    @State private var completedSummary: RideSummary? = nil

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
                    if let coord = rideStore.rideState.currentCoordinate?.clCoordinate {
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
            guard rideStore.rideState.isActive,
                  !rideStore.rideState.isPaused,
                  let coord = newValue?.clCoordinate else { return }
            updateRidingCamera(to: coord)
            Task { poiSpurs = await rideStore.computeSpurs() }
        }
        .onChange(of: rideStore.rideState.nextPOI?.id) { _, _ in
            Task { poiSpurs = await rideStore.computeSpurs() }
        }
        .sheet(item: $completedSummary) { summary in
            RideSummaryView(summary: summary) {
                completedSummary = nil
            }
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

                    VStack(spacing: 6) {
                        Button {
                            rideStore.start(route: route, pois: routeStore.selectedPOIs)
                        } label: {
                            Text("Start Ride")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(Color.white)
                        }

                        if rideStore.rideState.currentCoordinate == nil {
                            Label("Waiting for GPS…", systemImage: "location.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
            POIDiscoverySheet(route: route)
                .environmentObject(routeStore)
        }
    }

    // MARK: - Riding Layout

    private func ridingLayout(route: RouteModel) -> some View {
        ZStack(alignment: .top) {
            mapLayer(route: route, topControlInset: 62)
                .ignoresSafeArea()

            if !rideStore.rideState.rerouteSteps.isEmpty {
                floatingNavBanner
                    .padding(.top, 56)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 0) {
                    if rideStore.rideState.isPaused {
                        pausedBanner
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    chipsRow
                        .padding(.horizontal, 12)
                        .padding(.top, 6)

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
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: rideStore.rideState.rerouteSteps.isEmpty)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: rideStore.rideState.isPaused)
        .sheet(isPresented: $showNearbySheet) {
            if let loc = rideStore.currentLocation {
                NearbySearchSheet(coordinate: loc.coordinate)
                    .environmentObject(routeStore)
            }
        }
    }

    // MARK: - Paused Banner

    private var pausedBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 13))
            Text("Ride Paused")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(formatDuration(rideStore.rideState.movingTime) + " moving")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.orange.opacity(0.15), in: Capsule())
    }

    // MARK: - Floating Nav Banner

    private var floatingNavBanner: some View {
        let steps = rideStore.rideState.rerouteSteps
        let first  = steps.first
        let second = steps.dropFirst().first

        return HStack(spacing: 14) {
            Image(systemName: turnArrowSymbol(for: first?.instructions))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                if let dist = first?.distanceMeters, dist > 0 {
                    Text(formatDistance(dist))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(first?.instructions ?? "Return to route")
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(2)

                if let next = second {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Then: \(next.instructions)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if rideStore.rideState.isRerouting {
                ProgressView()
            } else if steps.count > 1 {
                Text("\(steps.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.secondary, in: Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
    }

    private func turnArrowSymbol(for instruction: String?) -> String {
        guard let instruction = instruction?.lowercased() else { return "arrow.up" }
        if instruction.contains("left")   { return "arrow.turn.up.left" }
        if instruction.contains("right")  { return "arrow.turn.up.right" }
        if instruction.contains("u-turn") || instruction.contains("uturn") { return "arrow.uturn.left" }
        if instruction.contains("arrive") || instruction.contains("destination") { return "checkmark.circle.fill" }
        return "arrow.up"
    }

    // MARK: - Chips Row

    private var chipsRow: some View {
        HStack(spacing: 8) {
            offRouteChip
            nextPOIChip
            Spacer()
            nearbyButton
                .disabled(rideStore.currentLocation == nil)
                .opacity(rideStore.currentLocation == nil ? 0.4 : 1)
            pauseResumeButton
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

    private var pauseResumeButton: some View {
        let isPaused = rideStore.rideState.isPaused
        return Button {
            if isPaused { rideStore.resume() } else { rideStore.pause() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(isPaused ? "Resume" : "Pause")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(isPaused ? Color.green : Color.gray.opacity(0.8), in: Capsule())
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isPaused)
    }

    private var endRideButton: some View {
        Button {
            completedSummary = rideStore.stopAndBuildSummary()
        } label: {
            Text("End")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.red, in: Capsule())
        }
    }

    // MARK: - Metrics HUD

    private func metricsHUD(route: RouteModel) -> some View {
        let s = rideStore.rideState
        let pct = rideStore.progressPercent
        let grade = rideStore.currentGrade
        return VStack(spacing: 6) {
            VStack(spacing: 2) {
                ProgressView(value: pct)
                    .tint(.blue)
                    .animation(.linear(duration: 1), value: pct)
                HStack {
                    Text("Route Progress")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%%", pct * 100))
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)

            HStack(spacing: 0) {
                metricCell(value: formatDistance(s.totalDistance),                label: "Distance")
                Divider().frame(height: 32)
                metricCell(value: formatSpeed(s.speed),                           label: "Speed")
                Divider().frame(height: 32)
                metricCell(value: formatDuration(s.movingTime),                   label: s.isPaused ? "Moving" : "Time")
                Divider().frame(height: 32)
                metricCell(value: formatDistance(remainingDistance(route: route)), label: "Remain")
                Divider().frame(height: 32)
                // Grade tile — colour-coded by severity.
                gradeTile(grade: grade)
            }
        }
    }

    /// Colour-coded gradient tile.
    /// grey  < 2%  — flat
    /// green 2–5%  — gentle climb
    /// amber 5–8%  — moderate
    /// red   > 8%  — steep
    /// Negative grades mirror the same thresholds (descent).
    private func gradeTile(grade: Double) -> some View {
        let abs = abs(grade)
        let color: Color = {
            switch abs {
            case 0..<2:  return .secondary
            case 2..<5:  return .green
            case 5..<8:  return .orange
            default:     return .red
            }
        }()
        let arrow: String = {
            if abs < 0.5 { return "minus" }
            return grade > 0 ? "arrow.up.right" : "arrow.down.right"
        }()
        let valueText = abs < 0.5
            ? "—"
            : String(format: "%+.1f%%", grade)

        return VStack(spacing: 2) {
            HStack(spacing: 2) {
                Image(systemName: arrow)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
                Text(valueText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
            }
            Text("Grade")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.4), value: grade)
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

    @ViewBuilder
    private func mapLayer(route: RouteModel, topControlInset: CGFloat) -> some View {
        Map(position: $position) {
            if let progress = rideStore.routeProgress {
                MapPolyline(coordinates: progress.ridden)
                    .stroke(.white, lineWidth: 7)
                MapPolyline(coordinates: progress.ridden)
                    .stroke(.blue.opacity(0.45), lineWidth: 4)

                MapPolyline(coordinates: progress.remaining)
                    .stroke(.white, lineWidth: 9)
                MapPolyline(coordinates: progress.remaining)
                    .stroke(.blue, lineWidth: 6)
            } else {
                MapPolyline(coordinates: route.trackPoints.map { $0.coordinate.clCoordinate })
                    .stroke(.white, lineWidth: 9)
                MapPolyline(coordinates: route.trackPoints.map { $0.coordinate.clCoordinate })
                    .stroke(.blue, lineWidth: 6)
            }

            if !rideStore.reroutePolyline.isEmpty {
                MapPolyline(coordinates: rideStore.reroutePolyline)
                    .stroke(.white, lineWidth: 8)
                MapPolyline(coordinates: rideStore.reroutePolyline)
                    .stroke(.orange, lineWidth: 5)
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

            if !rideStore.rideState.isActive {
                ForEach(route.waypoints) { waypoint in
                    Annotation(waypoint.name ?? "Waypoint",
                               coordinate: waypoint.coordinate.clCoordinate) {
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
        var latSum = 0.0; var lonSum = 0.0
        for c in coords { latSum += c.latitude; lonSum += c.longitude }
        let center = CLLocationCoordinate2D(latitude: latSum / Double(coords.count),
                                            longitude: lonSum / Double(coords.count))
        let region = MKCoordinateRegion(center: center,
                                        span: MKCoordinateSpan(latitudeDelta: 0.05,
                                                               longitudeDelta: 0.05))
        suppressNextCameraChange = true
        position = .region(region)
    }

    private func updateRidingCamera(to coord: CLLocationCoordinate2D? = nil) {
        let target = coord ?? rideStore.rideState.currentCoordinate?.clCoordinate
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
                .reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    private func formatDistance(_ metres: CLLocationDistance) -> String {
        metres >= 1000
            ? String(format: "%.1f km", metres / 1000)
            : String(format: "%.0f m", metres)
    }

    private func formatSpeed(_ mps: CLLocationSpeed) -> String {
        String(format: "%.1f", max(mps * 3.6, 0))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
