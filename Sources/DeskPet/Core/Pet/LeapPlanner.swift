import Foundation

/// 스킬 도약의 도착 방식
enum LeapTarget: Equatable {
    /// 창 윗변에 올라섬
    case stand(windowID: UInt32, x: CGFloat, y: CGFloat)
    /// 최고점에서 윗변 뒤로 숨어 거꾸로 빼꼼 (머리 공간이 없는 최대화 창)
    case peek(windowID: UInt32, x: CGFloat, footY: CGFloat)
    /// 최고점에서 창 아랫변에 거꾸로 달라붙음
    case cling(windowID: UInt32, x: CGFloat, footY: CGFloat)

    var windowID: UInt32 {
        switch self {
        case .stand(let id, _, _), .peek(let id, _, _), .cling(let id, _, _): return id
        }
    }
}

/// 도약 계획: 발사 속도와 도착 방식
struct LeapPlan: Equatable {
    let launch: CGVector
    let target: LeapTarget
}

/// This object is responsible for computing a ballistic leap from where a pet stands to a window's top:
/// landing exactly on a visible stretch of the top edge when there is headroom, or reaching the edge
/// at the peak of the jump (to slip behind it and peek) when the window is maximized. Pure math, no side effects.
enum LeapPlanner {
    /// 펫 크기 1.5배 기준 가로 속도 상한 (이보다 멀면 도약하지 않음)
    static let maxDrift: CGFloat = 900
    /// 올라설 때 최고점이 착지점보다 높은 정도
    static let standClearance: CGFloat = 50
    /// 빼꼼하러 갈 때 최고점의 머리와 윗변 사이 여유
    static let gripGap: CGFloat = 2

    /// fromAnywhere: 공중에 있거나 막 떨어지기 시작한 펫도 지금 자리에서 출발 (보던 창을 따라가는 펫)
    static func plan(for pet: Pet, to windowID: UInt32, in world: World, fromAnywhere: Bool = false) -> LeapPlan? {
        guard fromAnywhere || pet.support != nil, let window = world.window(id: windowID) else { return nil }
        return standPlan(for: pet, on: window, in: world) ?? peekPlan(for: pet, on: window, in: world)
    }

    private static func standPlan(for pet: Pet, on window: WindowSnapshot, in world: World) -> LeapPlan? {
        let margin = pet.bodyHalfWidth + 6
        let spots = world.ledges
            .filter { $0.owner == .window(id: window.id) && $0.maxX - $0.minX >= margin * 2 }
            .map { ledge -> CGPoint in
                CGPoint(x: min(max(pet.position.x, ledge.minX + margin), ledge.maxX - margin), y: ledge.y)
            }
            .filter { spot in
                guard let ceiling = world.ceiling(atX: spot.x, above: pet.position.y) else { return false }
                return spot.y + pet.bodyHeight + 4 <= ceiling
            }
        guard let spot = spots.min(by: { abs($0.x - pet.position.x) < abs($1.x - pet.position.x) }),
              spot.y > pet.position.y + 20,
              let ceiling = lowestCeiling(between: pet.position.x, and: spot.x, from: pet.position.y, in: world) else { return nil }

        let apex = min(spot.y + standClearance * pet.motionScale, ceiling - pet.bodyHeight - 2)
        guard apex > spot.y + 4 else { return nil }
        return ballistic(from: pet, apex: apex, landingY: spot.y, targetX: spot.x)
            .map { LeapPlan(launch: $0, target: .stand(windowID: window.id, x: spot.x, y: spot.y)) }
    }

    private static func peekPlan(for pet: Pet, on window: WindowSnapshot, in world: World) -> LeapPlan? {
        let footY = window.frame.maxY - pet.bodyHeight - gripGap
        guard footY > pet.position.y + 40 else { return nil }
        let margin = pet.bodyHalfWidth + 10
        guard window.frame.width > margin * 2 else { return nil }
        let x = min(max(pet.position.x, window.frame.minX + margin), window.frame.maxX - margin)
        // 숨을 윗변 지점이 실제로 보여야 함
        guard world.isVisible(CGPoint(x: x, y: window.frame.maxY - 1), onWindow: window.id) else { return nil }
        // 가는 길에 머리가 천장(메뉴바 등)에 걸리지 않아야 함
        guard let ceiling = lowestCeiling(between: pet.position.x, and: x, from: pet.position.y, in: world),
              footY + pet.bodyHeight <= ceiling else { return nil }
        // 최고점에서 윗변에 닿으므로 착지 높이 = 최고점
        return ballistic(from: pet, apex: footY, landingY: footY, targetX: x)
            .map { LeapPlan(launch: $0, target: .peek(windowID: window.id, x: x, footY: footY)) }
    }

    /// 아랫변에 붙으러 갈 때 가장 높이 뛰는 높이 (기준 크기)
    static let maxClingRise: CGFloat = 500

    /// 창 아랫변에 거꾸로 붙으러 가는 도약. 펫 쪽에서 가장 가까운 보이는 아랫변 지점의 바로 밑에서 머리가 닿게 뜀.
    /// 가는 길 위로 다른 아랫변이 먼저 있거나, 너무 높거나 멀면 nil
    static func clingPlan(for pet: Pet, to windowID: UInt32, in world: World) -> LeapPlan? {
        guard pet.support != nil else { return nil }
        let margin = pet.bodyHalfWidth + 6
        let spots = world.undersides
            .filter { $0.owner == .window(id: windowID) && $0.maxX - $0.minX >= margin * 2 && $0.y > pet.position.y }
            .map { CGPoint(x: min(max(pet.position.x, $0.minX + margin), $0.maxX - margin), y: $0.y) }
            .filter { spot in
                // 그 자리 바로 위 첫 아랫변이 이 창이어야 함 (다른 창 밑을 뚫고 가지 않음)
                world.underside(above: CGPoint(x: spot.x, y: pet.position.y + pet.bodyHeight))?.owner == .window(id: windowID)
            }
        guard let spot = spots.min(by: { abs($0.x - pet.position.x) < abs($1.x - pet.position.x) }) else { return nil }
        let footY = spot.y - pet.bodyHeight - gripGap
        guard footY >= pet.position.y + 10, footY - pet.position.y <= maxClingRise * pet.motionScale,
              let ceiling = lowestCeiling(between: pet.position.x, and: spot.x, from: pet.position.y, in: world),
              spot.y <= ceiling else { return nil }
        return ballistic(from: pet, apex: footY, landingY: footY, targetX: spot.x)
            .map { LeapPlan(launch: $0, target: .cling(windowID: windowID, x: spot.x, footY: footY)) }
    }

    /// 최고점 apex를 지나 targetX의 landingY에 닿는 발사 속도
    private static func ballistic(from pet: Pet, apex: CGFloat, landingY: CGFloat, targetX: CGFloat) -> CGVector? {
        let gravity = PetPhysics.gravity * pet.motionScale
        let rise = apex - pet.position.y
        guard rise > 0, apex >= landingY else { return nil }
        let upward = (2 * gravity * rise).squareRoot()
        let flightTime = upward / gravity + (2 * (apex - landingY) / gravity).squareRoot()
        let drift = (targetX - pet.position.x) / flightTime
        guard abs(drift) <= maxDrift * pet.motionScale else { return nil }
        return CGVector(dx: drift, dy: upward)
    }

    /// 두 x 사이 경로의 가장 낮은 천장
    private static func lowestCeiling(between a: CGFloat, and b: CGFloat, from fromY: CGFloat, in world: World) -> CGFloat? {
        let samples = stride(from: 0.0, through: 1.0, by: 0.25).map { a + (b - a) * CGFloat($0) }
        let ceilings = samples.compactMap { world.ceiling(atX: $0, above: fromY) }
        return ceilings.count == samples.count ? ceilings.min() : nil
    }
}
