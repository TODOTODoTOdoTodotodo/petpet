import Foundation

/// 그림 한 장의 RGBA 픽셀 (위쪽 줄부터, 픽셀마다 4바이트, 알파는 네 번째)
struct SpritePixels {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    /// (column, row) 픽셀의 알파. row 0이 맨 위 줄
    func alpha(column: Int, row: Int) -> UInt8 {
        rgba[(row * width + column) * 4 + 3]
    }
}

/// This object is responsible for reading which pixels of a sprite image are visible,
/// so blank padding cells can be dropped and a character's body size can be measured.
enum SpriteAlphaScanner {
    enum Result: Equatable {
        /// 보이는 픽셀 없음
        case blank
        /// 보이는 픽셀을 감싸는 사각형 (이미지 픽셀 단위, 원점 왼쪽 아래)
        case visible(CGRect)
        /// 픽셀을 읽지 못함
        case unreadable
    }

    static func scan(_ pixels: SpritePixels) -> Result {
        let width = pixels.width
        let height = pixels.height
        guard width > 0, height > 0 else { return .blank }
        guard pixels.rgba.count >= width * height * 4 else { return .unreadable }

        var minX = width, maxX = -1, minRow = height, maxRow = -1
        for row in 0..<height {
            for column in 0..<width where pixels.alpha(column: column, row: row) > 0 {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minRow = min(minRow, row)
                maxRow = max(maxRow, row)
            }
        }
        guard maxX >= 0 else { return .blank }

        // 픽셀은 위쪽 줄부터 저장되므로 아래 기준 y로 뒤집음
        let bottom = height - 1 - maxRow
        return .visible(CGRect(x: minX, y: bottom, width: maxX - minX + 1, height: maxRow - minRow + 1))
    }
}
