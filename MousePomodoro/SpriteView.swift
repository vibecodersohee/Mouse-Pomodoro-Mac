import SwiftUI

/// Renders one 32x32 pixel-grid mouse sprite from `SpriteSheet` via `Canvas`,
/// drawing each run of same-colored pixels as a filled rect (vector, so it stays
/// crisp at any size — no bitmap scaling artifacts).
struct SpriteView: View {
    let sprite: MouseSprite
    var size: CGFloat = 64

    var body: some View {
        Canvas { context, canvasSize in
            let sheet = SpriteSheet.shared
            guard let rows = sheet.sprites[sprite.rawValue] else { return }
            let cell = canvasSize.width / 32

            for (y, row) in rows.enumerated() {
                var x = 0
                let chars = Array(row)
                while x < chars.count {
                    let ch = chars[x]
                    if ch == "." {
                        x += 1
                        continue
                    }
                    var x2 = x
                    while x2 < chars.count, chars[x2] == ch { x2 += 1 }
                    if let hex = sheet.palette[String(ch)] {
                        let rect = CGRect(
                            x: CGFloat(x) * cell,
                            y: CGFloat(y) * cell,
                            width: CGFloat(x2 - x) * cell,
                            height: cell
                        )
                        context.fill(Path(rect), with: .color(Color(hex: hex)))
                    }
                    x = x2
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// The plugin's four sprite motions (`bob`/`hop`/`wiggle`/`pop` keyframes in
/// ui.src.html). All distances are in sprite "cells" (one pixel of the 32x32
/// grid), so they scale with `size` exactly like the plugin's `--cell` var.
enum SpriteMotion {
    case none
    case bob      // idle/focus/break: 2-frame bob, 1 cell up for the second half of 1.2s, looping
    case hop      // jump: 0.6s, one-shot
    case wiggle   // dancing: 0.36s stepped sway, looping
    case pop      // complete: 0.5s stepped rise-and-settle, one-shot
}

struct AnimatedSpriteView: View {
    let sprite: MouseSprite
    var motion: SpriteMotion = .none
    var size: CGFloat = 128
    /// Bump to restart a one-shot motion that's already playing (e.g. a second tap on a hop).
    var restartToken = 0

    @State private var start = Date()

    var body: some View {
        let cell = size / 32
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let m = Self.transform(motion, t: context.date.timeIntervalSince(start), cell: cell)
            SpriteView(sprite: sprite, size: size)
                .scaleEffect(m.scale)
                .offset(x: m.x, y: m.y)
        }
        .frame(width: size, height: size)
        .onChange(of: motion) { _, _ in start = Date() }
        .onChange(of: restartToken) { _, _ in start = Date() }
    }

    private static func transform(_ motion: SpriteMotion, t: TimeInterval, cell: CGFloat) -> (x: CGFloat, y: CGFloat, scale: CGFloat) {
        switch motion {
        case .none:
            return (0, 0, 1)

        case .bob:
            let phase = t.truncatingRemainder(dividingBy: 1.2)
            return (0, phase >= 0.6 ? -cell : 0, 1)

        case .hop:
            // 0% 0 · 30% -5 · 55% 0 · 75% -2 · 100% 0, ease-out within each leg
            let keys: [(f: Double, y: Double)] = [(0, 0), (0.30, -5), (0.55, 0), (0.75, -2), (1, 0)]
            let f = min(max(t / 0.6, 0), 1)
            for i in 1..<keys.count where f <= keys[i].f {
                let p = (f - keys[i - 1].f) / (keys[i].f - keys[i - 1].f)
                let eased = 1 - (1 - p) * (1 - p)
                let y = keys[i - 1].y + (keys[i].y - keys[i - 1].y) * eased
                return (0, CGFloat(y) * cell, 1)
            }
            return (0, 0, 1)

        case .wiggle:
            // steps(2, end) across 0 → -1 → +1 → 0 cells
            let f = t.truncatingRemainder(dividingBy: 0.36) / 0.36
            let x: CGFloat
            switch f {
            case ..<0.125: x = 0
            case ..<0.25: x = -0.5
            case ..<0.5: x = -1
            case ..<0.75: x = 0
            case ..<0.875: x = 1
            default: x = 0.5
            }
            return (x * cell, 0, 1)

        case .pop:
            // steps(5, end): +2 cells & 0.9 scale → -2 cells (0–60%), then → 0 (60–100%)
            let f = t / 0.5
            if f >= 1 { return (0, 0, 1) }
            if f < 0.6 {
                let k = Double(Int((f / 0.6) * 5))
                return (0, CGFloat(2 - 4 * k / 5) * cell, CGFloat(0.9 + 0.1 * k / 5))
            }
            let k = Double(Int(((f - 0.6) / 0.4) * 5))
            return (0, CGFloat(-2 + 2 * k / 5) * cell, 1)
        }
    }
}

#Preview {
    HStack {
        SpriteView(sprite: .idle)
        SpriteView(sprite: .focusing)
        SpriteView(sprite: .cheese)
    }
    .padding()
}
