import SwiftUI
import MapKit

// MARK: - DrawRouteView

/// Full-screen sheet for finger-drawing a road-snapped cycling route (F-D).
///
/// Entry point: "Draw Route" row in WaypointListSheet emptyPrompt (PlanView).
/// Exit paths:
///   - Cancel (with confirmation if content exists) → dismiss, no change
///   - Done → finalise snap → build RouteModel → routeStore.addAIPlannedRoute → dismiss
///
/// F-D4 (May 2026): Pan/Draw mode toggle.
///   - Default state is PAN — map scrolls and zooms normally.
///   - Tap the pencil toolbar button to enter DRAW mode — finger gestures
///     are captured by DragGesture and fed to DrawRouteEngine; the map
///     does NOT pan or zoom while draw mode is active.
///   - Tap pencil again (or tap the map without drawing) to return to pan mode.
struct DrawRouteView: View {
    @EnvironmentObject private var routeStore: RouteStore
    @Environment(\.dismiss) private var dismiss

    @State private var engine = DrawRouteEngine()
    @State private var showCancelConfirm = false
    @State private var isDone = false
    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    /// F-D4: false = pan mode (default), true = draw mode
    @State private var isDrawMode: Bool = false

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {

                // MARK: Map canvas
                mapCanvas

                // MARK: Mode indicator pill
                if isDrawMode {
                    drawModeIndicator
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }

                // MARK: Bottom bar
                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .navigationTitle("Draw Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if engine.hasContent {
                            showCancelConfirm = true
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel("Cancel drawing")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    // F-D4: Draw/Pan toggle
                    Button {
                        isDrawMode.toggle()
                        haptic.impactOccurred()
                    } label: {
                        Image(systemName: isDrawMode ? "pencil.circle.fill" : "pencil.circle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(isDrawMode ? Color.blue : Color.primary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(isDrawMode ? "Switch to pan mode" : "Switch to draw mode")

                    // Undo
                    Button {
                        engine.undoLastSegment()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(.regularMaterial, in: Circle())
                    }
                    .disabled(!engine.canUndo)
                    .accessibilityLabel("Undo last segment")
                }
            }
            .confirmationDialog(
                "Discard this route?",
                isPresented: $showCancelConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) {
                    engine.reset()
                    dismiss()
                }
                Button("Keep Drawing", role: .cancel) {}
            }
        }
        .overlay(alignment: .top) {
            if let err = engine.lastSnapError {
                snapErrorToast(err)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            engine.clearSnapError()
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.3), value: engine.lastSnapError)
        .animation(.spring(duration: 0.22), value: isDrawMode)
    }

    // MARK: - Draw Mode Indicator

    private var drawModeIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .bold))
            Text("Draw Mode — drag to trace your route")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.blue.opacity(0.88), in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    // MARK: - Map Canvas

    private var mapCanvas: some View {
        MapReader { proxy in
            Map(position: $mapPosition) {
                // Snapped polyline — solid blue
                if engine.allSnappedCoordinates.count >= 2 {
                    MapPolyline(coordinates: engine.allSnappedCoordinates)
                        .stroke(.blue, lineWidth: 4)
                }

                // Pending trace — dashed blue-grey
                if engine.pendingCoordinates.count >= 2 {
                    MapPolyline(coordinates: engine.pendingCoordinates)
                        .stroke(
                            .blue.opacity(engine.isSnapping ? 0.4 : 0.6),
                            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                        )
                }

                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            // F-D4: Only intercept drag when draw mode is active.
            // When isDrawMode is false the Map receives gestures normally (pan/zoom).
            .overlay {
                if isDrawMode {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 2, coordinateSpace: .local)
                                .onChanged { value in
                                    guard let coord = proxy.convert(value.location, from: .local) else { return }
                                    engine.addGesturePoint(lat: coord.latitude, lon: coord.longitude)
                                }
                                .onEnded { _ in
                                    Task { await engine.finaliseTrace() }
                                }
                        )
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 10) {

            if engine.hasContent {
                HStack(spacing: 12) {
                    Label(
                        String(format: "%.1f km", engine.totalDistance / 1000),
                        systemImage: "arrow.left.and.right"
                    )
                    .font(.subheadline.weight(.semibold))

                    Divider().frame(height: 14)

                    Label(
                        String(format: "%.0f m", engine.totalElevationGain),
                        systemImage: "mountain.2"
                    )
                    .font(.subheadline.weight(.semibold))

                    if engine.isSnapping {
                        Divider().frame(height: 14)
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.secondary)
                            Text("Snapping…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    String(format: "%.1f kilometres, %.0f metres elevation gain",
                           engine.totalDistance / 1000, engine.totalElevationGain)
                )
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }

            // Draw mode toggle hint — shown when map is empty and not yet in draw mode
            if !engine.hasContent && !isDrawMode {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.circle")
                        .foregroundStyle(.secondary)
                    Text("Tap the pencil to start drawing")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }

            Button {
                guard !isDone else { return }
                isDone = true
                Task {
                    await engine.finaliseTrace()
                    await commitRoute()
                    isDone = false
                }
            } label: {
                ZStack {
                    if isDone {
                        ProgressView().tint(.white)
                    } else {
                        Text("Done")
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    engine.segments.isEmpty ? Color(.systemGray4) : Color.blue,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .foregroundStyle(.white)
            }
            .disabled(engine.segments.isEmpty || isDone)
            .accessibilityLabel("Finish and save route")
        }
        .animation(.spring(duration: 0.25), value: engine.hasContent)
        .animation(.spring(duration: 0.25), value: isDrawMode)
    }

    // MARK: - Snap error toast

    private func snapErrorToast(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }

    // MARK: - Commit route to store

    @MainActor
    private func commitRoute() async {
        let coords = engine.allSnappedCoordinates
        guard coords.count >= 2 else { return }

        let trackPoints = coords.map { TrackPoint(coordinate: $0, elevation: nil, timestamp: nil) }
        let route = RouteModel(
            name: "Drawn Route",
            sourceFormat: .drawn,
            trackPoints: trackPoints
        )
        routeStore.addAIPlannedRoute(route)
        engine.reset()
        dismiss()
    }
}
