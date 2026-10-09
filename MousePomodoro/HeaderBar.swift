import SwiftUI

/// Ported from the Figma "Header" component shared by every screen:
/// mouse name (left), cheese count pill (center), action icons (right).
struct HeaderBar: View {
    let mouseName: String
    let cheeseLabel: String
    var onCalendar: () -> Void = {}
    var onCollapse: () -> Void = {}
    /// The plugin disables Minimize on the Plan screen.
    var collapseDisabled = false
    var onSettings: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image("icon-mouse-face")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 24, height: 24)
                Text(mouseName)
                    .font(DS.Font.regular(14))
            }
            .foregroundStyle(DS.Color.ink)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Image("icon-cheese")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(cheeseLabel)
                    .font(DS.Font.semibold(14))
            }
            .foregroundStyle(DS.Color.inkSoft)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(DS.Color.screenCard)
            .clipShape(Capsule())

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                iconButton("icon-calendar-weeks", action: onCalendar)
                iconButton("icon-collapse", action: onCollapse)
                    .disabled(collapseDisabled)
                    .opacity(collapseDisabled ? 0.3 : 1)
                iconButton("icon-settings-cog", action: onSettings)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(SwiftUI.Color.white)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Color.border).frame(height: 1)
        }
    }

    private func iconButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(name)
                .renderingMode(.template)
                .resizable()
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.Color.ink)
    }
}
