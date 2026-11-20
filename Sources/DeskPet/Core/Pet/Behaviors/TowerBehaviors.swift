import Foundation

/// This object is responsible for the pet at the bottom of a pet tower: standing still (riding along if its window moves)
/// while others stand on its head, for a while that grows as the tower grows, then stepping away so the tower comes apart.
/// Clicking or dragging it brings the whole tower down.
final class TowerBaseBehavior: PetBehavior {
    let name = "towerBase"
    let occupiesSpace = true
    let animation: AnimationKind = .idle
    private var duration: TimeInterval
    private var elapsed: TimeInterval = 0

    /// 탑을 받치는 최대 시간
    static let longestHold: TimeInterval = 18

    init(duration: TimeInterval) {
        self.duration = duration
    }

    var towerLevel: Int? { 0 }

    /// 위에 한 마리가 더 올라와 조금 더 버팀
    func extend(by extra: TimeInterval) {
        duration = min(duration + extra, Self.longestHold)
    }

    func begin(_ pet: Pet) {
        pet.velocity = .zero
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

/// This object is responsible for a pet standing on another pet's head in a tower:
/// keeping its feet on that head (swaying a little, more the higher it is), and tumbling off
/// when the pet below stops carrying it, is taken away, or the tower would leave the screen.
/// Clicking it makes it hop down; the higher ones get dizzy when the tower collapses.
final class StackedBehavior: PetBehavior {
    let name = "stacked"
    let animation: AnimationKind = .idle
    private weak var below: Pet?
    private let level: Int
    private var elapsed: TimeInterval = 0

    /// 흔들림 폭 (기준 크기, 한 층당)
    static let swayWidth: CGFloat = 1.2
    /// 흔들림 빠르기 (Hz)
    static let swayRate: Double = 0.8

    init(on below: Pet, level: Int) {
        self.below = below
        self.level = level
    }

    var towerLevel: Int? { level }

    /// 그 펫 머리 위에 서 있는지
    func stands(on pet: Pet) -> Bool {
        below === pet
    }

    func begin(_ pet: Pet) {
        pet.support = nil
        pet.velocity = .zero
        if let below { pet.facing = below.facing }
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard let below, below.behavior.towerLevel != nil else { return tumble(pet) }
        elapsed += dt
        let sway = CGFloat(sin(elapsed * 2 * .pi * Self.swayRate + Double(level))) * Self.swayWidth * pet.motionScale
        let spot = StackedBehavior.head(of: below)
        guard world.contains(CGPoint(x: spot.x, y: spot.y + pet.bodyHeight)) else { return tumble(pet) }
        pet.position = CGPoint(x: spot.x + sway, y: spot.y)
        return nil
    }

    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        pet.say(Chatter.love)
        return AirborneBehavior.jumping(toward: pet.facing, motionScale: pet.motionScale)
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        AirborneBehavior.jumping(toward: pet.facing, motionScale: pet.motionScale)
    }

    /// 그 펫 머리 위에 발을 올릴 자리 (발이 머리에 한 픽셀 겹침)
    static func head(of pet: Pet) -> CGPoint {
        CGPoint(x: pet.position.x, y: pet.position.y + pet.bodyHeight - pet.scale)
    }

    /// 받쳐 주던 펫이 사라짐: 층마다 번갈아 양옆으로, 높을수록 멀리 떨어지고 2층부터는 어지러워함
    private func tumble(_ pet: Pet) -> PetBehavior {
        let k = pet.motionScale
        let side: CGFloat = level % 2 == 0 ? 1 : -1
        let launch = CGVector(dx: side * pet.facing.sign * (60 + 40 * CGFloat(level)) * k, dy: (180 + 40 * CGFloat(level)) * k)
        let dizzy = level >= 2
        if dizzy { pet.say(Chatter.dizzy, for: 1.5) }
        return AirborneBehavior.tumbling(launch, dizzy: dizzy)
    }
}

/// This object is responsible for a pet jumping onto the head of the pet at the top of a tower:
/// a planned arc that comes down onto that head, landing there only if the pet is still carrying and close by,
/// otherwise just falling on.
final class StackLeapBehavior: PetBehavior {
    let name = "stackLeap"
    let animation: AnimationKind = .airborne
    private weak var target: Pet?
    private let level: Int
    private let launch: CGVector
    private let flightTime: TimeInterval
    private var start: CGPoint = .zero
    private var elapsed: TimeInterval = 0

    /// 착지할 머리 위로 넘는 높이 (기준 크기)
    static let arcHeight: CGFloat = 26
    /// 머리가 이만큼 어긋나 있으면 올라서지 못함
    static let landingTolerance: CGFloat = 20

    /// This object is responsible for the numbers of one leap onto a pet's head.
    struct Plan {
        let launch: CGVector
        let flightTime: TimeInterval
    }

    init(onto target: Pet, plan: Plan) {
        self.target = target
        self.level = (target.behavior.towerLevel ?? 0) + 1
        self.launch = plan.launch
        self.flightTime = plan.flightTime
    }

    /// 그 펫 머리로 뛰는 중인지
    func isHeading(to pet: Pet) -> Bool {
        target === pet
    }

    var displayFacing: Facing? { launch.dx == 0 ? nil : (launch.dx > 0 ? .east : .west) }

    func begin(_ pet: Pet) {
        pet.support = nil
        pet.velocity = launch
        start = pet.position
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        elapsed = min(elapsed + dt, flightTime)
        let g = PetPhysics.gravity * pet.motionScale
        let t = CGFloat(elapsed)
        pet.position = CGPoint(x: start.x + launch.dx * t, y: start.y + launch.dy * t - 0.5 * g * t * t)
        pet.velocity = CGVector(dx: launch.dx, dy: launch.dy - g * t)
        guard elapsed >= flightTime else { return nil }

        if let target, target.behavior.towerLevel != nil {
            let head = StackedBehavior.head(of: target)
            if abs(head.x - pet.position.x) <= Self.landingTolerance * pet.motionScale,
               abs(head.y - pet.position.y) <= Self.landingTolerance * pet.motionScale {
                pet.position = head
                if level >= 2 {
                    pet.say(Chatter.cheer, for: 1.2)
                    pet.note(.toppedTower)
                }
                return StackedBehavior(on: target, level: level)
            }
        }
        return AirborneBehavior(name: "falling", launch: pet.velocity)
    }

    /// pet이 top 머리 위로 뛰어오르는 궤적. 머리 공간(화면 위·창 아랫변)이 모자라면 nil
    static func plan(for pet: Pet, onto top: Pet, in world: World) -> Plan? {
        let landing = StackedBehavior.head(of: top)
        let k = pet.motionScale
        let g = PetPhysics.gravity * k
        let apex = max(landing.y, pet.position.y) + arcHeight * k
        var roof = world.ceiling(atX: landing.x, above: landing.y) ?? -.infinity
        if let underside = world.underside(above: CGPoint(x: landing.x, y: landing.y)) { roof = min(roof, underside.y) }
        guard apex + pet.bodyHeight <= roof - 2 else { return nil }
        let rise = apex - pet.position.y
        let vy = sqrt(2 * g * rise)
        let time = TimeInterval(vy / g + sqrt(2 * (apex - landing.y) / g))
        return Plan(launch: CGVector(dx: (landing.x - pet.position.x) / CGFloat(time), dy: vy), flightTime: time)
    }
}
