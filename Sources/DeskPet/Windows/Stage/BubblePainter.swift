import DeskPetText
import Foundation

/// This object is responsible for speech bubble pictures on Windows: measuring a bubble's text and having
/// DirectWrite paint the whole bubble (body, tail, text with color emoji) once per text, kind, tail position and
/// screen scale, keeping recent pictures so a bubble that stays up costs nothing per tick.
final class BubblePainter {
    /// 보관할 그림 수 (넘으면 비우고 다시 그림)
    private static let keep = 48

    private var sizes: [String: CGSize] = [:]
    private var pictures: [String: PremultipliedImage] = [:]
    /// DirectWrite가 실패한 횟수 (연기 시험 보고서용)
    private(set) var failures = 0
    /// 그린 말풍선 중 색이 있는 픽셀이 가장 많았던 수 (컬러 이모지가 나오는지 보는 값)
    private(set) var mostColoredPixels = 0
    private(set) var painted = 0

    /// 글자에 맞춘 몸통 크기 (포인트)
    func bodySize(for speech: Speech) -> CGSize? {
        let style = SpeechBubbleStyle(speech.kind)
        let key = "\(style.fontSize)|\(speech.text)"
        if let size = sizes[key] { return size }
        let units = Array(speech.text.utf16)
        var width: Float = 0, height: Float = 0
        guard dp_text_measure(units, Int32(units.count), Float(style.fontSize), &width, &height) == 1 else {
            failures += 1
            return nil
        }
        let size = SpeechBubbleLayout.bodySize(text: CGSize(width: CGFloat(width), height: CGFloat(height)))
        if sizes.count >= Self.keep * 4 { sizes = [:] }
        sizes[key] = size
        return size
    }

    /// 말풍선 그림 (몸통 바깥 1포인트 여백, 아래에 꼬리). scale: 포인트 하나의 픽셀 수
    func picture(for speech: Speech, body: CGSize, tailX: CGFloat, scale: CGFloat) -> PremultipliedImage? {
        let style = SpeechBubbleStyle(speech.kind)
        let key = "\(speech.kind)|\(Int((tailX * scale).rounded()))|\(scale)|\(speech.text)"
        if let picture = pictures[key] { return picture }
        var shape = DPBubbleStyle(bodyWidth: Float(body.width), bodyHeight: Float(body.height),
                                  cornerRadius: Float(SpeechBubbleLayout.cornerRadius), tailHeight: Float(SpeechBubbleLayout.tailHeight),
                                  tailX: Float(tailX), tailHalfWidth: Float(SpeechBubbleLayout.tailHalfWidth), fontSize: Float(style.fontSize),
                                  fill: style.fill, stroke: style.stroke, ink: style.ink, scale: Float(scale))
        let units = Array(speech.text.utf16)
        var drawn = DPImage()
        guard dp_bubble_draw(units, Int32(units.count), &shape, &drawn) == 1, let bytes = drawn.bgra else {
            failures += 1
            return nil
        }
        defer { dp_image_free(&drawn) }
        let width = Int(drawn.width), height = Int(drawn.height)
        let picture = PremultipliedImage(width: width, height: height, bgra: Array(UnsafeBufferPointer(start: bytes, count: width * height * 4)))
        if pictures.count >= Self.keep { pictures = [:] }
        pictures[key] = picture
        painted += 1
        mostColoredPixels = max(mostColoredPixels, Self.coloredPixels(in: picture))
        return picture
    }

    /// 채도가 뚜렷한 픽셀 수 (회색 글자·흰 바탕·테두리는 세지 않음)
    private static func coloredPixels(in picture: PremultipliedImage) -> Int {
        stride(from: 0, to: picture.bgra.count, by: 4).reduce(0) { count, index in
            let channels = picture.bgra[index..<(index + 3)]
            return count + ((channels.max() ?? 0) - (channels.min() ?? 0) > 60 ? 1 : 0)
        }
    }
}
