import Foundation

/// This object is responsible for the engine of a pet train: calling 🚂, waiting a moment for the others to line up,
/// then walking slowly along its ledge (riding along if its window moves) and blowing the whistle now and then.
/// The ride ends with 🎉 after a while or near the end of the ledge, and ends quietly when a wall, the screen side
/// or another pet is in the way. Its cars follow it on their own, so stopping the engine stops the train.
final class TrainLeadBehavior: PetBehavior {
    let name = "trainLeading"
    let occupiesSpace = true
    private let direction: Facing
    private let duration: TimeInterval
    private let stopX: CGFloat
    private var elapsed: TimeInterval = 0
    private var sinceWhistle: TimeInterval = 0
    private var moving = false

    /// 출발 전 줄 서기를 기다리는 시간
    static let boardingTime: TimeInterval = 0.8
    /// 걷는 속도 배율 (평소 걷기 대비)
    static let speedFactor: CGFloat = 0.8
    /// 기적 간격
    static let whistleInterval: TimeInterval = 4
    static let whistleText = "🚂"
    static let arrivalText = "🎉"

    /// stopX: 이 x에 닿으면 도착 (발판 끝 앞)
    init(direction: Facing, duration: TimeInterval, stopX: CGFloat) {
        self.direction = direction
        self.duration = duration
        self.stopX = stopX
    }

    var trainRank: Int? { 0 }
    var heading: Facing? { moving ? direction : nil }
    var animation: AnimationKind { moving ? .walk : .idle }
    var animationSpeed: Double { Double(Self.speedFactor) }

    func begin(_ pet: Pet) {
        pet.facing = direction
        pet.velocity = .zero
        pet.say(Self.whistleText, for: 1.5)
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard pet.followSupport(in: world) else { return AirborneBehavior.falling() }
        elapsed += dt
        guard elapsed >= Self.boardingTime else { return nil }
        if elapsed >= duration { return arrive(pet, context: context) }

        sinceWhistle += dt
        if sinceWhistle >= Self.whistleInterval {
            sinceWhistle = 0
            pet.say(Self.whistleText, for: 1.2)
        }
        let sign = direction.sign
        let speed = PetPhysics.walkSpeed * Self.speedFactor * context.vigor.speedFactor * pet.motionScale
        var nextX = pet.position.x + sign * speed * CGFloat(dt)
        if sign * (nextX - stopX) >= 0 {
            nextX = stopX
        }
        let front = nextX + sign * pet.bodyHalfWidth
        guard world.contains(CGPoint(x: front, y: pet.position.y + 1)),
              world.wall(hitMovingEast: sign > 0, from: pet.position.x + sign * pet.bodyHalfWidth, to: front,
                         bottom: pet.position.y, top: pet.position.y + pet.bodyHeight) == nil,
              PersonalSpace.blocker(ahead: pet, toX: nextX, among: context.friends) == nil else {
            return context.planner.rest()
        }
        pet.position.x = nextX
        moving = true
        guard pet.settle(in: world) else { return AirborneBehavior.falling() }
        return nextX == stopX ? arrive(pet, context: context) : nil
    }

    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        GroundReaction.poked(pet, streak: streak)
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        GroundReaction.announcing(pet, for: duration)
    }

    private func arrive(_ pet: Pet, context: PetContext) -> PetBehavior {
        pet.say(Self.arrivalText, for: 1.5)
        pet.note(.arrivedAsEngine)
        return IdleBehavior(duration: 1.5, lookAtUser: true)
    }
}

/// This object is responsible for one car of a pet train: keeping a small gap behind the pet in front of it,
/// hurrying to catch up when it falls behind and never passing it, and leaving the line when the pet in front
/// is no longer on the train or a pet that is not on the train stands in the way.
final class TrainCarBehavior: PetBehavior {
    let name = "trainRiding"
    let occupiesSpace = true
    private weak var front: Pet?
    private let rank: Int
    private let direction: Facing
    private var moving = false
    private var speed: CGFloat = 0

    /// 앞 펫과 몸 사이 간격 (기준 크기)
    static let gap: CGFloat = 6
    /// 따라잡을 때 벌어진 거리당 더하는 속도 (질주 속도까지)
    static let catchUpRate: CGFloat = 3

    init(following front: Pet, rank: Int, direction: Facing) {
        self.front = front
        self.rank = rank
        self.direction = direction
    }

    var trainRank: Int? { rank }
    var heading: Facing? { moving ? direction : nil }
    var animation: AnimationKind { moving ? .walk : .idle }
    var animationSpeed: Double { moving ? Double(max(speed / PetPhysics.walkSpeed, 0.6)) : 1 }

    /// 이 펫 뒤를 따르는지
    func follows(_ pet: Pet) -> Bool {
        front === pet
    }

    func begin(_ pet: Pet) {
        pet.velocity = .zero
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard pet.followSupport(in: world) else { return AirborneBehavior.falling() }
        guard let front, front.behavior.trainRank != nil, front.support?.owner == pet.support?.owner,
              abs(front.position.y - pet.position.y) < 2 else { return context.planner.rest() }

        let sign = direction.sign
        let spot = front.position.x - sign * (front.bodyHalfWidth + pet.bodyHalfWidth + PersonalSpace.gap + Self.gap * pet.motionScale)
        let behind = sign * (spot - pet.position.x)
        // 앞 펫이 반대쪽에 있으면(줄 앞에 서 있었음) 줄에서 빠짐
        guard sign * (front.position.x - pet.position.x) > 0 else { return context.planner.rest() }
        moving = behind > 0.5
        guard moving else {
            pet.facing = direction
            return nil
        }
        let k = pet.motionScale
        // 기관차 속도에 벌어진 만큼 더해 따라잡음 (질주 속도까지)
        speed = min(PetPhysics.walkSpeed * TrainLeadBehavior.speedFactor + behind / k * Self.catchUpRate, PetPhysics.sprintSpeed)
        let nextX = pet.position.x + sign * min(speed * k * CGFloat(dt), behind)
        pet.facing = direction
        // 줄에 없는 펫이 사이에 있으면 줄에서 빠짐
        if let blocker = PersonalSpace.blocker(ahead: pet, toX: nextX, among: context.friends), blocker.id != front.id {
            return context.planner.rest()
        }
        pet.position.x = nextX
        guard pet.settle(in: world) else { return AirborneBehavior.falling(drift: sign * speed * k * 0.5) }
        return nil
    }

    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        GroundReaction.poked(pet, streak: streak)
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        GroundReaction.announcing(pet, for: duration)
    }
}
