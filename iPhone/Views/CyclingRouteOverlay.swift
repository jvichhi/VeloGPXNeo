//
//  CyclingRouteOverlay.swift
//  VeloGPX
//
//  Drop-in SwiftUI view that:
//  1. Shows a "Get Cycling Route" button inside RouteDetailView
//  2. Computes the route start→end via CyclingRouteService
//  3. Displays the route as a MapPolyline on an inline Map
//  4. Shows route name, distance, and ETA
//
//  CyclingRouteResult.route is MKRoute (@MainActor-isolated).
//  This view is @MainActor (all SwiftUI views are), so accessing
//  result.route.distance / .polyline etc. here is safe.
//

import SwiftUI
import MapKit

struct CyclingRouteOverlay: View {

    let route: RouteModel

    @State private var isLoading = false
    @State private var routeResult: CyclingRouteResult? = nil
    @State private var errorMessage: String? = nil
    @State private var showMap = false

    private var startCoordinate: CLLocationCoordinate2D? {
        route.trackPoints.first?.coordinate.clCoordinate
    }

    private var endCoordinate: CLLocationCoordinate2D? {
        route.trackPoints.last?.coordinate.clCoordinate
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailSectionHeader(
                title: "Cycling Route",
                systemImage: "bicycle"
            )

            if let result = routeResult {
                // MARK: Route Map
                if showMap {
                    cyclingMapView(result: result)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 0))
                }

                // MARK: Route Stats
                HStack(spacing: 0) {
                    routeStat(
                        icon: "arrow.left.and.right",
                        value: String(format: "%.1f km", result.totalDistance / 1000),
                        label: "Distance",
                        color: .blue
                    )
                    Divider().frame(height: 44)
                    routeStat(
                        icon: "clock",
                        value: formattedETA(result.expectedTravelTime),
                        label: "Est. Time",
                        color: .green
                    )
                    Divider().frame(height: 44)
                    routeStat(
                        icon: result.isCycling ? "bicycle" : "figure.walk",
                        value: result.isCycling ? "Cycling" : "Walking",
                        label: "Mode",
                        color: result.isCycling ? .orange : .secondary
                    )
                }
                .padding(.vertical, 8)

                // MARK: Route Name
                if let name = result.routeName {
                    Divider().padding(.leading, 14)
                    HStack(spacing: 10) {
                        Image(systemName: "signpost.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                // MARK: Toggle Map
                Divider().padding(.leading, 14)
                Button {
                    withAnimation(.spring(duration: 0.35)) {
                        showMap.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: showMap ? "map.fill" : "map")
                            .frame(width: 20)
                        Text(showMap ? "Hide Map" : "Show on Map")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(showMap ? 90 : 0))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.blue)
                    .padding(14)
                }

            } else {
                // MARK: Prompt / Loading
                VStack(spacing: 12) {
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Calculating cycling route\u{2026}")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                    } else if let error = errorMessage {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(14)

                        Divider().padding(.leading, 14)
                        Button {
                            Task { await computeRoute() }
                        } label: {
                            Label("Try Again", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.blue)
                                .padding(14)
                        }
                    } else {
                        Button {
                            Task { await computeRoute() }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "bicycle")
                                    .frame(width: 20)
                                Text("Get Cycling Route")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.blue)
                            .padding(14)
                        }
                    }
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - Map

    @ViewBuilder
    private func cyclingMapView(result: CyclingRouteResult) -> some View {
        // result.route is MKRoute — @MainActor safe here (SwiftUI view is @MainActor)
        let polyline = result.route.polyline
        let region = MKCoordinateRegion(polyline.boundingMapRect)

        Map(initialPosition: .region(region)) {
            MapPolyline(result.route)
                .stroke(.blue, lineWidth: 4)

            if let start = startCoordinate {
                Annotation("Start", coordinate: start) {
                    Circle()
                        .fill(.green)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            if let end = endCoordinate {
                Annotation("End", coordinate: end) {
                    Circle()
                        .fill(.red)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(emphasis: .automatic, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls { MapCompass() }
        .disabled(false)
    }

    // MARK: - Stat Tile

    @ViewBuilder
    private func routeStat(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func formattedETA(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let h = minutes / 60
            let m = minutes % 60
            return m == 0 ? "\(h) hr" : "\(h)h \(m)m"
        }
    }

    private func computeRoute() async {
        guard let start = startCoordinate, let end = endCoordinate else {
            errorMessage = "Route has no start or end point."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let result = try await CyclingRouteService.shared.calculateRoute(from: start, to: end)
            routeResult = result
            showMap = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
