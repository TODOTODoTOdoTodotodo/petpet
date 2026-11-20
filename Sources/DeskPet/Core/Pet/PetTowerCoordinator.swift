import Foundation

/// This object is responsible for pet towers: starting one when two pets meet (one hops onto the other's head),
/// letting free pets nearby on the same ledge climb on top one at a time, up to a few pets or the room overhead,
/// and keeping the bottom pet holding a little longer each time the tower grows.
final class PetTowerCoordinator {
    /// 탑에 설 수 있는 펫 수 (맨 아래 포함)
    static let maxHeight = 4
    /// 맨 아래 펫이 버티는 시간
    static let holdTime: TimeInterval = 8
    /// 한 마리 더 올라올 때 늘어나는 시간
    static let joinBonus: TimeInterval = 4
    /// 이 안의 한가한 펫이 탑에 올라올 수 있음 (같은 발판, 기준 크기)
    static let joinDistance: CGFloat = 220
    /// 근처 한가한 펫이 초당 올라올 확률
    static let joinRate = 0.5

    var onEvent: ((String) -> Void)?

    /// climber가 base 머리 위로 뛰어올라 탑을 시작. 머리 공간이 없으면 false
    @discardableResult
    func start(base: Pet, climber: Pet, in world: World) -> Bool {
        guard let plan = StackLeapBehavior.plan(for: climber, onto: base, in: world) else { return false }
        base.switchTo(TowerBaseBehavior(duration: Self.holdTime))
        climber.switchTo(StackLeapBehavior(onto: base, plan: plan))
        onEvent?("🗼 [\(climber.id)] hops onto [\(base.id)]")
        return true
    }

    /// 탑 근처 한가한 펫을 하나씩 맨 위로 올려 보냄
    func step(dt: TimeInterval, pets: [Pet], world: World, planner: BehaviorPlanner) {
        for base in pets where base.behavior is TowerBaseBehavior {
            let tower = Self.tower(on: base, among: pets)
            guard tower.count < Self.maxHeight, let top = tower.last,
                  !pets.contains(where: { pet in tower.contains { (pet.behavior as? StackLeapBehavior)?.isHeading(to: $0) == true } })
            else { continue }
            let nearby = pets.filter { pet in
                pet.behavior.isAtLeisure && !pet.isShowingNotice && pet.support?.owner != nil
                    && pet.support?.owner == base.support?.owner
                    && abs(pet.position.x - base.position.x) <= Self.joinDistance * pet.motionScale
            }
            guard !nearby.isEmpty, planner.chance(Self.joinRate * dt),
                  let climber = nearby.min(by: { abs($0.position.x - base.position.x) < abs($1.position.x - base.position.x) }),
                  let plan = StackLeapBehavior.plan(for: climber, onto: top, in: world) else { continue }
            (base.behavior as? TowerBaseBehavior)?.extend(by: Self.joinBonus)
            climber.switchTo(StackLeapBehavior(onto: top, plan: plan))
            onEvent?("🗼 [\(climber.id)] climbs onto [\(top.id)] (\(tower.count + 1) high)")
        }
    }

    /// 맨 아래 펫부터 위로 쌓인 펫들
    static func tower(on base: Pet, among pets: [Pet]) -> [Pet] {
        var tower = [base]
        while let current = tower.last,
              let next = pets.first(where: { ($0.behavior as? StackedBehavior)?.stands(on: current) == true }),
              !tower.contains(where: { $0 === next }) {
            tower.append(next)
        }
        return tower
    }
}
