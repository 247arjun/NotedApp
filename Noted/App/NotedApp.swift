import SwiftUI

// MARK: - App Entry Point

@main
struct NotedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Noted")
                .font(.title)
                .fontWeight(.semibold)
            Text("v1.0")
                .foregroundStyle(.secondary)
            Text("A native macOS sticky notes app.")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(40)
        .frame(width: 300, height: 220)
    }
}
