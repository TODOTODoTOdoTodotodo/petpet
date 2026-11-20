import Foundation

/// This object is responsible for a pet held by the mouse: following the cursor,
/// keeping its feet above the floor, and turning the last hand motion into a throw on release.
final class DraggedBehavior: PetBehavior {
    let name = "dragged"
    let animation: AnimationKind = .dragged
    let displayFacing: Facing? = .south
    private let grabOffset: CGVector
    private var target: CGPoint?
    private var released = false
    private var throwVelocity: CGVector = .zero

    init(grabOffset: CGVector) {
        self.grabOffset = grabOffset
    }

    func begin(_ pet: Pet) {
        pet.support = nil
        pet.velocity = .zero
    }

    func move(to cursor: CGPoint) {
        target = CGPoint(x: cursor.x + grabOffset.dx, y: cursor.y + grabOffset.dy)
    }

    func release() {
        released = true
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        if var next = target, dt > 0 {
            if let floor = world.floor(atX: next.x) {
                next.y = max(next.y, floor.y)
            }
            let instant = CGVector(dx: (next.x - pet.position.x) / CGFloat(dt), dy: (next.y - pet.position.y) / CGFloat(dt))
            throwVelocity = CGVector(dx: throwVelocity.dx * 0.6 + instant.dx * 0.4, dy: throwVelocity.dy * 0.6 + instant.dy * 0.4)
            pet.position = next
            target = nil
        } else {
            // 손이 멈춰 있으면 던지는 힘이 빠짐
            throwVelocity = CGVector(dx: throwVelocity.dx * 0.5, dy: throwVelocity.dy * 0.5)
        }

        guard released else { return nil }
        let limit = PetPhysics.maxThrowSpeed
        let launch = CGVector(dx: min(max(throwVelocity.dx, -limit), limit), dy: min(max(throwVelocity.dy, -limit), limit))
        return AirborneBehavior(name: "thrown", launch: launch)
    }
}
