import SwiftUI

/// The white-padded "Screen" frame wrapping every screen's content, and the
/// light-green rounded card inside it. Ported from the Figma "Screen" / "Screen" pair.
struct ScreenCard<Content: View>: View {
    var background: Color = DS.Color.screenCard
    /// A purchased/seasonal scene image name (Assets.xcassets `scene-<id>`),
    /// shown behind the flat background color on Focus/Break screens only.
    var sceneImageName: String?
    /// Figma's gap between stacked items: 16 on Idle/Plan/Complete/Entire-complete,
    /// 12 on Focus/Break.
    var spacing: CGFloat = 16
    /// 258 on every screen; `nil` lets the card hug its content (Weekly stats).
    var fixedHeight: CGFloat? = 258
    @ViewBuilder var content: () -> Content

    var body: some View {
        // Content flows from the top edge (after the 12px padding), exactly like
        // the plugin's flex column — it is NOT vertically centered in the card.
        VStack(spacing: spacing) {
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(12)
        .frame(height: fixedHeight)
        .background {
            if let sceneImageName {
                Image("scene-\(sceneImageName)")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                background
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(12)
        .background(SwiftUI.Color.white)
    }
}

/// The translucent timer readout pill shown on Focus/Break screens
/// ("FOCUS Time" / "20:00"), ported from the Figma design's blurred label.
struct TimerPill: View {
    let label: String
    var progress: String?
    let time: String
    var dimmed: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(DS.Font.bold(16))
                if let progress {
                    Text(progress)
                        .font(DS.Font.medium(12))
                }
            }
            Text(time)
                .font(DS.Font.bold(32))
                .foregroundStyle(dimmed ? DS.Color.ink.opacity(0.5) : DS.Color.ink)
        }
        .foregroundStyle(DS.Color.inkSoft)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
