import Foundation

/// This object is responsible for how lively the pets are, derived from how much of the Claude usage limit is used:
/// fresh below 50%, slowing to 80%, weary to 95%, exhausted above. Unknown usage counts as fresh.
enum Vigor: Int, Comparable {
    case fresh
    case slowing
    case weary
    case exhausted

    init(usedPercent: Double?) {
        switch usedPercent ?? 0 {
        case ..<50: self = .fresh
        case ..<80: self = .slowing
        case ..<95: self = .weary
        default: self = .exhausted
        }
    }

    static func < (lhs: Vigor, rhs: Vigor) -> Bool { lhs.rawValue < rhs.rawValue }

    /// 걷는 속도 배율
    var speedFactor: CGFloat {
        switch self {
        case .fresh: return 1
        case .slowing: return 0.75
        case .weary: return 0.5
        case .exhausted: return 0.35
        }
    }

    /// 점프·창 도약 선택 비중 배율
    var leapFactor: Double {
        switch self {
        case .fresh: return 1
        case .slowing: return 0.5
        case .weary, .exhausted: return 0
        }
    }

    /// 쉬기 선택 비중 배율
    var restFactor: Double {
        switch self {
        case .fresh: return 1
        case .slowing: return 1.5
        case .weary, .exhausted: return 3
        }
    }

    /// 스킬 도약·대결을 할 기운이 있는지
    var isEnergetic: Bool { self <= .slowing }

    static let sighText = "😮‍💨"
    static let emptyText = "🪫"
    static let rechargedText = "⚡"
}
