import Foundation

/// This object is responsible for a pet going to the Dock (or taskbar) icon of the app whose AI task just finished:
/// walking along the floor to stand right above the icon (running when far, walking off a window edge first when it
/// is up on a window), then knocking on the icon (attack frames twice, or a hop without them) with the app icon and ✅.
/// It gives up in place after a while, or when a wall or another pet blocks the way.
final class VisitBehavior: PetBehavior {
    let name = "visitingApp"
    let occupiesSpace = true
    /// 아이콘 바로 위 바닥 자리 (전역 좌표)
    private let goal: CGPoint
    private let text: String
    private let badge: SpeechBadge?
    private let app: Int32?
    private var elapsed: TimeInterval = 0
    private var knocking: TimeInterval?
    private var knockLength: TimeInterval = 0
    private var knocks = 0
    private var hasActionFrames = false
    private var speed: CGFloat = PetPhysics.walkSpeed
    private var direction: Facing?
    /// 높은 발판에서 내려갈 끝 (그 발판 높이, 가로 위치). 끝에 걸친 채 방향을 바꾸지 않게 한 번 정하면 유지
    private var exit: (y: CGFloat, x: CGFloat)?

    /// 이보다 오래 걸리면 그 자리에서 알림
    static let timeout: TimeInterval = 15
    /// 이보다 멀면 뜀 (기준 크기)
    static let runDistance: CGFloat = 80
    /// 두드리는 횟수
    static let knockCount = 2
    /// 도착해서 띄우는 말풍선 시간
    static let arrivalSpeech: TimeInterval = 3

    init(goal: CGPoint, text: String, badge: SpeechBadge?, app: Int32?) {
        self.goal = goal
        self.text = text
        self.badge = badge
        self.app = app
    }

    var animation: AnimationKind {
        guard knocking != nil else { return .walk }
        return hasActionFrames ? .act : .idle
    }

    var animationSpeed: Double { knocking == nil ? Double(speed / PetPhysics.walkSpeed) : 1 }
    var heading: Facing? { knocking == nil ? direction : nil }
    /// 두드릴 때는 사용자 쪽(아래 아이콘)을 봄
    var displayFacing: Facing? { knocking != nil && !hasActionFrames ? .south : nil }

    func begin(_ pet: Pet) {
        hasActionFrames = pet.appearance.supports(.act)
        knockLength = hasActionFrames ? max(0.3, pet.appearance.cycleDuration(of: .act, facing: pet.facing)) : 0.4
        pet.velocity = .zero
        pet.facing = goal.x >= pet.position.x ? .east : .west
        direction = pet.facing
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard pet.followSupport(in: world) else { return AirborneBehavior.falling(then: self) }
        elapsed += dt
        if let knock = knocking {
            return knockStep(pet, knock: knock + dt, context: context)
        }
        guard elapsed < Self.timeout else { return arrive(pet, context: context, reached: false) }

        let onGoalFloor = abs(goal.y - pet.position.y) <= 3
        let goalX: CGFloat
        if onGoalFloor {
            goalX = goal.x
        } else if let exit, abs(exit.y - pet.position.y) < 1 {
            goalX = exit.x
        } else {
            goalX = Self.dropOffX(for: pet, toward: goal, in: world)
            exit = (pet.position.y, goalX)
        }
        let gap = goalX - pet.position.x
        let reach = max(pet.bodyHalfWidth * 0.3, 3)
        if onGoalFloor && abs(gap) <= reach {
            knocking = 0
            pet.restartAnimation()
            return nil
        }

        pet.facing = gap > 0 ? .east : .west
        direction = pet.facing
        let k = pet.motionScale
        speed = abs(gap) > Self.runDistance * k ? PetPhysics.sprintSpeed : PetPhysics.walkSpeed
        let sign = pet.facing.sign
        let step = speed * k * CGFloat(dt)
        let travel = onGoalFloor ? min(step, abs(gap)) : step
        let nextX = pet.position.x + sign * travel
        let frontNow = pet.position.x + sign * pet.bodyHalfWidth
        let frontNext = nextX + sign * pet.bodyHalfWidth
        guard world.contains(CGPoint(x: frontNext, y: pet.position.y + 1)),
              world.wall(hitMovingEast: sign > 0, from: frontNow, to: frontNext,
                         bottom: pet.position.y, top: pet.position.y + pet.bodyHeight) == nil else {
            return arrive(pet, context: context, reached: false)
        }
        if let blocker = PersonalSpace.blocker(ahead: pet, toX: nextX, among: context.friends) {
            // 같은 쪽으로 가는 펫 뒤에서는 따라가고, 마주 선 펫이면 그 자리에서 알림
            if blocker.heading == pet.facing { return nil }
            pet.position.x = PersonalSpace.stopX(for: pet, before: blocker)
            return arrive(pet, context: context, reached: false)
        }
        pet.position.x = nextX
        if !pet.settle(in: world) {
            // 발판 끝에서 내려가 착지한 뒤 가던 길을 이어 감
            return AirborneBehavior.falling(drift: sign * speed * k * 0.5, then: self)
        }
        return nil
    }

    /// 지금 발판이 목표 바로 위를 덮고 있으면 가까운 끝 너머로 걸어 내려감
    static func dropOffX(for pet: Pet, toward goal: CGPoint, in world: World) -> CGFloat {
        guard let ledge = world.ledge(atX: pet.position.x, nearY: pet.position.y, tolerance: 1),
              ledge.spans(goal.x) else { return goal.x }
        let overshoot = pet.bodyHalfWidth * 2
        return goal.x - ledge.minX <= ledge.maxX - goal.x ? ledge.minX - overshoot : ledge.maxX + overshoot
    }

    private func knockStep(_ pet: Pet, knock: TimeInterval, context: PetContext) -> PetBehavior? {
        knocking = knock
        guard knock >= knockLength else { return nil }
        knocks += 1
        // 동작이 있으면 두 번 휘두르고, 없으면 잠깐 아래를 본 뒤 깡충 한 번
        guard knocks >= (hasActionFrames ? Self.knockCount : 1) else {
            knocking = 0
            pet.restartAnimation()
            return nil
        }
        return arrive(pet, context: context, reached: true)
    }

    /// 도착(또는 포기)해서 앱 아이콘과 함께 알림. 동작이 없는 캐릭터는 깡충으로 두드림
    private func arrive(_ pet: Pet, context: PetContext, reached: Bool) -> PetBehavior {
        pet.say(text, for: Self.arrivalSpeech, badge: badge, app: app)
        if reached && !hasActionFrames {
            return AirborneBehavior.hop(name: "knocking", motionScale: pet.motionScale)
        }
        return IdleBehavior(duration: 1.2, lookAtUser: true, name: reached ? "knocked" : "visitStopped")
    }

    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        GroundReaction.poked(pet, streak: streak)
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        GroundReaction.announcing(pet, for: duration)
    }
}
