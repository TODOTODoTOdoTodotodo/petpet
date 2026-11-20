import Foundation

/// This object is responsible for checking collection stage 3: daily caps and midnight reset, level thresholds and
/// a single level-up, names and held items, the saved record, which moments become ❤️, and the level actions
/// (spin from Lv.2, somersault from Lv.3) appearing only after their level.
enum AffectionChecks {
    static func run(_ check: Checker) {
        rules(check)
        record(check)
        moments(check)
        levelActions(check)
    }

    private static func rules(_ check: Checker) {
        check.section("친밀도: 하루 상한과 레벨")
        let box = Treasury()
        for _ in 0..<12 { box.award(.pokes, to: "a", on: "d1") }
        check.expect(box.hearts(of: "a") == 10, "쓰다듬기는 하루 10까지", "\(box.hearts(of: "a"))")
        box.award(.pokes, to: "a", on: "d2")
        check.expect(box.hearts(of: "a") == 11 && box.given(.pokes, to: "a", on: "d2") == 1, "날짜가 바뀌면 상한 초기화")
        let caps = HeartSource.allCases.map { source -> Int in
            let fresh = Treasury()
            for _ in 0..<40 { fresh.award(source, to: "x", on: "d") }
            return fresh.hearts(of: "x")
        }
        check.expect(caps == [16, 10, 1, 80, 5], "함께 16·쓰다듬기 10·인사 1·줍기 상한 없음(+2씩)·활약 5", "\(caps)")
        let levels = [0, 9, 10, 29, 30, 59, 60, 99, 100, 149, 150, 400].map(Treasury.level(forHearts:))
        check.expect(levels == [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6], "레벨 경계 10·30·60·100·150", "\(levels)")
        let climb = Treasury()
        var ups: [Int] = []
        for _ in 0..<15 { if let up = climb.award(.pickup, to: "b", on: "d") { ups.append(up.level) } }
        check.expect(ups == [2, 3], "경계를 넘을 때 한 번씩만 레벨업", "\(ups)")
        check.expect(climb.hearts(of: "b") == 30 && climb.nextThreshold(of: "b") == 60, "다음 레벨까지 (30/60)")
        for _ in 0..<60 { climb.award(.pickup, to: "b", on: "d") }
        check.expect(climb.level(of: "b") == 6 && climb.nextThreshold(of: "b") == nil, "Lv.6 뒤에도 쌓이고 다음 경계 없음")
        let tiers = [0, 299, 300, 499, 500, 900].map(Treasury.sparkleTier(forHearts:))
        check.expect(tiers == [0, 0, 1, 1, 2, 2], "반짝 발자국 색: 300 분홍, 500 금색", "\(tiers)")

        let acorn = ItemCatalog.item("acorn")!
        let named = Treasury()
        check.expect(!named.rename("c", to: "나비") && !named.hold(acorn, for: "c"), "레벨이 낮으면 이름·소품 안 됨")
        for _ in 0..<30 { named.award(.pickup, to: "c", on: "d") }
        check.expect(named.level(of: "c") == 4 && !named.hold(acorn, for: "c"), "Lv.4라도 못 찾은 물건은 못 듦")
        named.collect(acorn, on: "d")
        check.expect(named.hold(acorn, for: "c") && named.held(of: "c") == acorn, "Lv.4부터 모은 물건을 손에 듦")
        check.expect(named.hold(nil, for: "c") && named.held(of: "c") == nil, "내려놓기")
        check.expect(!named.rename("c", to: "나비"), "이름은 Lv.6부터")
        for _ in 0..<50 { named.award(.pickup, to: "c", on: "d") }
        check.expect(named.rename("c", to: "  나비  ") && named.name(of: "c") == "나비", "Lv.6 이름 짓기 (앞뒤 공백 뺌)")
        check.expect(named.rename("c", to: "가나다라마바사아자차카타") && !named.rename("c", to: "가나다라마바사아자차카타파"), "이름은 12자까지")
        check.expect(named.rename("c", to: "") && named.name(of: "c") == nil, "비우면 이름 지움")
    }

    private static func record(_ check: Checker) {
        check.section("친밀도: 저장")
        let box = Treasury()
        let acorn = ItemCatalog.item("acorn")!
        box.collect(acorn, on: "d")
        for _ in 0..<80 { box.award(.pickup, to: "p", on: "d") }
        box.rename("p", to: "나비")
        box.hold(acorn, for: "p")
        box.award(.pokes, to: "p", on: "d")
        let (back, broken) = Treasury.restore(from: box.encoded())
        check.expect(!broken && back.hearts(of: "p") == 161 && back.name(of: "p") == "나비" && back.held(of: "p") == acorn
                     && back.given(.pokes, to: "p", on: "d") == 1, "❤️·이름·소품·오늘 받은 수를 저장했다 다시 읽음")
        let stageTwo = Data(#"{"version":1,"items":{"acorn":5},"firstFound":{},"hats":["acorn_cap"],"pets":{"q":{"hat":"acorn_cap"}}}"#.utf8)
        let old = Treasury.restore(from: stageTwo)
        check.expect(!old.broken && old.treasury.hat(of: "q")?.id == "acorn_cap" && old.treasury.hearts(of: "q") == 0, "2단계 저장(모자만)도 읽음")
        back.keepPets([])
        check.expect(back.hearts(of: "p") == 0 && back.name(of: "p") == nil, "뺀 펫의 친밀도·이름은 지움")
    }

    private static func roster(seed: UInt64) -> (PetRoster, World, Treasury) {
        let world = Sim.world()
        let roster = PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: seed)), findingRandom: SeededRandomSource(seed: seed + 9))
        let treasury = Treasury()
        roster.affection.treasury = treasury
        roster.affection.today = { "d" }
        return (roster, world, treasury)
    }

    private static func pet(in roster: PetRoster, world: World, x: CGFloat, id: String, behavior: PetBehavior = IdleBehavior(duration: 999)) -> Pet {
        let pet = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        pet.keeperID = id
        pet.position = CGPoint(x: x, y: 80)
        pet.settle(in: world)
        pet.switchTo(behavior)
        return pet
    }

    private static func run(_ roster: PetRoster, in world: World, seconds: Double, idle: TimeInterval = 0, until stop: (() -> Bool)? = nil) {
        for _ in 0..<Int(seconds * 60) {
            roster.step(dt: Sim.dt, in: world, cursor: nil, idleSeconds: idle)
            if let stop, stop() { return }
        }
    }

    private static func moments(_ check: Checker) {
        check.section("친밀도: 쌓이는 일")
        do {
            let (roster, world, box) = roster(seed: 601)
            let pet = pet(in: roster, world: world, x: 500, id: "k")
            pet.poke()
            run(roster, in: world, seconds: 0.1)
            check.expect(box.hearts(of: "k") == 1 && box.given(.pokes, to: "k", on: "d") == 1, "쓰다듬으면 ❤️ +1")
            run(roster, in: world, seconds: 3)
            pet.poke(); pet.poke(); pet.poke()
            run(roster, in: world, seconds: 0.1)
            check.expect(box.hearts(of: "k") == 3, "연달아 3번째(💢)는 셈하지 않음", "\(box.hearts(of: "k"))")
        }
        do {
            let (roster, world, box) = roster(seed: 602)
            let pet = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world, entrance: .startup(order: 0))
            pet.keeperID = "e"
            run(roster, in: world, seconds: 4)
            check.expect(box.given(.greet, to: "e", on: "d") == 1, "등장해 👋 하면 인사 ❤️")
        }
        do {
            let (roster, world, box) = roster(seed: 603)
            pet(in: roster, world: world, x: 500, id: "f")
            roster.finding.release(DroppedItem(id: "x", kind: ItemCatalog.item("acorn")!, scale: 1.5, position: CGPoint(x: 700, y: 200)))
            run(roster, in: world, seconds: 15, until: { box.hearts(of: "f") > 0 })
            check.expect(box.given(.pickup, to: "f", on: "d") == 2, "물건을 주우면 ❤️ +2")
            let veteran = Self.pet(in: roster, world: world, x: 1300, id: "w")
            for _ in 0..<149 { box.award(.pickup, to: "w", on: "d") }
            roster.affection.sync([veteran])
            check.expect(veteran.sparkleTier == 0, "❤️ 298이면 기본 발자국")
            veteran.note(.pickedUp)
            run(roster, in: world, seconds: 0.05)
            check.expect(veteran.sparkleTier == 1, "❤️ 300을 넘으면 분홍 발자국")
        }
        do {
            let (roster, world, box) = roster(seed: 604)
            let pets = [600, 700, 800].enumerated().map { pet(in: roster, world: world, x: CGFloat($0.element), id: "t\($0.offset)") }
            roster.trains.depart(pets, world: world, planner: BehaviorPlanner(random: SeededRandomSource(seed: 1)))
            run(roster, in: world, seconds: 15, until: { box.given(.feats, to: "t2", on: "d") > 0 })
            check.expect(box.given(.feats, to: "t2", on: "d") == 1 && box.given(.feats, to: "t1", on: "d") == 0, "기관차로 도착하면 활약 ❤️ (기관차만)")
        }
        do {
            let (roster, world, box) = roster(seed: 605)
            let pets = [pet(in: roster, world: world, x: 400, id: "g1"), pet(in: roster, world: world, x: 900, id: "g2")]
            run(roster, in: world, seconds: AffectionCoordinator.togetherInterval + 1)
            check.expect(pets.allSatisfy { box.given(.together, to: $0.keeperID!, on: "d") == 1 }, "사용 중 30분 함께 있으면 모두 ❤️ +1")
            let (idleRoster, idleWorld, idleBox) = Self.roster(seed: 606)
            pet(in: idleRoster, world: idleWorld, x: 400, id: "h")
            run(idleRoster, in: idleWorld, seconds: AffectionCoordinator.togetherInterval + 1, idle: 400)
            check.expect(idleBox.hearts(of: "h") == 0, "자리를 비운 시간은 세지 않음")
        }
        do {
            let (roster, world, box) = roster(seed: 607)
            let pet = pet(in: roster, world: world, x: 500, id: "u")
            for _ in 0..<4 { box.award(.pickup, to: "u", on: "d") }
            box.award(.pokes, to: "u", on: "d")
            roster.affection.sync([pet])
            check.expect(pet.level == 1 && box.hearts(of: "u") == 9, "9개면 Lv.1")
            pet.poke()
            run(roster, in: world, seconds: 0.1)
            check.expect(pet.level == 2 && pet.speech?.text == "❤️ Lv.2" && pet.behavior is AirborneBehavior, "10개째에 ❤️ Lv.2 하고 깡충",
                         "\(pet.level) \(String(describing: pet.speech?.text)) \(pet.behavior.name)")
            // 쉬던 펫이 함께 있음으로 레벨이 오르면 축하 깡충
            let calm = Self.pet(in: roster, world: world, x: 1200, id: "v")
            for _ in 0..<14 { box.award(.pickup, to: "v", on: "d") }
            roster.affection.sync([calm])
            calm.note(.pickedUp)
            run(roster, in: world, seconds: 0.05)
            check.expect(calm.level == 3 && calm.behavior.name == "levelUp", "쉬던 펫은 레벨업 깡충", calm.behavior.name)
            box.rename("u", to: nil)
            let messenger = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world, role: .messenger)
            messenger.keeperID = "m"
            messenger.note(.poked)
            run(roster, in: world, seconds: 0.1)
            check.expect(box.hearts(of: "m") == 0, "전령은 쌓지 않음")
        }
        do {
            let pet = Sim.pet(at: CGPoint(x: 500, y: 80), behavior: IdleBehavior(duration: 999))
            check.expect(pet.loveText == "❤️", "이름이 없으면 ❤️")
            pet.nickname = "나비"
            check.expect(pet.loveText == "❤️ 나비", "이름이 있으면 ❤️ 나비")
        }
    }

    private static func levelActions(_ check: Checker) {
        check.section("친밀도: 레벨별 동작")
        let world = Sim.world()
        func tally(level: Int, seed: UInt64) -> (spins: Int, flips: Int, jumps: Int) {
            let planner = BehaviorPlanner(random: SeededRandomSource(seed: seed))
            let pet = Sim.pet(at: CGPoint(x: 800, y: 80), behavior: IdleBehavior(duration: 999))
            pet.settle(in: world)
            pet.level = level
            var spins = 0, flips = 0, jumps = 0
            for _ in 0..<3000 {
                let next = planner.next(after: pet, in: world, context: PetContext(cursor: nil, planner: planner))
                if next is SpinBehavior { spins += 1 }
                if next.name == "somersault" { flips += 1 }
                if next.name == "jumping" || next.name == "somersault" { jumps += 1 }
            }
            return (spins, flips, jumps)
        }
        let one = tally(level: 1, seed: 1)
        let two = tally(level: 2, seed: 1)
        let three = tally(level: 3, seed: 1)
        check.expect(one.spins == 0 && one.flips == 0, "Lv.1은 한 바퀴·공중제비 없음")
        check.expect(two.spins > 0 && two.flips == 0, "Lv.2부터 한 바퀴", "\(two)")
        let share = Double(three.flips) / Double(max(three.jumps, 1))
        check.expect(three.spins > 0 && abs(share - BehaviorPlanner.somersaultChance) < 0.08, "Lv.3부터 점프의 35%가 공중제비", "\(three) \(share)")

        let flip = AirborneBehavior.jumping(toward: .east, motionScale: 1, somersault: true)
        let jumper = Sim.pet(at: CGPoint(x: 800, y: 80), behavior: flip)
        var turned: CGFloat = 0
        for _ in 0..<120 {
            jumper.step(dt: Sim.dt, in: world, context: PetContext(cursor: nil, planner: BehaviorPlanner(random: SeededRandomSource(seed: 2))))
            if jumper.behavior === flip { turned = flip.bodyRotation }
        }
        check.expect(abs(abs(turned) - 2 * .pi) < 0.3 && turned < 0, "공중제비는 착지 무렵 앞으로 한 바퀴", "\(turned)")
        check.expect(AirborneBehavior.jumping(toward: .east, motionScale: 1).bodyRotation == 0, "보통 점프는 돌지 않음")

        let spinner = Sim.pet(at: CGPoint(x: 800, y: 80), behavior: IdleBehavior(duration: 999))
        spinner.settle(in: world)
        spinner.facing = .west
        spinner.switchTo(SpinBehavior())
        let sang = spinner.speech?.text == SpinBehavior.noteText
        var faces: [Facing] = [spinner.facing]
        for _ in 0..<60 {
            spinner.step(dt: Sim.dt, in: world, context: PetContext(cursor: nil, planner: BehaviorPlanner(random: SeededRandomSource(seed: 3))))
            if faces.last != spinner.facing { faces.append(spinner.facing) }
        }
        check.expect(faces.count == SpinBehavior.turnCount + 1 && sang, "한 바퀴: ♪ 하며 6번 방향을 바꿈", "\(faces.count)")

        let holder = Sim.pet(at: CGPoint(x: 800, y: 80), behavior: IdleBehavior(duration: 999))
        holder.facing = .east
        check.expect(HeldPlacement.rect(on: holder) == nil, "든 물건이 없으면 그리지 않음")
        holder.heldItem = ItemCatalog.item("acorn")
        let hand = HeldPlacement.rect(on: holder)
        check.expect(hand.map { $0.midX > 800 && $0.midY > 80 && $0.midY < 80 + holder.bodyHeight } == true, "앞손 가슴 높이에 듦", "\(String(describing: hand))")
        holder.switchTo(SleepBehavior())
        check.expect(HeldPlacement.rect(on: holder) == nil, "자는 동안은 숨김")
    }
}
