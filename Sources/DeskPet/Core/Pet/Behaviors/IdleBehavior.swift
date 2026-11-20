import Foundation

/// This object is responsible for a pet resting in place, riding along if its window moves,
/// and asking the planner what to do once the rest is over.
final class IdleBehavior: PetBehavior {
    let name: String
    let occupiesSpace = true
    let animation: AnimationKind = .idle
    let displayFacing: Facing?
    private let duration: TimeInterval
    private var elapsed: TimeInterval = 0

    init(duration: TimeInterval, lookAtUser: Bool = false, name: String? = nil) {
        self.duration = duration
        self.name = name ?? (lookAtUser ? "lookingAtUser" : "idle")
        self.displayFacing = lookAtUser ? .south : nil
    }

    var isAtLeisure: Bool { name == "idle" }

    func begin(_ pet: Pet) {
        pet.velocity = .zero
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard pet.followSupport(in: world) else { return AirborneBehavior.falling() }
        elapsed += dt
        return elapsed >= duration ? context.planner.next(after: pet, in: world, context: context) : nil
    }

    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        GroundReaction.poked(pet, streak: streak)
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        GroundReaction.announcing(pet, for: duration)
    }
}
