import Foundation

/// 본으로 쓸 부분 (서 있는 그림의 보이는 몸 기준 비율)
struct Bone {
    /// 위에서부터 (0 맨 윗줄, 1 발)
    let rows: ClosedRange<Double>
    /// 얼굴 쪽 가장자리부터 (0 앞, 1 뒤). 정면·뒷면 그림은 앞뒤가 없어 전체 폭
    let columns: ClosedRange<Double>
    /// 못 찾았을 때 보이는 윗줄이 내려간 만큼 따라갈지 (머리만)
    let followsTopWhenLost: Bool

    /// 몸 위쪽 40%
    static let head = Bone(rows: 0...HeadTracker.headShare, columns: 0...1, followsTopWhenLost: true)
    /// 가슴 높이의 앞쪽: 물건을 드는 손과 팔
    static let hand = Bone(rows: 0.35...0.75, columns: 0...0.45, followsTopWhenLost: false)
}

/// This object is responsible for finding where a part of a character (its head, or its front hand) moved to in one
/// animation frame, compared with its standing picture: that part of the standing body is used as a template and slid
/// over the frame to the place where the most pixels agree in color. Raised arms or weapons above the head
/// do not fool the head, because they do not look like the head. Runs once while a skin loads, never per tick.
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
        fileprivate var followsTopWhenLost = true

        var isEmpty: Bool { points.isEmpty }
    }

    /// front: 그림이 보는 쪽 (east 오른쪽, west 왼쪽). 그 밖이면 전체 폭
    static func template(from reference: SpritePixels, mirrored: Bool = false, bone: Bone = .head, front: Facing? = nil) -> Template? {
        let pixels = mirrored ? reference.mirrored() : reference
        guard case .visible(let bounds) = SpriteAlphaScanner.scan(pixels) else { return nil }
        let top = pixels.height - Int(bounds.maxY)
        let height = Double(bounds.height)
        let first = top + Int((height * bone.rows.lowerBound).rounded())
        let last = top + max(4, Int((height * bone.rows.upperBound).rounded()))
        let width = Double(bounds.width)
        let columns: ClosedRange<Double>
        switch front {
        case .east: columns = (Double(bounds.maxX) - width * bone.columns.upperBound)...(Double(bounds.maxX) - width * bone.columns.lowerBound)
        case .west: columns = (Double(bounds.minX) + width * bone.columns.lowerBound)...(Double(bounds.minX) + width * bone.columns.upperBound)
        default: columns = Double(bounds.minX)...Double(bounds.maxX)
        }
        var points: [(column: Int, row: Int, rgb: (Int, Int, Int))] = []
        for row in max(0, first)..<min(pixels.height, last) {
            for column in 0..<pixels.width where columns.contains(Double(column) + 0.5) && pixels.alpha(column: column, row: row) > 0 {
                points.append((column, row, pixels.rgb(column: column, row: row)))
            }
        }
        var template = Template(points: points, top: top, width: pixels.width)
        template.followsTopWhenLost = bone.followsTopWhenLost
        return template
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
        guard template.followsTopWhenLost else { return nil }
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
