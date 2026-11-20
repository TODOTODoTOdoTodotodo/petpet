import Foundation

/// This object is responsible for a pet in the air (jumping, falling or thrown):
/// applying gravity in small steps, bouncing off screen sides and landing on the first visible ledge below.
final class AirborneBehavior: PetBehavior {
    let name: String
    let animation: AnimationKind = .airborne
    private let launch: CGVector
    /// 내려온 뒤 어지러워하는지 (흔들린 창에서 튕겨 나감, 탑이 무너짐)
    private let isDizzy: Bool
    /// 내려온 뒤 사용자 쪽을 보며 하는 말 (처음 등장)
    private let landingRemark: String?
    /// 공중에서 몸이 한 바퀴 도는지 (친밀도 Lv.3 점프)
    private let somersault: Bool
    private var airTime: TimeInterval = 0
    /// 앞쪽으로 도는 방향 부호 (동쪽 점프면 시계 방향)
    private var spinSign: CGFloat = 1

    /// 어지러워 멈춰 있는 시간
    static let dizzyTime: TimeInterval = 1.4

    /// 인사하며 사용자를 보는 시간
    static let greetTime: TimeInterval = 1.4

    init(name: String, launch: CGVector, dizzy: Bool = false, landingRemark: String? = nil, somersault: Bool = false) {
        self.name = name
        self.launch = launch
        self.isDizzy = dizzy
        self.landingRemark = landingRemark
        self.somersault = somersault
    }

    /// 제자리 높이로 돌아오기까지 걸리는 시간 동안 한 바퀴 (그 뒤는 바로 선 채)
    var bodyRotation: CGFloat {
        guard somersault, launch.dy > 0 else { return 0 }
        let flight = TimeInterval(2 * launch.dy / (PetPhysics.gravity * max(launch.dy / PetPhysics.jumpSpeed, 0.01)))
        let progress = min(airTime / max(flight, 0.1), 1)
        return -spinSign * 2 * .pi * CGFloat(progress)
    }

    static func falling(drift: CGFloat = 0) -> AirborneBehavior {
        AirborneBehavior(name: "falling", launch: CGVector(dx: drift, dy: 0))
    }

    static func jumping(toward facing: Facing, motionScale: CGFloat, somersault: Bool = false) -> AirborneBehavior {
        AirborneBehavior(
            name: somersault ? "somersault" : "jumping",
            launch: CGVector(dx: facing.sign * PetPhysics.jumpDrift * motionScale, dy: PetPhysics.jumpSpeed * motionScale),
            somersault: somersault
        )
    }

    /// 흔들린 창에서 튕겨 나감
    static func flung(_ launch: CGVector) -> AirborneBehavior {
        AirborneBehavior(name: "flung", launch: launch, dizzy: true)
    }

    /// 탑에서 떨어짐. 높은 층이면 어지러워함
    static func tumbling(_ launch: CGVector, dizzy: Bool) -> AirborneBehavior {
        AirborneBehavior(name: "tumbling", launch: launch, dizzy: dizzy)
    }

    /// 제자리 깡충
    static func hop(name: String, motionScale: CGFloat) -> AirborneBehavior {
        AirborneBehavior(name: name, launch: CGVector(dx: 0, dy: PetPhysics.hopSpeed * motionScale))
    }

    func begin(_ pet: Pet) {
        pet.support = nil
        pet.velocity = launch
        if launch.dx != 0 {
            pet.facing = launch.dx > 0 ? .east : .west
        }
        spinSign = pet.facing.sign
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        airTime += dt
        var remaining = dt
        while remaining > 0 {
            let slice = min(remaining, PetPhysics.maxStep)
            remaining -= slice
            if integrate(pet, in: world, dt: CGFloat(slice)) {
                if isDizzy {
                    pet.say(Chatter.dizzy, for: Self.dizzyTime)
                    return IdleBehavior(duration: Self.dizzyTime, name: "dizzy")
                }
                if let landingRemark {
                    pet.say(landingRemark, for: Self.greetTime)
                    pet.note(.greeted)
                    return IdleBehavior(duration: Self.greetTime, lookAtUser: true, name: "greetingUser")
                }
                return IdleBehavior(duration: PetPhysics.landingPause)
            }
        }
        return nil
    }

    /// 한 조각 시간만큼 움직이고 착지했으면 true
    private func integrate(_ pet: Pet, in world: World, dt: CGFloat) -> Bool {
        let k = pet.motionScale
        pet.velocity.dy = max(pet.velocity.dy - PetPhysics.gravity * k * dt, -PetPhysics.terminalSpeed * k)

        var next = CGPoint(x: pet.position.x + pet.velocity.dx * dt, y: pet.position.y + pet.velocity.dy * dt)

        // 화면 옆 경계에서 튕김
        if pet.velocity.dx != 0 {
            let side: CGFloat = pet.velocity.dx > 0 ? 1 : -1
            let front = CGPoint(x: next.x + side * pet.bodyHalfWidth, y: max(next.y, pet.position.y) + 1)
            if !world.contains(front) {
                pet.velocity.dx = -pet.velocity.dx * 0.3
                next.x = pet.position.x
            }
        }

        // 천장에 머리가 닿으면 상승 멈춤
        if pet.velocity.dy > 0, let ceiling = world.ceiling(atX: next.x, above: pet.position.y), next.y + pet.bodyHeight > ceiling {
            next.y = max(pet.position.y, ceiling - pet.bodyHeight)
            pet.velocity.dy = 0
        }

        if pet.velocity.dy <= 0 {
            if let ledge = world.landingLedge(atX: next.x, from: pet.position.y, to: next.y) {
                land(pet, on: ledge, atX: next.x, in: world)
                return true
            }
            // 바닥보다 아래에서 시작한 경우의 안전장치
            if let floor = world.floor(atX: next.x), next.y < floor.y {
                land(pet, on: floor, atX: next.x, in: world)
                return true
            }
        }

        pet.position = next
        return false
    }

    private func land(_ pet: Pet, on ledge: Ledge, atX x: CGFloat, in world: World) {
        pet.position.x = x
        pet.velocity = .zero
        pet.stand(on: ledge, in: world)
    }
}
