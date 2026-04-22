import SwiftUI

// MARK: - ThemePickerView

/// SwiftUI view shown in a popover for per-note theme selection.
struct ThemePickerView: View {
    let currentThemeID: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ThemeRegistry.allThemes) { theme in
                Button {
                    onSelect(theme.id)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(nsColor: theme.headerBackgroundColor))
                            .frame(width: 26, height: 26)
                        if theme.id == currentThemeID {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.7), lineWidth: 2.5)
                                .frame(width: 30, height: 30)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.displayName)
                .accessibilityAddTraits(theme.id == currentThemeID ? .isSelected : [])
            }
        }
        .padding(12)
    }
}
