import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    SettingsCard {
                        SettingsRow(
                            icon: "square.and.arrow.down",
                            iconColor: .blue,
                            title: "GPX & GeoJSON Import",
                            subtitle: "Open files from Safari, Files, or Mail and they'll land straight in VeloGPX."
                        )
                    }

                    SettingsCard {
                        SettingsRow(
                            icon: "map.fill",
                            iconColor: .green,
                            title: "Map Engine",
                            subtitle: "Uses SwiftUI MapKit with MapCameraPosition, MapPolyline, and Annotation APIs."
                        )
                        Divider().padding(.leading, 54)
                        SettingsRow(
                            icon: "safari.fill",
                            iconColor: .blue,
                            title: "Bird's Eye Mode",
                            subtitle: "Tap the map before starting a ride to preview the full route and elevation."
                        )
                    }

                    SettingsCard {
                        SettingsRow(
                            icon: "applewatch",
                            iconColor: .primary,
                            title: "Apple Watch",
                            subtitle: "Glanceable speed, distance, and heart rate companion with haptic cues."
                        )
                    }

                    SettingsCard {
                        SettingsRow(
                            icon: "mappin.and.ellipse",
                            iconColor: .orange,
                            title: "Points of Interest",
                            subtitle: "Discover cafés, water sources, bike shops, and more along your route."
                        )
                        Divider().padding(.leading, 54)
                        SettingsRow(
                            icon: "square.and.arrow.up",
                            iconColor: .purple,
                            title: "GPX Export",
                            subtitle: "Export your actual track, planned route, and visited POIs as a single GPX file."
                        )
                    }

                    Text("VeloGPX")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Settings Card

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// MARK: - Settings Row

private struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
    }
}
