import Foundation

/// This object is responsible for checking that pets standing on the same ledge never overlap:
/// a walker stops in front of the pet in its way and then jumps over it, calls it out to a duel or turns back,
/// pets heading to the same spot line up side by side, and pets that land on each other step aside.
enum SpaceChecks {
    static func run(_ check: Checker) {
        blocking(check)
        leapfrog(check)
        dueling(check)
        crowding(check)
    }

    private static func roster(seed: UInt64, pointer: Bool = false) -> PetRoster {
        let roster = PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: seed)))
        if pointer { roster.chase = ChaseModes.make(PointerChase.key) }
        return roster
    }

    /// 기본은 바라보며 서 있기 (한가하지 않아 마주쳐도 인사·대결·올라타기를 하지 않음)
    private static func pet(in roster: PetRoster, world: World, x: CGFloat, y: CGFloat = 80,
                            behavior: PetBehavior = IdleBehavior(duration: 999, lookAtUser: true)) -> Pet {
        let pet = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        pet.position = CGPoint(x: x, y: y)
        pet.settle(in: world)
        pet.switchTo(behavior)
        return pet
    }

    /// 같은 발판에서 자리를 차지한 두 펫의 몸이 겹친 가장 큰 깊이
    private static func worstOverlap(_ pets: [Pet]) -> CGFloat {
        var worst: CGFloat = 0
        for (index, a) in pets.enumerated() {
            for b in pets[(index + 1)...] {
                let first = PersonalSpace.sighting(of: a)
                let second = PersonalSpace.sighting(of: b)
                guard first.isObstacle, second.isObstacle, first.support == second.support,
                      abs(a.position.y - b.position.y) < 2 else { continue }
                worst = max(worst, a.bodyHalfWidth + b.bodyHalfWidth - abs(a.position.x - b.position.x))
            }
        }
        return worst
    }

    /// seconds 동안 진행하며 가장 크게 겹친 깊이를 돌려줌
    @discardableResult
    private static func run(_ roster: PetRoster, in world: World, cursor: CGPoint? = nil, seconds: Double, until stop: (() -> Bool)? = nil) -> CGFloat {
        var worst: CGFloat = 0
        for _ in 0..<Int(seconds * 60) {
            roster.step(dt: Sim.dt, in: world, cursor: cursor)
            worst = max(worst, worstOverlap(roster.pets))
            if let stop, stop() { break }
        }
        return worst
    }

    private static func blocking(_ check: Checker) {
        check.section("겹치지 않기: 길이 막히면")
        var outcomes = Set<String>()
        var worst: CGFloat = 0
        var stoppedInFront = true
        for seed in UInt64(1)...24 {
            let world = Sim.world()
            let roster = Self.roster(seed: seed)
            let sitter = pet(in: roster, world: world, x: 800)
            let walker = pet(in: roster, world: world, x: 600, behavior: WalkBehavior(direction: .east, duration: 20))
            worst = max(worst, run(roster, in: world, seconds: 8, until: { walker.behavior.name != "walking" || walker.facing == .west }))
            outcomes.insert(walker.facing == .west && walker.behavior.name == "walking" ? "turningBack" : walker.behavior.name == "sparring" ? "challenging" : walker.behavior.name)
            if walker.behavior.name == "challenging" || walker.behavior.name == "leapfrogging" {
                stoppedInFront = stoppedInFront && walker.position.x <= sitter.position.x - (walker.bodyHalfWidth + sitter.bodyHalfWidth) + 1
            }
        }
        check.expect(worst <= 0.01, "걸어가도 앞 펫과 겹치지 않음", "\(worst)")
        check.expect(stoppedInFront, "앞 펫 바로 앞에서 멈춤")
        check.expect(outcomes.isSuperset(of: ["leapfrogging", "challenging", "turningBack"]),
                     "뛰어넘기·결투 걸기·돌아서기 중 고름", "\(outcomes)")

        // 통화 중이면 결투 없음
        var quietOutcomes = Set<String>()
        for seed in UInt64(1)...24 {
            let world = Sim.world()
            let roster = Self.roster(seed: seed)
            roster.isQuiet = true
            _ = pet(in: roster, world: world, x: 800)
            let walker = pet(in: roster, world: world, x: 600, behavior: WalkBehavior(direction: .east, duration: 20))
            run(roster, in: world, seconds: 8, until: { walker.behavior.name != "walking" || walker.facing == .west })
            quietOutcomes.insert(walker.behavior.name)
        }
        check.expect(!quietOutcomes.contains("challenging"), "통화 중에는 결투를 걸지 않음", "\(quietOutcomes)")

        // 서두르는 중이면 뛰어넘음
        let world = Sim.world()
        let roster = Self.roster(seed: 5)
        _ = pet(in: roster, world: world, x: 800)
        let runner = pet(in: roster, world: world, x: 600, behavior: WalkBehavior(name: "sprinting", direction: .east, speed: PetPhysics.sprintSpeed, duration: 20))
        run(roster, in: world, seconds: 4, until: { runner.behavior.name != "sprinting" })
        check.expect(runner.behavior.name == "leapfrogging", "뛰어가던 펫은 뛰어넘음", runner.behavior.name)

        // 마주 오면 한쪽이 기다리고 겹치지 않음
        let headOn = Sim.world()
        let pair = Self.roster(seed: 6)
        let east = pet(in: pair, world: headOn, x: 600, behavior: WalkBehavior(name: "strolling", direction: .east, duration: 6))
        let west = pet(in: pair, world: headOn, x: 900, behavior: WalkBehavior(name: "strolling", direction: .west, duration: 6))
        var waited = false
        let headOnWorst = run(pair, in: headOn, seconds: 6, until: {
            if [east, west].contains(where: { $0.behavior.name == "waiting" }) { waited = true }
            return false
        })
        check.expect(waited && headOnWorst <= 0.01, "마주 오면 한쪽이 기다리고 겹치지 않음", "\(headOnWorst)")

        // 같은 쪽으로 가는 펫 뒤에서는 넘지 않고 기다림
        let sameWay = Sim.world()
        let convoy = Self.roster(seed: 8)
        let slow = pet(in: convoy, world: sameWay, x: 700, behavior: WalkBehavior(name: "strolling", direction: .east, speed: PetPhysics.walkSpeed * 0.4, duration: 10))
        let fast = pet(in: convoy, world: sameWay, x: 600, behavior: WalkBehavior(name: "sprinting", direction: .east, speed: PetPhysics.sprintSpeed, duration: 10))
        var waitedBehind = false
        var hopped = false
        let convoyWorst = run(convoy, in: sameWay, seconds: 3, until: {
            if fast.behavior.name == "waiting" { waitedBehind = true }
            if fast.behavior.name == "leapfrogging" { hopped = true }
            return waitedBehind || hopped
        })
        check.expect(waitedBehind && !hopped && convoyWorst <= 0.01 && fast.position.x < slow.position.x,
                     "같은 쪽으로 가는 펫 뒤에서는 넘지 않고 기다림", fast.behavior.name)

        // 목적지 근처에 서 있는 무리가 있으면 그 곁에 멈춤 (포인터 곁에 모일 때)
        let crowdWorld = Sim.world()
        let crowd = Self.roster(seed: 9)
        let standing = pet(in: crowd, world: crowdWorld, x: 800)
        let arriving = pet(in: crowd, world: crowdWorld, x: 500,
                           behavior: WalkBehavior(name: "chasingPointer", direction: .east, duration: 20, targetX: standing.position.x + 90))
        run(crowd, in: crowdWorld, seconds: 8, until: { arriving.behavior.name != "chasingPointer" })
        check.expect(arriving.behavior.name == "idle" && arriving.position.x < standing.position.x,
                     "목적지 근처 서 있는 펫 곁에 멈춤", arriving.behavior.name)

        // 목적지가 멀면 뛰어넘거나, 그 자리에 멈춰 바라보기도 함
        var farOutcomes = Set<String>()
        for seed in UInt64(30)...50 {
            let farWorld = Sim.world()
            let far = Self.roster(seed: seed)
            far.isQuiet = true
            _ = pet(in: far, world: farWorld, x: 800)
            let chaser = pet(in: far, world: farWorld, x: 600,
                             behavior: WalkBehavior(name: "chasingPointer", direction: .east, duration: 20, targetX: 1300))
            run(far, in: farWorld, seconds: 8, until: { chaser.behavior.name != "chasingPointer" })
            farOutcomes.insert(chaser.behavior.name)
        }
        check.expect(farOutcomes.isSuperset(of: ["leapfrogging", "lookingAtUser"]) && !farOutcomes.contains("walking"),
                     "쫓던 곳이 멀면 뛰어넘거나 멈춰 바라봄 (돌아서지 않음)", "\(farOutcomes)")

        // 탑은 뛰어넘지 않음
        let towerWorld = Sim.world()
        let towerRoster = Self.roster(seed: 7)
        let base = pet(in: towerRoster, world: towerWorld, x: 800)
        let top = pet(in: towerRoster, world: towerWorld, x: 860)
        towerRoster.towers.start(base: base, climber: top, in: towerWorld)
        run(towerRoster, in: towerWorld, seconds: 2, until: { top.behavior is StackedBehavior })
        let walker = pet(in: towerRoster, world: towerWorld, x: 600, behavior: WalkBehavior(direction: .east, duration: 20))
        let towerWorst = run(towerRoster, in: towerWorld, seconds: 6, until: { walker.behavior.name != "walking" || walker.facing == .west })
        check.expect(walker.behavior.name != "leapfrogging" && towerWorst <= 0.01, "탑은 뛰어넘지 않고 겹치지도 않음", walker.behavior.name)
    }

    private static func leapfrog(_ check: Checker) {
        check.section("겹치지 않기: 뛰어넘기")
        let world = Sim.world()
        let roster = Self.roster(seed: 11)
        let sitter = pet(in: roster, world: world, x: 800)
        let jumper = pet(in: roster, world: world, x: 800 - 2 * sitter.bodyHalfWidth - PersonalSpace.gap)
        jumper.facing = .east
        let planner = BehaviorPlanner(random: SeededRandomSource(seed: 11))
        let hop = planner.leapfrog(jumper, over: PersonalSpace.sighting(of: sitter), in: world)
        check.expect(hop != nil, "머리 위 공간이 있으면 뛰어넘을 수 있음")
        jumper.switchTo(hop!)
        var lowestOver = CGFloat.infinity
        let worst = run(roster, in: world, seconds: 2, until: {
            if abs(jumper.position.x - sitter.position.x) < sitter.bodyHalfWidth { lowestOver = min(lowestOver, jumper.position.y) }
            return jumper.support != nil
        })
        check.expect(lowestOver >= sitter.position.y + sitter.bodyHeight, "앞 펫 머리 위로 넘어감", "\(lowestOver)")
        check.expect(jumper.support != nil && jumper.position.x > sitter.position.x + sitter.bodyHalfWidth + jumper.bodyHalfWidth && worst <= 0.01,
                     "건너편에 겹치지 않게 내려섬", "\(jumper.position)")

        // 머리 위 창 아랫변이 낮으면 뛰어넘지 않음
        let low = Sim.world(windows: [Sim.window(7, 500, 200, 600, 300)])
        let lowRoster = Self.roster(seed: 12)
        let a = pet(in: lowRoster, world: low, x: 800)
        let b = pet(in: lowRoster, world: low, x: 760)
        b.facing = .east
        check.expect(planner.leapfrog(b, over: PersonalSpace.sighting(of: a), in: low) == nil, "머리 위 공간이 모자라면 뛰어넘지 않음")
    }

    private static func dueling(_ check: Checker) {
        check.section("겹치지 않기: 결투로 지나가기")
        var passed = false
        var yielded = false
        var worst: CGFloat = 0
        for seed in UInt64(20)...40 where !(passed && yielded) {
            let world = Sim.world()
            let roster = Self.roster(seed: seed)
            let sitter = pet(in: roster, world: world, x: 800)
            let challenger = pet(in: roster, world: world, x: 800 - 2 * sitter.bodyHalfWidth - PersonalSpace.gap)
            challenger.switchTo(ChallengeBehavior(opponent: PersonalSpace.sighting(of: sitter), fallback: nil))
            check.expect(challenger.speech?.text == ChallengeBehavior.challengeText, "길 막은 펫에게 ⚔️", challenger.speech?.text ?? "nil")
            roster.step(dt: Sim.dt, in: world, cursor: nil)
            guard challenger.behavior is SparBehavior && sitter.behavior is SparBehavior else {
                check.expect(false, "쉬던 펫이 결투를 받음", "\(challenger.behavior.name) \(sitter.behavior.name)")
                return
            }
            worst = max(worst, run(roster, in: world, seconds: 8, until: { !(challenger.behavior is SparBehavior) }))
            if challenger.behavior.name == "leapfrogging" {
                worst = max(worst, run(roster, in: world, seconds: 2, until: { challenger.support != nil }))
                if challenger.position.x > sitter.position.x { passed = true }
            } else if challenger.behavior.name == "walking" && challenger.facing == .west {
                yielded = true
            }
        }
        check.expect(passed, "결투에 이기면 뛰어넘어 지나감")
        check.expect(yielded, "지면 돌아섬")
        check.expect(worst <= 0.01, "결투 내내 겹치지 않음", "\(worst)")

        // 자는 펫은 결투를 받지 않음 → 뛰어넘음
        let world = Sim.world()
        let roster = Self.roster(seed: 41)
        let sleeper = pet(in: roster, world: world, x: 800, behavior: SleepBehavior())
        let challenger = pet(in: roster, world: world, x: 800 - 2 * sleeper.bodyHalfWidth - PersonalSpace.gap)
        challenger.facing = .east
        let planner = BehaviorPlanner(random: SeededRandomSource(seed: 41))
        let hop = planner.leapfrog(challenger, over: PersonalSpace.sighting(of: sleeper), in: world)
        challenger.switchTo(ChallengeBehavior(opponent: PersonalSpace.sighting(of: sleeper), fallback: hop))
        // 입력이 오래 없어 계속 자는 중
        for _ in 0..<60 where challenger.behavior.name == "challenging" {
            roster.step(dt: Sim.dt, in: world, cursor: nil, idleSeconds: 600)
        }
        check.expect(sleeper.behavior is SleepBehavior && challenger.behavior.name == "leapfrogging",
                     "자는 펫은 깨우지 않고 뛰어넘음", challenger.behavior.name)
    }

    private static func crowding(_ check: Checker) {
        check.section("겹치지 않기: 모이기·비켜 서기")
        // 포인터 아래로 모여도 나란히 섬
        let world = Sim.world()
        let roster = Self.roster(seed: 51, pointer: true)
        let pets = [300, 420, 1200, 1350].map { pet(in: roster, world: world, x: CGFloat($0), behavior: IdleBehavior(duration: 0.5)) }
        let cursor = CGPoint(x: 800, y: 140)
        // 뛰어올랐다 내려앉은 자리가 겹치는 순간은 있음. 곧 비켜 서는지 (1.5초 넘게 겹친 채 있지 않은지)
        var overlapping: TimeInterval = 0
        var longest: TimeInterval = 0
        for _ in 0..<(20 * 60) {
            roster.step(dt: Sim.dt, in: world, cursor: cursor)
            overlapping = worstOverlap(roster.pets) > 0.5 ? overlapping + Sim.dt : 0
            longest = max(longest, overlapping)
        }
        let spread = pets.map(\.position.x).sorted()
        let near = pets.filter { abs($0.position.x - cursor.x) < 200 }.count
        check.expect(longest <= 1.5, "포인터 아래 모여도 겹친 채 있지 않음", "\(longest)s \(spread)")
        check.expect(near >= 3, "포인터 곁에 나란히 모임", "\(spread)")

        // 같은 자리에 내려온 펫은 비켜 섬
        let landing = Sim.world()
        let landed = Self.roster(seed: 52)
        let first = pet(in: landed, world: landing, x: 800)
        let second = pet(in: landed, world: landing, x: 806)
        run(landed, in: landing, seconds: 3)
        check.expect(worstOverlap(landed.pets) <= 0.01 && first.position.x == 800,
                     "겹쳐 내려온 펫이 옆으로 비켜 섬", "\(first.position.x) \(second.position.x)")

        // 겹친 자리에서 탑 둘이 시작해도 벌어지고, 위 펫은 머리 위에 그대로
        let twin = Sim.world()
        let towers = Self.roster(seed: 54)
        let baseA = pet(in: towers, world: twin, x: 800)
        let baseB = pet(in: towers, world: twin, x: 803)
        let riderA = pet(in: towers, world: twin, x: 700)
        baseA.switchTo(TowerBaseBehavior(duration: 30))
        baseB.switchTo(TowerBaseBehavior(duration: 30))
        riderA.switchTo(StackLeapBehavior(onto: baseA, plan: StackLeapBehavior.plan(for: riderA, onto: baseA, in: twin)!))
        run(towers, in: twin, seconds: 3)
        check.expect(worstOverlap(towers.pets) <= PersonalSpaceCoordinator.overlapTolerance && riderA.behavior is StackedBehavior
                     && abs(riderA.position.x - baseA.position.x) < 3,
                     "겹쳐 시작한 두 탑도 벌어지고 위 펫은 그대로", "\(baseA.position.x) \(baseB.position.x) \(riderA.behavior.name)")

        // 옆에 설 곳이 없으면 뛰어넘어 반대편으로
        let ledge = Sim.world(windows: [Sim.window(7, 700, 300, 120, 300)])
        let narrow = Self.roster(seed: 53)
        let sitter = pet(in: narrow, world: ledge, x: 790, y: 600)
        let crowd = pet(in: narrow, world: ledge, x: 800, y: 600)
        run(narrow, in: ledge, seconds: 3)
        check.expect(worstOverlap(narrow.pets) <= 0.01 && crowd.perchWindowID == 7 && sitter.perchWindowID == 7,
                     "설 곳이 좁으면 반대편으로 넘어가 둘 다 창 위에 섬", "\(sitter.position.x) \(crowd.position.x)")
    }
}
