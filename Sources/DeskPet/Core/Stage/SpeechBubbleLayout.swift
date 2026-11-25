import Foundation

/// 말풍선 하나의 생김새 (색은 0xAARRGGBB)
struct SpeechBubbleStyle: Equatable {
    let fontSize: CGFloat
    let fill: UInt32
    let stroke: UInt32
    let ink: UInt32

    init(_ kind: Speech.Kind) {
        switch kind {
        case .notice:
            // 일정 안내: 연노랑 바탕, 주황 테두리, 조금 작은 글자
            (fontSize, fill, stroke) = (13, 0xF7FFF2B8, 0xFFD98C1A)
        case .chatter:
            (fontSize, fill, stroke) = (15, 0xF2FFFFFF, 0xFF8C8C8C)
        }
        ink = 0xFF1F1F1F
    }
}

/// This object is responsible for a speech bubble's geometry, the same as the macOS `SpeechBubbleNode`: the body size
/// around the measured text (padding and a minimum width), and placing it above the pet's head with the tail pointing
/// at the pet while the body stays inside the screen's width (the tail slides along the bottom edge instead).
enum SpeechBubbleLayout {
    static let padding = CGSize(width: 9, height: 5)
    static let minimumWidth: CGFloat = 26
    static let tailHeight: CGFloat = 6
    /// 꼬리 밑변 절반 너비
    static let tailHalfWidth: CGFloat = 5
    static let cornerRadius: CGFloat = 8
    /// 꼬리가 몸통 모서리에서 떨어지는 최소 거리
    static let tailInset: CGFloat = 10

    /// 잰 글자 크기 → 몸통 크기
    static func bodySize(text: CGSize) -> CGSize {
        CGSize(width: max(text.width + padding.width * 2, minimumWidth), height: text.height + padding.height * 2)
    }

    /// 몸통 사각형(전역 좌표)과 꼬리 끝의 몸통 왼쪽에서부터 가로 거리. 꼬리 끝은 anchor 바로 위
    /// swell: 오래 둔 알림이 커진 배율. 몸통 사각형은 커진 크기, 꼬리 거리는 커지기 전 몸통 기준
    static func place(body size: CGSize, pointingAt anchor: CGPoint, within bounds: ClosedRange<CGFloat>,
                      swell: CGFloat = 1) -> (body: CGRect, tailX: CGFloat) {
        let half = size.width * swell / 2
        let lowest = bounds.lowerBound + half + 2
        let highest = bounds.upperBound - half - 2
        let centerX = lowest <= highest ? min(max(anchor.x, lowest), highest) : anchor.x
        let tail = min(max(anchor.x - centerX, -half + tailInset * swell), half - tailInset * swell)
        return (CGRect(x: centerX - half, y: anchor.y + tailHeight * swell, width: size.width * swell, height: size.height * swell),
                (half + tail) / swell)
    }
}
