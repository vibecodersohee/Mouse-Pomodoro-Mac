import SwiftUI

/// The ivory-colored footer every screen ends with, ported from the Figma "Bottom" component.
struct BottomBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 8) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(DS.Color.bottomBar)
    }
}

/// The full-width green CTA button (e.g. "Start Focus Session", "Pause", "Resume").
struct PrimaryButton: View {
    let title: String
    var icon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 24, height: 24)
                }
                Text(title)
                    .font(DS.Font.semibold(18))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(DS.Color.primaryButton)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

/// The row of smaller text-only links under the primary button
/// (e.g. "End session early" / "Wrap up today"), or the two-button row in a
/// confirm modal ("Keep going!" / "End session"). Ported from the design
/// system's "Secondary" button (Default/Danger states) — plain text, no
/// background or border, equal-width when there's more than one.
struct SecondaryButtonRow: View {
    let items: [(title: String, isDanger: Bool, action: () -> Void)]
    /// `true` = each button hugs its text and the row is space-between (the Break
    /// footer); `false` = equal-width buttons (Focus footer, confirm modals).
    let spaced: Bool

    init(items: [(title: String, action: () -> Void)], spaced: Bool = false) {
        self.items = items.map { ($0.title, false, $0.action) }
        self.spaced = spaced
    }

    init(danger items: [(title: String, isDanger: Bool, action: () -> Void)]) {
        self.items = items
        self.spaced = false
    }

    var body: some View {
        HStack(spacing: spaced ? 0 : 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if spaced, index > 0 { Spacer(minLength: 0) }
                Button(action: item.action) {
                    Text(item.title)
                        .font(DS.Font.semibold(14))
                        .foregroundStyle(item.isDanger ? DS.Color.danger : DS.Color.secondaryText)
                        .frame(maxWidth: spaced ? nil : .infinity)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
