//
//  PlanView.swift
//  VeloGPX
//
//  Plan tab: interactive cycling route builder.
//  - Tap the map to place waypoints
//  - MapKit snaps each pair to a cycling route via PlanRouteEngine
//  - Close the loop, save to library, or ride immediately
//

import SwiftUI
import MapKit
import CoreLocation

struct PlanView: View {

    @StateObject private var plan = PlanState()
    private let engine = PlanRouteEngine()

    @EnvironmentObject private var routeStore: RouteStore

    /// Lets "Ride Now" switch to the Ride tab from outside this view.
    /// Bound by RootView via a shared selectedTab binding.
    var switchToRide: () -> Void = {}

    // Camera
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    // Sheet
    @State private var sheetDetent: PresentationDetent = .height(220)
    @State private var isSheetPresented = true

    // Error banner
    @State private var showErrorBanner = false

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            if showErrorBanner, let err = plan.routingError {
                errorBanner(message: err)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $isSheetPresented) {
            WaypointListSheet(plan: plan, engine: engine) {
                switchToRide()
            }
            .presentationDetents([.height(220), .medium, .large], selection: $sheetDetent)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled)
            .interactiveDismissDisabled()
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

    // MARK: - Map Layer

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $position) {
                // Solid route polyline
                if !plan.routePolyline.isEmpty {
                    MapPolyline(coordinates: plan.routePolyline)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }

                // Dashed close-loop polyline
                if plan.isLoopClosed && !plan.loopPolyline.isEmpty {
                    MapPolyline(coordinates: plan.loopPolyline)
                        .stroke(.blue.opacity(0.55),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round,
                                                   dash: [8, 6]))
                }

                // Waypoint annotations
                ForEach(Array(plan.waypoints.enumerated()), id: \.element.id) { index, wp in
                    Annotation(
                        wp.name ?? "",
                        coordinate: wp.coordinate,
                        anchor: .bottom
                    ) {
                        WaypointPin(
                            index: index,
                            total: plan.waypoints.count,
                            isLoopClosed: plan.isLoopClosed
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
                    // New waypoint is at index waypointCount (0-based after append)
                    Task {
                        await engine.refreshSegments(
                            in: plan,
                            affectedWaypointIndices: [waypointCount]
                        )
                    }
                }
                // Expand sheet slightly on first waypoint
                if plan.waypoints.count == 1 {
                    withAnimation { sheetDetent = .medium }
                }
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
            Button { withAnimation { showErrorBanner = false; plan.routingError = nil } } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 56)
    }
}

// MARK: - Waypoint Pin View

private struct WaypointPin: View {
    let index: Int
    let total: Int
    let isLoopClosed: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(fillColor)
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
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
