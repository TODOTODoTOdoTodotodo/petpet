import Foundation

/// This object is responsible for a happy spin in place (affection Lv.2): turning to face the other way
/// a few times in quick succession with a ♪, then resting.
final class SpinBehavior: PetBehavior {
    let name = "spinning"
    let animation: AnimationKind = .idle
    let occupiesSpace = true
    private var elapsed: TimeInterval = 0
    private var turns = 0

    /// 방향을 바꾸는 간격과 횟수
    static let turnInterval: TimeInterval = 0.12
    static let turnCount = 6
    static let noteText = "♪"

    func begin(_ pet: Pet) {
        pet.velocity = .zero
        pet.say(Self.noteText, for: 1.0)
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard pet.followSupport(in: world) else { return AirborneBehavior.falling() }
        elapsed += dt
        while turns < Self.turnCount && elapsed >= Double(turns + 1) * Self.turnInterval {
            pet.facing = pet.facing.opposite
            turns += 1
        }
        return turns >= Self.turnCount ? context.planner.rest() : nil
    }

    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        GroundReaction.poked(pet, streak: streak)
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        GroundReaction.announcing(pet, for: duration)
    }
}
