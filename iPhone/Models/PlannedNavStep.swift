//
//  PlannedNavStep.swift
//  VeloGPX
//
//  A single turn instruction derived from MKDirections for a planned route.
//  Stored as a value type; identity is by array index (currentStepIndex).
//

import CoreLocation

struct PlannedNavStep {
    /// Human-readable instruction, e.g. "Turn left on Rue Saint-Denis"
    let instruction: String
    /// The coordinate at which the maneuver occurs.
    let maneuverCoordinate: CLLocationCoordinate2D
    /// Metres from the *previous* step's maneuver point to this one.
    /// Zero for the first step (departure).
    let distanceMeters: Double
}
