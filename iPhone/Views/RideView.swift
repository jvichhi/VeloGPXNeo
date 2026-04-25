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
// inbound  = you → POI           (green dashed)
// outbound = POI → GPX route     (red dashed, shortest real-road route)
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
    @State private var position: MapCameraPosition = .automatic
    @State private var viewMode: RideViewMode = .birdseye
    @State private var showNearbySearch = false
    @State private var poiSpurs: [POISpur] = []
    @State private var lastSpurRefreshLocation: CLLocationCoordinate2D?
    @State private var isFollowing: Bool = true
    @State private var suppressNextCameraChange: Bool = false
    @State private var rideSummary: RideSummary? = nil
    @State private var showRideSummary = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let route = routeStore.selectedRoute {
                    ZStack(alignment: .top) {
                        mapLayer(route: route)
                        topBanners

                        // Re-center button — bottom trailing, only when user has panned away
                        if viewMode == .riding && !isFollowing {
                            VStack {
                                Spacer()
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
                                            .padding(14)
                                            .background(.thinMaterial, in: Circle())
                                            .shadow(radius: 4)
                                    }
                                    .padding(.trailing, 16)
                                    .padding(.bottom, 16)
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                    }
                    .animation(.spring(duration: 0.3), value: isFollowing)
                    .frame(maxHeight: viewMode == .riding ? .infinity : 320)

                    if viewMode == .riding {
                        ridingHUD(route: route)
                    } else {
                        birdsEyeHUD(route: route)
                    }
                } else {
                    ContentUnavailableView(
                        "Select a route",
                        systemImage: "bicycle",
                        description: Text("Import or choose a GPX route from your library.")
                    )
                }
            }
            .navigationTitle(viewMode == .riding ? "Riding" : "Route Overview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewMode == .riding {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showNearbySearch = true } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .disabled(rideStore.rideState.currentCoordinate == nil)
                    }
                }
            }
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

    // MARK: - POI Spur Computation

    private func computePOISpurs(route: RouteModel) async {
        let pois = routeStore.selectedPOIs
        guard !pois.isEmpty else { poiSpurs = []; return }

        // Prefer remaining route coords (ahead of rider) if riding, else full route
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

    // MARK: - Shortest Road Route Back to GPX

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

    // MARK: - Helpers

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

    // MARK: - Map

    @ViewBuilder
    private func mapLayer(route: RouteModel) -> some View {
        Map(position: $position) {

            // ── Main GPX route ───────────────────────────────────────────
            if let progress = rideStore.routeProgress {
                MapPolyline(coordinates: progress.ridden)
                    .stroke(.blue.opacity(0.3), lineWidth: 4)
                MapPolyline(coordinates: progress.remaining)
                    .stroke(.blue, lineWidth: 5)
            } else {
                MapPolyline(coordinates: route.trackPoints.map { $0.coordinate.clCoordinate })
                    .stroke(.blue, lineWidth: 5)
            }

            // ── Off-route turn-by-turn reroute (solid orange) ────────────
            if !rideStore.reroutePolyline.isEmpty {
                MapPolyline(coordinates: rideStore.reroutePolyline)
                    .stroke(.orange, lineWidth: 4)
            }

            // ── POI spurs ────────────────────────────────────────────────
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

            // ── Waypoints ────────────────────────────────────────────────
            ForEach(route.waypoints) { waypoint in
                Annotation(waypoint.name ?? "Waypoint", coordinate: waypoint.coordinate.clCoordinate) {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                }
            }

            // ── POI pins ─────────────────────────────────────────────────
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

            // ── Current position ─────────────────────────────────────────
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
                NextPOIBanner(item: makeMapItem(from: poi), distance: dist)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
        .animation(.spring(duration: 0.3), value: rideStore.rideState.isOffRoute)
        .animation(.spring(duration: 0.3), value: rideStore.rideState.nextPOI?.id)
    }

    private func makeMapItem(from poi: POIModel) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: poi.coordinate.clCoordinate))
        item.name = poi.name
        return item
    }

    // MARK: - Off Route Banner

    @ViewBuilder
    private var offRouteBanner: some View {
        HStack(spacing: 8) {
            Label(
                "Off Route \(Int(rideStore.rideState.offRouteDistance))m",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)

            if let bearing = rideStore.rideState.bearingToRoute,
               rideStore.rideState.offRouteDistance <= 200 {
                let relativeBearing = (bearing - rideStore.rideState.currentHeading + 360)
                    .truncatingRemainder(dividingBy: 360)
                Image(systemName: "arrow.up")
                    .rotationEffect(.degrees(relativeBearing))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }

            if rideStore.rideState.isRerouting {
                ProgressView().tint(.white).scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.red, in: Capsule())
        .transition(.move(edge: .top).combined(with: .opacity))
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
        .background(.orange.opacity(0.12))
    }

    // MARK: - Bird's Eye HUD

    @ViewBuilder
    private func birdsEyeHUD(route: RouteModel) -> some View {
        VStack(spacing: 10) {
            HStack {
                metricTile("Distance", String(format: "%.1f km", route.totalDistance / 1000))
                metricTile("Elevation ↑", String(format: "%.0f m", route.elevationGain))
                metricTile("Elevation ↓", String(format: "%.0f m", route.elevationLoss))
            }
            HStack(spacing: 12) {
                Button("Start Ride") {
                    rideStore.start(route: route, pois: routeStore.selectedPOIs)
                }
                .buttonStyle(.borderedProminent)
                Button("Center") { position = .rect(route.mapRect) }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.thinMaterial)
    }

    // MARK: - Riding HUD

    @ViewBuilder
    private func ridingHUD(route: RouteModel) -> some View {
        VStack(spacing: 0) {
            if !rideStore.rideState.rerouteSteps.isEmpty {
                rerouteStepsList
            }
            statGrid
            elevationStrip(route: route)
            Button("Stop Ride") {
                // Build summary BEFORE stopping so breadcrumbs are intact
                if let summary = rideStore.stopAndBuildSummary() {
                    rideSummary = summary
                    showRideSummary = true
                } else {
                    rideStore.stop()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding(.vertical, 10)
        }
        .background(.thinMaterial)
    }

    // MARK: - Stat Grid

    @ViewBuilder
    private var statGrid: some View {
        let s = rideStore.rideState
        VStack(spacing: 1) {
            HStack(spacing: 1) {
                bigMetricTile("SPEED", String(format: "%.1f", s.speedKmh), unit: "km/h", accent: true)
                bigMetricTile("TIME", s.elapsedTime.formattedDuration, unit: "")
            }
            HStack(spacing: 1) {
                bigMetricTile("DISTANCE", String(format: "%.2f", s.distanceKm), unit: "km")
                bigMetricTile("AVG SPEED", String(format: "%.1f", s.avgSpeedKmh), unit: "km/h")
            }
            HStack(spacing: 1) {
                bigMetricTile("ELEV GAIN", String(format: "%.0f", s.elevationGain), unit: "m")
                bigMetricTile("PROGRESS", String(format: "%.0f%%", rideStore.progressPercent * 100), unit: "")
            }
        }
        .padding(.horizontal, 1)
        .padding(.top, 8)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
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

    // MARK: - Metric Tiles

    @ViewBuilder
    private func metricTile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.monospacedDigit()).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func bigMetricTile(_ label: String, _ value: String, unit: String, accent: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: accent ? 36 : 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent ? Color.blue : Color.primary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemBackground).opacity(0.6))
    }

    // MARK: - Elevation Data Builder

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
