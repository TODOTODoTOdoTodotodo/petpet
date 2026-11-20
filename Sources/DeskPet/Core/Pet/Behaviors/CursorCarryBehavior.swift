import Foundation

/// This object is responsible for a pet running off with the mouse pointer for a moment (a prank, opt-in):
/// it holds the pointer in its front hand and dashes along its ledge for about a second, stopping early at a wall,
/// the screen side, the ledge end or another pet. Where the pointer should be is read by the roster each tick;
/// the moment the user moves the mouse, the roster takes the pointer back and the pet is startled.
final class CursorCarryBehavior: PetBehavior {
    let name = "carryingCursor"
    let animation: AnimationKind = .walk
    let occupiesSpace = true
    private let direction: Facing
    private let duration: TimeInterval
    private var elapsed: TimeInterval = 0

    /// 달리는 속도 배율 (평소 걷기 대비)
    static let speedFactor: CGFloat = 2.2
    static let grabText = "😆"
    static let doneText = "😝"

    init(direction: Facing, duration: TimeInterval) {
        self.direction = direction
        self.duration = duration
    }

    var heading: Facing? { direction }
    var animationSpeed: Double { Double(Self.speedFactor) }

    /// 포인터를 쥔 손 (몸 앞쪽 가슴 높이)
    static func hand(of pet: Pet) -> CGPoint {
        CGPoint(x: pet.position.x + pet.facing.sign * pet.bodyHalfWidth * 0.9, y: pet.position.y + pet.bodyHeight * 0.55)
    }

    func begin(_ pet: Pet) {
        pet.facing = direction
        pet.velocity = .zero
        pet.say(Self.grabText, for: 1.2)
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard pet.followSupport(in: world) else { return AirborneBehavior.falling() }
        elapsed += dt
        guard elapsed < duration else { return finish(pet, context: context) }
        let sign = direction.sign
        let nextX = pet.position.x + sign * PetPhysics.walkSpeed * Self.speedFactor * pet.motionScale * CGFloat(dt)
        let front = nextX + sign * pet.bodyHalfWidth
        guard world.contains(CGPoint(x: front, y: pet.position.y + 1)),
              // 몸 전체가 발판 위에 있는 동안만 달림 (끝에서 떨어지지 않음)
              world.ledge(atX: nextX, nearY: pet.position.y, tolerance: 1, margin: -pet.bodyHalfWidth) != nil,
              world.wall(hitMovingEast: sign > 0, from: pet.position.x + sign * pet.bodyHalfWidth, to: front,
                         bottom: pet.position.y, top: pet.position.y + pet.bodyHeight) == nil,
              PersonalSpace.blocker(ahead: pet, toX: nextX, among: context.friends) == nil else {
            return finish(pet, context: context)
        }
        pet.position.x = nextX
        pet.settle(in: world)
        return nil
    }

    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        GroundReaction.poked(pet, streak: streak)
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        GroundReaction.announcing(pet, for: duration)
    }

    private func finish(_ pet: Pet, context: PetContext) -> PetBehavior {
        pet.say(Self.doneText, for: 1.2)
        pet.note(.prankDone)
        return IdleBehavior(duration: 1.2, lookAtUser: true)
    }
}
