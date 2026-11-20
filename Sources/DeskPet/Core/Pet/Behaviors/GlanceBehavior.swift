import Foundation

/// This object is responsible for a pet turning toward something (a friend, the window the user switched to)
/// and staying put for a moment, optionally with a short remark, before resting.
final class GlanceBehavior: PetBehavior {
    let name: String
    let occupiesSpace = true
    let animation: AnimationKind = .idle
    private let targetX: CGFloat
    private let duration: TimeInterval
    private let remark: String?
    private var elapsed: TimeInterval = 0

    init(name: String, towardX targetX: CGFloat, duration: TimeInterval, remark: String? = nil) {
        self.name = name
        self.targetX = targetX
        self.duration = duration
        self.remark = remark
    }

    /// 가까운 친구에게 손 흔들기
    static func greeting(friendX: CGFloat) -> GlanceBehavior {
        GlanceBehavior(name: "greeting", towardX: friendX, duration: 1.6, remark: Chatter.hello)
    }

    func begin(_ pet: Pet) {
        pet.velocity = .zero
        pet.facing = targetX >= pet.position.x ? .east : .west
        if let remark {
            pet.say(remark, for: min(duration, 2.5))
        }
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard pet.followSupport(in: world) else { return AirborneBehavior.falling() }
        elapsed += dt
        return elapsed >= duration ? context.planner.rest() : nil
    }

    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        GroundReaction.poked(pet, streak: streak)
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        GroundReaction.announcing(pet, for: duration)
    }
}
