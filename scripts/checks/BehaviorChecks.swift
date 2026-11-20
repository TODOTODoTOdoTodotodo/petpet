import Foundation

/// This object is responsible for running scripted pet scenarios: landing, occlusion, riding windows,
/// climbing, multi-display travel, respawn, drag and the action rules.
enum BehaviorChecks {
    static func run(_ check: Checker) {
        landing(check)
        riding(check)
        climbing(check)
        actions(check)
        multiDisplay(check)
        dragAndRespawn(check)
        // 오르기처럼 드문 행동은 한 번의 무작위 진행에 안 나올 수 있어 세 시드를 합쳐 확인
        let visited = [7, 77, 777].reduce(into: Set<String>()) { $0.formUnion(soak(check, seed: $1)) }
        check.expect(["walking", "climbing", "jumping", "falling", "acting", "lookingAtUser", "skill:big_jump", "glancing", "peeking"]
                        .allSatisfy(visited.contains), "세 시드 합쳐 주요 행동이 모두 나타남", "\(visited.sorted())")
    }

    /// 창이 계속 바뀌는 화면에서 오래 돌려 불변식 확인 (화면 이탈, 행동 고착, 허공 대기)
    /// 거친 행동 이름들을 돌려줌
    @discardableResult
    private static func soak(_ check: Checker, seed: UInt64) -> Set<String> {
        check.section("장시간 무작위 진행 (시뮬레이션 10분 × 펫 3, 시드 \(seed))")
        let random = SeededRandomSource(seed: seed)
        let right = ScreenArea(id: 3, name: "Right", frame: CGRect(x: 1600, y: 0, width: 1920, height: 1080),
                               visibleFrame: CGRect(x: 1600, y: 0, width: 1920, height: 1055), backingScale: 1)
        let screens = [Sim.main, right]
        let world = Sim.world(screens: screens)
        let roster = PetRoster(planner: BehaviorPlanner(random: random))
        let pets = (0..<3).map { _ in roster.add(appearance: FakeAppearance(hasAction: true), scale: 1.5, in: world) }

        var escapes = 0, floating = 0, longest: (name: String, seconds: Double) = ("", 0)
        var current: [String: (name: String, since: Double)] = [:]
        var visited = Set<String>()
        var time = 0.0
        while time < 600 {
            if Int(time * 60) % 300 == 0 {
                // 5초마다 창 배치를 바꿈 (이동·닫힘·겹침 순서 변화)
                let count = Int(random.uniform(0, 6))
                let windows = (0..<count).map { index in
                    Sim.window(UInt32(10 + index), CGFloat(random.uniform(0, 3000)), CGFloat(random.uniform(80, 500)),
                               CGFloat(random.uniform(200, 900)), CGFloat(random.uniform(150, 600)))
                }
                world.update(windows: windows)
            }
            if Int(time * 60) % 900 == 0 {
                // 15초마다 보고 있는 창을 바꿔 스킬 도약·따라가기·돌아보기를 섞음
                let windows = world.windows
                world.focus(processID: windows.isEmpty ? nil : windows[Int(random.uniform(0, Double(windows.count)))].processID)
            }
            roster.step(dt: Sim.dt, in: world, cursor: CGPoint(x: random.uniform(0, 3500), y: random.uniform(0, 1000)))
            time += Sim.dt

            for pet in pets {
                visited.insert(pet.behavior.name)
                // 윗변 뒤에 숨은 펫은 발이 화면 위로 나가도 붙잡은 창이 있음
                if pet.isLost(in: world) {
                    escapes += 1
                    print("    escape: \(pet.id) \(pet.behavior.name) at \(pet.position) v=\(pet.velocity) t=\(String(format: "%.2f", time))")
                }
                let standing = pet.behavior is IdleBehavior || pet.behavior is WalkBehavior || pet.behavior is ActBehavior
                if standing && world.ledge(atX: pet.position.x, nearY: pet.position.y, tolerance: 0.5,
                                           margin: pet.bodyHalfWidth) == nil { floating += 1 }
                if current[pet.id]?.name != pet.behavior.name || pet.animationElapsed < Sim.dt * 1.5 {
                    current[pet.id] = (pet.behavior.name, time)
                }
                if let entry = current[pet.id], time - entry.since > longest.seconds { longest = (entry.name, time - entry.since) }
            }
        }
        check.expect(escapes == 0, "펫이 화면 밖에 머문 틱 없음", "\(escapes)")
        check.expect(floating == 0, "서 있는 행동인데 발밑에 발판 없는 틱 없음", "\(floating)")
        check.expect(longest.seconds < 20, "한 행동에 20초 이상 고착 없음", "\(longest)")
        return visited
    }

    private static func landing(_ check: Checker) {
        check.section("착지와 가림")
        let world = Sim.world(windows: [Sim.window(2, 500, 500, 600, 400), Sim.window(1, 200, 300, 600, 400)])
        let planner = BehaviorPlanner(random: SeededRandomSource(seed: 1))

        let onTop = Sim.pet(at: CGPoint(x: 300, y: 850), behavior: AirborneBehavior.falling())
        Sim.run(onTop, in: world, planner: planner, seconds: 3, until: Sim.isGrounded)
        check.expect(onTop.position.y == 700 && onTop.support?.owner == .window(id: 1),
                     "보이는 창 윗변에 착지", "y=\(onTop.position.y) \(String(describing: onTop.support?.owner))")

        let hidden = Sim.pet(at: CGPoint(x: 650, y: 850), behavior: AirborneBehavior.falling())
        Sim.run(hidden, in: world, planner: planner, seconds: 3, until: Sim.isGrounded)
        check.expect(hidden.position.y == 80 && hidden.support?.owner == .ground(screenID: 1),
                     "앞 창에 가려진 윗변은 지나쳐 바닥에 착지", "y=\(hidden.position.y)")
    }

    private static func riding(_ check: Checker) {
        check.section("창 따라 이동")
        let planner = BehaviorPlanner(random: SeededRandomSource(seed: 2))
        let world = Sim.world(windows: [Sim.window(1, 200, 300, 600, 400)])
        let pet = Sim.pet(at: CGPoint(x: 300, y: 700), behavior: IdleBehavior(duration: 999))
        pet.facing = .west
        pet.settle(in: world)
        Sim.run(pet, in: world, planner: planner, seconds: 0.1)

        world.update(windows: [Sim.window(1, 300, 350, 600, 400)])
        Sim.run(pet, in: world, planner: planner, seconds: Sim.dt)
        check.expect(pet.position.x == 400 && pet.position.y == 750, "창을 옮기면 같이 움직임", "\(pet.position)")
        check.expect(pet.facing == .west, "대기 중 방향 유지")

        world.update(windows: [])
        let names = Sim.run(pet, in: world, planner: planner, seconds: 3, until: { $0.position.y == 80 && Sim.isGrounded($0) })
        check.expect(names.contains("falling") && pet.position.y == 80, "창이 닫히면 바닥으로 떨어짐", "\(names) y=\(pet.position.y)")

        // 최대화·모니터 이동처럼 창이 한 번에 멀리 가면 타지 않음
        let jumpy = Sim.world(windows: [Sim.window(1, 200, 300, 600, 400)])
        let rider = Sim.pet(at: CGPoint(x: 300, y: 700), behavior: IdleBehavior(duration: 999))
        rider.settle(in: jumpy)
        Sim.run(rider, in: jumpy, planner: planner, seconds: 0.1)
        jumpy.update(windows: [Sim.window(1, 1100, 350, 400, 400)])
        Sim.run(rider, in: jumpy, planner: planner, seconds: Sim.dt)
        check.expect(rider.position.x == 300 && rider.behavior is AirborneBehavior,
                     "창이 순간이동하면 따라가지 않고 그 자리에서 떨어짐", "\(rider.behavior.name) \(rider.position)")
    }

    private static func climbing(_ check: Checker) {
        check.section("등반")
        let eager = BehaviorPlanner(random: FixedRandom(0))
        let world = Sim.world(windows: [Sim.window(3, 300, 80, 400, 500)])  // top 580
        let pet = Sim.pet(at: CGPoint(x: 200, y: 80), behavior: WalkBehavior(direction: .east, duration: 999))
        pet.settle(in: world)

        let names = Sim.run(pet, in: world, planner: eager, seconds: 20,
                            until: { $0.support?.owner == .window(id: 3) })
        check.expect(names.contains("climbing"), "벽에 닿으면 오름", "\(names)")
        check.expect(pet.position.y == 580 && (300...700).contains(pet.position.x),
                     "꼭대기에서 지붕 안쪽으로 올라섬", "\(pet.position)")
        Sim.run(pet, in: world, planner: eager, seconds: 0.5)
        check.expect(pet.support?.owner == .window(id: 3), "올라선 직후 떨어지지 않음", "\(pet.behavior.name) \(pet.position)")

        // 꼭대기가 메뉴바 아래 끝(895)이면 머리 공간이 없어 오르지 않음
        let blocked = Sim.world(windows: [Sim.window(4, 300, 80, 400, 815)])
        let walker = Sim.pet(at: CGPoint(x: 200, y: 80), behavior: WalkBehavior(direction: .east, duration: 999))
        walker.settle(in: blocked)
        let walkNames = Sim.run(walker, in: blocked, planner: eager, seconds: 3)
        check.expect(!walkNames.contains("climbing") && walker.facing == .west, "머리 공간 없는 창은 오르지 않고 돌아섬", "\(walkNames)")

        // 오르는 중 창이 움직이면 벽을 따라감
        let moving = Sim.world(windows: [Sim.window(3, 300, 80, 400, 500)])
        let climber = Sim.pet(at: CGPoint(x: 200, y: 80), behavior: WalkBehavior(direction: .east, duration: 999))
        climber.settle(in: moving)
        Sim.run(climber, in: moving, planner: eager, seconds: 10, until: { $0.behavior is ClimbBehavior })
        Sim.run(climber, in: moving, planner: eager, seconds: 1)
        moving.update(windows: [Sim.window(3, 350, 80, 400, 500)])
        Sim.run(climber, in: moving, planner: eager, seconds: Sim.dt)
        check.expect(climber.behavior is ClimbBehavior && abs(climber.position.x - (350 - climber.bodyHalfWidth)) < 0.01,
                     "오르는 중 창이 움직이면 벽에 붙어 따라감", "\(climber.behavior.name) \(climber.position)")
    }

    private static func actions(_ check: Checker) {
        check.section("행동 선택")
        let world = Sim.world()
        let random = SeededRandomSource(seed: 3)
        let planner = BehaviorPlanner(random: random)

        let plain = Sim.pet(at: CGPoint(x: 800, y: 80), appearance: FakeAppearance(hasAction: false), behavior: IdleBehavior(duration: 999))
        plain.settle(in: world)
        let plainChoices = (0..<2000).map { _ in planner.next(after: plain, in: world, context: PetContext(cursor: nil, planner: planner)) }
        check.expect(!plainChoices.contains { $0 is ActBehavior }, "공격 애니메이션 없는 스킨은 공격을 고르지 않음")

        let fighter = Sim.pet(at: CGPoint(x: 800, y: 80), appearance: FakeAppearance(hasAction: true), behavior: IdleBehavior(duration: 999))
        fighter.settle(in: world)
        let fighterChoices = (0..<2000).map { _ in planner.next(after: fighter, in: world, context: PetContext(cursor: nil, planner: planner)) }
        check.expect(fighterChoices.contains { $0 is ActBehavior }, "공격 애니메이션 있는 스킨은 공격도 고름")

        fighter.switchTo(ActBehavior())
        Sim.run(fighter, in: world, planner: planner, seconds: 1.0)
        check.expect(!(fighter.behavior is ActBehavior), "공격은 한 바퀴 뒤 끝남", fighter.behavior.name)

        let follower = Sim.pet(at: CGPoint(x: 400, y: 80), behavior: IdleBehavior(duration: 999))
        follower.settle(in: world)
        let followChoices = (0..<500).map { _ in planner.next(after: follower, in: world, context: PetContext(cursor: CGPoint(x: 900, y: 150), planner: planner)) }
        check.expect(followChoices.contains { $0.name == "followingCursor" }, "가까운 높이의 커서는 따라감")
    }

    private static func multiDisplay(_ check: Checker) {
        check.section("다중 모니터")
        let planner = BehaviorPlanner(random: SeededRandomSource(seed: 4))

        let upper = ScreenArea(id: 2, name: "Upper", frame: CGRect(x: 0, y: 1000, width: 1600, height: 900),
                               visibleFrame: CGRect(x: 0, y: 1000, width: 1600, height: 900), backingScale: 2)
        let stacked = Sim.world(screens: [Sim.main, upper])
        let faller = Sim.pet(at: CGPoint(x: 800, y: 1500), behavior: AirborneBehavior.falling())
        Sim.run(faller, in: stacked, planner: planner, seconds: 4, until: Sim.isGrounded)
        check.expect(faller.position.y == 1000 && faller.support?.owner == .ground(screenID: 2),
                     "위 모니터에서 떨어지면 위 모니터 바닥에 섬", "y=\(faller.position.y)")

        let right = ScreenArea(id: 3, name: "Right", frame: CGRect(x: 1600, y: 0, width: 1920, height: 1080),
                               visibleFrame: CGRect(x: 1600, y: 0, width: 1920, height: 1080), backingScale: 1)
        let sideBySide = Sim.world(screens: [Sim.main, right])
        let walker = Sim.pet(at: CGPoint(x: 1500, y: 80), behavior: WalkBehavior(direction: .east, duration: 999))
        walker.settle(in: sideBySide)
        Sim.run(walker, in: sideBySide, planner: planner, seconds: 6, until: { $0.position.x > 1650 && Sim.isGrounded($0) })
        check.expect(walker.position.x > 1600 && walker.position.y == 0 && walker.support?.owner == .ground(screenID: 3),
                     "옆 모니터로 걸어 넘어감", "\(walker.position) \(walker.behavior.name)")
    }

    private static func dragAndRespawn(_ check: Checker) {
        check.section("드래그와 복귀")
        let world = Sim.world()
        let roster = PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: 5)))
        let pet = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        roster.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(world.contains(pet.position), "새 펫은 주 모니터 안에서 떨어지기 시작함", "\(pet.position)")

        pet.position = CGPoint(x: 5000, y: 500)
        roster.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(world.contains(CGPoint(x: pet.position.x, y: pet.position.y + 1)), "화면 밖으로 사라진 펫은 다시 떨어뜨림", "\(pet.position)")

        let held = Sim.pet(at: CGPoint(x: 800, y: 80), behavior: IdleBehavior(duration: 999))
        held.settle(in: world)
        let planner = BehaviorPlanner(random: SeededRandomSource(seed: 6))
        held.beginDrag(grabbedAt: CGPoint(x: 800, y: 110))
        held.drag(to: CGPoint(x: 800, y: 20))
        Sim.run(held, in: world, planner: planner, seconds: Sim.dt)
        check.expect(held.position.y == 80, "끌어도 발은 바닥 아래로 안 내려감", "\(held.position)")

        for step in 1...10 {
            held.drag(to: CGPoint(x: 800 + CGFloat(step) * 12, y: 400 + CGFloat(step) * 4))
            Sim.run(held, in: world, planner: planner, seconds: Sim.dt)
        }
        held.endDrag()
        let names = Sim.run(held, in: world, planner: planner, seconds: 4, until: { Sim.isGrounded($0) && !$0.isDragged })
        check.expect(names.contains("thrown") && held.position.y == 80 && held.position.x > 920,
                     "놓으면 손 움직임 방향으로 던져진 뒤 착지", "\(names) \(held.position)")
    }
}
