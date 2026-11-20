import Foundation

/// This object is responsible for a pet drumming along with the user's typing, like tapping on a desk:
/// it plays its attack frames (or steps in place when it has none) faster the faster the user types,
/// rides along if its window moves, and stops after a while or once the typing calms down.
final class DrummingBehavior: PetBehavior {
    let name = "drumming"
    let occupiesSpace = true
    private let hasActionFrames: Bool
    private let duration: TimeInterval
    private var elapsed: TimeInterval = 0
    private var calm: TimeInterval = 0
    private var speed = 1.0

    /// 이 빠르기(초당 누름)일 때 평소 속도로 두드림
    static let normalRate = 6.0
    static let speedRange: ClosedRange<Double> = 0.4...2.2
    /// 이보다 느려진 채 이만큼 지나면 멈춤
    static let calmRate = 1.0
    static let calmTime: TimeInterval = 1

    init(hasActionFrames: Bool, duration: TimeInterval) {
        self.hasActionFrames = hasActionFrames
        self.duration = duration
    }

    var animation: AnimationKind { hasActionFrames ? .act : .walk }
    var animationSpeed: Double { speed }

    func begin(_ pet: Pet) {
        pet.velocity = .zero
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard pet.followSupport(in: world) else { return AirborneBehavior.falling() }
        elapsed += dt
        let rate = context.typingRate
        speed = min(max(rate / Self.normalRate, Self.speedRange.lowerBound), Self.speedRange.upperBound)
        calm = rate < Self.calmRate ? calm + dt : 0
        return elapsed >= duration || calm >= Self.calmTime ? context.planner.rest() : nil
    }

    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        GroundReaction.poked(pet, streak: streak)
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        GroundReaction.announcing(pet, for: duration)
    }
}
