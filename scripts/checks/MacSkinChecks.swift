#if canImport(AppKit)
import AppKit

/// This object is responsible for the skin checks that need macOS image decoding: the app's real
/// SpriteKit loader, and agreement between the portable PNG decoder and Core Graphics on every skin picture.
enum MacSkinChecks {
    static func run(_ check: Checker, skinsDirectory: URL) {
        check.section("스캐너 (맥)")
        check.expect(scanSinglePixelImage() == .visible(CGRect(x: 0, y: 0, width: 1, height: 1)),
                     "왼쪽 아래 픽셀을 아래 기준 좌표로 읽음", "\(scanSinglePixelImage())")

        check.section("PNG 해독 = Core Graphics")
        let files = (FileManager.default.enumerator(at: skinsDirectory, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension.lowercased() == "png" }
        let mismatched = files.filter { !decodesLikeCoreGraphics($0) }
        check.expect(!files.isEmpty && mismatched.isEmpty, "스킨 PNG \(files.count)장을 같은 픽셀로 읽음 (윈도우판 로더)",
                     mismatched.prefix(3).map(\.lastPathComponent).joined(separator: ", "))

        SkinChecks.runLibrary(check, skinsDirectory: skinsDirectory, loader: MacSpriteLoader.load,
                              pixels: { MacSpriteLoader.pixels(of: $0.cgImage()) })
    }

    /// 알파는 정확히 같고, 불투명 픽셀의 색은 색 관리 오차(±2) 안
    private static func decodesLikeCoreGraphics(_ url: URL) -> Bool {
        guard let portable = PNGDecoder.decode(contentsOf: url),
              let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let reference = MacSpriteLoader.pixels(of: image),
              portable.width == reference.width, portable.height == reference.height,
              portable.rgba.count == reference.rgba.count else { return false }
        for index in stride(from: 0, to: portable.rgba.count, by: 4) {
            let alpha = portable.rgba[index + 3]
            guard alpha == reference.rgba[index + 3] else { return false }
            guard alpha == 255 else { continue }
            for channel in 0..<3 where abs(Int(portable.rgba[index + channel]) - Int(reference.rgba[index + channel])) > 2 {
                return false
            }
        }
        return true
    }

    /// 4x4 이미지의 왼쪽 아래 1픽셀만 칠해 스캔
    private static func scanSinglePixelImage() -> SpriteAlphaScanner.Result {
        guard let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .unreadable }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let image = context.makeImage(), let pixels = MacSpriteLoader.pixels(of: image) else { return .unreadable }
        return SpriteAlphaScanner.scan(pixels)
    }
}
#endif
