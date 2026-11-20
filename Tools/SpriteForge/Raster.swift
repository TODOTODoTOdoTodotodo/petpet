import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 캔버스 한 장 (위에서 아래 줄, 투명은 nil)
typealias PixelGrid = [[RGBA?]]

/// This object is responsible for painting a rig in a pose onto a canvas and saving canvases as PNG files.
enum Raster {
    static func blank(_ size: Int) -> PixelGrid {
        Array(repeating: Array(repeating: nil, count: size), count: size)
    }

    /// 자세대로 부위를 뒤에서 앞으로 칠함. 칸 밖으로 나간 픽셀 수와, 위로 든 팔의 가장 윗줄을 함께 돌려줌
    static func render(_ rig: Rig, pose: Pose) -> (grid: PixelGrid, clipped: Int, raisedHandTop: Int?) {
        var grid = blank(rig.canvas)
        var clipped = 0
        var raisedHandTop: Int?
        let arms = ["frontArm", "backArm"]
        var order = Rig.drawOrder
        // 머리 위로 뻗는 팔은 머리 뒤에 그려 얼굴을 가리지 않게 함
        if pose.reachAboveHead, let headIndex = order.firstIndex(of: "head") {
            order.removeAll { arms.contains($0) }
            order.insert(contentsOf: arms, at: order.firstIndex(of: "head") ?? headIndex)
        }
        // 안테나·귀처럼 가는 돌출은 빼고 머리 본체의 윗줄 기준
        let headTop = rig.layers["head"].map { $0.y + solidTopRow($0) + pose.dy + (pose.parts["head"]?.dy ?? 0) }
        let headCenterX = rig.layers["head"].map { $0.x + $0.width / 2 + pose.dx + (pose.parts["head"]?.dx ?? 0) }
        let frontSide = rig.facingWest ? -1 : 1

        for name in order {
            guard let layer = rig.layers[name] else { continue }
            let part = pose.parts[name] ?? PartPose()
            var offset = (dx: pose.dx + part.dx, dy: pose.dy + part.dy)
            if pose.reachAboveHead, arms.contains(name), part.turn == .up, let headTop {
                // 손끝이 머리 본체 윗줄보다 2줄 위에 오도록 팔을 끌어올림
                let raisedTop = 2 * layer.pivot.y - (layer.y + layer.height - 1) + offset.dy
                offset.dy += min(0, (headTop - 2) - raisedTop)
                let handTop = raisedTop + min(0, (headTop - 2) - raisedTop)
                raisedHandTop = min(raisedHandTop ?? handTop, handTop)
                // 귀·뿔과 겹치지 않게 손을 머리 가운데 쪽으로 모음 (앞팔은 앞쪽, 뒷팔은 뒤쪽으로 3칸)
                if let headCenterX {
                    let side = name == "frontArm" ? frontSide : -frontSide
                    offset.dx = headCenterX + side * 3 - layer.pivot.x
                }
            }
            clipped += paint(layer, offset: offset, turn: part.turn, pivot: layer.pivot, facingWest: rig.facingWest, into: &grid)

            // 눈 감은 겹침은 머리를, 소품은 앞팔을 따라감
            if name == "head", pose.eyesClosed, let eyes = rig.overlays["eyesClosed"] {
                clipped += paint(eyes, offset: offset, turn: .none, pivot: eyes.pivot, facingWest: rig.facingWest, into: &grid)
            }
            if name == "frontArm", let prop = rig.overlays["prop"] {
                clipped += paint(prop, offset: offset, turn: part.turn, pivot: layer.pivot, facingWest: rig.facingWest, into: &grid)
            }
        }
        return (grid, clipped, raisedHandTop)
    }

    /// 칠한 칸이 폭의 절반 이상인 첫 줄 (가는 돌출을 건너뛴 본체 윗줄)
    static func solidTopRow(_ layer: Layer) -> Int {
        layer.pixels.firstIndex { row in row.filter { $0 != nil }.count * 2 >= layer.width } ?? 0
    }

    /// 부위 하나를 이동·회전해 칠함 (축은 절대 좌표)
    private static func paint(_ layer: Layer, offset: (dx: Int, dy: Int), turn: Turn, pivot: (x: Int, y: Int),
                              facingWest: Bool, into grid: inout PixelGrid) -> Int {
        var clipped = 0
        let size = grid.count
        for (row, line) in layer.pixels.enumerated() {
            for (column, color) in line.enumerated() {
                guard let color else { continue }
                let x = layer.x + column
                let y = layer.y + row
                var target: (x: Int, y: Int)
                switch turn {
                case .none:
                    target = (x, y)
                case .up:
                    target = (x, 2 * pivot.y - y)
                case .forward:
                    // 아래를 향한 팔이 바라보는 쪽을 향하도록 90도 회전
                    let relX = x - pivot.x
                    let relY = y - pivot.y
                    target = facingWest ? (pivot.x - relY, pivot.y + relX) : (pivot.x + relY, pivot.y - relX)
                }
                let finalX = target.x + offset.dx
                let finalY = target.y + offset.dy
                guard finalX >= 0, finalY >= 0, finalX < size, finalY < size else {
                    clipped += 1
                    continue
                }
                grid[finalY][finalX] = color
            }
        }
        return clipped
    }

    /// 보이는 픽셀이 있는 가장 윗줄
    static func topRow(_ grid: PixelGrid) -> Int? {
        grid.firstIndex { row in row.contains { $0 != nil } }
    }

    /// 보이는 픽셀이 있는 가장 아랫줄
    static func bottomRow(_ grid: PixelGrid) -> Int? {
        grid.lastIndex { row in row.contains { $0 != nil } }
    }

    /// 아래로 rows줄 밀기 (음수면 위로)
    static func shiftedDown(_ grid: PixelGrid, by rows: Int) -> PixelGrid {
        guard rows != 0 else { return grid }
        let size = grid.count
        let empty = [RGBA?](repeating: nil, count: size)
        if rows > 0 {
            return Array(repeating: empty, count: rows) + grid.prefix(size - rows)
        }
        return Array(grid.dropFirst(-rows)) + Array(repeating: empty, count: -rows)
    }

    /// 좌우 반전 (미리보기용)
    static func mirrored(_ grid: PixelGrid) -> PixelGrid {
        grid.map { $0.reversed() }
    }

    static func cgImage(_ grid: PixelGrid) -> CGImage? {
        let height = grid.count
        let width = grid.first?.count ?? 0
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for (y, row) in grid.enumerated() {
            for (x, color) in row.enumerated() {
                guard let color else { continue }
                let index = (y * width + x) * 4
                let alpha = UInt16(color.a)
                // CGImage는 미리 곱한 알파를 씀
                bytes[index] = UInt8(UInt16(color.r) * alpha / 255)
                bytes[index + 1] = UInt8(UInt16(color.g) * alpha / 255)
                bytes[index + 2] = UInt8(UInt16(color.b) * alpha / 255)
                bytes[index + 3] = color.a
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ForgeError(description: "PNG 저장 실패: \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ForgeError(description: "PNG 저장 실패: \(url.path)") }
    }

    static func writePNG(_ grid: PixelGrid, to url: URL) throws {
        guard let image = cgImage(grid) else { throw ForgeError(description: "이미지 생성 실패: \(url.path)") }
        try writePNG(image, to: url)
    }

    /// PNG·JPEG 등을 RGBA 격자로 읽음 (도트화 입력용)
    static func readImage(_ url: URL) throws -> (width: Int, height: Int, pixels: [RGBA]) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ForgeError(description: "이미지를 열 수 없음: \(url.path)")
        }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw ForgeError(description: "이미지를 읽을 수 없음: \(url.path)") }
        var pixels: [RGBA] = []
        pixels.reserveCapacity(width * height)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = bytes[index + 3]
            // 미리 곱한 값을 되돌림
            let unmultiply = { (value: UInt8) -> UInt8 in
                alpha == 0 ? 0 : UInt8(min(255, Int(value) * 255 / Int(alpha)))
            }
            pixels.append(RGBA(r: unmultiply(bytes[index]), g: unmultiply(bytes[index + 1]), b: unmultiply(bytes[index + 2]), a: alpha))
        }
        return (width, height, pixels)
    }
}
