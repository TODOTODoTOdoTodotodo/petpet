import Foundation

/// This object is responsible for one skin picture ready for Windows drawing: premultiplied BGRA pixels,
/// top row first — the layout layered windows expect — decoded by the shared `PNGDecoder` (no WIC).
/// A class, so the same frame is the same object, like a texture.
final class WinSprite {
    let image: PremultipliedImage

    init(pixels: SpritePixels) {
        image = PremultipliedImage(pixels: pixels)
    }

    static func load(_ url: URL) -> LoadedSprite<WinSprite>? {
        PNGDecoder.decode(contentsOf: url).map { LoadedSprite(frame: WinSprite(pixels: $0), pixels: $0) }
    }
}

/// 윈도우판 스킨
typealias WinSkin = PetSkin<WinSprite>
