import Foundation

/// 던지기 정확도 단계 (메뉴에서 고름)
enum ThrowAccuracy: String, CaseIterable {
    case always
    case often
    case sometimes
    case wild

    static let standard = ThrowAccuracy.often

    /// 맞힐 확률 (캐릭터 성격 더하기 전)
    var hitChance: Double {
        switch self {
        case .always: return 1
        case .often: return 0.65
        case .sometimes: return 0.35
        case .wild: return 0.1
        }
    }

    /// 빗나갈 때 포인터에서 떨어지는 거리 (기준 크기 pt)
    var missRange: ClosedRange<Double> {
        switch self {
        case .always, .often: return 30...80
        case .sometimes: return 40...120
        case .wild: return 60...200
        }
    }
}

/// 던질 곳과 빗나갔는지
struct ThrowShot: Equatable {
    let target: CGPoint
    let missed: Bool
}

/// This object is responsible for how well pets aim when they throw at the pointer: the accuracy step the user chose,
/// nudged by each character's own aim (a ninja hits more, a big demon less), and where a miss lands — a little
/// off the pointer, never off screen. It keeps its own random numbers so pets' other choices stay as they were.
final class ThrowAim {
    var accuracy = ThrowAccuracy.standard
    private let random: RandomSource

    /// 캐릭터 성격을 더해도 이 범위 안 (늘 명중 단계는 예외)
    static let chanceFloor = 0.05
    static let chanceCeiling = 0.95

    init(random: RandomSource = SystemRandomSource()) {
        self.random = random
    }

    /// 그 펫이 맞힐 확률
    func hitChance(for pet: Pet) -> Double {
        guard accuracy != .always else { return 1 }
        return min(max(accuracy.hitChance + pet.appearance.aimBias, Self.chanceFloor), Self.chanceCeiling)
    }

    /// 포인터를 겨냥해 던질 곳. 빗나가면 포인터 둘레 아무 쪽으로 정한 거리만큼, 화면 밖이면 반대쪽
    func shot(at pointer: CGPoint, by pet: Pet, in world: World) -> ThrowShot {
        guard accuracy != .always, random.next() >= hitChance(for: pet) else { return ThrowShot(target: pointer, missed: false) }
        let distance = CGFloat(random.uniform(accuracy.missRange.lowerBound, accuracy.missRange.upperBound)) * pet.motionScale
        let angle = CGFloat(random.uniform(0, 2 * .pi))
        for turn in [CGFloat(0), .pi, .pi / 2, -.pi / 2] {
            let point = CGPoint(x: pointer.x + cos(angle + turn) * distance, y: pointer.y + sin(angle + turn) * distance)
            if world.contains(point) { return ThrowShot(target: point, missed: true) }
        }
        // 화면 구석이라 어느 쪽도 화면 밖이면 거리를 줄여 포인터 바로 옆
        return ThrowShot(target: CGPoint(x: pointer.x, y: pointer.y - min(distance, 12)), missed: true)
    }
}
