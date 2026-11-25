import Foundation

/// This object is responsible for a pet getting rid of a notice it has held too long: turning toward the pile,
/// winding up (with the attack frames when the skin has them, or a short crouch), and letting go once — the caller
/// crumples the notice and flies it to the pile at that moment — then resting. A click before the release simply
/// acknowledges the notice, and nothing is tossed.
final class TossNoticeBehavior: PetBehavior {
    let name = "tossingNotice"
    let occupiesSpace = true
    private let targetX: CGFloat
    private let release: (Pet, CGPoint) -> Void
    private var elapsed: TimeInterval = 0
    private var hasReleased = false
    private var usesAction = false
    private var duration = TossNoticeBehavior.minimumTime

    /// 손을 놓는 때
    static let releaseTime: TimeInterval = 0.35
    /// 가장 짧은 전체 시간 (공격 동작이 없을 때)
    static let minimumTime: TimeInterval = 0.7

    /// release: 손을 놓는 순간 (펫, 손 위치)
    init(toward targetX: CGFloat, release: @escaping (Pet, CGPoint) -> Void) {
        self.targetX = targetX
        self.release = release
    }

    var animation: AnimationKind { usesAction ? .act : .idle }

    func begin(_ pet: Pet) {
        pet.velocity = .zero
        pet.facing = targetX >= pet.position.x ? .east : .west
        usesAction = pet.appearance.supports(.act)
        if usesAction {
            duration = max(Self.minimumTime, pet.appearance.cycleDuration(of: .act, facing: pet.facing))
        }
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard pet.followSupport(in: world) else { return AirborneBehavior.falling() }
        elapsed += dt
        if !hasReleased && elapsed >= Self.releaseTime {
            hasReleased = true
            let hand = CGPoint(x: pet.position.x + pet.facing.sign * pet.bodyHalfWidth, y: pet.position.y + pet.bodyHeight * 0.6)
            release(pet, hand)
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
