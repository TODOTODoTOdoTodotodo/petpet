import DeskPetText
import Foundation

/// This object is responsible for speech bubble pictures on Windows: measuring a bubble's text and having
/// DirectWrite paint the whole bubble (body, tail, text with color emoji) once per text, kind, badge, tail position and
/// screen scale, then setting the optional app-icon badge (an AI task alert) before the text with sharp dots the way the
/// macOS bubble does, keeping recent pictures so a bubble that stays up costs nothing per tick.
final class BubblePainter {
    /// 보관할 그림 수 (넘으면 비우고 다시 그림)
    private static let keep = 48
    /// 배지 한 도트가 차지하는 포인트 (맥 SpeechBubbleNode.badgeDot과 같음)
    static let badgeDot: CGFloat = 1.5
    /// 배지와 글자 사이 (맥과 같음)
    static let badgeGap: CGFloat = 3

    private var sizes: [String: CGSize] = [:]
    private var pictures: [String: PremultipliedImage] = [:]
    /// DirectWrite가 실패한 횟수 (연기 시험 보고서용)
    private(set) var failures = 0
    /// 그린 말풍선 중 색이 있는 픽셀이 가장 많았던 수 (컬러 이모지가 나오는지 보는 값)
    private(set) var mostColoredPixels = 0
    private(set) var painted = 0
    /// 앱 아이콘 배지를 붙여 그린 말풍선 수
    private(set) var badged = 0

    /// 글자(와 배지)에 맞춘 몸통 크기 (포인트)
    func bodySize(for speech: Speech) -> CGSize? {
        guard let text = textSize(for: speech) else { return nil }
        let content = Self.content(text: text, badge: speech.badge, hasText: !speech.text.isEmpty)
        return SpeechBubbleLayout.bodySize(text: CGSize(width: content.width, height: content.height))
    }

    /// 말풍선 그림 (몸통 바깥 1포인트 여백, 아래에 꼬리). scale: 포인트 하나의 픽셀 수
    func picture(for speech: Speech, body: CGSize, tailX: CGFloat, scale: CGFloat) -> PremultipliedImage? {
        let style = SpeechBubbleStyle(speech.kind)
        let key = "\(speech.kind)|\(Int((tailX * scale).rounded()))|\(scale)|\(speech.badge?.id ?? "")|\(speech.text)"
        if let picture = pictures[key] { return picture }
        guard let text = textSize(for: speech) else { return nil }
        let content = Self.content(text: text, badge: speech.badge, hasText: !speech.text.isEmpty)
        var shape = DPBubbleStyle(bodyWidth: Float(body.width), bodyHeight: Float(body.height),
                                  cornerRadius: Float(SpeechBubbleLayout.cornerRadius), tailHeight: Float(SpeechBubbleLayout.tailHeight),
                                  tailX: Float(tailX), tailHalfWidth: Float(SpeechBubbleLayout.tailHalfWidth), fontSize: Float(style.fontSize),
                                  fill: style.fill, stroke: style.stroke, ink: style.ink, scale: Float(scale),
                                  textInset: Float(content.lead))
        let units = Array(speech.text.utf16)
        var drawn = DPImage()
        guard dp_bubble_draw(units, Int32(units.count), &shape, &drawn) == 1, let bytes = drawn.bgra else {
            failures += 1
            return nil
        }
        defer { dp_image_free(&drawn) }
        let width = Int(drawn.width), height = Int(drawn.height)
        var bgra = Array(UnsafeBufferPointer(start: bytes, count: width * height * 4))
        if let badge = speech.badge, content.lead > 0 {
            // 배지는 글자와 함께 몸통 가운데에 놓인 내용의 왼쪽 끝, 세로 가운데 (그림은 몸통 바깥 1포인트 여백부터)
            let origin = CGPoint(x: 1 + (body.width - content.width) / 2, y: 1 + (body.height - content.iconSide) / 2)
            Self.stamp(badge.pixels, into: &bgra, width: width, height: height, at: origin, scale: scale)
            badged += 1
        }
        let picture = PremultipliedImage(width: width, height: height, bgra: bgra)
        if pictures.count >= Self.keep { pictures = [:] }
        pictures[key] = picture
        painted += 1
        mostColoredPixels = max(mostColoredPixels, Self.coloredPixels(in: picture))
        return picture
    }

    private func textSize(for speech: Speech) -> CGSize? {
        let style = SpeechBubbleStyle(speech.kind)
        let key = "\(style.fontSize)|\(speech.text)"
        if let size = sizes[key] { return size }
        let units = Array(speech.text.utf16)
        var width: Float = 0, height: Float = 0
        guard dp_text_measure(units, Int32(units.count), Float(style.fontSize), &width, &height) == 1 else {
            failures += 1
            return nil
        }
        let size = CGSize(width: CGFloat(width), height: CGFloat(height))
        if sizes.count >= Self.keep * 4 { sizes = [:] }
        sizes[key] = size
        return size
    }

    /// 배지와 글자를 합친 내용의 크기, 글자 앞 비움(배지+간격), 배지 한 변 (포인트)
    private static func content(text: CGSize, badge: SpeechBadge?, hasText: Bool) -> (width: CGFloat, height: CGFloat, lead: CGFloat, iconSide: CGFloat) {
        guard let badge, badge.pixels.width > 0 else { return (text.width, text.height, 0, 0) }
        let iconSide = CGFloat(badge.pixels.width) * badgeDot
        let lead = iconSide + (hasText ? badgeGap : 0)
        return (lead + text.width, max(text.height, iconSide), lead, iconSide)
    }

    /// 곧은 알파 RGBA 배지를 도트 그대로 키워 찍음 (알파 절반 이상인 도트만, 불투명)
    private static func stamp(_ badge: SpritePixels, into bgra: inout [UInt8], width: Int, height: Int, at origin: CGPoint, scale: CGFloat) {
        guard badge.width > 0, badge.rgba.count == badge.width * badge.height * 4 else { return }
        let dot = badgeDot * scale
        let left = Int((origin.x * scale).rounded()), top = Int((origin.y * scale).rounded())
        let right = left + Int((CGFloat(badge.width) * dot).rounded()), bottom = top + Int((CGFloat(badge.height) * dot).rounded())
        let rows = max(top, 0)..<max(min(bottom, height), max(top, 0))
        let columns = max(left, 0)..<max(min(right, width), max(left, 0))
        for y in rows {
            let row = min(Int(CGFloat(y - top) / dot), badge.height - 1)
            for x in columns {
                let column = min(Int(CGFloat(x - left) / dot), badge.width - 1)
                let source = (row * badge.width + column) * 4
                guard badge.rgba[source + 3] >= 128 else { continue }
                let target = (y * width + x) * 4
                bgra[target] = badge.rgba[source + 2]
                bgra[target + 1] = badge.rgba[source + 1]
                bgra[target + 2] = badge.rgba[source]
                bgra[target + 3] = 255
            }
        }
    }

    /// 채도가 뚜렷한 픽셀 수 (회색 글자·흰 바탕·테두리는 세지 않음)
    private static func coloredPixels(in picture: PremultipliedImage) -> Int {
        stride(from: 0, to: picture.bgra.count, by: 4).reduce(0) { count, index in
            let channels = picture.bgra[index..<(index + 3)]
            return count + ((channels.max() ?? 0) - (channels.min() ?? 0) > 60 ? 1 : 0)
        }
    }
}
