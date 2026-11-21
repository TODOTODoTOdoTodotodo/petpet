import Foundation

/// This object is responsible for finding where a character's head moved to in one animation frame,
/// compared with its standing picture: the top part of the standing body is used as a template and slid
/// over the frame to the place where the most pixels agree in color. Raised arms or weapons above the head
/// do not fool it, because they do not look like the head. Runs once while a skin loads, never per tick.
enum HeadTracker {
    /// 몸 높이 중 머리 본으로 쓰는 위쪽 비율
    static let headShare = 0.4
    /// 찾는 범위 (이미지 픽셀, 좌우·위아래)
    static let reachX = 4
    static let reachY = 6
    /// 본 픽셀 중 이만큼은 맞아야 찾은 것으로 봄
    static let minimumAgreement = 0.6
    /// 같은 색으로 보는 RGB 차이 합
    static let colorTolerance = 60

    /// 머리 본: 기준 그림 위쪽의 보이는 픽셀 (열, 행, 색)
    struct Template {
        fileprivate let points: [(column: Int, row: Int, rgb: (Int, Int, Int))]
        /// 기준 그림의 보이는 맨 윗줄
        fileprivate let top: Int
        let width: Int

        var isEmpty: Bool { points.isEmpty }
    }

    static func template(from reference: SpritePixels, mirrored: Bool = false) -> Template? {
        let pixels = mirrored ? reference.mirrored() : reference
        guard case .visible(let bounds) = SpriteAlphaScanner.scan(pixels) else { return nil }
        let top = pixels.height - Int(bounds.maxY)
        let rows = max(4, Int((Double(bounds.height) * headShare).rounded()))
        var points: [(column: Int, row: Int, rgb: (Int, Int, Int))] = []
        for row in top..<min(pixels.height, top + rows) {
            for column in 0..<pixels.width where pixels.alpha(column: column, row: row) > 0 {
                points.append((column, row, pixels.rgb(column: column, row: row)))
            }
        }
        return Template(points: points, top: top, width: pixels.width)
    }

    /// 기준 그림 대비 머리 이동 (이미지 픽셀, x는 오른쪽 +, y는 위 +). 크기가 다르거나 비었으면 nil
    static func shift(of frame: SpritePixels, from template: Template) -> CGVector? {
        guard !template.isEmpty, frame.width == template.width,
              frame.rgba.count >= frame.width * frame.height * 4 else { return nil }
        var best: (score: Int, dx: Int, dy: Int)?
        for dy in -reachY...reachY {
            for dx in -reachX...reachX {
                let score = agreement(of: frame, with: template, dx: dx, dy: dy)
                // 점수가 같으면 덜 움직인 쪽
                if let current = best, score < current.score
                    || (score == current.score && abs(dx) + abs(dy) >= abs(current.dx) + abs(current.dy)) {
                    continue
                }
                best = (score, dx, dy)
            }
        }
        if let best, Double(best.score) >= Double(template.points.count) * minimumAgreement {
            return CGVector(dx: best.dx, dy: -best.dy)
        }
        // 머리를 못 찾으면(누운 잠 등) 보이는 맨 윗줄이 내려간 만큼만 따라감. 올라간 윗줄은 팔·무기일 수 있어 무시
        guard case .visible(let bounds) = SpriteAlphaScanner.scan(frame) else { return nil }
        let drop = (frame.height - Int(bounds.maxY)) - template.top
        return CGVector(dx: 0, dy: -CGFloat(max(0, drop)))
    }

    /// 같은 색 +1, 다른 색 0, 빈 칸 -1
    private static func agreement(of frame: SpritePixels, with template: Template, dx: Int, dy: Int) -> Int {
        var score = 0
        for point in template.points {
            let column = point.column + dx, row = point.row + dy
            guard column >= 0, column < frame.width, row >= 0, row < frame.height,
                  frame.alpha(column: column, row: row) > 0 else {
                score -= 1
                continue
            }
            let rgb = frame.rgb(column: column, row: row)
            let distance = abs(rgb.0 - point.rgb.0) + abs(rgb.1 - point.rgb.1) + abs(rgb.2 - point.rgb.2)
            if distance <= colorTolerance { score += 1 }
        }
        return score
    }
}

extension SpritePixels {
    /// (column, row) 픽셀의 색
    func rgb(column: Int, row: Int) -> (Int, Int, Int) {
        let index = (row * width + column) * 4
        return (Int(rgba[index]), Int(rgba[index + 1]), Int(rgba[index + 2]))
    }

    /// 좌우를 뒤집은 그림
    func mirrored() -> SpritePixels {
        var flipped = rgba
        for row in 0..<height {
            for column in 0..<width {
                let from = (row * width + column) * 4
                let to = (row * width + (width - 1 - column)) * 4
                for channel in 0..<4 { flipped[to + channel] = rgba[from + channel] }
            }
        }
        return SpritePixels(width: width, height: height, rgba: flipped)
    }
}
