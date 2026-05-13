//
//  RideActivityAttributes.swift
//  Shared — compiled into both VeloGPX (iPhone app) and VeloGPXLiveActivity (widget extension)
//
//  Defines the ActivityKit contract: static attributes set at ride start,
//  and the dynamic ContentState pushed on every GPS update.
//

import ActivityKit
import Foundation

/// Static ride metadata set once when the activity is requested.
/// Dynamic stats (speed, distance, time) live in ContentState.
public struct RideActivityAttributes: ActivityAttributes {

    /// Route name shown in the compact/minimal Dynamic Island views.
    public var routeName: String

    public init(routeName: String) {
        self.routeName = routeName
    }

    // MARK: - Dynamic state pushed on every GPS tick

    public struct ContentState: Codable, Hashable {
        /// Total distance ridden in metres.
        public var totalDistance: Double
        /// Active elapsed seconds (excludes paused time).
        public var elapsedTime: TimeInterval
        /// Current speed in m/s (0 when paused).
        public var speed: Double
        /// True while the rider has manually paused the ride.
        public var isPaused: Bool

        public init(
            totalDistance: Double,
            elapsedTime: TimeInterval,
            speed: Double,
            isPaused: Bool
        ) {
            self.totalDistance = totalDistance
            self.elapsedTime = elapsedTime
            self.speed = speed
            self.isPaused = isPaused
        }

        // MARK: Computed helpers for the widget UI

        /// Distance formatted as "12.4 km" or "850 m".
        public var distanceString: String {
            if totalDistance >= 1000 {
                return String(format: "%.1f km", totalDistance / 1000)
            } else {
                return String(format: "%.0f m", totalDistance)
            }
        }

        /// Elapsed time formatted as "1:23:45" or "23:45".
        public var elapsedTimeString: String {
            let h = Int(elapsedTime) / 3600
            let m = (Int(elapsedTime) % 3600) / 60
            let s = Int(elapsedTime) % 60
            if h > 0 {
                return String(format: "%d:%02d:%02d", h, m, s)
            } else {
                return String(format: "%d:%02d", m, s)
            }
        }

        /// Speed formatted as "28.4 km/h".
        public var speedString: String {
            String(format: "%.1f km/h", speed * 3.6)
        }
    }
}
