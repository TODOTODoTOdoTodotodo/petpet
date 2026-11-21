import Foundation

/// This object is responsible for checking the shared software compositor the Windows stage draws with:
/// nearest-neighbor scaling, mirroring and flipping, hiding the top part, transparency, blending,
/// clipping at the edges, and the changed-region bookkeeping that limits screen uploads.
enum CanvasChecks {
    static func run(_ check: Checker) {
        check.section("픽셀 합성 (공통)")
        // 2x2 그림: 왼쪽 위 빨강, 오른쪽 위 초록, 왼쪽 아래 파랑, 오른쪽 아래 투명
        let image = PremultipliedImage(width: 2, height: 2, bgra: [
            0, 0, 255, 255, 0, 255, 0, 255,
            255, 0, 0, 255, 0, 0, 0, 0,
        ])
        let red: [UInt8] = [0, 0, 255, 255], green: [UInt8] = [0, 255, 0, 255], blue: [UInt8] = [255, 0, 0, 255]
        let clear: [UInt8] = [0, 0, 0, 0]

        let canvas = PixelCanvas(width: 6, height: 6)
        let drawn = canvas.draw(image, in: PixelBox(x: 1, y: 1, width: 4, height: 4))
        check.expect(drawn == PixelBox(x: 1, y: 1, width: 4, height: 4), "그린 영역을 돌려줌", "\(drawn)")
        check.expect(pixel(canvas, 1, 1) == red && pixel(canvas, 2, 2) == red && pixel(canvas, 3, 1) == green
                     && pixel(canvas, 1, 4) == blue && pixel(canvas, 4, 4) == clear,
                     "2배 최근접 확대 (도트가 2x2 칸)")
        check.expect(pixel(canvas, 0, 0) == clear && pixel(canvas, 5, 5) == clear, "칸 밖은 그대로")

        let mirrored = PixelCanvas(width: 2, height: 2)
        mirrored.draw(image, in: mirrored.bounds, mirrored: true, flipped: true)
        check.expect(pixel(mirrored, 0, 0) == clear && pixel(mirrored, 1, 0) == blue && pixel(mirrored, 0, 1) == green,
                     "좌우 반전 + 위아래 뒤집기")

        let peek = PixelCanvas(width: 2, height: 4)
        peek.draw(image, in: peek.bounds, visibleShare: 0.5)
        check.expect(pixel(peek, 0, 1) == clear && pixel(peek, 0, 2) == blue, "보일 비율 0.5면 위 절반은 안 그림")

        let faint = PixelCanvas(width: 2, height: 2)
        faint.draw(image, in: faint.bounds, alpha: 0.5)
        check.expect(pixel(faint, 0, 0) == [0, 0, 128, 128], "투명도 50%는 미리 곱한 값도 절반", "\(pixel(faint, 0, 0))")
        faint.draw(PremultipliedImage(width: 1, height: 1, bgra: blue), in: faint.bounds, alpha: 0.5)
        check.expect(pixel(faint, 0, 0) == [128, 0, 64, 192], "반투명 위에 반투명을 겹침 (source-over)", "\(pixel(faint, 0, 0))")

        let edge = PixelCanvas(width: 3, height: 3)
        let clipped = edge.draw(image, in: PixelBox(x: 2, y: -1, width: 2, height: 2))
        check.expect(clipped == PixelBox(x: 2, y: 0, width: 1, height: 1) && pixel(edge, 2, 0) == blue,
                     "가장자리에 걸치면 잘라 그림", "\(clipped)")
        check.expect(edge.takeDirty() == clipped && edge.takeDirty().isEmpty, "바뀐 영역을 넘기면 비워짐")
        edge.clear(PixelBox(x: 0, y: 0, width: 3, height: 3))
        check.expect(pixel(edge, 2, 0) == clear && edge.visiblePixelCount == 0 && edge.dirty == edge.bounds, "지우기도 바뀐 영역")
        check.expect(PixelBox(x: 0, y: 0, width: 2, height: 2).union(PixelBox(x: 3, y: 1, width: 1, height: 3))
                     == PixelBox(x: 0, y: 0, width: 4, height: 4), "영역 합치기")

        let decoded = PremultipliedImage(pixels: SpritePixels(width: 1, height: 1, rgba: [255, 128, 0, 128]))
        check.expect(decoded.bgra == [0, 64, 128, 128], "RGBA(곧은 알파) → 미리 곱한 BGRA", "\(decoded.bgra)")
    }

    private static func pixel(_ canvas: PixelCanvas, _ x: Int, _ y: Int) -> [UInt8] {
        let start = (y * canvas.width + x) * 4
        return Array(canvas.bgra[start..<(start + 4)])
    }
}
