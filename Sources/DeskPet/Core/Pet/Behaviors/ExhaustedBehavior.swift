import Foundation

/// This object is responsible for a pet that has run out of energy (Claude usage almost used up):
/// lying down and breathing with an empty-battery bubble now and then, stirring only briefly when clicked,
/// and asking the planner again after a while (it stays down until the usage window resets).
final class ExhaustedBehavior: PetBehavior {
    let name = "exhausted"
    let occupiesSpace = true
    let animation: AnimationKind = .sleep
    let effect: VisualEffect = .breathing
    private var elapsed: TimeInterval = 0
    private var sinceBubble: TimeInterval = .infinity

    static let duration: TimeInterval = 8
    private let bubbleInterval: TimeInterval = 6

    func begin(_ pet: Pet) {
        pet.velocity = .zero
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard pet.followSupport(in: world) else { return AirborneBehavior.falling() }
        elapsed += dt
        sinceBubble += dt
        if sinceBubble >= bubbleInterval {
            sinceBubble = 0
            pet.say(Vigor.emptyText, for: 2)
        }
        return elapsed >= Self.duration ? context.planner.next(after: pet, in: world, context: context) : nil
    }

    /// 클릭하면 힘없이 꿈틀
    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        pet.say(Chatter.drowsy)
        return IdleBehavior(duration: 1.2)
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        GroundReaction.announcing(pet, for: duration)
    }
}
