//
//  PlanView.swift
//  VeloGPX
//

import SwiftUI
import MapKit
import CoreLocation

struct PlanView: View {

    @StateObject private var plan = PlanState()
    private let engine = PlanRouteEngine()

    @EnvironmentObject private var routeStore: RouteStore

    var switchToRide: () -> Void = {}

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var sheetDetent: PresentationDetent = .height(220)
    @State private var isSheetPresented = true
    @State private var showErrorBanner = false
    @State private var showSavedBanner = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                mapLayer
                    .ignoresSafeArea(edges: .top)

                if showErrorBanner, let err = plan.routingError {
                    errorBanner(message: err, isError: true)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                        .padding(.top, 8)
                }

                if showSavedBanner {
                    errorBanner(message: "Route saved to library", isError: false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                        .padding(.top, 8)
                }
            }
            .navigationBarHidden(true)
            // Re-present sheet whenever this tab becomes active
            .onAppear {
                if !isSheetPresented {
                    isSheetPresented = true
                }
            }
            .sheet(isPresented: $isSheetPresented) {
                WaypointListSheet(
                    plan: plan,
                    engine: engine,
                    onRideNow: {
                        isSheetPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            switchToRide()
                        }
                    },
                    onSaved: {
                        withAnimation { showSavedBanner = true }
                        Task {
                            try? await Task.sleep(for: .seconds(2.5))
                            withAnimation { showSavedBanner = false }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            plan.clearAll()
                            sheetDetent = .height(220)
                        }
                    }
                )
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
    }

    // MARK: - Map Layer

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
                ForEach(Array(plan.waypoints.enumerated()), id: \.element.id) { index, wp in
                    // Pass empty string as label — name is rendered inside WaypointPin
                    // to avoid MapKit callout overlapping the pin view
                    Annotation("", coordinate: wp.coordinate, anchor: .bottom) {
                        WaypointPin(
                            index: index,
                            total: plan.waypoints.count,
                            isLoopClosed: plan.isLoopClosed,
                            name: wp.name
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
                    Task {
                        await engine.refreshSegments(
                            in: plan,
                            affectedWaypointIndices: [waypointCount]
                        )
                    }
                }
                if plan.waypoints.count == 1 {
                    withAnimation { sheetDetent = .medium }
                }
            }
        }
    }

    // MARK: - Banner

    private func errorBanner(message: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? Color.orange : Color.green)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.primary)
            Spacer()
            if isError {
                Button {
                    withAnimation { showErrorBanner = false; plan.routingError = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 52)
    }
}

// MARK: - Waypoint Pin

private struct WaypointPin: View {
    let index: Int
    let total: Int
    let isLoopClosed: Bool
    var name: String?

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            // Show name tag below pin only when a custom name exists,
            // so it never overlaps the circle
            if let name, !name.isEmpty {
                Text(name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                    .fixedSize()
            }
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
