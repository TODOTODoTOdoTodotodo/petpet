import Foundation

/// This object is responsible for starting a pet train now and then: when two or more free pets share a ledge
/// and there is room ahead, the front-most one becomes the engine heading toward the open side, and the others
/// nearby line up behind it in order of distance, each following the pet in front of it.
final class TrainCoordinator {
    /// 이만큼 모이면 (기관차 포함)
    static let minimumPets = 2
    /// 기관차 뒤 최대 칸 수
    static let maxCars = 5
    /// 기관차에서 이 안에 있는 한가한 펫이 탐 (기준 크기)
    static let boardingDistance: CGFloat = 400
    /// 앞쪽에 이만큼은 걸어갈 자리가 있어야 함 (기준 크기)
    static let minimumRun: CGFloat = 160
    /// 조건이 맞을 때 초당 시작할 확률
    static let startChance = 0.04
    /// 다음 기차까지 기다리는 시간
    static let cooldown: TimeInterval = 60
    /// 기차 한 번 시간 범위
    static let rideTime: ClosedRange<Double> = 7...12

    private var clock: TimeInterval = 0
    private var lastTrain: TimeInterval = -.infinity
    var onEvent: ((String) -> Void)?

    func step(dt: TimeInterval, pets: [Pet], world: World, planner: BehaviorPlanner) {
        clock += dt
        guard clock - lastTrain >= Self.cooldown else { return }
        let free = pets.filter { $0.behavior.isAtLeisure && !$0.isShowingNotice && $0.support != nil }
        let supports = Set(free.compactMap { $0.support?.owner })
        for support in supports {
            let group = free.filter { $0.support?.owner == support }
            guard group.count >= Self.minimumPets, planner.chance(Self.startChance * dt),
                  depart(group, world: world, planner: planner) else { continue }
            lastTrain = clock
            return
        }
    }

    /// 지금 바로 기차를 출발시킴 (조건이 맞으면 true). 앞쪽 자리가 더 넓은 쪽으로, 그쪽 맨 앞 펫이 기관차
    @discardableResult
    func depart(_ group: [Pet], world: World, planner: BehaviorPlanner) -> Bool {
        guard group.count >= Self.minimumPets, let sample = group.first,
              let ledge = world.ledge(atX: sample.position.x, nearY: sample.position.y, tolerance: 1) else { return false }
        let xs = group.map(\.position.x)
        let roomEast = ledge.maxX - (xs.max() ?? 0)
        let roomWest = (xs.min() ?? 0) - ledge.minX
        let direction: Facing = roomEast >= roomWest ? .east : .west
        let sign = direction.sign
        guard let engine = group.max(by: { sign * $0.position.x < sign * $1.position.x }) else { return false }
        let stopX = (direction == .east ? ledge.maxX : ledge.minX) - sign * (engine.bodyHalfWidth + 8 * engine.motionScale)
        guard sign * (stopX - engine.position.x) >= Self.minimumRun * engine.motionScale else { return false }
        let cars = group
            .filter { $0 !== engine && abs($0.position.x - engine.position.x) <= Self.boardingDistance * $0.motionScale }
            .sorted { abs($0.position.x - engine.position.x) < abs($1.position.x - engine.position.x) }
            .prefix(Self.maxCars)
        guard cars.count + 1 >= Self.minimumPets else { return false }

        engine.switchTo(TrainLeadBehavior(direction: direction, duration: planner.uniform(Self.rideTime.lowerBound, Self.rideTime.upperBound),
                                          stopX: stopX))
        var front = engine
        for (index, car) in cars.enumerated() {
            car.switchTo(TrainCarBehavior(following: front, rank: index + 1, direction: direction))
            front = car
        }
        onEvent?("🚂 [\(engine.id)] leads \(cars.map(\.id).joined(separator: ", ")) \(direction.rawValue)")
        return true
    }

    /// 기관차부터 뒤 칸 순서의 펫들
    static func train(led engine: Pet, among pets: [Pet]) -> [Pet] {
        var train = [engine]
        while let last = train.last,
              let next = pets.first(where: { ($0.behavior as? TrainCarBehavior)?.follows(last) == true }),
              !train.contains(where: { $0 === next }) {
            train.append(next)
        }
        return train
    }
}
