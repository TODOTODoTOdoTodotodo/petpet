import Foundation

/// 정수 픽셀 사각형 (왼쪽 위 원점, 아래로 +y)
struct PixelBox: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    static let empty = PixelBox(x: 0, y: 0, width: 0, height: 0)

    var isEmpty: Bool { width <= 0 || height <= 0 }
    var maxX: Int { x + width }
    var maxY: Int { y + height }

    func intersection(_ other: PixelBox) -> PixelBox {
        let left = max(x, other.x), top = max(y, other.y)
        let right = min(maxX, other.maxX), bottom = min(maxY, other.maxY)
        return right > left && bottom > top ? PixelBox(x: left, y: top, width: right - left, height: bottom - top) : .empty
    }

    func union(_ other: PixelBox) -> PixelBox {
        if isEmpty { return other }
        if other.isEmpty { return self }
        let left = min(x, other.x), top = min(y, other.y)
        return PixelBox(x: left, y: top, width: max(maxX, other.maxX) - left, height: max(maxY, other.maxY) - top)
    }
}

/// 미리 곱한 BGRA 그림 (위쪽 줄부터). 윈도우 레이어드 창과 같은 배치
struct PremultipliedImage {
    let width: Int
    let height: Int
    let bgra: [UInt8]

    /// 곧은 알파 RGBA 픽셀(PNGDecoder 결과)에서
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

    init(width: Int, height: Int, bgra: [UInt8]) {
        self.width = width
        self.height = height
        self.bgra = bgra
    }
}

/// This object is responsible for software compositing on a premultiplied BGRA surface for platforms
/// that draw sprites themselves (Windows layered windows): clearing regions, and drawing a sprite scaled
/// with nearest-neighbor sampling (pixel art stays sharp), mirrored or flipped, turned about its center, with its top part hidden
/// and with extra transparency, blended over what is already there, plus invisible hit areas so a pet's whole
/// grab box takes clicks. It also tracks what changed since
/// the last upload so only that region needs to reach the screen.
final class PixelCanvas {
    let width: Int
    let height: Int
    private(set) var bgra: [UInt8]
    /// 마지막으로 내보낸 뒤 바뀐 영역
    private(set) var dirty = PixelBox.empty

    var bounds: PixelBox { PixelBox(x: 0, y: 0, width: width, height: height) }

    init(width: Int, height: Int) {
        self.width = max(width, 0)
        self.height = max(height, 0)
        bgra = [UInt8](repeating: 0, count: self.width * self.height * 4)
    }

    /// 영역을 투명하게
    func clear(_ box: PixelBox) {
        let area = box.intersection(bounds)
        guard !area.isEmpty else { return }
        for row in area.y..<area.maxY {
            let start = (row * width + area.x) * 4
            for index in start..<(start + area.width * 4) { bgra[index] = 0 }
        }
        dirty = dirty.union(area)
    }

    /// box에 그림을 늘려 그림. visibleShare: 아래쪽에서부터 보일 비율 (0이면 안 그림). 실제로 그린 영역을 돌려줌
    @discardableResult
    func draw(_ image: PremultipliedImage, in box: PixelBox, mirrored: Bool = false, flipped: Bool = false,
              visibleShare: CGFloat = 1, alpha: CGFloat = 1) -> PixelBox {
        guard !box.isEmpty, image.width > 0, image.height > 0, image.bgra.count >= image.width * image.height * 4 else { return .empty }
        let hiddenRows = Int((CGFloat(box.height) * (1 - min(max(visibleShare, 0), 1))).rounded())
        let shown = PixelBox(x: box.x, y: box.y + hiddenRows, width: box.width, height: box.height - hiddenRows)
        let area = shown.intersection(bounds)
        let opacity = UInt32((min(max(alpha, 0), 1) * 255).rounded())
        guard !area.isEmpty, opacity > 0 else { return .empty }

        for row in area.y..<area.maxY {
            // 칸 가운데로 원본 픽셀을 고름 (최근접)
            var sourceRow = ((row - box.y) * 2 + 1) * image.height / (box.height * 2)
            if flipped { sourceRow = image.height - 1 - sourceRow }
            for column in area.x..<area.maxX {
                var sourceColumn = ((column - box.x) * 2 + 1) * image.width / (box.width * 2)
                if mirrored { sourceColumn = image.width - 1 - sourceColumn }
                // 디버그 빌드에서도 빠르게: 자주 도는 길이라 함수 호출 없이 바로 섞음
                let source = (sourceRow * image.width + sourceColumn) * 4
                let sourceAlpha = Self.scale(UInt32(image.bgra[source + 3]), opacity)
                guard sourceAlpha > 0 else { continue }
                let target = (row * width + column) * 4
                let keep = 255 - sourceAlpha
                for channel in 0..<3 {
                    let color = Self.scale(UInt32(image.bgra[source + channel]), opacity)
                    bgra[target + channel] = UInt8(min(color + Self.scale(UInt32(bgra[target + channel]), keep), 255))
                }
                bgra[target + 3] = UInt8(min(sourceAlpha + Self.scale(UInt32(bgra[target + 3]), keep), 255))
            }
        }
        dirty = dirty.union(area)
        return area
    }

    /// 가운데(center, 픽셀)에 size로 늘려 rotation(라디안, 화면에서 반시계)만큼 돌려 그림 (최근접).
    /// 맥 SpriteKit의 zRotation과 같은 방향. 돌지 않으면 box 그리기와 같음. 실제로 그린 영역을 돌려줌
    @discardableResult
    func draw(_ image: PremultipliedImage, center: CGPoint, size: CGSize, rotation: CGFloat,
              mirrored: Bool = false, flipped: Bool = false, alpha: CGFloat = 1) -> PixelBox {
        guard rotation != 0 else {
            let box = PixelBox(x: Int((center.x - size.width / 2).rounded()), y: Int((center.y - size.height / 2).rounded()),
                               width: Int(size.width.rounded()), height: Int(size.height.rounded()))
            return draw(image, in: box, mirrored: mirrored, flipped: flipped, alpha: alpha)
        }
        guard size.width >= 1, size.height >= 1, image.width > 0, image.height > 0,
              image.bgra.count >= image.width * image.height * 4 else { return .empty }
        let opacity = UInt32((min(max(alpha, 0), 1) * 255).rounded())
        guard opacity > 0 else { return .empty }
        let c = cos(rotation), s = sin(rotation)
        let halfX = (abs(size.width * c) + abs(size.height * s)) / 2, halfY = (abs(size.width * s) + abs(size.height * c)) / 2
        let reach = PixelBox(x: Int((center.x - halfX).rounded(.down)) - 1, y: Int((center.y - halfY).rounded(.down)) - 1,
                             width: Int((halfX * 2).rounded(.up)) + 3, height: Int((halfY * 2).rounded(.up)) + 3)
        let area = reach.intersection(bounds)
        guard !area.isEmpty else { return .empty }

        var touched = PixelBox.empty
        for row in area.y..<area.maxY {
            var first: Int?, last = 0
            for column in area.x..<area.maxX {
                // 칸 가운데를 위로 +y 좌표로 바꿔 거꾸로 돌린 뒤, 그림 안 비율(u 왼→오, v 위→아래)로
                let dx = CGFloat(column) + 0.5 - center.x, up = center.y - (CGFloat(row) + 0.5)
                let localX = dx * c + up * s, localUp = -dx * s + up * c
                var u = localX / size.width + 0.5, v = 0.5 - localUp / size.height
                guard u >= 0, u < 1, v >= 0, v < 1 else { continue }
                if mirrored { u = 1 - u }
                if flipped { v = 1 - v }
                let sourceColumn = min(Int(u * CGFloat(image.width)), image.width - 1)
                let sourceRow = min(Int(v * CGFloat(image.height)), image.height - 1)
                if blend(image.bgra, at: (sourceRow * image.width + sourceColumn) * 4, into: (row * width + column) * 4, opacity: opacity) {
                    if first == nil { first = column }
                    last = column
                }
            }
            if let first { touched = touched.union(PixelBox(x: first, y: row, width: last - first + 1, height: 1)) }
        }
        dirty = dirty.union(touched)
        return touched
    }

    /// 원본 픽셀 하나를 투명도를 곱해 겹침 (source-over). 그렸으면 true
    private func blend(_ source: [UInt8], at index: Int, into target: Int, opacity: UInt32) -> Bool {
        let sourceAlpha = Self.scale(UInt32(source[index + 3]), opacity)
        guard sourceAlpha > 0 else { return false }
        let keep = 255 - sourceAlpha
        for channel in 0..<3 {
            let color = Self.scale(UInt32(source[index + channel]), opacity)
            bgra[target + channel] = UInt8(min(color + Self.scale(UInt32(bgra[target + channel]), keep), 255))
        }
        bgra[target + 3] = UInt8(min(sourceAlpha + Self.scale(UInt32(bgra[target + 3]), keep), 255))
        return true
    }

    /// 클릭만 받는 칸의 알파 (레이어드 창은 알파 0 픽셀의 클릭을 뒤 창으로 넘김). 눈에는 안 보임
    static let hitAlpha: UInt8 = 1

    /// 빈 픽셀만 hitAlpha로 채워 영역 전체가 클릭을 받게 함 (그린 픽셀은 그대로). 채운 영역을 돌려줌
    @discardableResult
    func markHitArea(_ box: PixelBox) -> PixelBox {
        let area = box.intersection(bounds)
        guard !area.isEmpty else { return .empty }
        for row in area.y..<area.maxY {
            for column in area.x..<area.maxX {
                let alpha = (row * width + column) * 4 + 3
                if bgra[alpha] == 0 { bgra[alpha] = Self.hitAlpha }
            }
        }
        dirty = dirty.union(area)
        return area
    }

    /// value × factor / 255 반올림 (잘라 버리면 겹칠수록 어두워짐)
    private static func scale(_ value: UInt32, _ factor: UInt32) -> UInt32 {
        (value * factor + 127) / 255
    }

    /// 바뀐 영역을 넘겨받고 비움 (화면에 올린 뒤)
    func takeDirty() -> PixelBox {
        defer { dirty = .empty }
        return dirty
    }

    /// 보이는 픽셀 수 (연기 시험용, 클릭만 받는 칸은 뺌)
    var visiblePixelCount: Int {
        stride(from: 3, to: bgra.count, by: 4).reduce(0) { $0 + (bgra[$1] > Self.hitAlpha ? 1 : 0) }
    }
}
