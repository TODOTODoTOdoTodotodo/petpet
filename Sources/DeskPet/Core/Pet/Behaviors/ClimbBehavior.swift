import Foundation

/// This object is responsible for a pet climbing a window side, following the window if it moves,
/// and stepping inward onto the roof when it reaches the top.
final class ClimbBehavior: PetBehavior {
    let name = "climbing"
    let animation: AnimationKind = .climb
    private let windowID: UInt32
    private let face: WallFace

    init(wall: Wall) {
        self.windowID = wall.windowID
        self.face = wall.face
    }

    func begin(_ pet: Pet) {
        pet.support = nil
        pet.velocity = .zero
        // 벽 쪽을 봄 (뒷모습이 없는 스킨은 이 방향의 걷기 프레임으로 오름)
        pet.facing = face == .left ? .east : .west
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        let outward = face.outwardSign
        guard let window = world.window(id: windowID) else {
            return AirborneBehavior.falling(drift: outward * 40)
        }

        let edgeX = face == .left ? window.frame.minX : window.frame.maxX
        let clingX = edgeX + outward * pet.bodyHalfWidth
        // 창이 순간이동했거나 따라가면 화면 밖이면 붙지 않고 그 자리에서 떨어짐
        guard abs(clingX - pet.position.x) <= Pet.maxRideStep,
              world.contains(CGPoint(x: clingX, y: pet.position.y + 1)) else {
            return AirborneBehavior.falling()
        }
        pet.position.x = clingX
        pet.position.y += PetPhysics.climbSpeed * pet.motionScale * CGFloat(dt)

        let top = window.frame.maxY
        if pet.position.y >= top {
            // 지붕 모서리 안쪽으로 올라섬
            pet.position = CGPoint(x: edgeX - outward * (pet.bodyHalfWidth + 2), y: top)
            pet.facing = face == .left ? .east : .west
            guard pet.settle(in: world, tolerance: 1) else { return AirborneBehavior.falling() }
            return WalkBehavior(direction: pet.facing, duration: context.planner.strollDuration())
        }

        // 손 높이. 꼭대기 근처에서는 윗변 바로 아래를 잡음
        let grip = min(pet.position.y + pet.bodyHeight * 0.5, top - 1)
        guard world.visibleWall(windowID: windowID, face: face, coveringY: grip) != nil else {
            return AirborneBehavior.falling(drift: outward * 40)
        }
        return nil
    }
}
