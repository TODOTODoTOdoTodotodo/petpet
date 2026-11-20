import CoreGraphics
import Foundation

/// This object is responsible for checking what the pets chase: the active window (default) or the mouse pointer,
/// with the pointer mode settling on the window right under the pointer, walking toward it, stepping down to it,
/// leaping onto it, gathering on the pointer's display, and jumping at or throwing weapons at a pointer out of reach.
enum ChaseChecks {
    static func run(_ check: Checker) {
        targets(check)
        walkingToPointer(check)
        leapingUnderPointer(check)
        steppingDown(check)
        crossingToPointerDisplay(check)
        projectileFlight(check)
        outOfReach(check)
    }

    private static func roster(seed: UInt64, pointer: Bool = true) -> PetRoster {
        let roster = PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: seed)))
        roster.chase = ChaseModes.make(pointer ? PointerChase.key : ActiveWindowChase.key)
        return roster
    }

    private static func restingPet(in roster: PetRoster, world: World, x: CGFloat, y: CGFloat = 80) -> Pet {
        let pet = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        pet.position = CGPoint(x: x, y: y)
        pet.settle(in: world)
        pet.switchTo(IdleBehavior(duration: 0.5))
        return pet
    }

    private static func run(_ roster: PetRoster, in world: World, cursor: CGPoint, seconds: Double, until stop: (() -> Bool)? = nil) {
        for _ in 0..<Int(seconds * 60) {
            roster.step(dt: Sim.dt, in: world, cursor: cursor)
            if let stop, stop() { return }
        }
    }

    private static func targets(_ check: Checker) {
        check.section("쫓을 곳: 활성 창 / 마우스 포인터")
        let window = Sim.window(7, 300, 300, 600, 300)   // 윗변 600
        let other = Sim.window(9, 1000, 300, 400, 250)   // 윗변 550
        let world = Sim.world(windows: [window, other])
        world.focus(processID: 9)

        let active = ChaseModes.make(nil)
        let byWindow = active.target(in: world, cursor: CGPoint(x: 600, y: 700), dt: Sim.dt)
        check.expect(active.key == ActiveWindowChase.key && byWindow.windowID == 9 && byWindow.point == nil
                     && byWindow.anchorX == 1200 && byWindow.screenID == 1,
                     "기본은 활성 창 (포인터와 무관)", "\(byWindow)")
        check.expect(ChaseModes.make("모르는 값").key == ActiveWindowChase.key, "모르는 설정이면 활성 창")

        let pointer = PointerChase()
        let above = CGPoint(x: 600, y: 700)
        var target = pointer.target(in: world, cursor: above, dt: Sim.dt)
        check.expect(target.windowID == nil && target.point == above && target.screenID == 1, "포인터를 막 올리면 아직 창을 고르지 않음", "\(target)")
        for _ in 0..<Int(PointerChase.settleTime * 60) + 3 { target = pointer.target(in: world, cursor: above, dt: Sim.dt) }
        check.expect(target.windowID == 7 && target.anchorX == 600, "포인터 바로 아래 윗변의 창을 고름 (활성 창과 무관)", "\(target)")

        // 다른 창 위를 잠깐 스쳐 지나가면 바꾸지 않음
        for _ in 0..<Int(PointerChase.settleTime * 30) { target = pointer.target(in: world, cursor: CGPoint(x: 1200, y: 700), dt: Sim.dt) }
        for _ in 0..<5 { target = pointer.target(in: world, cursor: above, dt: Sim.dt) }
        check.expect(target.windowID == 7, "스쳐 지나간 창으로는 바꾸지 않음", "\(target)")

        // 창 안(윗변 아래)이면 바닥이 아래 발판
        for _ in 0..<Int(PointerChase.settleTime * 60) + 3 { target = pointer.target(in: world, cursor: CGPoint(x: 1450, y: 200), dt: Sim.dt) }
        check.expect(target.windowID == nil, "포인터 아래가 바닥이면 올라갈 창 없음", "\(target)")
        target = pointer.target(in: world, cursor: nil, dt: Sim.dt)
        check.expect(target.point == CGPoint(x: 1450, y: 200), "포인터를 모르면 직전 목표 유지")
    }

    private static func walkingToPointer(_ check: Checker) {
        check.section("포인터 모드: 걸어서 따라감")
        let world = Sim.world(windows: [Sim.window(7, 300, 300, 600, 300)])
        world.focus(processID: 7)
        let roster = Self.roster(seed: 61)
        let pet = restingPet(in: roster, world: world, x: 1500)
        let cursor = CGPoint(x: 100, y: 200)
        var names: Set<String> = []
        var visitedFocus = false
        var nearTicks = 0
        var arrived = false
        run(roster, in: world, cursor: cursor, seconds: 40) {
            names.insert(pet.behavior.name)
            if pet.perchWindowID == 7 { visitedFocus = true }
            if abs(pet.position.x - cursor.x) < 60 && pet.position.y == 80 { arrived = true }
            if arrived && abs(pet.position.x - cursor.x) < 150 { nearTicks += 1 }
            return false
        }
        check.expect(names.contains("chasingPointer"), "포인터 쪽으로 걷거나 뜀", "\(names.sorted())")
        check.expect(arrived, "포인터 아래 바닥에 옴")
        check.expect(Double(nearTicks) / (40 * 60) > 0.5, "온 뒤엔 대부분 포인터 곁에 머묾", "\(nearTicks)")
        check.expect(!visitedFocus, "포인터 모드에선 활성 창으로 도약하지 않음")
    }

    private static func leapingUnderPointer(_ check: Checker) {
        check.section("포인터 모드: 포인터 아래 창으로 도약")
        let world = Sim.world(windows: [Sim.window(7, 300, 300, 600, 300), Sim.window(9, 1000, 300, 400, 250)])
        world.focus(processID: 9)
        let roster = Self.roster(seed: 62)
        // 창 바로 밑에서 시작 (천장에 막혀 바로는 못 뜀)
        let pet = restingPet(in: roster, world: world, x: 700)
        let cursor = CGPoint(x: 800, y: 700)
        run(roster, in: world, cursor: cursor, seconds: 15, until: { pet.perchWindowID == 7 && pet.behavior is IdleBehavior })
        check.expect(pet.perchWindowID == 7, "포인터 아래 창 윗변에 올라감", "\(pet.behavior.name) \(pet.position)")
        run(roster, in: world, cursor: cursor, seconds: 15, until: { abs(pet.position.x - cursor.x) < 60 })
        check.expect(abs(pet.position.x - cursor.x) < 60 && pet.perchWindowID == 7, "그 창 위에서 포인터 쪽으로 감", "\(pet.position)")
    }

    private static func steppingDown(_ check: Checker) {
        check.section("포인터 모드: 포인터가 아래면 내려옴")
        let world = Sim.world(windows: [Sim.window(7, 300, 300, 600, 300)])
        let roster = Self.roster(seed: 63)
        let pet = restingPet(in: roster, world: world, x: 600, y: 600)
        check.expect(pet.perchWindowID == 7, "창 위에서 시작")
        // 창 아래 바닥 가까이 (창 위 펫과 같은 x, 아랫변에 붙을 거리보다 멀리)
        let cursor = CGPoint(x: 600, y: 100)
        run(roster, in: world, cursor: cursor, seconds: 25, until: { pet.position.y == 80 && abs(pet.position.x - cursor.x) < 60 })
        check.expect(pet.position.y == 80 && abs(pet.position.x - cursor.x) < 60, "창 끝으로 걸어 내려와 포인터 아래로 감", "\(pet.position)")
    }

    private static func crossingToPointerDisplay(_ check: Checker) {
        check.section("포인터 모드: 포인터가 있는 모니터로 모임")
        let right = ScreenArea(id: 2, name: "Right", frame: CGRect(x: 1600, y: 0, width: 1600, height: 1000),
                               visibleFrame: CGRect(x: 1600, y: 0, width: 1600, height: 975), backingScale: 2)
        let world = Sim.world(screens: [Sim.main, right])
        world.focus(processID: nil)
        let roster = Self.roster(seed: 64)
        let pet = restingPet(in: roster, world: world, x: 400)
        let cursor = CGPoint(x: 2600, y: 400)
        run(roster, in: world, cursor: cursor, seconds: DisplayFollowCoordinator.settleDelay + 12, until: {
            world.screen(containing: CGPoint(x: pet.position.x, y: pet.position.y + 1))?.id == 2
        })
        check.expect(world.screen(containing: CGPoint(x: pet.position.x, y: pet.position.y + 1))?.id == 2,
                     "포인터가 머문 모니터로 건너가거나 걸어감", "\(pet.position) \(pet.behavior.name)")
        check.expect(roster.follow.activeScreenID == 2, "전령도 포인터 모니터에 나타남 (활성 모니터 = 포인터 모니터)")
    }

    private static func projectileFlight(_ check: Checker) {
        check.section("포인터 모드: 던진 무기의 궤적")
        check.expect(SkillStyle.poleVault.projectile == .club && SkillStyle.flameRocket.projectile == .fireball
                     && SkillStyle.slashJump.projectile == .blade && SkillStyle.bigJump.projectile == .rock,
                     "캐릭터 스킬마다 무기 (몽둥이·불꽃·칼·돌멩이)")
        for kind in [ProjectileKind.club, .fireball, .blade, .rock] {
            check.expect(kind.rows.count == 8 && kind.rows.allSatisfy { $0.count == 8 }
                         && kind.rows.joined().allSatisfy { $0 == "." || kind.palette[$0] != nil }, "\(kind.name): 8x8 도트, 팔레트 글자만")
        }

        let start = CGPoint(x: 100, y: 100)
        let target = CGPoint(x: 500, y: 400)
        let rock = Projectile(id: "r", kind: .rock, throwerID: "Pet", from: start, to: target, scale: 1.5)
        var aboveLine = false
        var arrivals = 0
        var ticks = 0
        while !rock.isFinished && ticks < 600 {
            if rock.step(dt: Sim.dt) { arrivals += 1 }
            ticks += 1
            let along = (rock.position.x - start.x) / (target.x - start.x)
            if !rock.isBursting, along > 0.2, along < 0.8, rock.position.y > start.y + (target.y - start.y) * along + 10 { aboveLine = true }
            if arrivals == 1 && rock.isBursting && rock.burstProgress == 0 { break }
        }
        check.expect(arrivals == 1 && rock.position == target, "정한 시간에 정확히 목표에 닿음", "\(rock.position)")
        check.expect(aboveLine, "돌멩이는 포물선으로 날아감")
        let flight = Double(ticks) * Sim.dt
        check.expect(Projectile.flightRange.contains(flight - Sim.dt), "비행 시간은 0.25~1.2초", "\(flight)")
        for _ in 0..<Int(Projectile.burstTime * 60) + 2 { rock.step(dt: Sim.dt) }
        check.expect(rock.isFinished, "반짝임 뒤 사라짐")

        let fire = Projectile(id: "f", kind: .fireball, throwerID: "Pet", from: start, to: target, scale: 1.5)
        var straight = true
        while !fire.isBursting {
            fire.step(dt: Sim.dt)
            let along = (fire.position.x - start.x) / (target.x - start.x)
            if !fire.isBursting, abs(fire.position.y - (start.y + (target.y - start.y) * along)) > 0.5 { straight = false }
        }
        check.expect(straight && fire.position == target, "불꽃은 곧게 날아감")
    }

    private static func outOfReach(_ check: Checker) {
        check.section("포인터 모드: 닿지 않는 포인터에 뛰어오르기·던지기")
        // 머리 위 높은 곳 (뛰어도 안 닿음) → 던짐
        do {
            let world = Sim.world()
            let roster = Self.roster(seed: 65)
            var events: [String] = []
            roster.onEvent = { events.append($0) }
            let pet = restingPet(in: roster, world: world, x: 800)
            let pointer = CGPoint(x: 820, y: 700)
            var names: Set<String> = []
            var burstAt: CGPoint?
            var wandered = false
            run(roster, in: world, cursor: pointer, seconds: 20) {
                names.insert(pet.behavior.name)
                if let hit = roster.projectiles.first(where: { $0.isBursting }) { burstAt = hit.position }
                if abs(pet.position.x - pointer.x) > 200 { wandered = true }
                return false
            }
            let throwsCount = events.filter { $0.contains("threw rock") }.count
            check.expect(names.contains("throwing") && throwsCount >= 2, "높은 포인터엔 무기를 던짐", "\(throwsCount) \(names.sorted())")
            check.expect(burstAt == pointer, "무기가 포인터 자리에 닿아 반짝임", "\(String(describing: burstAt))")
            check.expect(!wandered, "던지는 동안 포인터 밑을 떠나지 않음")
            check.expect(roster.projectiles.count <= PetRoster.maxProjectiles, "무기 수 제한")
        }
        // 뛰면 닿는 높이 → 뛰어올라 ✨
        do {
            let world = Sim.world()
            let roster = Self.roster(seed: 66)
            let pet = restingPet(in: roster, world: world, x: 800)
            let pointer = CGPoint(x: 810, y: 80 + pet.bodyHeight + 60)
            let plan = PounceBehavior.plan(for: pet, toward: pointer, in: world)
            check.expect(plan?.reaches == true, "이 높이는 뛰면 닿음", "\(String(describing: plan))")
            var caught = false
            var pounced = false
            run(roster, in: world, cursor: pointer, seconds: 20) {
                if pet.behavior is PounceBehavior { pounced = true }
                if pet.speech?.text == PounceBehavior.caughtText { caught = true }
                return caught
            }
            check.expect(pounced && caught, "포인터로 뛰어올라 닿으면 ✨")
            run(roster, in: world, cursor: pointer, seconds: 3, until: { pet.support != nil })
            check.expect(pet.position.y == 80, "뛰고 나서 바닥에 내려옴", "\(pet.position)")
            let far = PounceBehavior.plan(for: pet, toward: CGPoint(x: 800, y: 800), in: world)
            check.expect(far?.reaches == false, "아주 높으면 뛰어도 안 닿는 것으로 봄")
        }
        // 활성 창 모드에선 던지지 않음
        do {
            let world = Sim.world()
            let roster = Self.roster(seed: 65, pointer: false)
            var events: [String] = []
            roster.onEvent = { events.append($0) }
            _ = restingPet(in: roster, world: world, x: 800)
            run(roster, in: world, cursor: CGPoint(x: 820, y: 700), seconds: 20)
            check.expect(!events.contains { $0.contains("threw") }, "활성 창 모드에선 던지지 않음")
        }
        // 한꺼번에 많이 던져도 8개까지만 날림
        do {
            let world = Sim.world()
            let roster = Self.roster(seed: 67)
            let pet = restingPet(in: roster, world: world, x: 800)
            for _ in 0..<12 { pet.hurl(.rock, at: CGPoint(x: 900, y: 600)) }
            roster.step(dt: Sim.dt, in: world, cursor: CGPoint(x: 900, y: 600))
            check.expect(roster.projectiles.count == PetRoster.maxProjectiles, "동시에 나는 무기는 8개까지", "\(roster.projectiles.count)")
        }
    }
}
