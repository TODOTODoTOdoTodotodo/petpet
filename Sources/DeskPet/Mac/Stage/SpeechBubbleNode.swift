import AppKit
import SpriteKit

/// This object is responsible for drawing one rounded speech bubble with a tail pointing at its pet,
/// with an optional dot badge (the app icon of an AI signal) before the text, scaled up from the tail tip as a notice
/// is left unanswered, redrawing its shape only when the text, kind or badge changes.
final class SpeechBubbleNode: SKNode {
    private let body = SKShapeNode()
    /// 꼬리는 채움과 테두리를 나눠, 몸통 테두리가 꼬리 이음새에 비치지 않게 함
    private let tail = SKNode()
    private let tailFill = SKShapeNode()
    private let tailEdge = SKShapeNode()
    private let label = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    /// 글자 앞 앱 아이콘 (도트 그대로 키움)
    private let badge = SKSpriteNode()
    private var shown: (text: String, kind: Speech.Kind, badge: String?)?
    /// 아이콘 한 픽셀이 차지하는 크기 (펫 기본 크기와 같은 도트 굵기)
    static let badgeDot: CGFloat = 1.5
    /// 아이콘과 글자 사이
    static let badgeGap: CGFloat = 3
    private(set) var bubbleSize: CGSize = .zero

    private let padding = CGSize(width: 9, height: 5)
    private let tailHeight: CGFloat = 6

    override init() {
        super.init()
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        let fillPath = CGMutablePath()
        fillPath.move(to: CGPoint(x: -5, y: 1.5))
        fillPath.addLine(to: CGPoint(x: 5, y: 1.5))
        fillPath.addLine(to: CGPoint(x: 0, y: -tailHeight))
        fillPath.closeSubpath()
        tailFill.path = fillPath
        tailFill.lineWidth = 0

        let edgePath = CGMutablePath()
        edgePath.move(to: CGPoint(x: -5, y: 0))
        edgePath.addLine(to: CGPoint(x: 0, y: -tailHeight))
        edgePath.addLine(to: CGPoint(x: 5, y: 0))
        tailEdge.path = edgePath

        tail.addChild(tailFill)
        tail.addChild(tailEdge)
        addChild(body)
        addChild(tail)
        addChild(label)
        addChild(badge)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 말풍선 내용 갱신 (같으면 다시 그리지 않음)
    func show(_ speech: Speech) {
        if xScale != speech.swell { setScale(speech.swell) }
        if let shown, shown.text == speech.text, shown.kind == speech.kind, shown.badge == speech.badge?.id { return }
        shown = (speech.text, speech.kind, speech.badge?.id)

        let isNotice = speech.kind == .notice
        label.text = speech.text
        label.fontSize = isNotice ? 13 : 15
        label.fontColor = NSColor(white: 0.12, alpha: 1)

        let textSize = label.frame.size
        let icon = speech.badge.flatMap(Self.texture(for:))
        let iconSide = icon.map { $0.size().width * Self.badgeDot } ?? 0
        let gap = icon != nil && !speech.text.isEmpty ? Self.badgeGap : 0
        let content = CGSize(width: iconSide + gap + textSize.width, height: max(textSize.height, iconSide))
        bubbleSize = CGSize(width: max(content.width + padding.width * 2, 26), height: content.height + padding.height * 2)
        let rect = CGRect(x: -bubbleSize.width / 2, y: 0, width: bubbleSize.width, height: bubbleSize.height)
        body.path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        let left = -content.width / 2
        label.position = CGPoint(x: left + iconSide + gap + textSize.width / 2, y: bubbleSize.height / 2)
        badge.isHidden = icon == nil
        if let icon {
            badge.texture = icon
            badge.size = CGSize(width: iconSide, height: iconSide)
            badge.position = CGPoint(x: left + iconSide / 2, y: bubbleSize.height / 2)
        }

        let fill = isNotice ? NSColor(red: 1, green: 0.95, blue: 0.72, alpha: 0.97) : NSColor(white: 1, alpha: 0.95)
        let stroke = isNotice ? NSColor(red: 0.85, green: 0.55, blue: 0.1, alpha: 1) : NSColor(white: 0.55, alpha: 1)
        body.fillColor = fill
        body.strokeColor = stroke
        body.lineWidth = 1
        tailFill.fillColor = fill
        tailFill.strokeColor = .clear
        tailEdge.fillColor = .clear
        tailEdge.strokeColor = stroke
        tailEdge.lineWidth = 1
    }

    /// 꼬리가 가리킬 지점(펫 머리 위)과, 말풍선이 들어가야 할 화면 가로 범위
    func place(pointingAt anchor: CGPoint, within bounds: ClosedRange<CGFloat>) {
        // 커진 알림은 꼬리 끝을 기준으로 노드 배율만 키움 (자리 계산은 커진 크기로)
        let swell = xScale
        let half = bubbleSize.width * swell / 2
        let lowest = bounds.lowerBound + half + 2
        let highest = bounds.upperBound - half - 2
        let centerX = lowest <= highest ? min(max(anchor.x, lowest), highest) : anchor.x
        position = CGPoint(x: centerX, y: anchor.y + tailHeight * swell)
        tail.position = CGPoint(x: min(max(anchor.x - centerX, -half + 10 * swell), half - 10 * swell) / swell, y: 0.5)
    }

    /// 아이콘 픽셀 → 흐리지 않게 키우는 텍스처 (같은 아이콘은 한 번만 만듦)
    private static var textures: [String: SKTexture] = [:]

    private static func texture(for badge: SpeechBadge) -> SKTexture? {
        if let cached = textures[badge.id] { return cached }
        let pixels = badge.pixels
        guard pixels.width > 0, pixels.rgba.count == pixels.width * pixels.height * 4,
              let provider = CGDataProvider(data: Data(pixels.rgba) as CFData),
              let image = CGImage(width: pixels.width, height: pixels.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: pixels.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        textures[badge.id] = texture
        return texture
    }
}
