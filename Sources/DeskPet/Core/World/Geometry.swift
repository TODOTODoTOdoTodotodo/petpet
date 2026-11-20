import Foundation

/// This object is responsible for describing one display in global Cocoa coordinates
/// (origin at the bottom-left of the primary display, y grows upward).
struct ScreenArea: Equatable {
    let id: UInt32
    let name: String
    let frame: CGRect
    /// 메뉴바·Dock을 뺀 영역
    let visibleFrame: CGRect
    /// 1pt당 화면 픽셀 수
    let backingScale: CGFloat
}

/// This object is responsible for describing one on-screen app window in global Cocoa coordinates.
struct WindowSnapshot: Equatable {
    let id: UInt32
    let owner: String
    let frame: CGRect
    /// 창을 가진 앱의 프로세스 ID (보고 있는 앱의 창을 고를 때 사용)
    var processID: Int32 = 0
}

/// 발판의 주인 (모니터 바닥 또는 창)
enum SurfaceOwner: Hashable {
    case ground(screenID: UInt32)
    case window(id: UInt32)

    var windowID: UInt32? {
        if case .window(let id) = self { return id }
        return nil
    }
}

/// This object is responsible for one walkable horizontal span that is actually visible on screen.
struct Ledge: Equatable {
    let owner: SurfaceOwner
    let y: CGFloat
    let minX: CGFloat
    let maxX: CGFloat

    /// x가 구간 안(여유 margin 포함)에 있는지
    func spans(_ x: CGFloat, margin: CGFloat = 0) -> Bool {
        x >= minX - margin && x <= maxX + margin
    }
}

/// 창의 어느 옆면인지. left는 창 왼쪽 면으로, 동쪽으로 걷다 부딪힘
enum WallFace {
    case left
    case right

    /// 이 면에 붙은 펫이 창 바깥쪽으로 놓이는 방향 부호
    var outwardSign: CGFloat { self == .left ? -1 : 1 }
}

/// This object is responsible for one climbable vertical span of a window side that is actually visible.
struct Wall: Equatable {
    let windowID: UInt32
    let face: WallFace
    let x: CGFloat
    let minY: CGFloat
    let maxY: CGFloat
}

/// This object is responsible for the 1D span arithmetic used to clip edges by screens and front windows.
enum SpanMath {
    typealias Span = (lo: CGFloat, hi: CGFloat)

    /// base에서 cuts를 뺀 나머지 구간 목록
    static func subtract(_ base: Span, _ cuts: [Span]) -> [Span] {
        var pieces: [Span] = [base]
        for cut in cuts where cut.hi > cut.lo {
            pieces = pieces.flatMap { piece -> [Span] in
                if cut.hi <= piece.lo || cut.lo >= piece.hi { return [piece] }
                var rest: [Span] = []
                if cut.lo > piece.lo { rest.append((piece.lo, cut.lo)) }
                if cut.hi < piece.hi { rest.append((cut.hi, piece.hi)) }
                return rest
            }
        }
        return pieces
    }

    /// base 중 allowed 구간들과 겹치는 부분 (맞닿은 조각은 하나로 합침)
    static func intersect(_ base: Span, _ allowed: [Span]) -> [Span] {
        let pieces = allowed.compactMap { span -> Span? in
            let lo = max(base.lo, span.lo)
            let hi = min(base.hi, span.hi)
            return hi > lo ? (lo, hi) : nil
        }
        return merge(pieces)
    }

    /// 겹치거나 맞닿은 구간을 합침
    static func merge(_ spans: [Span]) -> [Span] {
        let sorted = spans.sorted { $0.lo < $1.lo }
        var merged: [Span] = []
        for span in sorted {
            if let last = merged.last, span.lo <= last.hi + 0.5 {
                merged[merged.count - 1] = (last.lo, max(last.hi, span.hi))
            } else {
                merged.append(span)
            }
        }
        return merged
    }
}
