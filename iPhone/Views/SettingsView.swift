import SwiftUI
import FoundationModels

struct SettingsView: View {
    @ObservedObject private var lm = LocalizationManager.shared
    @State private var showLanguagePicker = false
    @AppStorage(VeloAI.enabledKey) private var aiEnabled = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // MARK: - Language
                    SettingsCard {
                        Button { showLanguagePicker = true } label: {
                            HStack(alignment: .center, spacing: 14) {
                                settingsIcon("globe", color: .indigo)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Language")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("App display language")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                HStack(spacing: 6) {
                                    Text(lm.currentLanguage.flag)
                                        .font(.system(size: 20))
                                    Text(lm.currentLanguage.displayName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(14)
                        }
                        .buttonStyle(.plain)
                    }

                    // MARK: - Apple Intelligence
                    if VeloAI.isAvailable {
                        SettingsCard {
                            HStack(alignment: .top, spacing: 14) {
                                settingsIcon("sparkles", color: .purple)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("AI Features")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("Ride summaries, route name suggestions, and smart POI ranking. All processed on-device — your data never leaves your iPhone.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Toggle("", isOn: $aiEnabled)
                                    .labelsHidden()
                                    .tint(.purple)
                            }
                            .padding(14)
                        }
                    }

                    // MARK: - Import
                    SettingsCard {
                        SettingsRow(icon: "square.and.arrow.down", iconColor: .blue,
                                    title: "Import Routes",
                                    subtitle: "Import GPX files from Files app")
                    }

                    // MARK: - Map
                    SettingsCard {
                        SettingsRow(icon: "map.fill", iconColor: .green,
                                    title: "Map Engine",
                                    subtitle: "Apple Maps standard with realistic elevation")
                        Divider().padding(.leading, 54)
                        SettingsRow(icon: "safari.fill", iconColor: .blue,
                                    title: "Bird’s Eye View",
                                    subtitle: "Overview mode before starting a ride")
                    }

                    // MARK: - Watch
                    SettingsCard {
                        SettingsRow(icon: "applewatch", iconColor: .primary,
                                    title: "Apple Watch",
                                    subtitle: "Sync metrics and controls to your Watch")
                    }

                    // MARK: - POI & Export
                    SettingsCard {
                        SettingsRow(icon: "mappin.and.ellipse", iconColor: .orange,
                                    title: "Points of Interest",
                                    subtitle: "Manage POI categories and display")
                        Divider().padding(.leading, 54)
                        SettingsRow(icon: "square.and.arrow.up", iconColor: .purple,
                                    title: "Export",
                                    subtitle: "Export rides as GPX or FIT files")
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
            .sheet(isPresented: $showLanguagePicker) {
                LanguagePickerSheet()
            }
        }
    }

    @ViewBuilder
    private func settingsIcon(_ symbol: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(color.opacity(0.15))
                .frame(width: 36, height: 36)
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Language Picker Sheet

private struct LanguagePickerSheet: View {
    @ObservedObject private var lm = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [AppLanguage] {
        let all = AppLanguage.alphabetical
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return all }
        let q = query.lowercased()
        return all.filter {
            $0.displayName.lowercased().contains(q) ||
            $0.nativeName.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { lang in
                Button {
                    lm.set(lang)
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Text(lang.flag)
                            .font(.system(size: 26))
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.displayName)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(lang.nativeName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if lm.currentLanguage == lang {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.system(size: 20))
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search languages")
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Settings Card

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
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
