//
//  RidePlanAssistantView.swift
//  VeloGPX — iPhone target ONLY. Never add to Watch target.
//
//  PURPOSE:
//  The UI half of F-C1. Presents as a .sheet over PlanView.
//  Drives PlanAssistantEngine and renders its AsyncStream<AssistantEvent> output.
//
//  ENTRY POINT:
//  WaypointListSheet shows a "Plan with AI" button in its empty state.
//  That button sets showAssistant = true on PlanView, which presents this sheet.
//
//  STATES:
//    .idle        — text field + primary button visible
//    .planning    — ProgressView spinner, streaming stop list appears
//    .disambiguation(index, candidates) — inline picker for ambiguous stop
//    .done        — brief "Route ready ✓" then auto-dismiss
//    .failed(msg) — inline error, user can retry
//
//  DOES NOT:
//  — Touch PlanView's ZStack, map controls, or drawerCard
//  — Add new map annotations or overlays
//  — Present additional sheets on top of itself (disambiguation is inline)
//

import SwiftUI
import MapKit

struct RidePlanAssistantView: View {

    @ObservedObject var plan: PlanState
    /// Map centre coordinate — passed in as Doubles to avoid @MainActor confusion.
    var nearLat: Double
    var nearLon: Double

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    private enum Phase {
        case idle
        case planning
        case done
        case failed(String)
    }

    private let engine = PlanAssistantEngine()

    @State private var prompt = ""
    @State private var phase: Phase = .idle
    @State private var resolvedStops: [StopRow] = []
    @State private var disambigIndex: Int? = nil
    @State private var disambigCandidates: [MKMapItem] = []
    @FocusState private var fieldFocused: Bool

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    promptField
                    planButton
                    if !resolvedStops.isEmpty || phase.isPlanning {
                        stopsSection
                    }
                    if let idx = disambigIndex, !disambigCandidates.isEmpty {
                        disambigSection(index: idx, candidates: disambigCandidates)
                    }
                    if case .failed(let msg) = phase {
                        errorRow(message: msg)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(phase.isPlanning)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { fieldFocused = true }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Plan a Ride")
                    .font(.title2.weight(.semibold))
            }
            Text("Describe your route in plain language")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Prompt Field

    private var promptField: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("e.g. 60 km loop with a café stop in Laval and a park near the end")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $prompt)
                    .font(.subheadline)
                    .frame(minHeight: 72, maxHeight: 120)
                    .focused($fieldFocused)
                    .scrollContentBackground(.hidden)
                    .disabled(phase.isPlanning)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Plan Button

    private var planButton: some View {
        Button {
            Task { await startPlanning() }
        } label: {
            Group {
                if phase.isPlanning {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Planning…")
                    }
                } else if case .done = phase {
                    Label("Route ready", systemImage: "checkmark")
                } else {
                    Label("Plan this route", systemImage: "sparkles")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                planButtonBackground,
                in: RoundedRectangle(cornerRadius: 13)
            )
        }
        .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || phase.isPlanning)
    }

    @ViewBuilder
    private var planButtonBackground: some ShapeStyle {
        if case .done = phase {
            AnyShapeStyle(Color.green)
        } else if prompt.trimmingCharacters(in: .whitespaces).isEmpty {
            AnyShapeStyle(Color(.systemGray3))
        } else {
            AnyShapeStyle(Color.blue)
        }
    }

    // MARK: - Stops Section

    private var stopsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stops")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(Array(resolvedStops.enumerated()), id: \.element.id) { _, row in
                    HStack(spacing: 10) {
                        stopStateIcon(row.state)
                        Text(row.name)
                            .font(.subheadline)
                            .foregroundStyle(row.state == .pending ? .secondary : .primary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    if resolvedStops.last?.id != row.id {
                        Divider().padding(.leading, 38)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func stopStateIcon(_ state: StopRow.State) -> some View {
        switch state {
        case .pending:
            ProgressView().scaleEffect(0.7).frame(width: 20, height: 20)
        case .resolved:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 16))
                .frame(width: 20, height: 20)
        case .ambiguous:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 16))
                .frame(width: 20, height: 20)
        case .skipped:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 16))
                .frame(width: 20, height: 20)
        }
    }

    // MARK: - Disambiguation Section

    private func disambigSection(index: Int, candidates: [MKMapItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Which one did you mean?")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(candidates, id: \.self) { item in
                    Button {
                        resolveDisambiguation(index: index, mapItem: item)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin")
                                .font(.system(size: 13))
                                .foregroundStyle(.blue)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name ?? "Unknown")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                if let subtitle = item.placemark.title {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    if candidates.last !== item {
                        Divider().padding(.leading, 38)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Error Row

    private func errorRow(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Button("Retry") {
                Task { await startPlanning() }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.blue)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Engine Integration

    private func startPlanning() async {
        let trimmed = prompt.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        fieldFocused = false
        withAnimation { phase = .planning; resolvedStops = []; disambigIndex = nil; disambigCandidates = [] }

        for await event in engine.plan(prompt: trimmed, nearLat: nearLat, nearLon: nearLon, planState: plan) {
            await handleEvent(event)
        }
    }

    @MainActor
    private func handleEvent(_ event: AssistantEvent) async {
        switch event {
        case .intentParsed(let intent):
            withAnimation {
                resolvedStops = intent.stops.enumerated().map { idx, stop in
                    StopRow(id: idx, name: stop.label, state: .pending)
                }
            }

        case .stopResolved(let index, let name):
            withAnimation {
                if index < resolvedStops.count {
                    resolvedStops[index] = StopRow(id: index, name: name, state: .resolved)
                }
            }

        case .stopNeedsDisambiguation(let index, let candidates):
            withAnimation {
                if index < resolvedStops.count {
                    resolvedStops[index] = StopRow(id: index, name: resolvedStops[index].name, state: .ambiguous)
                }
                disambigIndex = index
                disambigCandidates = candidates
            }

        case .completed:
            withAnimation { phase = .done }
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()

        case .failed(let msg):
            withAnimation { phase = .failed(msg) }
        }
    }

    @MainActor
    private func resolveDisambiguation(index: Int, mapItem: MKMapItem) {
        let name = engine.commitDisambiguatedStop(mapItem: mapItem, planState: plan)
        withAnimation {
            if index < resolvedStops.count {
                resolvedStops[index] = StopRow(id: index, name: name, state: .resolved)
            }
            disambigIndex = nil
            disambigCandidates = []
        }
        // If all stops are now resolved, mark done
        let allDone = resolvedStops.allSatisfy { $0.state == .resolved || $0.state == .skipped }
        if allDone { withAnimation { phase = .done } }
    }

    // MARK: - Supporting Types

    private struct StopRow: Identifiable {
        let id: Int
        let name: String
        var state: State

        enum State: Equatable {
            case pending, resolved, ambiguous, skipped
        }
    }
}

// MARK: - Phase helpers

private extension RidePlanAssistantView.Phase {
    var isPlanning: Bool {
        if case .planning = self { return true }
        return false
    }
}
