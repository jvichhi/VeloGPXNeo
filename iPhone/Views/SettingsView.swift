import SwiftUI

struct SettingsView: View {
    @ObservedObject private var lm = LocalizationManager.shared
    @State private var showLanguagePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // MARK: - Language
                    SettingsCard {
                        Button {
                            showLanguagePicker = true
                        } label: {
                            HStack(alignment: .center, spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(Color.indigo.opacity(0.15))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "globe")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(.indigo)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("settings.language".localized)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("settings.language_subtitle".localized)
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

                    // MARK: - Import
                    SettingsCard {
                        SettingsRow(
                            icon: "square.and.arrow.down",
                            iconColor: .blue,
                            title: "settings.import".localized,
                            subtitle: "settings.import_subtitle".localized
                        )
                    }

                    // MARK: - Map
                    SettingsCard {
                        SettingsRow(
                            icon: "map.fill",
                            iconColor: .green,
                            title: "settings.map_engine".localized,
                            subtitle: "settings.map_engine_subtitle".localized
                        )
                        Divider().padding(.leading, 54)
                        SettingsRow(
                            icon: "safari.fill",
                            iconColor: .blue,
                            title: "settings.birdseye".localized,
                            subtitle: "settings.birdseye_subtitle".localized
                        )
                    }

                    // MARK: - Watch
                    SettingsCard {
                        SettingsRow(
                            icon: "applewatch",
                            iconColor: .primary,
                            title: "settings.apple_watch".localized,
                            subtitle: "settings.apple_watch_subtitle".localized
                        )
                    }

                    // MARK: - POI & Export
                    SettingsCard {
                        SettingsRow(
                            icon: "mappin.and.ellipse",
                            iconColor: .orange,
                            title: "settings.poi".localized,
                            subtitle: "settings.poi_subtitle".localized
                        )
                        Divider().padding(.leading, 54)
                        SettingsRow(
                            icon: "square.and.arrow.up",
                            iconColor: .purple,
                            title: "settings.export".localized,
                            subtitle: "settings.export_subtitle".localized
                        )
                    }

                    Text("app.name".localized)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("settings.title".localized)
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showLanguagePicker) {
                LanguagePickerSheet()
            }
        }
    }
}

// MARK: - Language Picker Sheet

private struct LanguagePickerSheet: View {
    @ObservedObject private var lm = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss

    // Grouped regions for clean UX
    private let regions: [(String, [AppLanguage])] = [
        ("🌍 Western Europe", [.english, .french, .german, .italian, .spanish, .portuguese, .dutch]),
        ("🌿 Nordic",         [.danish, .swedish, .norwegian]),
        ("🏙 Central Europe", [.polish]),
        ("🌏 Asia Pacific",   [.japanese, .chinese, .korean]),
        ("🌙 Middle East",    [.arabic])
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(regions, id: \.0) { region, languages in
                    Section(region) {
                        ForEach(languages) { lang in
                            Button {
                                lm.set(lang)
                                dismiss()
                            } label: {
                                HStack(spacing: 14) {
                                    Text(lang.flag)
                                        .font(.system(size: 26))
                                        .frame(width: 34)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lang.displayName)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Text(lang.rawValue)
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
                                .padding(.vertical, 3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("settings.language".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
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
