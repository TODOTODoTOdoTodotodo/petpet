import Foundation

/// This object is responsible for a pet throwing its character's weapon at a point it cannot reach (the mouse pointer):
/// turning toward it, winding up (with the attack frames when the skin has them), letting go aimed at where the point is now,
/// and resting after. The thrown weapon itself is handed to the roster through the pet.
final class ThrowBehavior: PetBehavior {
    let name = "throwing"
    let occupiesSpace = true
    private var aim: CGPoint
    private var elapsed: TimeInterval = 0
    private var hasThrown = false
    private var usesAction = false
    private var duration: TimeInterval = ThrowBehavior.minimumTime

    /// 손을 놓는 때
    static let releaseTime: TimeInterval = 0.3
    /// 가장 짧은 전체 시간 (공격 동작이 없을 때)
    static let minimumTime: TimeInterval = 0.6

    init(at aim: CGPoint) {
        self.aim = aim
    }

    var animation: AnimationKind { usesAction ? .act : .idle }

    func begin(_ pet: Pet) {
        pet.velocity = .zero
        pet.facing = aim.x >= pet.position.x ? .east : .west
        usesAction = pet.appearance.supports(.act)
        if usesAction {
            duration = max(Self.minimumTime, pet.appearance.cycleDuration(of: .act, facing: pet.facing))
        }
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard pet.followSupport(in: world) else { return AirborneBehavior.falling() }
        elapsed += dt
        if let pointer = context.pointer { aim = pointer }
        if !hasThrown && elapsed >= Self.releaseTime {
            hasThrown = true
            pet.facing = aim.x >= pet.position.x ? .east : .west
            pet.hurl(pet.appearance.skillStyle.projectile, at: aim)
        }
        return elapsed >= duration ? context.planner.rest() : nil
    }

    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        GroundReaction.poked(pet, streak: streak)
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        GroundReaction.announcing(pet, for: duration)
    }
}
