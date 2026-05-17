//
//  RideSessionStore+Spurs.swift
//  VeloGPX
//
//  Computes road-snapped POISpurs for every POI within 800 m along-route.
//
//  Strategy
//  --------
//  • CyclingRouteService (MKDirections .cycling) is called once per POI
//    and the result is cached in `spurCache`.
//  • Cache key = POI id + rider's track-index *bucket* (floor divided by 10,
//    i.e. one bucket ≈ 100 m at typical 10 m/pt GPX density).
//    This means the cache is refreshed roughly every 100 m of riding without
//    hammering MKDirections on every 5-metre GPS tick.
//  • While the async route is computing, a thin straight-line placeholder
//    spur (isPending = true) is returned immediately so the map always has
//    *something* to show.
//  • Re-entry snap point is the nearest track point **at or ahead** of the
//    rider's current progress index, preventing a backwards detour.
//  • When the rider enters 80 m of nextPOI and the outbound leg is cached,
//    rerouteSteps is populated automatically for seamless turn-by-turn back.
//
//  Proximity gates
//  ---------------
//  • Spurs only rendered for POIs ≤ 800 m along-route ahead of rider.
//  • Approach alert fires at 200 m (handled in RideSessionStore).
//  • Auto-reroute back-to-track activates at 80 m straight-line to nextPOI.

import Foundation
import CoreLocation
import MapKit

// MARK: - Spur cache entry

private struct SpurCacheEntry {
    let inbound: [CLLocationCoordinate2D]
    let outbound: [CLLocationCoordinate2D]
    let inboundDistance: CLLocationDistance
    let outboundDistance: CLLocationDistance
    /// The MKRoute steps for the outbound leg, ready to inject into rerouteSteps.
    let outboundSteps: [RerouteStep]
    /// Track-index bucket this entry was computed for (riderIdx / 10).
    let bucket: Int
}

// MARK: - Extension

extension RideSessionStore {

    // MARK: - Internal cache (stored via associated-object trick on the class)
    //
    // Swift extensions on classes can't add stored properties, so we keep
    // the two dictionaries as static nonisolated storage keyed by object
    // identity. Both are only ever accessed from MainActor so no lock needed.

    private static var _spurCache: [ObjectIdentifier: [UUID: SpurCacheEntry]] = [:]
    private static var _computingIDs: [ObjectIdentifier: Set<UUID>] = [:]

    private var spurCache: [UUID: SpurCacheEntry] {
        get { Self._spurCache[ObjectIdentifier(self)] ?? [:] }
        set { Self._spurCache[ObjectIdentifier(self)] = newValue }
    }

    private var computingIDs: Set<UUID> {
        get { Self._computingIDs[ObjectIdentifier(self)] ?? [] }
        set { Self._computingIDs[ObjectIdentifier(self)] = newValue }
    }

    // MARK: - Public entry point

    /// Build one POISpur per POI within 800 m along-route ahead of the rider.
    /// Returns immediately (never suspends the caller) — cached spurs are used
    /// when available; async computation is kicked off in the background.
    func computeSpurs() async -> [POISpur] {
        guard
            let route,
            rideState.currentCoordinate != nil,
            !pois.isEmpty
        else {
            // Clear dangling cache when the ride ends or POIs are removed.
            spurCache.removeAll()
            computingIDs.removeAll()
            return []
        }

        let trackPoints = route.trackPoints
        guard trackPoints.count > 1 else { return [] }

        let riderIdx = nearestTrackIndex
        let currentBucket = riderIdx / 10

        var result: [POISpur] = []

        for poi in pois {
            let poiCoord = poi.coordinate.clCoordinate

            // ── Snap search: nearest track point AHEAD of rider, up to 800 m ──
            let windowEnd = min(trackPoints.count - 1, riderIdx + 80)
            guard windowEnd >= riderIdx else { continue }

            var snapIdx  = riderIdx
            var snapDist = poiCoord.distance(to: trackPoints[riderIdx].coordinate.clCoordinate)
            for i in (riderIdx + 1)...windowEnd {
                let d = poiCoord.distance(to: trackPoints[i].coordinate.clCoordinate)
                if d < snapDist { snapDist = d; snapIdx = i }
            }

            // POI already passed or outside 800 m window
            guard snapIdx >= riderIdx else { continue }
            let alongRoute = trackArcDistance(from: riderIdx, to: snapIdx, points: trackPoints)
            guard alongRoute <= 800 else { continue }

            let snapCoord  = trackPoints[snapIdx].coordinate.clCoordinate
            let isNext     = poi.id == rideState.nextPOI?.id

            // ── Check cache ──────────────────────────────────────────────────
            if let cached = spurCache[poi.id], cached.bucket == currentBucket {
                // Cache hit for this 100-m bucket.
                result.append(POISpur(
                    id: poi.id,
                    inbound: cached.inbound,
                    outbound: cached.outbound,
                    isNext: isNext,
                    isPending: false,
                    inboundDistance: cached.inboundDistance,
                    outboundDistance: cached.outboundDistance
                ))

                // Auto-inject outbound turn-by-turn when rider is within 80 m of nextPOI.
                if isNext,
                   let riderCoord = rideState.currentCoordinate?.clCoordinate,
                   riderCoord.distance(to: poiCoord) <= 80,
                   rideState.rerouteSteps.isEmpty,
                   !cached.outboundSteps.isEmpty {
                    rideState.rerouteSteps = cached.outboundSteps
                    reroutePolyline = cached.outbound
                }

                continue
            }

            // ── Cache miss: return pending placeholder, kick off async fetch ──
            result.append(POISpur(
                id: poi.id,
                inbound: [snapCoord, poiCoord],
                outbound: [poiCoord, snapCoord],
                isNext: isNext,
                isPending: true,
                inboundDistance: 0,
                outboundDistance: 0
            ))

            guard !computingIDs.contains(poi.id) else { continue }
            computingIDs.insert(poi.id)

            let poiID   = poi.id
            let snapLat = snapCoord.latitude,  snapLon = snapCoord.longitude
            let poiLat  = poiCoord.latitude,   poiLon  = poiCoord.longitude
            let bucket  = currentBucket

            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.fetchAndCacheSpur(
                    poiID: poiID,
                    snapLat: snapLat, snapLon: snapLon,
                    poiLat: poiLat,   poiLon: poiLon,
                    bucket: bucket
                )
            }
        }

        return result
    }

    // MARK: - Async fetch

    private func fetchAndCacheSpur(
        poiID: UUID,
        snapLat: Double, snapLon: Double,
        poiLat: Double,  poiLon: Double,
        bucket: Int
    ) async {
        defer { computingIDs.remove(poiID) }

        async let inboundResult  = fetchLeg(from: snapLat, snapLon, to: poiLat, poiLon)
        async let outboundResult = fetchLeg(from: poiLat,  poiLon,  to: snapLat, snapLon)

        let (inbound, outbound) = await (inboundResult, outboundResult)
        guard let inbound, let outbound else { return }

        let entry = SpurCacheEntry(
            inbound: inbound.coords,
            outbound: outbound.coords,
            inboundDistance: inbound.distance,
            outboundDistance: outbound.distance,
            outboundSteps: outbound.steps,
            bucket: bucket
        )
        spurCache[poiID] = entry
    }

    // MARK: - Single-leg fetch

    private struct LegResult {
        let coords: [CLLocationCoordinate2D]
        let distance: CLLocationDistance
        let steps: [RerouteStep]
    }

    private func fetchLeg(
        from fLat: Double, _ fLon: Double,
        to tLat: Double, _ tLon: Double
    ) async -> LegResult? {
        do {
            let result = try await CyclingRouteService.shared.calculateRoute(
                from: fLat, fLon,
                to:   tLat, tLon
            )
            let coords = result.route.polyline.coordinates
            let steps  = result.steps
                .filter { !$0.instructions.isEmpty }
                .map    { RerouteStep(instructions: $0.instructions, distanceMeters: $0.distance) }
            return LegResult(coords: coords, distance: result.totalDistance, steps: steps)
        } catch {
            return nil
        }
    }

    // MARK: - Cache invalidation

    /// Call when POIs change (add/remove) so stale entries don't linger.
    func invalidateSpurCache() {
        spurCache.removeAll()
        computingIDs.removeAll()
    }
}
