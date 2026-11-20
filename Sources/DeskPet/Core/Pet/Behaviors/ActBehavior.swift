import Foundation

/// This object is responsible for playing a skin's special action (e.g. an attack swing) once in place.
/// The planner only chooses it for skins that actually have action frames.
final class ActBehavior: PetBehavior {
    let name = "acting"
    let occupiesSpace = true
    let animation: AnimationKind = .act
    private var duration: TimeInterval = 0
    private var elapsed: TimeInterval = 0

    func begin(_ pet: Pet) {
        pet.velocity = .zero
        duration = max(0.2, pet.appearance.cycleDuration(of: .act, facing: pet.facing))
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
