import AppKit
import SpriteKit

/// This object is responsible for drawing one rounded speech bubble with a tail pointing at its pet,
/// redrawing its shape only when the text or kind changes.
final class SpeechBubbleNode: SKNode {
    private let body = SKShapeNode()
    /// 꼬리는 채움과 테두리를 나눠, 몸통 테두리가 꼬리 이음새에 비치지 않게 함
    private let tail = SKNode()
    private let tailFill = SKShapeNode()
    private let tailEdge = SKShapeNode()
    private let label = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private var shown: (text: String, kind: Speech.Kind)?
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
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 말풍선 내용 갱신 (같으면 다시 그리지 않음)
    func show(_ speech: Speech) {
        if let shown, shown.text == speech.text, shown.kind == speech.kind { return }
        shown = (speech.text, speech.kind)

        let isNotice = speech.kind == .notice
        label.text = speech.text
        label.fontSize = isNotice ? 13 : 15
        label.fontColor = NSColor(white: 0.12, alpha: 1)

        let textSize = label.frame.size
        bubbleSize = CGSize(width: max(textSize.width + padding.width * 2, 26), height: textSize.height + padding.height * 2)
        let rect = CGRect(x: -bubbleSize.width / 2, y: 0, width: bubbleSize.width, height: bubbleSize.height)
        body.path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        label.position = CGPoint(x: 0, y: bubbleSize.height / 2)

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
        let half = bubbleSize.width / 2
        let lowest = bounds.lowerBound + half + 2
        let highest = bounds.upperBound - half - 2
        let centerX = lowest <= highest ? min(max(anchor.x, lowest), highest) : anchor.x
        position = CGPoint(x: centerX, y: anchor.y + tailHeight)
        tail.position = CGPoint(x: min(max(anchor.x - centerX, -half + 10), half - 10), y: 0.5)
    }
}
