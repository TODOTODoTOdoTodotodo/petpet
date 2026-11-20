import AppKit
import SpriteKit

/// 맥에서 쓰는 스킨 (SpriteKit 텍스처)
typealias MacSkin = PetSkin<SKTexture>
typealias MacSkinLibrary = SkinLibrary<SKTexture>

/// 맥 무대가 그리는 펫 하나 (SpriteKit 텍스처)
typealias MacPetDrawing = PetDrawing<SKTexture>

/// This object is responsible for decoding a skin PNG on macOS into a pixel-sharp SpriteKit texture,
/// plus its RGBA pixels so blank cells and body size can be measured by the shared code.
enum MacSpriteLoader {
    static func load(_ url: URL) -> LoadedSprite<SKTexture>? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap(Self.pixels(of:))
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return LoadedSprite(frame: texture, pixels: pixels)
    }

    /// CGImage를 위쪽 줄부터의 RGBA 픽셀로
    static func pixels(of image: CGImage) -> SpritePixels? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return SpritePixels(width: width, height: height, rgba: []) }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? SpritePixels(width: width, height: height, rgba: rgba) : nil
    }
}
