//
//  PreRidePOISheet.swift
//  VeloGPX
//
//  Pre-ride POI management sheet.
//  Opened by the 📍 button in birdsEyeLayout.
//  Two sections:
//   - On this route: list of saved POIs + swipe-to-delete
//   - Add nearby: navigates into POIDiscoverySheet
//

import SwiftUI

struct PreRidePOISheet: View {
    let route: RouteModel
    @EnvironmentObject private var routeStore: RouteStore
    @State private var showSearch = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // MARK: On this route
                Section("On this route") {
                    if routeStore.selectedPOIs.isEmpty {
                        Text("No pinned POIs yet")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(routeStore.selectedPOIs) { poi in
                            Label {
                                Text(poi.name)
                            } icon: {
                                Image(systemName: poi.category.systemImage)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .onDelete { indexSet in
                            routeStore.selectedPOIs.remove(atOffsets: indexSet)
                            routeStore.savePOIs()
                        }
                    }
                }

                // MARK: Add nearby
                Section("Add nearby") {
                    Button {
                        showSearch = true
                    } label: {
                        Label("Search nearby…", systemImage: "magnifyingglass")
                    }
                }
            }
            .navigationTitle("POIs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSearch) {
                POIDiscoverySheet(route: route)
                    .environmentObject(routeStore)
            }
        }
    }
}
