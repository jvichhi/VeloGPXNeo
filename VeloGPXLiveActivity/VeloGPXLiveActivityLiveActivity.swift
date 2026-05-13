//
//  VeloGPXLiveActivityLiveActivity.swift
//  VeloGPXLiveActivity
//
//  Live Activity UI rendered on the Dynamic Island and Lock Screen
//  while a VeloGPX ride is in progress.
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Widget entry point

struct VeloGPXLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in

            // ── Lock Screen / Notification Banner ──────────────────────────
            LockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.06, green: 0.06, blue: 0.07)) // near-black
                .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {

                // Expanded (long-press or always-on display)
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.routeName, systemImage: "bicycle")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isPaused ? "Paused" : context.state.speedString)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(context.state.isPaused ? .yellow : .green)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 24) {
                        StatPill(value: context.state.distanceString, label: "Distance")
                        StatPill(value: context.state.elapsedTimeString, label: "Time")
                        StatPill(value: context.state.speedString, label: "Speed")
                    }
                    .padding(.bottom, 6)
                }

            } compactLeading: {
                // Compact — left capsule: bicycle icon
                Image(systemName: "bicycle")
                    .foregroundStyle(.green)
                    .font(.caption2)

            } compactTrailing: {
                // Compact — right capsule: distance
                Text(context.state.distanceString)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)

            } minimal: {
                // Minimal (second app running) — just the icon
                Image(systemName: "bicycle")
                    .foregroundStyle(.green)
            }
            .widgetURL(URL(string: "velogpx://ride"))
            .keylineTint(.green)
        }
    }
}

// MARK: - Lock Screen banner

private struct LockScreenView: View {
    let context: ActivityViewContext<RideActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            // Left: icon + route name
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "bicycle")
                        .foregroundStyle(.green)
                    Text(context.attributes.routeName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text(context.state.isPaused ? "Paused" : "Recording")
                    .font(.caption2)
                    .foregroundStyle(context.state.isPaused ? .yellow : .green)
            }

            Spacer()

            // Right: three stat pills
            HStack(spacing: 12) {
                StatPill(value: context.state.distanceString, label: "Dist")
                StatPill(value: context.state.elapsedTimeString, label: "Time")
                StatPill(value: context.state.speedString, label: "Speed")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Reusable stat pill

private struct StatPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Xcode Previews

extension RideActivityAttributes {
    fileprivate static var preview: RideActivityAttributes {
        RideActivityAttributes(routeName: "Mont Royal Loop")
    }
}

extension RideActivityAttributes.ContentState {
    fileprivate static var riding: RideActivityAttributes.ContentState {
        .init(totalDistance: 12450, elapsedTime: 2713, speed: 7.8, isPaused: false)
    }
    fileprivate static var paused: RideActivityAttributes.ContentState {
        .init(totalDistance: 8200, elapsedTime: 1830, speed: 0, isPaused: true)
    }
}

#Preview("Notification", as: .content, using: RideActivityAttributes.preview) {
    VeloGPXLiveActivityLiveActivity()
} contentStates: {
    RideActivityAttributes.ContentState.riding
    RideActivityAttributes.ContentState.paused
}
