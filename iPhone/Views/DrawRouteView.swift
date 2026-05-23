import SwiftUI
import MapKit

// MARK: - DrawRouteView

/// Full-screen sheet for finger-drawing a road-snapped cycling route (F-D).
///
/// Entry point: `pencil.and.map` toolbar button in RouteLibraryView.
/// Exit paths:
///   - Cancel (with confirmation if content exists) → dismiss, no change
///   - Done → finalise snap → build RouteModel → routeStore.addAIPlannedRoute → dismiss
struct DrawRouteView: View {
    @EnvironmentObject private var routeStore: RouteStore
    @Environment(\.dismiss) private var dismiss

    @State private var engine = DrawRouteEngine()
    @State private var showCancelConfirm = false
    @State private var isDone = false
    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {

                // MARK: Map canvas
                mapCanvas

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

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        engine.undoLastSegment()
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
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
        // Error toast
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
            .simultaneousGesture(
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
        .ignoresSafeArea()
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 10) {

            // Stats pill — hidden until first point placed
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

            // Done button
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
                        ProgressView()
                            .tint(.white)
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
