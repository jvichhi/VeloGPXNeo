import SwiftUI
import MapKit
import Charts

// MARK: - View Mode
enum RideViewMode { case birdseye, riding }

// MARK: - Elevation Sample
private struct ElevSample: Identifiable {
    let id = UUID()
    let distance: Double
    let elevation: Double
}

// MARK: - POI Spur
private struct POISpur: Identifiable {
    let id: UUID
    let inbound: [CLLocationCoordinate2D]
    let outbound: [CLLocationCoordinate2D]
    let isNext: Bool
}

// MARK: - Candidate route result
private struct CandidateRoute {
    let coordinates: [CLLocationCoordinate2D]
    let distance: CLLocationDistance
}

// MARK: - TimeInterval helper
private extension TimeInterval {
    var formattedDuration: String {
        let h = Int(self) / 3600
        let m = (Int(self) % 3600) / 60
        let s = Int(self) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - RouteModel mapRect
private extension RouteModel {
    var mapRect: MKMapRect {
        let coords = trackPoints.map { $0.coordinate.clCoordinate }
        guard let first = coords.first else { return .world }
        return coords.dropFirst().reduce(
            MKMapRect(origin: MKMapPoint(first), size: MKMapSize(width: 1, height: 1))
        ) { rect, coord in
            rect.union(MKMapRect(origin: MKMapPoint(coord), size: MKMapSize(width: 1, height: 1)))
        }
    }
}

// MARK: - RideView
struct RideView: View {
    @EnvironmentObject private var routeStore: RouteStore
    @StateObject private var rideStore = RideSessionStore()
    @EnvironmentObject private var historyStore: RideHistoryStore
    @State private var position: MapCameraPosition = .automatic
    @State private var viewMode: RideViewMode = .birdseye
    @State private var showNearbySearch = false
    @State private var poiSpurs: [POISpur] = []
    @State private var lastSpurRefreshLocation: CLLocationCoordinate2D?
    @State private var isFollowing: Bool = true
    @State private var suppressNextCameraChange: Bool = false
    @State private var rideSummary: RideSummary? = nil
    @State private var showRideSummary = false
    @State private var statsExpanded: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if let route = routeStore.selectedRoute {
                    if viewMode == .riding {
                        ridingLayout(route: route)
                    } else {
                        birdsEyeLayout(route: route)
                    }
                } else {
                    ContentUnavailableView(
                        "Select a route",
                        systemImage: "bicycle",
                        description: Text("Import or choose a GPX route from your library.")
                    )
                }
            }
            .ignoresSafeArea(edges: .top)
            .sheet(isPresented: $showNearbySearch) {
                if let coord = rideStore.rideState.currentCoordinate {
                    NearbySearchSheet(coordinate: coord.clCoordinate)
                        .onDisappear {
                            rideStore.updatePOIs(routeStore.selectedPOIs)
                            routeStore.savePOIs()
                            if let route = routeStore.selectedRoute {
                                Task { await computePOISpurs(route: route) }
                            }
                        }
                }
            }
            .fullScreenCover(isPresented: $showRideSummary) {
                if let summary = rideSummary {
                    RideSummaryView(summary: summary) {
                        showRideSummary = false
                        rideSummary = nil
                    }
                }
            }
            .onAppear {
                rideStore.prepare()
                if let route = routeStore.selectedRoute {
                    position = .rect(route.mapRect)
                    Task { await computePOISpurs(route: route) }
                }
            }
            .onAppear {
                rideStore.setHistoryStore(historyStore)
            }
            .onChange(of: routeStore.selectedPOIs) { _, _ in
                if let route = routeStore.selectedRoute {
                    Task { await computePOISpurs(route: route) }
                }
            }
            .onChange(of: rideStore.rideState.nextPOI?.id) { _, _ in
                if let route = routeStore.selectedRoute {
                    Task { await computePOISpurs(route: route) }
                }
            }
            .onChange(of: rideStore.rideState.isActive) { _, newValue in
                withAnimation(.spring(duration: 0.4)) {
                    viewMode = newValue ? .riding : .birdseye
                    statsExpanded = false
                }
                isFollowing = true
                if newValue, let coord = rideStore.rideState.currentCoordinate {
                    updateRidingCamera(coord: coord.clCoordinate)
                } else if let route = routeStore.selectedRoute {
                    position = .rect(route.mapRect)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active && rideStore.rideState.isActive {
                    UIApplication.shared.isIdleTimerDisabled = true
                } else if newPhase != .active {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            }
            .onChange(of: rideStore.rideState.currentCoordinate) { _, newValue in
                guard viewMode == .riding, let newValue else { return }
                updateRidingCamera(coord: newValue.clCoordinate)
                if let route = routeStore.selectedRoute,
                   shouldRefreshSpurs(for: newValue.clCoordinate) {
                    Task { await computePOISpurs(route: route) }
                }
            }
        }
    }

    // MARK: - Bird's Eye Layout

    @ViewBuilder
    private func birdsEyeLayout(route: RouteModel) -> some View {
        ZStack(alignment: .bottom) {
            mapLayer(route: route)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                Capsule()
                    .fill(Color(.systemFill))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(route.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(String(format: "%.1f km", route.totalDistance / 1000))  \u{00B7}  \u{2191}\(String(format: "%.0f m", route.elevationGain))  \u{2193}\(String(format: "%.0f m", route.elevationLoss))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "bicycle")
                        .font(.system(size: 22))
                        .foregroundStyle(.blue)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 8)

                Divider().padding(.horizontal, 20)

                elevationStrip(route: route)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                Button {
                    rideStore.start(route: route, pois: routeStore.selectedPOIs)
                } label: {
                    Label("Start Ride", systemImage: "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)

                Button("Center Map") { position = .rect(route.mapRect) }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 20)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: -4)
        }
    }

    // MARK: - Riding Layout

    @ViewBuilder
    private func ridingLayout(route: RouteModel) -> some View {
        ZStack(alignment: .bottom) {
            mapLayer(route: route)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 8) {
                topBanners
                    .padding(.top, 56)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)

            if !isFollowing {
                HStack {
                    Spacer()
                    Button {
                        if let coord = rideStore.rideState.currentCoordinate {
                            updateRidingCamera(coord: coord.clCoordinate)
                        }
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.blue)
                            .padding(13)
                            .background(.ultraThickMaterial, in: Circle())
                            .shadow(radius: 6)
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, statsExpanded ? 310 : 210)
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: isFollowing)
            }

            HStack(spacing: 12) {
                Button {
                    showNearbySearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(.ultraThickMaterial, in: Circle())
                        .shadow(radius: 4)
                }
                .disabled(rideStore.rideState.currentCoordinate == nil)

                Spacer()

                Button {
                    if let summary = rideStore.stopAndBuildSummary() {
                        rideSummary = summary
                        showRideSummary = true
                    } else {
                        rideStore.stop()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(Color.red, in: Capsule())
                    .shadow(radius: 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, statsExpanded ? 302 : 202)
            .animation(.spring(duration: 0.35), value: statsExpanded)

            ridingHUDPanel(route: route)
        }
        .animation(.spring(duration: 0.3), value: isFollowing)
    }

    // MARK: - Riding HUD Panel

    @ViewBuilder
    private func ridingHUDPanel(route: RouteModel) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.35)) {
                    statsExpanded.toggle()
                }
            } label: {
                VStack(spacing: 6) {
                    Capsule()
                        .fill(Color(.systemFill))
                        .frame(width: 36, height: 4)
                    Image(systemName: statsExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 10)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            if !rideStore.rideState.rerouteSteps.isEmpty {
                rerouteStepsList
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            primaryMetricsRow

            if statsExpanded {
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                expandedStatsGrid
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                elevationStrip(route: route)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: -6)
    }

    // MARK: - Primary Metrics Row

    @ViewBuilder
    private var primaryMetricsRow: some View {
        let s = rideStore.rideState
        HStack(spacing: 0) {
            VStack(spacing: 1) {
                Text("SPEED")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(String(format: "%.1f", s.speedKmh))
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.blue)
                    Text("km/h")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)

            Divider().frame(height: 48)

            VStack(spacing: 1) {
                Text("DISTANCE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(String(format: "%.2f", s.distanceKm))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("km")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)

            Divider().frame(height: 48)

            VStack(spacing: 1) {
                Text("TIME")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                Text(s.elapsedTime.formattedDuration)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)

            Divider().frame(height: 48)

            VStack(spacing: 1) {
                Text("ROUTE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.18), lineWidth: 4)
                        .frame(width: 34, height: 34)
                    Circle()
                        .trim(from: 0, to: rideStore.progressPercent)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 34, height: 34)
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(rideStore.progressPercent * 100))%")
                        .font(.system(size: 9, weight: .bold))
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Expanded Stats Grid

    @ViewBuilder
    private var expandedStatsGrid: some View {
        let s = rideStore.rideState
        HStack(spacing: 0) {
            compactStat("AVG SPEED", String(format: "%.1f", s.avgSpeedKmh), unit: "km/h")
            Divider().frame(height: 36)
            compactStat("ELEV GAIN", String(format: "%.0f", s.elevationGain), unit: "m", icon: "arrow.up.right")
            Divider().frame(height: 36)
            compactStat("ELEV LOSS", String(format: "%.0f", s.elevationLoss), unit: "m", icon: "arrow.down.right")
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func compactStat(_ label: String, _ value: String, unit: String, icon: String? = nil) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
            }
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: - Map

    @ViewBuilder
    private func mapLayer(route: RouteModel) -> some View {
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

            ForEach(route.waypoints) { waypoint in
                Annotation(waypoint.name ?? "Waypoint", coordinate: waypoint.coordinate.clCoordinate) {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
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

            if let coord = rideStore.rideState.currentCoordinate {
                Annotation("You", coordinate: coord.clCoordinate) {
                    ZStack {
                        Circle().fill(.white).frame(width: 24, height: 24).shadow(radius: 3)
                        Circle().fill(.blue).frame(width: 14, height: 14)
                    }
                }
            }
        }
        .onMapCameraChange(frequency: .onEnd) { _ in
            if suppressNextCameraChange {
                suppressNextCameraChange = false
            } else if viewMode == .riding {
                isFollowing = false
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapPitchToggle()
            MapUserLocationButton()
        }
    }

    // MARK: - Top Banners

    @ViewBuilder
    private var topBanners: some View {
        VStack(spacing: 8) {
            if rideStore.rideState.isOffRoute {
                offRouteBanner
            }
            if let poi = rideStore.rideState.nextPOI,
               let dist = rideStore.rideState.nextPOIDistance,
               dist <= 2000 {
                nextPOIBanner(poi: poi, distance: dist)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .animation(.spring(duration: 0.3), value: rideStore.rideState.isOffRoute)
        .animation(.spring(duration: 0.3), value: rideStore.rideState.nextPOI?.id)
    }

    // MARK: - Off Route Banner

    @ViewBuilder
    private var offRouteBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 1) {
                Text("Off Route")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(Int(rideStore.rideState.offRouteDistance))m from route")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            if let bearing = rideStore.rideState.bearingToRoute,
               rideStore.rideState.offRouteDistance <= 200 {
                let relativeBearing = (bearing - rideStore.rideState.currentHeading + 360)
                    .truncatingRemainder(dividingBy: 360)
                Image(systemName: "arrow.up")
                    .rotationEffect(.degrees(relativeBearing))
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
            }

            if rideStore.rideState.isRerouting {
                ProgressView().tint(.white).scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.red, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .red.opacity(0.4), radius: 8, x: 0, y: 3)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Next POI Banner

    @ViewBuilder
    private func nextPOIBanner(poi: POIModel, distance: CLLocationDistance) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.18))
                    .frame(width: 42, height: 42)
                Image(systemName: poi.category.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(poi.name)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(distance < 1000
                         ? "\(Int(distance))m ahead"
                         : String(format: "%.1f km ahead", distance / 1000))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }

    // MARK: - Re-route Steps

    @ViewBuilder
    private var rerouteStepsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Back to route", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(rideStore.rideState.rerouteSteps.prefix(3), id: \.instructions) { step in
                HStack {
                    Text(step.instructions).font(.caption).foregroundStyle(.primary)
                    Spacer()
                    Text("\(Int(step.distanceMeters))m").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Elevation Strip

    @ViewBuilder
    private func elevationStrip(route: RouteModel) -> some View {
        let samples = buildElevationSamples(route: route)
        let progress = rideStore.progressPercent
        if !samples.isEmpty {
            Chart {
                ForEach(samples) { s in
                    AreaMark(x: .value("km", s.distance), y: .value("m", s.elevation))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue.opacity(0.35), .blue.opacity(0.05)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    LineMark(x: .value("km", s.distance), y: .value("m", s.elevation))
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                if let maxDist = samples.last?.distance {
                    RuleMark(x: .value("pos", maxDist * progress))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4]))
                        .foregroundStyle(.orange)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 52)
        }
    }

    // MARK: - Camera

    private func updateRidingCamera(coord: CLLocationCoordinate2D) {
        let heading = rideStore.rideState.currentHeading
        suppressNextCameraChange = true
        isFollowing = true
        position = .camera(MapCamera(
            centerCoordinate: coord,
            distance: 400,
            heading: heading,
            pitch: 45
        ))
    }

    // MARK: - POI Spur Computation

    private func computePOISpurs(route: RouteModel) async {
        let pois = routeStore.selectedPOIs
        guard !pois.isEmpty else { poiSpurs = []; return }

        let routeCoords: [CLLocationCoordinate2D] = {
            if let remaining = rideStore.routeProgress?.remaining, !remaining.isEmpty {
                return remaining
            }
            return route.trackPoints.map { $0.coordinate.clCoordinate }
        }()

        let nextPOIID = rideStore.rideState.nextPOI?.id

        let inboundOrigin: (POIModel) -> CLLocationCoordinate2D = { poi in
            if let current = rideStore.rideState.currentCoordinate {
                return current.clCoordinate
            }
            return geometricNearest(in: routeCoords, to: poi.coordinate.clCoordinate)
        }

        var spurs: [POISpur] = []
        await withTaskGroup(of: POISpur?.self) { group in
            for poi in pois {
                let origin   = inboundOrigin(poi)
                let poiCoord = poi.coordinate.clCoordinate
                group.addTask {
                    async let inCoords  = fetchSpurCoordinates(from: origin,   to: poiCoord)
                    async let outResult = shortestRouteBackToGPX(from: poiCoord, routeCoords: routeCoords)
                    return POISpur(
                        id: poi.id,
                        inbound:  await inCoords,
                        outbound: await outResult,
                        isNext: poi.id == nextPOIID
                    )
                }
            }
            for await result in group {
                if let spur = result { spurs.append(spur) }
            }
        }
        poiSpurs = spurs.sorted { !$0.isNext && $1.isNext }
    }

    private func shortestRouteBackToGPX(
        from poiCoord: CLLocationCoordinate2D,
        routeCoords: [CLLocationCoordinate2D],
        candidateCount: Int = 5
    ) async -> [CLLocationCoordinate2D] {
        guard !routeCoords.isEmpty else { return [poiCoord] }
        let subsampledCoords = subsample(routeCoords, maxPoints: 200)
        let candidates = subsampledCoords
            .sorted { $0.distance(to: poiCoord) < $1.distance(to: poiCoord) }
            .prefix(candidateCount)

        let results: [CandidateRoute] = await withTaskGroup(of: CandidateRoute?.self) { group in
            for candidate in candidates {
                group.addTask {
                    let request = MKDirections.Request()
                    request.source      = MKMapItem(placemark: MKPlacemark(coordinate: poiCoord))
                    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: candidate))
                    request.transportType = .walking
                    request.requestsAlternateRoutes = false
                    do {
                        let response = try await MKDirections(request: request).calculate()
                        if let route = response.routes.first {
                            return CandidateRoute(coordinates: route.polyline.coordinates, distance: route.distance)
                        }
                    } catch { }
                    return CandidateRoute(coordinates: [poiCoord, candidate], distance: poiCoord.distance(to: candidate))
                }
            }
            var collected: [CandidateRoute] = []
            for await r in group {
                if let r { collected.append(r) }
            }
            return collected
        }
        return results.min(by: { $0.distance < $1.distance })?.coordinates ?? [poiCoord]
    }

    private func geometricNearest(
        in polyline: [CLLocationCoordinate2D],
        to target: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        polyline.min(by: { $0.distance(to: target) < $1.distance(to: target) }) ?? target
    }

    private func subsample(_ coords: [CLLocationCoordinate2D], maxPoints: Int) -> [CLLocationCoordinate2D] {
        guard coords.count > maxPoints else { return coords }
        let stride = coords.count / maxPoints
        return coords.enumerated().filter { $0.offset % stride == 0 }.map { $0.element }
    }

    private func fetchSpurCoordinates(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async -> [CLLocationCoordinate2D] {
        let request = MKDirections.Request()
        request.source      = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .walking
        request.requestsAlternateRoutes = false
        do {
            let response = try await MKDirections(request: request).calculate()
            return response.routes.first?.polyline.coordinates ?? [from, to]
        } catch {
            return [from, to]
        }
    }

    private func shouldRefreshSpurs(for coord: CLLocationCoordinate2D) -> Bool {
        guard let last = lastSpurRefreshLocation else {
            lastSpurRefreshLocation = coord
            return true
        }
        if coord.distance(to: last) > 100 {
            lastSpurRefreshLocation = coord
            return true
        }
        return false
    }

    private func buildElevationSamples(route: RouteModel) -> [ElevSample] {
        var samples: [ElevSample] = []
        var cumulative = 0.0
        let points = route.trackPoints
        for (i, point) in points.enumerated() {
            guard let ele = point.elevation else { continue }
            if i > 0 {
                cumulative += point.coordinate.clCoordinate.distance(to: points[i-1].coordinate.clCoordinate)
            }
            samples.append(ElevSample(distance: cumulative / 1000, elevation: ele))
        }
        if samples.count > 200 {
            let stride = samples.count / 200
            samples = samples.enumerated().filter { $0.offset % stride == 0 }.map { $0.element }
        }
        return samples
    }
}
