import SwiftUI
import NotedKit

// MARK: - ThemePickerView

struct ThemePickerView: View {
    let currentThemeID: String
    let onPick: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Note Color")
                .font(.headline)
                .padding(.top, 16)

            HStack(spacing: 14) {
                ForEach(ThemeRegistry.allThemes) { theme in
                    Button {
                        onPick(theme.id)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(theme.headerBackgroundColor))
                                .frame(width: 44, height: 44)
                            if theme.id == currentThemeID {
                                Circle()
                                    .stroke(Color.accentColor, lineWidth: 3)
                                    .frame(width: 50, height: 50)
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color(theme.titleTextColor))
                                    .bold()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.displayName)
                }
            }
            .padding(.horizontal, 16)
            Spacer()
        }
    }
}
