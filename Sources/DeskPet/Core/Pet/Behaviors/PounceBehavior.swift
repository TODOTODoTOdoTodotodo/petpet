import Foundation

/// This object is responsible for a pet jumping up at the mouse pointer from where it stands:
/// a planned jump toward it (as high as the ceiling and the pet's legs allow), a ✨ once if its body touches the pointer,
/// and an ordinary landing afterward.
final class PounceBehavior: PetBehavior {
    let name = "pouncing"
    let animation: AnimationKind = .airborne
    private let flight: AirborneBehavior
    private var caught = false

    /// 포인터에 닿았을 때
    static let caughtText = "✨"
    /// 몸 둘레 이만큼까지 닿은 것으로 봄
    static let touchMargin: CGFloat = 8
    /// 평소 점프보다 더 높이 뛸 수 있는 배율
    static let boost: CGFloat = 1.25

    init(launch: CGVector) {
        flight = AirborneBehavior(name: "pouncing", launch: launch)
    }

    /// 포인터 쪽으로 뛸 발사 속도와, 그 높이로 닿는지. 머리 위 공간이 너무 좁으면 nil
    static func plan(for pet: Pet, toward pointer: CGPoint, in world: World) -> (launch: CGVector, reaches: Bool)? {
        guard let ceiling = world.ceiling(atX: pet.position.x, above: pet.position.y) else { return nil }
        let k = pet.motionScale
        let gravity = PetPhysics.gravity * k
        let room = ceiling - pet.position.y - pet.bodyHeight - 4
        guard room > 20 else { return nil }
        // 몸 위쪽(머리)이 포인터에 닿을 높이
        let wanted = pointer.y - (pet.position.y + pet.bodyHeight * 0.8)
        let rise = min(max(wanted, 20), room)
        let vy = min(sqrt(2 * gravity * rise), PetPhysics.jumpSpeed * k * boost)
        let toApex = vy / gravity
        let drift = PetPhysics.jumpDrift * k
        let vx = min(max((pointer.x - pet.position.x) / toApex, -drift), drift)
        let apex = vy * vy / (2 * gravity)
        return (CGVector(dx: vx, dy: vy), apex >= wanted - 4)
    }

    func begin(_ pet: Pet) {
        flight.begin(pet)
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        if !caught, let pointer = context.pointer,
           pet.bodyRect.insetBy(dx: -Self.touchMargin, dy: -Self.touchMargin).contains(pointer) {
            caught = true
            pet.say(Self.caughtText, for: 1.0)
        }
        return flight.step(pet, in: world, context: context, dt: dt)
    }
}
