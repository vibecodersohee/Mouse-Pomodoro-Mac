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
        static let overlayDim = SwiftUI.Color(hex: "#2e3a22").opacity(0.45)
    }

    enum Font {
        static func regular(_ size: CGFloat) -> SwiftUI.Font { .custom("PixelifySans-Regular", size: size) }
        static func medium(_ size: CGFloat) -> SwiftUI.Font { .custom("PixelifySans-Medium", size: size) }
        static func semibold(_ size: CGFloat) -> SwiftUI.Font { .custom("PixelifySans-SemiBold", size: size) }
        static func bold(_ size: CGFloat) -> SwiftUI.Font { .custom("PixelifySans-Bold", size: size) }
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
