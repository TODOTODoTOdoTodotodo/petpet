import Foundation

/// This object is responsible for checking skill leaps onto the window the user is looking at:
/// standing on a roomy top, peeking upside down from behind a maximized one, when the skill fires, and which pet uses it.
enum SkillChecks {
    static func run(_ check: Checker) {
        standing(check)
        peeking(check)
        triggering(check)
        limits(check)
    }

    private static func roster(seed: UInt64) -> PetRoster {
        PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: seed)))
    }

    /// 바닥에 서서 쉬고 있는 기본 펫
    private static func restingPet(in roster: PetRoster, world: World, x: CGFloat) -> Pet {
        let pet = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        pet.position = CGPoint(x: x, y: 80)
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

    private static func standing(_ check: Checker) {
        check.section("스킬 도약: 올라서기")
        let world = Sim.world(windows: [Sim.window(7, 300, 300, 600, 300)])   // top 600, 머리 공간 있음
        let roster = Self.roster(seed: 21)
        let pet = restingPet(in: roster, world: world, x: 200)
        guard let plan = LeapPlanner.plan(for: pet, to: 7, in: world), case .stand(_, let targetX, let targetY) = plan.target else {
            check.expect(false, "머리 공간 있는 창은 올라서기 계획")
            return
        }
        check.expect(targetY == 600 && (300...900).contains(targetX), "머리 공간 있는 창은 올라서기 계획", "\(plan)")

        world.focus(processID: 7)
        roster.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(pet.behavior is SkillLeapBehavior, "보고 있는 창이 바뀌면 스킬 도약", pet.behavior.name)
        run(roster, in: world, seconds: 5, until: { pet.support?.owner == .window(id: 7) })
        check.expect(pet.support?.owner == .window(id: 7) && pet.position.y == 600 && abs(pet.position.x - targetX) < 6,
                     "계획한 지점에 정확히 착지", "\(pet.position) target x=\(targetX)")
    }

    private static func peeking(_ check: Checker) {
        check.section("스킬 도약: 최대화 창에 거꾸로 빼꼼")
        let maximized = Sim.window(8, 0, 80, 1600, 815)   // top 895 = 메뉴바 바로 아래
        let world = Sim.world(windows: [maximized])
        let roster = Self.roster(seed: 22)
        let pet = restingPet(in: roster, world: world, x: 800)
        let plan = LeapPlanner.plan(for: pet, to: 8, in: world)
        var isPeek = false
        if case .peek = plan?.target { isPeek = true }
        check.expect(isPeek, "머리 공간이 없으면 빼꼼 계획", "\(String(describing: plan))")

        world.focus(processID: 8)
        run(roster, in: world, seconds: 4, until: { pet.behavior is PeekBehavior })
        let reachY = 895 - pet.bodyHeight - LeapPlanner.gripGap
        check.expect(pet.behavior is PeekBehavior && abs(pet.position.y - reachY) < 0.01,
                     "최고점에서 머리가 윗변에 닿음 (메뉴바 아래)", "\(pet.behavior.name) \(pet.position)")

        // 윗변 위(메뉴바)로는 한 번도 그려지지 않음
        var showedAboveEdge = false
        var hid = false
        var lost = false
        run(roster, in: world, seconds: 2, until: {
            if let visible = pet.visibleBodyRect, visible.maxY > 895.01 { showedAboveEdge = true }
            if pet.visibleBodyRect == nil { hid = true }
            if pet.isLost(in: world) { lost = true }
            return hid && pet.pose.upsideDown && (pet.visibleBodyRect?.height ?? 0) >= pet.bodyHeight * PeekBehavior.peekShare - 1.5
        })
        check.expect(hid, "윗변 뒤로 올라가 완전히 숨음")
        check.expect(pet.pose.upsideDown && pet.pose.hiddenAbove == 895, "거꾸로 뒤집혀 윗변 아래만 보임", "\(pet.pose)")
        let head = pet.visibleBodyRect ?? .null
        check.expect(abs(head.maxY - 895) < 0.01 && abs(head.height - pet.bodyHeight * PeekBehavior.peekShare) < 1.5,
                     "머리 정도(몸의 절반)만 내밂", "\(head)")
        check.expect(!showedAboveEdge, "메뉴바 쪽으로는 몸이 보이지 않음")
        check.expect(!lost && pet.position.y > 900, "발이 화면 위로 나가도 길 잃은 펫으로 보지 않음", "\(pet.position)")
        check.expect(roster.pet(at: CGPoint(x: 800, y: 895 - 5)) === pet && roster.pet(at: CGPoint(x: 800, y: 898)) == nil,
                     "보이는 머리만 클릭됨")

        world.update(windows: [Sim.window(8, 20, 80, 1600, 815)])
        let before = pet.position.x
        run(roster, in: world, seconds: Sim.dt)
        check.expect(abs(pet.position.x - before - 20) < 0.01 && pet.behavior is PeekBehavior, "창이 움직이면 빼꼼한 채 따라감")

        var landedUpright = false
        run(roster, in: world, seconds: PeekBehavior.longestStay + 3, until: {
            if let visible = pet.visibleBodyRect, visible.maxY > 895.01, pet.behavior is PeekBehavior { showedAboveEdge = true }
            landedUpright = pet.position.y == 80 && pet.pose == .upright
            return landedUpright
        })
        check.expect(landedUpright, "잠시 뒤 몸이 빠져나와 바로 서며 바닥으로 떨어짐", "\(pet.position)")
        check.expect(!showedAboveEdge, "숨었다 다시 빼꼼해도 메뉴바 쪽으로는 보이지 않음")

        // 클릭하면 놀라며 빠져나와 떨어짐
        let second = Self.roster(seed: 23)
        let world2 = Sim.world(windows: [maximized])
        let clicker = restingPet(in: second, world: world2, x: 600)
        world2.focus(processID: 8)
        run(second, in: world2, seconds: 5, until: { (clicker.visibleBodyRect?.height ?? 0) > 10 && clicker.pose.upsideDown })
        clicker.poke()
        check.expect(clicker.speech?.text == Chatter.surprised, "빼꼼한 펫을 클릭하면 놀람")
        run(second, in: world2, seconds: PeekBehavior.dropTime + 0.1)
        check.expect(clicker.behavior is AirborneBehavior && clicker.pose == .upright
                     && clicker.position.y + clicker.bodyHeight <= 895 + 0.01,
                     "바로 서서 윗변 아래에서 떨어짐", "\(clicker.behavior.name) \(clicker.position)")
    }

    private static func triggering(_ check: Checker) {
        check.section("스킬 발동 조건")
        let windows = [Sim.window(7, 300, 300, 600, 300), Sim.window(9, 1000, 300, 400, 250)]
        let world = Sim.world(windows: windows)
        let roster = Self.roster(seed: 24)
        let pet = restingPet(in: roster, world: world, x: 200)

        world.focus(processID: 7)
        run(roster, in: world, seconds: 5, until: { pet.support?.owner == .window(id: 7) })
        pet.switchTo(IdleBehavior(duration: 999))
        run(roster, in: world, seconds: 1)
        check.expect(pet.behavior is IdleBehavior, "같은 창을 계속 보면 다시 쓰지 않음", pet.behavior.name)

        world.focus(processID: 9)
        roster.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(!(pet.behavior is SkillLeapBehavior), "30초 안에는 다른 창으로 바꿔도 대기", pet.behavior.name)

        run(roster, in: world, seconds: SkillCoordinator.cooldown)
        pet.position = CGPoint(x: 900, y: 80)
        pet.settle(in: world)
        pet.switchTo(IdleBehavior(duration: 999))
        world.focus(processID: 7)
        roster.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(pet.behavior is SkillLeapBehavior, "대기 시간이 지나면 다시 씀", pet.behavior.name)

        let off = Self.roster(seed: 25)
        off.skills.isEnabled = false
        let lazy = restingPet(in: off, world: world, x: 200)
        world.focus(processID: 9)
        off.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(!(lazy.behavior is SkillLeapBehavior), "메뉴에서 끄면 쓰지 않음")

        let busy = Self.roster(seed: 26)
        let reader = restingPet(in: busy, world: world, x: 200)
        reader.announce(ScheduleNotice(topic: "x", text: "지금 · 회의"))
        reader.switchTo(IdleBehavior(duration: 999))
        world.focus(processID: 7)
        busy.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(!(reader.behavior is SkillLeapBehavior), "일정 알림을 든 펫은 쓰지 않음")
    }

    private static func limits(_ check: Checker) {
        check.section("스킬 도약 한계")
        let right = ScreenArea(id: 3, name: "Right", frame: CGRect(x: 1600, y: 0, width: 1920, height: 1080),
                               visibleFrame: CGRect(x: 1600, y: 0, width: 1920, height: 1055), backingScale: 1)
        let far = Sim.world(screens: [Sim.main, right], windows: [Sim.window(10, 3000, 100, 400, 200)])
        let roster = Self.roster(seed: 27)
        let pet = restingPet(in: roster, world: far, x: 100)
        check.expect(LeapPlanner.plan(for: pet, to: 10, in: far) == nil, "너무 먼 창은 도약하지 않음")

        // 위 모니터가 있어도 아래 모니터의 메뉴바는 천장
        let upper = ScreenArea(id: 2, name: "Upper", frame: CGRect(x: 0, y: 1000, width: 1600, height: 900),
                               visibleFrame: CGRect(x: 0, y: 1000, width: 1600, height: 875), backingScale: 2)
        let stacked = Sim.world(screens: [Sim.main, upper], windows: [Sim.window(11, 0, 80, 1600, 815)])
        let stackedRoster = Self.roster(seed: 28)
        let climber = restingPet(in: stackedRoster, world: stacked, x: 800)
        check.expect(stacked.ceiling(atX: 800, above: 80) == 895, "위 모니터가 있어도 메뉴바(895)가 천장", "\(String(describing: stacked.ceiling(atX: 800, above: 80)))")
        var peeks = false
        if case .peek = LeapPlanner.plan(for: climber, to: 11, in: stacked)?.target { peeks = true }
        check.expect(peeks, "위 모니터가 있어도 최대화 창엔 올라서지 않고 빼꼼")

        let alreadyThere = Self.roster(seed: 29)
        let world = Sim.world(windows: [Sim.window(7, 300, 300, 600, 300)])
        let sitter = alreadyThere.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        sitter.position = CGPoint(x: 500, y: 600)
        sitter.settle(in: world)
        sitter.switchTo(IdleBehavior(duration: 999))
        let other = restingPet(in: alreadyThere, world: world, x: 200)
        world.focus(processID: 7)
        alreadyThere.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(!(other.behavior is SkillLeapBehavior), "이미 그 창 위에 펫이 있으면 생략")
    }
}
