import SwiftUI

/// Colors and type ported directly from the Figma design system (Final UI section).
enum DS {
    enum Color {
        static let ink = SwiftUI.Color(hex: "#2e3a22")
        static let inkSoft = SwiftUI.Color(hex: "#3e5a28")
        static let secondaryText = SwiftUI.Color(hex: "#2b3f17")
        static let screenCard = SwiftUI.Color(hex: "#d3e7b1")
        static let bottomBar = SwiftUI.Color(hex: "#f4f1e6")
        static let primaryButton = SwiftUI.Color(hex: "#5c7a3e")
        static let danger = SwiftUI.Color(hex: "#b85c3e")
        static let border = SwiftUI.Color(hex: "#a8b896")
        static let inputBackground = SwiftUI.Color(hex: "#fcfbf8")
        static let shopItem = SwiftUI.Color(hex: "#fafafa")
        static let shopItemActive = SwiftUI.Color(hex: "#f3f8e9")
        static let shopItemActiveBorder = SwiftUI.Color(hex: "#9bbc7b")
        static let shopItemLocked = SwiftUI.Color(hex: "#d2d2d2")
        static let tabInactive = SwiftUI.Color(hex: "#bad693")
        static let levelBanner = SwiftUI.Color(hex: "#41571b")
        static let overlayDim = SwiftUI.Color(hex: "#2e3a22").opacity(0.45)
    }

    enum Font {
        static func regular(_ size: CGFloat) -> SwiftUI.Font { .custom("PixelifySans-Regular", size: size) }
        static func medium(_ size: CGFloat) -> SwiftUI.Font { .custom("PixelifySans-Medium", size: size) }
        static func semibold(_ size: CGFloat) -> SwiftUI.Font { .custom("PixelifySans-SemiBold", size: size) }
        static func bold(_ size: CGFloat) -> SwiftUI.Font { .custom("PixelifySans-Bold", size: size) }
    }
}

/// The design system's Toggle (Figma 233:5207): a 32×20 pill with a 14px white knob.
/// Off = grey, On = green.
struct PixelToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? SwiftUI.Color(hex: "#627548") : SwiftUI.Color(hex: "#a5a5a5"))
                Capsule()
                    .fill(isOn ? SwiftUI.Color(hex: "#92af6c") : SwiftUI.Color(hex: "#d2d2d2"))
                    .padding(1)
                Circle().fill(SwiftUI.Color.white).frame(width: 14, height: 14).padding(.horizontal, 3)
            }
                .frame(width: 32, height: 20)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
        .animation(.easeOut(duration: 0.12), value: isOn)
    }
}

/// The design system's 48px numeric Input (Plan + Settings rows). Digits only,
/// max two characters; the bound value is clamped live and the text is
/// normalized on blur/submit. Border turns `inkSoft` while focused (Figma's
/// "Status=Active" variant).
struct NumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(DS.Font.regular(14))
            .foregroundStyle(DS.Color.ink)
            .padding(8)
            .frame(width: 48)
            .background(DS.Color.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(focused ? DS.Color.inkSoft : DS.Color.border, lineWidth: 1)
            )
            .focused($focused)
            .onAppear { text = String(value) }
            .onChange(of: text) { _, new in
                let digits = String(new.filter(\.isNumber).prefix(2))
                if digits != new { text = digits }
                if let n = Int(digits) {
                    value = min(max(n, range.lowerBound), range.upperBound)
                }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onChange(of: value) { _, newValue in
                if !focused { text = String(newValue) }
            }
            .onSubmit { commit() }
    }

    private func commit() {
        let n = Int(text) ?? value
        let clamped = min(max(n, range.lowerBound), range.upperBound)
        value = clamped
        text = String(clamped)
    }
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
