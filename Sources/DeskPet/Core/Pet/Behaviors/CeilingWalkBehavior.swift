import Foundation

/// This object is responsible for a pet clinging upside down to the underside of a window, like a gecko on a ceiling:
/// strolling and pausing along the visible bottom edge (its feet on the edge, its body hanging below), riding along when
/// the window moves, heading toward the mouse pointer when it is below this window (pointer mode),
/// and dropping off after a while, when clicked, when announcing, or when the edge disappears or gets covered.
/// The stage draws the usual walk and idle frames flipped, so every skin works the same way.
final class CeilingWalkBehavior: PetBehavior {
    let name = "clinging"
    private let windowID: UInt32
    private var lastWindowMinX: CGFloat?
    private var elapsed: TimeInterval = 0
    private var phaseElapsed: TimeInterval = 0
    private var phaseLength: TimeInterval = 0
    /// 걷는 방향 (nil이면 쉬는 중)
    private var direction: Facing?
    private var targetX: CGFloat?

    /// 붙어 있는 시간 (포인터가 이 창 밑에 있으면 천천히 셈)
    static let stay: TimeInterval = 9
    /// 포인터가 밑에 있을 때 시간이 흐르는 비율
    static let pointerStayRate = 0.25
    /// 걷는 속도 배율 (평소 걷기 대비)
    static let speedFactor: CGFloat = 0.7
    /// 이보다 포인터가 아래로 멀면 쫓지 않음 (기준 크기)
    static let pointerReach: CGFloat = 220

    init(windowID: UInt32) {
        self.windowID = windowID
    }

    var animation: AnimationKind { direction == nil ? .idle : .walk }
    var animationSpeed: Double { direction == nil ? 1 : Double(Self.speedFactor) }
    var heldWindowID: UInt32? { windowID }
    var pose: BodyPose { BodyPose(upsideDown: true, hiddenAbove: nil) }

    func begin(_ pet: Pet) {
        pet.support = nil
        pet.velocity = .zero
        phaseLength = 0.6
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard let window = world.window(id: windowID) else { return AirborneBehavior.falling() }
        // 창이 움직이면 따라감. 순간이동(최대화 등)이면 놓음
        let shift = lastWindowMinX.map { window.frame.minX - $0 } ?? 0
        guard abs(shift) <= Pet.maxRideStep else { return AirborneBehavior.falling() }
        lastWindowMinX = window.frame.minX
        let before = pet.position
        pet.position = CGPoint(x: pet.position.x + shift, y: window.frame.minY)
        guard let edge = world.underside(atX: pet.position.x, nearY: window.frame.minY, tolerance: 1),
              edge.owner == .window(id: windowID) else {
            // 따라간 자리에 아랫변이 없으면(화면 밖·가려짐) 원래 자리에서 놓음
            pet.position = before
            return AirborneBehavior.falling()
        }

        let pointerX = pointerBelow(context.pointer, edge: edge, pet: pet)
        elapsed += pointerX == nil ? dt : dt * Self.pointerStayRate
        guard elapsed < Self.stay else { return AirborneBehavior.falling() }

        phaseElapsed += dt
        if let direction {
            walk(pet, direction: direction, along: edge, dt: dt)
        } else if phaseElapsed >= phaseLength {
            startWalking(pet, along: edge, toward: pointerX, context: context)
        }
        return nil
    }

    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        pet.say(Chatter.surprised)
        return AirborneBehavior.falling()
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        AirborneBehavior.falling()
    }

    // MARK: - Steps

    /// 포인터가 이 아랫변 바로 밑(가까이)에 있으면 그 x
    private func pointerBelow(_ pointer: CGPoint?, edge: Ledge, pet: Pet) -> CGFloat? {
        guard let pointer, pointer.y < edge.y, edge.y - pointer.y <= Self.pointerReach * pet.motionScale,
              edge.spans(pointer.x) else { return nil }
        return pointer.x
    }

    private func startWalking(_ pet: Pet, along edge: Ledge, toward pointerX: CGFloat?, context: PetContext) {
        let low = edge.minX + pet.bodyHalfWidth
        let high = edge.maxX - pet.bodyHalfWidth
        if let pointerX {
            let goal = min(max(pointerX, low), high)
            // 포인터 바로 위에 있으면 그 자리에서 내려다봄
            guard abs(goal - pet.position.x) > 12 else { rest(context) ; return }
            targetX = goal
            direction = goal > pet.position.x ? .east : .west
        } else {
            targetX = nil
            // 끝에 가까우면 안쪽으로
            let roomEast = high - pet.position.x
            let roomWest = pet.position.x - low
            if roomEast < 30 || roomWest < 30 {
                direction = roomEast > roomWest ? .east : .west
            } else {
                direction = context.planner.chance(0.5) ? .east : .west
            }
        }
        pet.facing = direction ?? pet.facing
        phaseElapsed = 0
        phaseLength = context.planner.strollDuration()
    }

    private func walk(_ pet: Pet, direction: Facing, along edge: Ledge, dt: TimeInterval) {
        let low = edge.minX + pet.bodyHalfWidth
        let high = edge.maxX - pet.bodyHalfWidth
        let speed = PetPhysics.walkSpeed * Self.speedFactor * pet.motionScale
        var x = pet.position.x + direction.sign * speed * CGFloat(dt)
        var arrived = phaseElapsed >= phaseLength
        if let targetX, (direction == .east && x >= targetX) || (direction == .west && x <= targetX) {
            x = targetX
            arrived = true
        }
        if x <= low || x >= high {
            x = min(max(x, low), high)
            arrived = true
        }
        pet.position.x = x
        if arrived {
            self.direction = nil
            targetX = nil
            phaseElapsed = 0
            phaseLength = 1.2
        }
    }

    private func rest(_ context: PetContext) {
        direction = nil
        targetX = nil
        phaseElapsed = 0
        phaseLength = context.planner.restDuration()
    }
}
