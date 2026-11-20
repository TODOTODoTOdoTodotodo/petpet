import Foundation

/// This object is responsible for a pet whose way is blocked calling the blocking pet out to a duel (⚔️):
/// it faces that pet and waits a moment for the duel to be accepted, and if nobody answers (the other is asleep,
/// busy or gone) it jumps over instead, or just rests when it cannot.
final class ChallengeBehavior: PetBehavior {
    let name = "challenging"
    let occupiesSpace = true
    let animation: AnimationKind = .idle
    private let opponentID: String
    private let opponentX: CGFloat
    private let fallback: PetBehavior?
    private var elapsed: TimeInterval = 0

    /// 결투를 받아 주길 기다리는 시간
    static let waitTime: TimeInterval = 0.7
    static let challengeText = "⚔️"

    init(opponent: FriendSighting, fallback: PetBehavior?) {
        self.opponentID = opponent.id
        self.opponentX = opponent.position.x
        self.fallback = fallback
    }

    var challengedID: String? { opponentID }

    func begin(_ pet: Pet) {
        pet.velocity = .zero
        pet.facing = opponentX >= pet.position.x ? .east : .west
        pet.say(Self.challengeText, for: Self.waitTime + 0.3)
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard pet.followSupport(in: world) else { return AirborneBehavior.falling() }
        elapsed += dt
        guard elapsed >= Self.waitTime else { return nil }
        return fallback ?? context.planner.rest()
    }

    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        GroundReaction.poked(pet, streak: streak)
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        GroundReaction.announcing(pet, for: duration)
    }
}
