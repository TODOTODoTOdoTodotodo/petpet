import CoreGraphics
import Foundation

/// This object is responsible for checking pets clinging upside down to window undersides:
/// which bottom edges count, the leap that reaches them, walking and riding along upside down,
/// letting go in the same spot, and going there by themselves or toward the pointer.
enum CeilingChecks {
    static func run(_ check: Checker) {
        undersides(check)
        clinging(check)
        lettingGo(check)
        choosing(check)
    }

    private static func roster(seed: UInt64, pointer: Bool = false) -> PetRoster {
        let roster = PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: seed)))
        roster.chase = ChaseModes.make(pointer ? PointerChase.key : ActiveWindowChase.key)
        return roster
    }

    private static func restingPet(in roster: PetRoster, world: World, x: CGFloat, idle: TimeInterval = 999) -> Pet {
        let pet = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        pet.position = CGPoint(x: x, y: 80)
        pet.settle(in: world)
        pet.switchTo(IdleBehavior(duration: idle))
        return pet
    }

    private static func run(_ roster: PetRoster, in world: World, cursor: CGPoint? = nil, seconds: Double, until stop: (() -> Bool)? = nil) {
        for _ in 0..<Int(seconds * 60) {
            roster.step(dt: Sim.dt, in: world, cursor: cursor)
            if let stop, stop() { return }
        }
    }

    /// 창 아랫변에 붙은 펫 (바로 붙임)
    private static func clingingPet(in roster: PetRoster, world: World, window: UInt32, x: CGFloat) -> Pet {
        let pet = restingPet(in: roster, world: world, x: x)
        let plan = LeapPlanner.clingPlan(for: pet, to: window, in: world)!
        pet.switchTo(SkillLeapBehavior(plan: plan, style: .bigJump, hasActionFrames: false))
        run(roster, in: world, seconds: 4, until: { pet.behavior is CeilingWalkBehavior })
        return pet
    }

    private static func undersides(_ check: Checker) {
        check.section("창 아랫면: 붙을 수 있는 구간")
        let back = Sim.window(7, 300, 300, 600, 300)        // 아랫변 300
        let front = Sim.window(8, 500, 250, 200, 100)       // 아랫변 300을 가로질러 가림
        let low = Sim.window(9, 1000, 100, 400, 300)        // 아랫변 100 (바닥 80과 너무 가까움)
        let world = Sim.world(windows: [front, back, low])
        let spans = world.undersides.filter { $0.owner == .window(id: 7) }.map { [$0.minX, $0.maxX] }
        check.expect(spans == [[300, 500], [700, 900]], "앞 창에 가린 곳을 뺀 아랫변", "\(spans)")
        check.expect(world.undersides.allSatisfy { $0.owner != .window(id: 9) }, "바닥에 너무 가까운 아랫변은 제외")
        check.expect(world.underside(above: CGPoint(x: 350, y: 120))?.owner == .window(id: 7), "점 바로 위 첫 아랫변")
        check.expect(world.underside(above: CGPoint(x: 600, y: 120))?.owner == .window(id: 8), "더 낮은 앞 창 아랫변이 먼저")
    }

    private static func clinging(_ check: Checker) {
        check.section("창 아랫면: 거꾸로 붙어 다니기")
        let world = Sim.world(windows: [Sim.window(7, 300, 300, 600, 300)])
        let roster = Self.roster(seed: 81)
        let pet = restingPet(in: roster, world: world, x: 600)
        let plan = LeapPlanner.clingPlan(for: pet, to: 7, in: world)
        var isCling = false
        if case .cling(7, _, let footY) = plan?.target, abs(footY - (300 - pet.bodyHeight - LeapPlanner.gripGap)) < 0.01 { isCling = true }
        check.expect(isCling, "아랫변 바로 밑에서 머리가 닿는 도약 계획", "\(String(describing: plan))")
        check.expect(LeapPlanner.clingPlan(for: pet, to: 99, in: world) == nil, "없는 창은 계획 없음")

        pet.switchTo(SkillLeapBehavior(plan: plan!, style: .bigJump, hasActionFrames: false))
        run(roster, in: world, seconds: 4, until: { pet.behavior is CeilingWalkBehavior })
        check.expect(pet.behavior is CeilingWalkBehavior && pet.position.y == 300 && pet.perchWindowID == 7,
                     "최고점에서 아랫변에 달라붙음 (발이 아랫변)", "\(pet.behavior.name) \(pet.position)")
        check.expect(pet.pose.upsideDown && pet.bodyRect.maxY == 300 && pet.bodyRect.minY == 300 - pet.bodyHeight,
                     "거꾸로 뒤집혀 몸이 아래로 늘어짐", "\(pet.bodyRect)")
        check.expect(!pet.isLost(in: world) && roster.pet(at: CGPoint(x: pet.position.x, y: 280)) === pet, "보이는 몸이 클릭됨")

        var walked = false
        var leftEdge = false
        let start = pet.position.x
        run(roster, in: world, seconds: 5, until: {
            if abs(pet.position.x - start) > 20 && pet.animation == .walk { walked = true }
            if pet.position.x < 300 + pet.bodyHalfWidth - 0.01 || pet.position.x > 900 - pet.bodyHalfWidth + 0.01 { leftEdge = true }
            return !(pet.behavior is CeilingWalkBehavior)
        })
        check.expect(walked, "거꾸로 걸어 다님")
        check.expect(!leftEdge, "아랫변 끝을 넘지 않음")

        world.update(windows: [Sim.window(7, 330, 280, 600, 300)])
        let before = pet.position
        run(roster, in: world, seconds: Sim.dt)
        check.expect(pet.behavior is CeilingWalkBehavior && pet.position.y == 280 && abs(pet.position.x - before.x - 30) < 3,
                     "창이 움직이면 붙은 채 따라감", "\(pet.position)")
    }

    private static func lettingGo(_ check: Checker) {
        check.section("창 아랫면: 떨어지기")
        do {
            let world = Sim.world(windows: [Sim.window(7, 300, 300, 600, 300)])
            let roster = Self.roster(seed: 82)
            let pet = clingingPet(in: roster, world: world, window: 7, x: 600)
            let box = pet.bodyRect
            run(roster, in: world, seconds: CeilingWalkBehavior.stay + 1, until: { !(pet.behavior is CeilingWalkBehavior) })
            check.expect(pet.behavior is AirborneBehavior && pet.pose == .upright, "잠시 뒤 놓고 떨어짐", pet.behavior.name)
            check.expect(pet.bodyRect.maxY <= 300 + 0.01 && abs(pet.bodyRect.height - box.height) < 0.01,
                         "같은 자리에서 바로 서서 아랫변 아래로 떨어짐", "\(pet.bodyRect)")
            run(roster, in: world, seconds: 3, until: { pet.support != nil })
            check.expect(pet.position.y == 80, "바닥에 내려옴", "\(pet.position)")
        }
        do {
            let world = Sim.world(windows: [Sim.window(7, 300, 300, 600, 300)])
            let roster = Self.roster(seed: 83)
            let pet = clingingPet(in: roster, world: world, window: 7, x: 600)
            pet.poke()
            check.expect(pet.behavior is AirborneBehavior && pet.speech?.text == Chatter.surprised && pet.bodyRect.maxY <= 300.01,
                         "클릭하면 놀라며 떨어짐")
        }
        do {
            let world = Sim.world(windows: [Sim.window(7, 300, 300, 600, 300)])
            let roster = Self.roster(seed: 84)
            let pet = clingingPet(in: roster, world: world, window: 7, x: 600)
            world.update(windows: [Sim.window(8, 0, 200, 1600, 300), Sim.window(7, 300, 300, 600, 300)])
            run(roster, in: world, seconds: Sim.dt * 2)
            check.expect(!(pet.behavior is CeilingWalkBehavior), "아랫변이 앞 창에 가리면 떨어짐", pet.behavior.name)
        }
    }

    private static func choosing(_ check: Checker) {
        check.section("창 아랫면: 스스로 가기·포인터 따라 가기")
        // 평소: 머리 위 아랫변이 있으면 가끔 붙으러 감 (보고 있는 창 없음)
        do {
            let world = Sim.world(windows: [Sim.window(7, 200, 300, 1200, 300)])
            let roster = Self.roster(seed: 85)
            let pet = restingPet(in: roster, world: world, x: 800, idle: 0.5)
            var clung = false
            run(roster, in: world, seconds: 120, until: {
                if pet.behavior is CeilingWalkBehavior { clung = true }
                return clung
            })
            check.expect(clung, "머리 위 창 아랫변에 가끔 스스로 붙음")
        }
        // 스킬을 끄면 가지 않음
        do {
            let world = Sim.world(windows: [Sim.window(7, 200, 300, 1200, 300)])
            let roster = Self.roster(seed: 85)
            roster.skills.isEnabled = false
            let pet = restingPet(in: roster, world: world, x: 800, idle: 0.5)
            var clung = false
            run(roster, in: world, seconds: 120, until: {
                if pet.behavior is CeilingWalkBehavior { clung = true }
                return clung
            })
            check.expect(!clung, "Skill Jumps를 끄면 붙으러 가지 않음")
        }
        // 포인터 모드: 포인터가 창 바로 밑이면 그 아랫변으로 가서 포인터 쪽으로 감
        do {
            let world = Sim.world(windows: [Sim.window(7, 300, 300, 600, 300)])
            let roster = Self.roster(seed: 86, pointer: true)
            let pet = restingPet(in: roster, world: world, x: 400, idle: 0.5)
            let pointer = CGPoint(x: 760, y: 220)
            let chase = PointerChase()
            var target = ChaseTarget.none
            for _ in 0..<Int(PointerChase.settleTime * 60) + 3 { target = chase.target(in: world, cursor: pointer, dt: Sim.dt) }
            check.expect(target.clingWindowID == 7 && target.windowID == nil, "포인터가 창 바로 밑이면 그 아랫변이 목표", "\(target)")

            run(roster, in: world, cursor: pointer, seconds: 20, until: {
                pet.behavior is CeilingWalkBehavior && abs(pet.position.x - pointer.x) < 14
            })
            check.expect(pet.behavior is CeilingWalkBehavior && abs(pet.position.x - pointer.x) < 14,
                         "아랫변에 붙어 포인터 바로 위로 감", "\(pet.behavior.name) \(pet.position)")
            var stayed = true
            run(roster, in: world, cursor: pointer, seconds: CeilingWalkBehavior.stay) {
                if !(pet.behavior is CeilingWalkBehavior) { stayed = false }
                return false
            }
            check.expect(stayed, "포인터가 밑에 있으면 더 오래 붙어 있음")
        }
    }
}
