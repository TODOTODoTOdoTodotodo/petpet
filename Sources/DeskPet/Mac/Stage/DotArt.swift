import AppKit
import SpriteKit

/// This object is responsible for turning text pixel grids (weapons, items) into crisp images:
/// SpriteKit textures for the stage and small menu icons, with a gray silhouette for items not found yet.
enum DotArt {
    private static var textures: [String: SKTexture] = [:]
    private static var icons: [String: NSImage] = [:]

    static func texture(named name: String, rows: [String], palette: [Character: UInt32]) -> SKTexture {
        if let cached = textures[name] { return cached }
        let texture = image(rows: rows, palette: palette).map { SKTexture(cgImage: $0) } ?? SKTexture()
        texture.filteringMode = .nearest
        textures[name] = texture
        return texture
    }

    /// 메뉴 아이콘 (가로세로 side pt). silhouette이면 회색 그림자만
    static func icon(named name: String, rows: [String], palette: [Character: UInt32], side: CGFloat = 16, silhouette: Bool = false) -> NSImage? {
        let key = "\(name)|\(silhouette)|\(side)"
        if let cached = icons[key] { return cached }
        let colors = silhouette ? palette.mapValues { _ in UInt32(0x9A9AA2) } : palette
        guard let cgImage = image(rows: rows, palette: colors) else { return nil }
        let icon = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .none
            NSGraphicsContext.current?.cgContext.draw(cgImage, in: rect)
            return true
        }
        icons[key] = icon
        return icon
    }

    static func image(rows: [String], palette: [Character: UInt32]) -> CGImage? {
        let height = rows.count
        let width = rows.map(\.count).max() ?? 0
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for (y, row) in rows.enumerated() {
            for (x, symbol) in row.enumerated() {
                guard let color = palette[symbol] else { continue }
                let index = (y * width + x) * 4
                bytes[index] = UInt8((color >> 16) & 0xFF)
                bytes[index + 1] = UInt8((color >> 8) & 0xFF)
                bytes[index + 2] = UInt8(color & 0xFF)
                bytes[index + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// 한 무대에 그릴 물건 하나 (전역 좌표)
struct ItemDrawing {
    let id: String
    let kind: ItemKind
    /// 그림 사각형
    let rect: CGRect
    let alpha: CGFloat
    /// 드문 물건의 반짝임, 또는 클릭했을 때의 반짝임 세기 (0이면 없음)
    let sparkle: CGFloat
    /// 드문 물건이 메뉴바로 날아가며 반짝임 꼬리를 남기는지
    let trail: Bool

    init(_ item: DroppedItem, clock: TimeInterval) {
        id = item.id
        kind = item.kind
        rect = item.rect
        alpha = item.isBlinkedOut ? 0.15 : CGFloat(1 - 0.4 * (item.flightProgress ?? 0))
        let flash = CGFloat(item.flashLeft / DroppedItem.flashTime)
        let rare = item.kind.rarity == .rare && item.flightProgress == nil ? CGFloat(0.35 + 0.35 * sin(clock * 5)) : 0
        sparkle = max(flash, rare)
        trail = item.kind.rarity == .rare && item.isFlying
    }
}
