//
//  RidePlanIntent+Generable.swift
//  VeloGPX — iPhone target ONLY. Never add to Watch target.
//
//  PURPOSE:
//  Defines the structured output schema that PlanAssistantEngine asks the
//  on-device FoundationModels LLM to fill in when the user types a natural-
//  language route request such as:
//    "60 km loop with a café stop in Laval and a park near the end"
//
//  The model produces a RidePlanIntent value; PlanAssistantEngine then:
//    1. Resolves each IntentStop's `searchQuery` via MKLocalSearch.
//    2. Feeds resolved coordinates into PlanState + PlanRouteEngine.
//
//  USAGE:
//    let session = VeloAI.makeSession()
//    let intent  = try await session.respond(
//        to: userPrompt,
//        generating: RidePlanIntent.self
//    )
//
//  WHY @Generable:
//  @Generable synthesises the JSON schema that FoundationModels needs to
//  produce strongly-typed structured output. Without it we'd parse raw
//  strings manually. Every stored property must be a type supported by
//  FoundationModels' schema system: String, Int, Double, Bool, enums
//  that conform to @Generable, or arrays of those types.
//  CLLocationCoordinate2D is NOT supported — the model never produces
//  coordinates; MKLocalSearch resolves names to coordinates after the fact.
//
//  iOS 26 NOTE:
//  No @available guard — iOS 26 is the project minimum (see PROJECT.md).
//

import FoundationModels

// MARK: - Stop type

/// The kind of stop the user intends at a waypoint.
///
/// Drives:
/// - The SF Symbol shown in WaypointListSheet (F-C2).
/// - Dwell-time estimation in PlanAssistantEngine (e.g. café → 15 min).
/// - The MKLocalSearch category hint passed to POISearchService.
@Generable
enum IntentStopKind: String {
    /// A food or drink stop — café, restaurant, bakery, etc.
    case cafe
    /// A park, green space, viewpoint, or natural landmark.
    case park
    /// A named town, village, borough, or neighbourhood.
    case town
    /// A water refill, bike shop, or practical service stop.
    case service
    /// Any other named place the user mentioned explicitly.
    case other
}

// MARK: - Single stop

/// One named stop along the intended route.
///
/// `searchQuery` is a natural-language string suitable for passing directly
/// to MKLocalSearch (e.g. "café Laval QC", "Parc de la Rivière-des-Mille-Îles").
/// PlanAssistantEngine uses it verbatim; no further prompt engineering needed.
@Generable
struct IntentStop {
    /// Human-readable label for the stop, extracted from the user's prompt.
    /// Used as the initial `PlanWaypoint.name`. The user can edit it afterward.
    var label: String

    /// Search string for MKLocalSearch. Should include enough context (city,
    /// region) to resolve unambiguously where possible.
    var searchQuery: String

    /// Best-guess stop type inferred from the user's description.
    var kind: IntentStopKind

    /// Estimated dwell time in minutes the user implied, or -1 if unspecified.
    /// PlanAssistantEngine substitutes per-kind defaults when this is -1:
    ///   café → 15 min, park → 10 min, town → 5 min, service → 5 min, other → 0 min.
    var dwellMinutes: Int
}

// MARK: - Full ride intent

/// The structured output produced by the LLM from a free-text route request.
///
/// The model extracts:
/// - An ordered list of stops (start → intermediate stops → end, if specified).
/// - A rough target distance in kilometres (0 if the user didn't mention one).
/// - Whether the user wants a loop (start == finish).
/// - A suggested route name derived from the stops and distance.
///
/// PlanAssistantEngine is responsible for all MKLocalSearch resolution and
/// for populating PlanState; this struct is pure parsed intent with no
/// MapKit or CoreLocation dependencies.
@Generable
struct RidePlanIntent {

    /// Ordered stops as extracted from the user prompt.
    /// Index 0 is the first waypoint (start), last index is the destination.
    /// May contain only one entry if the user said "loop from here" —
    /// PlanAssistantEngine treats a single stop as a loop anchor.
    var stops: [IntentStop]

    /// Approximate target total distance in kilometres, or 0 if not mentioned.
    var targetDistanceKm: Double

    /// True when the user explicitly asked for a loop / round trip.
    var isLoop: Bool

    /// A short suggested route name the LLM derives from the stops and distance.
    /// Example: "Laval Café Loop · 60 km".
    /// PlanAssistantEngine uses this as the default name in PlanState;
    /// the user can override it before saving.
    var suggestedName: String
}
