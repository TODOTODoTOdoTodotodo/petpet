import Foundation

/// This object is responsible for one skin picture ready for Windows drawing: premultiplied BGRA pixels,
/// top row first — the layout `UpdateLayeredWindow` expects — decoded by the shared `PNGDecoder` (no WIC).
final class WinSprite {
    let width: Int
    let height: Int
    let bgra: [UInt8]

    init(pixels: SpritePixels) {
        width = pixels.width
        height = pixels.height
        var bgra = [UInt8](repeating: 0, count: pixels.rgba.count)
        for index in stride(from: 0, to: pixels.rgba.count, by: 4) {
            let alpha = UInt16(pixels.rgba[index + 3])
            bgra[index] = UInt8(UInt16(pixels.rgba[index + 2]) * alpha / 255)
            bgra[index + 1] = UInt8(UInt16(pixels.rgba[index + 1]) * alpha / 255)
            bgra[index + 2] = UInt8(UInt16(pixels.rgba[index]) * alpha / 255)
            bgra[index + 3] = UInt8(alpha)
        }
        self.bgra = bgra
    }

    static func load(_ url: URL) -> LoadedSprite<WinSprite>? {
        PNGDecoder.decode(contentsOf: url).map { LoadedSprite(frame: WinSprite(pixels: $0), pixels: $0) }
    }
}

/// 윈도우판 스킨
typealias WinSkin = PetSkin<WinSprite>
