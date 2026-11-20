import Foundation

/// This object is responsible for moving a pet along the ledge it stands on:
/// turning at screen edges, stepping off ledge ends, and meeting walls by climbing or turning back.
final class WalkBehavior: PetBehavior {
    let name: String
    let occupiesSpace = true
    let animation: AnimationKind = .walk
    let animationSpeed: Double
    private let direction: Facing
    private let speed: CGFloat
    private let duration: TimeInterval
    private let targetX: CGFloat?
    private var elapsed: TimeInterval = 0

    init(name: String = "walking", direction: Facing, speed: CGFloat = PetPhysics.walkSpeed, duration: TimeInterval, targetX: CGFloat? = nil) {
        self.name = name
        self.direction = direction
        self.speed = speed
        self.duration = duration
        self.targetX = targetX
        self.animationSpeed = Double(speed / PetPhysics.walkSpeed)
    }

    func begin(_ pet: Pet) {
        pet.facing = direction
        pet.velocity = .zero
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard pet.followSupport(in: world) else { return AirborneBehavior.falling() }
        elapsed += dt

        let sign = pet.facing.sign
        let nextX = pet.position.x + sign * speed * pet.motionScale * CGFloat(dt)
        let frontNow = pet.position.x + sign * pet.bodyHalfWidth
        let frontNext = nextX + sign * pet.bodyHalfWidth

        // 화면 공간 밖이면 돌아섬
        if !world.contains(CGPoint(x: frontNext, y: pet.position.y + 1)) {
            return turnBack(pet, context: context)
        }

        if let wall = world.wall(hitMovingEast: sign > 0, from: frontNow, to: frontNext,
                                 bottom: pet.position.y, top: pet.position.y + pet.bodyHeight) {
            pet.position.x = wall.x - sign * pet.bodyHalfWidth
            if context.planner.wantsToClimb(wall, pet: pet, in: world) {
                return ClimbBehavior(wall: wall)
            }
            return turnBack(pet, context: context)
        }

        // 앞에 선 펫과 겹치지 않음: 그 앞에서 멈추고 뛰어넘기·결투·돌아서기 중 고름
        if let blocker = PersonalSpace.blocker(ahead: pet, toX: nextX, among: context.friends) {
            pet.position.x = PersonalSpace.stopX(for: pet, before: blocker)
            return context.planner.pass(pet, blocker: blocker, targetX: targetX,
                                        hurried: speed > PetPhysics.walkSpeed, in: world, context: context)
        }

        pet.position.x = nextX
        if !pet.settle(in: world) {
            return AirborneBehavior.falling(drift: sign * speed * pet.motionScale * 0.5)
        }

        if let target = targetX, abs(target - nextX) <= 12 {
            return context.planner.rest()
        }
        return elapsed >= duration ? context.planner.rest() : nil
    }

    var isAtLeisure: Bool { name == "walking" || name == "followingFriend" }
    var heading: Facing? { direction }

    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        GroundReaction.poked(pet, streak: streak)
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        GroundReaction.announcing(pet, for: duration)
    }

    /// 진행 방향을 뒤집음. 목표가 있던 걸음은 거기서 멈춤
    private func turnBack(_ pet: Pet, context: PetContext) -> PetBehavior? {
        pet.facing = pet.facing.opposite
        return targetX == nil ? nil : context.planner.rest()
    }
}
