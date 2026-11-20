import Foundation

/// This object is responsible for checking the two ways pets play with the user's screen and each other:
/// flinging off a window the user shakes, and stacking into towers on each other's heads.
enum PlayChecks {
    static func run(_ check: Checker) {
        shakeDetection(check)
        shakingOff(check)
        towers(check)
        towerCollapse(check)
    }

    private static func roster(seed: UInt64) -> PetRoster {
        PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: seed)))
    }

    private static func pet(in roster: PetRoster, world: World, x: CGFloat, y: CGFloat = 80) -> Pet {
        let pet = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        pet.position = CGPoint(x: x, y: y)
        pet.settle(in: world)
        pet.switchTo(IdleBehavior(duration: 999))
        return pet
    }

    private static func run(_ roster: PetRoster, in world: World, seconds: Double, until stop: (() -> Bool)? = nil) {
        for _ in 0..<Int(seconds * 60) {
            roster.step(dt: Sim.dt, in: world, cursor: nil)
            if let stop, stop() { return }
        }
    }

    /// 창 7을 steps 순서대로 한 틱에 하나씩 옮기며 흔들림 감지 (창 위에 펫이 있다고 보고 살핌)
    private static func shakes(_ steps: [CGFloat], vertical: Bool = false) -> [WindowShake] {
        let detector = WindowShakeDetector()
        var origin = CGPoint(x: 300, y: 300)
        let world = Sim.world(windows: [Sim.window(7, origin.x, origin.y, 600, 300)])
        var found: [WindowShake] = []
        found += detector.step(dt: Sim.dt, world: world, watching: [7])
        for step in steps {
            if vertical { origin.y += step } else { origin.x += step }
            world.update(windows: [Sim.window(7, origin.x, origin.y, 600, 300)])
            found += detector.step(dt: Sim.dt, world: world, watching: [7])
        }
        return found
    }

    /// 좌우로 swing만큼씩 times번 휘두르는 이동 (한 틱 step)
    private static func swings(_ times: Int, swing: CGFloat = 60, step: CGFloat = 12) -> [CGFloat] {
        (0..<times).flatMap { index in Array(repeating: index % 2 == 0 ? step : -step, count: Int(swing / step)) }
    }

    private static func shakeDetection(_ check: Checker) {
        check.section("창 흔들기: 알아채기")
        let shaken = shakes(swings(3))
        check.expect(shaken.count == 1 && shaken.first?.windowID == 7, "좌·우·좌로 흔들면 흔들기", "\(shaken)")
        check.expect((shaken.first?.push.dx ?? 0) > 500, "마지막 움직임 속도를 넘김", "\(shaken)")
        check.expect(shakes(swings(3), vertical: true).count == 1, "위아래로 흔들어도 흔들기")
        check.expect(shakes(swings(2)).isEmpty, "한 번 갔다 오는 것은 아님")
        check.expect(shakes(Array(repeating: 5, count: 120)).isEmpty, "한 방향으로 끄는 것은 아님")
        check.expect(shakes(swings(6, swing: 24, step: 12)).isEmpty, "조금씩 떨리는 것은 아님")
        check.expect(shakes([400, -400, 400, -400]).isEmpty, "순간이동은 아님")
        // 느리게: 한 번 휘두르는 데 1초 → 1.5초 안에 세 번이 안 됨
        check.expect(shakes(swings(3, swing: 60, step: 1)).isEmpty, "천천히 옮겨 맞추는 것은 아님")
    }

    private static func shake(_ roster: PetRoster, world: World, window: (CGFloat) -> WindowSnapshot, start: CGFloat, until stop: () -> Bool) {
        var x = start
        for step in swings(4) {
            x += step
            world.update(windows: [window(x)])
            roster.step(dt: Sim.dt, in: world, cursor: nil)
            if stop() { return }
        }
    }

    private static func shakingOff(_ check: Checker) {
        check.section("창 흔들기: 튕겨 나가기")
        let windowAt = { (x: CGFloat) in Sim.window(7, x, 300, 600, 300) }
        let world = Sim.world(windows: [windowAt(300)])
        let roster = Self.roster(seed: 91)
        let riders = [pet(in: roster, world: world, x: 450, y: 600), pet(in: roster, world: world, x: 650, y: 600)]
        let bystander = pet(in: roster, world: world, x: 1300)
        check.expect(riders.allSatisfy { $0.perchWindowID == 7 }, "두 펫이 창 위에 있음")

        // 천천히 옮기면 탄 채 따라감
        for index in 1...60 {
            world.update(windows: [windowAt(300 + CGFloat(index))])
            roster.step(dt: Sim.dt, in: world, cursor: nil)
        }
        check.expect(riders.allSatisfy { $0.perchWindowID == 7 && $0.behavior is IdleBehavior }, "천천히 옮기면 탄 채 따라감")

        shake(roster, world: world, window: windowAt, start: 360) { riders.allSatisfy { $0.behavior is AirborneBehavior } }
        check.expect(riders.allSatisfy { $0.behavior.name == "flung" && $0.speech?.text == Chatter.dizzy },
                     "흔들면 💫 하고 튕겨 나감", riders.map(\.behavior.name).joined(separator: ","))
        check.expect(riders[0].velocity.dx != riders[1].velocity.dx, "펫마다 다르게 흩어짐")
        check.expect(bystander.behavior.name == "idle", "다른 곳 펫은 그대로", bystander.behavior.name)

        var dizzy = false
        run(roster, in: world, seconds: 4, until: {
            if riders.contains(where: { $0.behavior.name == "dizzy" }) { dizzy = true }
            return riders.allSatisfy { $0.support != nil && $0.behavior.name != "flung" }
        })
        check.expect(dizzy, "내려와서 잠시 어지러워함")
        check.expect(riders.allSatisfy { !$0.isLost(in: world) && $0.support != nil }, "모두 화면 안에 내려섬")

        // 창 아랫변에 붙은 펫도 튕겨 나감
        let clingWorld = Sim.world(windows: [windowAt(300)])
        let clingRoster = Self.roster(seed: 92)
        let clinger = pet(in: clingRoster, world: clingWorld, x: 600)
        clinger.switchTo(SkillLeapBehavior(plan: LeapPlanner.clingPlan(for: clinger, to: 7, in: clingWorld)!, style: .bigJump, hasActionFrames: false))
        run(clingRoster, in: clingWorld, seconds: 4, until: { clinger.behavior is CeilingWalkBehavior })
        shake(clingRoster, world: clingWorld, window: windowAt, start: 300) { clinger.behavior is AirborneBehavior }
        check.expect(clinger.behavior.name == "flung" && clinger.pose == .upright, "아랫변에 붙은 펫도 튕겨 나감", clinger.behavior.name)
    }

    private static func towers(_ check: Checker) {
        check.section("펫 탑: 쌓기")
        let world = Sim.world()
        let roster = Self.roster(seed: 93)
        let base = pet(in: roster, world: world, x: 700)
        let climber = pet(in: roster, world: world, x: 760)
        check.expect(roster.towers.start(base: base, climber: climber, in: world), "머리 공간이 있으면 올라타기 시작")
        check.expect(base.behavior is TowerBaseBehavior && climber.behavior is StackLeapBehavior, "아래 펫은 버티고 위 펫은 뜀")
        run(roster, in: world, seconds: 2, until: { climber.behavior is StackedBehavior })
        let head = base.position.y + base.bodyHeight - base.scale
        check.expect(climber.behavior is StackedBehavior && climber.position.y == head && abs(climber.position.x - base.position.x) < 3,
                     "아래 펫 머리 위에 섬", "\(climber.behavior.name) \(climber.position)")

        // 근처 한가한 펫이 맨 위로 올라옴
        let third = pet(in: roster, world: world, x: 880)
        var cheered = false
        run(roster, in: world, seconds: 6, until: {
            if third.speech?.text == Chatter.cheer { cheered = true }
            return third.behavior is StackedBehavior
        })
        let tower = PetTowerCoordinator.tower(on: base, among: roster.pets)
        check.expect(tower.count == 3 && tower.last === third, "근처 펫이 맨 위로 올라와 3층", "\(tower.map(\.id))")
        check.expect(cheered && third.position.y == climber.position.y + climber.bodyHeight - climber.scale, "3층은 🎉 하고 2층 머리 위에 섬")
        check.expect(roster.pet(at: CGPoint(x: third.position.x, y: third.position.y + 20)) === third, "맨 위 펫이 클릭됨")

        // 꽉 차면 더 오르지 않음
        let fourth = pet(in: roster, world: world, x: 600)
        let fifth = pet(in: roster, world: world, x: 860)
        run(roster, in: world, seconds: 6)
        let full = PetTowerCoordinator.tower(on: base, among: roster.pets)
        check.expect(full.count == PetTowerCoordinator.maxHeight && !(fifth.behavior is StackedBehavior && fourth.behavior is StackedBehavior),
                     "최대 \(PetTowerCoordinator.maxHeight)층까지", "\(full.map(\.id))")
        check.expect(roster.pets.allSatisfy { !$0.isLost(in: world) }, "탑이 화면 안에 있음")

        // 머리 위 창 아랫변이 낮으면 시작하지 않음
        let low = Sim.world(windows: [Sim.window(7, 500, 200, 600, 300)])
        let lowRoster = Self.roster(seed: 94)
        let a = pet(in: lowRoster, world: low, x: 700)
        let b = pet(in: lowRoster, world: low, x: 760)
        check.expect(!lowRoster.towers.start(base: a, climber: b, in: low) && a.behavior.name == "idle", "머리 위 공간이 모자라면 올라타지 않음")

        // 마주치면 가끔 올라탐
        let meetWorld = Sim.world()
        let meet = Self.roster(seed: 13)
        let p = pet(in: meet, world: meetWorld, x: 700)
        let q = pet(in: meet, world: meetWorld, x: 740)
        meet.step(dt: Sim.dt, in: meetWorld, cursor: nil)
        check.expect([p, q].contains { $0.behavior is TowerBaseBehavior } && [p, q].contains { $0.behavior is StackLeapBehavior },
                     "마주치면 가끔 한 마리가 올라탐", "\(p.behavior.name) \(q.behavior.name)")
    }

    /// 3층 탑을 바로 쌓음
    private static func tallTower(in roster: PetRoster, world: World, baseX: CGFloat = 700, y: CGFloat = 80) -> [Pet] {
        let pets = [pet(in: roster, world: world, x: baseX, y: y), pet(in: roster, world: world, x: baseX + 60, y: y),
                    pet(in: roster, world: world, x: baseX - 60, y: y)]
        roster.towers.start(base: pets[0], climber: pets[1], in: world)
        run(roster, in: world, seconds: 2, until: { pets[1].behavior is StackedBehavior })
        pets[2].switchTo(StackLeapBehavior(onto: pets[1], plan: StackLeapBehavior.plan(for: pets[2], onto: pets[1], in: world)!))
        run(roster, in: world, seconds: 2, until: { pets[2].behavior is StackedBehavior })
        return pets
    }

    private static func towerCollapse(_ check: Checker) {
        check.section("펫 탑: 무너지기")
        do {
            let world = Sim.world()
            let roster = Self.roster(seed: 95)
            let pets = tallTower(in: roster, world: world)
            check.expect(PetTowerCoordinator.tower(on: pets[0], among: roster.pets).count == 3, "3층 탑")
            pets[0].poke()
            run(roster, in: world, seconds: Sim.dt * 2)
            check.expect(pets[1...].allSatisfy { $0.behavior.name == "tumbling" }, "아래 펫을 클릭하면 위 펫들이 떨어짐",
                         pets.map(\.behavior.name).joined(separator: ","))
            check.expect(pets[2].speech?.text == Chatter.dizzy && pets[1].velocity.dx * pets[2].velocity.dx < 0,
                         "높은 층은 💫, 층마다 반대쪽으로 흩어짐")
            run(roster, in: world, seconds: 4, until: { pets.allSatisfy { $0.support != nil && Sim.isGrounded($0) } })
            check.expect(pets.allSatisfy { $0.support != nil && !$0.isLost(in: world) }, "모두 바닥에 내려섬")
        }
        do {
            let world = Sim.world()
            let roster = Self.roster(seed: 96)
            let pets = tallTower(in: roster, world: world)
            pets[2].poke()
            run(roster, in: world, seconds: Sim.dt * 2)
            check.expect(pets[2].behavior is AirborneBehavior && pets[1].behavior is StackedBehavior && pets[0].behavior is TowerBaseBehavior,
                         "맨 위 펫을 클릭하면 그 펫만 뛰어내림")
            pets[1].beginDrag(grabbedAt: CGPoint(x: pets[1].position.x, y: pets[1].position.y + 20))
            run(roster, in: world, seconds: Sim.dt * 2)
            check.expect(pets[0].behavior is TowerBaseBehavior && pets[1].isDragged, "가운데 펫을 집어 들 수 있음")
        }
        do {
            let world = Sim.world()
            let roster = Self.roster(seed: 97)
            let pets = tallTower(in: roster, world: world)
            var apart = false
            run(roster, in: world, seconds: TowerBaseBehavior.longestHold + 3, until: {
                if !(pets[0].behavior is TowerBaseBehavior) && pets[1...].allSatisfy({ !($0.behavior is StackedBehavior) }) { apart = true }
                return apart
            })
            check.expect(apart, "버티는 시간이 지나면 탑이 풀림")
        }
        do {
            let windowAt = { (x: CGFloat) in Sim.window(7, x, 300, 600, 300) }
            let world = Sim.world(windows: [windowAt(300)])
            let roster = Self.roster(seed: 98)
            let pets = tallTower(in: roster, world: world, baseX: 600, y: 600)
            check.expect(PetTowerCoordinator.tower(on: pets[0], among: roster.pets).count == 3, "창 위 3층 탑")
            shake(roster, world: world, window: windowAt, start: 300) { pets[0].behavior is AirborneBehavior }
            run(roster, in: world, seconds: Sim.dt * 2)
            check.expect(pets[0].behavior.name == "flung" && pets[1...].allSatisfy { $0.behavior is AirborneBehavior },
                         "창을 흔들면 탑째 무너짐", pets.map(\.behavior.name).joined(separator: ","))
        }
    }
}
