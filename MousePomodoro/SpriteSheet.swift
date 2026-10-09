import Foundation

/// The mouse pixel-art sprites, ported directly from the Figma plugin's `sprites.json`:
/// each sprite is a 32x32 grid of palette-key characters ("." = transparent).
/// The plugin rasterizes these into run-length-encoded SVG rects at render time;
/// natively we draw the same grid straight into a SwiftUI `Canvas` (see SpriteView).
struct SpriteSheet: Decodable {
    let palette: [String: String]
    let sprites: [String: [String]]

    static let shared: SpriteSheet = {
        guard let url = Bundle.main.url(forResource: "sprites", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let sheet = try? JSONDecoder().decode(SpriteSheet.self, from: data) else {
            fatalError("sprites.json missing or malformed in app bundle")
        }
        return sheet
    }()
}

enum MouseSprite: String {
    case cheese, dancing, feeding, focusing, idle, jumping, regular, sleeping
}
