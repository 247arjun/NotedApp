import SwiftUI
import NotedKit

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var themeID: String = AppSettings.shared.defaultThemeID
    @State private var fontSize: Double = Double(AppSettings.shared.defaultFontSize)

    var body: some View {
        Form {
            Section("Storage") {
                HStack {
                    Image(systemName: appModel.usingICloud ? "icloud.fill" : "internaldrive")
                        .foregroundStyle(appModel.usingICloud ? .blue : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appModel.usingICloud ? "iCloud Drive" : "On This Device")
                            .font(.body)
                        Text(appModel.usingICloud
                             ? "Notes are synced via iCloud Drive › Noted."
                             : "Sign into iCloud in Settings to enable sync.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Refresh from iCloud") {
                    appModel.refresh()
                }
                .disabled(!appModel.usingICloud)
            }

            Section("Appearance") {
                Picker("Default theme", selection: $themeID) {
                    ForEach(ThemeRegistry.allThemes) { theme in
                        HStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(theme.headerBackgroundColor))
                                .frame(width: 16, height: 16)
                            Text(theme.displayName)
                        }
                        .tag(theme.id)
                    }
                }
                .onChange(of: themeID) { _, new in
                    AppSettings.shared.defaultThemeID = new
                }
            }

            Section("Editor") {
                HStack {
                    Text("Default size")
                    Spacer()
                    Stepper(value: $fontSize, in: 9...48, step: 1) {
                        Text("\(Int(fontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .onChange(of: fontSize) { _, new in
                        AppSettings.shared.defaultFontSize = CGFloat(new)
                    }
                }
            }

            Section {
                LabeledContent("Version", value: appVersion)
            } header: { Text("About") }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }
}
