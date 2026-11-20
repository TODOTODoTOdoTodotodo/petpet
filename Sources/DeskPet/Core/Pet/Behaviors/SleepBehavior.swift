import Foundation

/// This object is responsible for a pet dozing off while the user is away:
/// sitting front-facing, drowsy at first, then asleep and breathing, and waking with a start
/// as soon as keyboard or mouse input comes back (or it is clicked).
final class SleepBehavior: PetBehavior {
    let name = "sleeping"
    let occupiesSpace = true
    let animation: AnimationKind = .sleep
    let effect: VisualEffect = .breathing
    private var elapsed: TimeInterval = 0
    private var sinceBubble: TimeInterval = .infinity

    /// 졸기(…)에서 잠(Zzz)으로 넘어가는 시간
    static let drowsyDuration: TimeInterval = 6
    /// 이보다 최근에 입력이 있으면 깨어남
    static let wakeInputSeconds: TimeInterval = 1.5
    private let bubbleInterval: TimeInterval = 3.5

    func begin(_ pet: Pet) {
        pet.velocity = .zero
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard pet.followSupport(in: world) else { return AirborneBehavior.falling() }
        if context.idleSeconds < Self.wakeInputSeconds {
            return wake(pet)
        }
        elapsed += dt
        sinceBubble += dt
        if sinceBubble >= bubbleInterval {
            sinceBubble = 0
            pet.say(elapsed < Self.drowsyDuration ? Chatter.drowsy : Chatter.asleep, for: bubbleInterval - 0.3)
        }
        return nil
    }

    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        wake(pet)
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        GroundReaction.announcing(pet, for: duration)
    }

    private func wake(_ pet: Pet) -> PetBehavior {
        pet.say(Chatter.surprised)
        return AirborneBehavior.hop(name: "waking", motionScale: pet.motionScale)
    }
}
