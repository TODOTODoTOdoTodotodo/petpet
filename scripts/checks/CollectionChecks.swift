import Foundation

/// This object is responsible for checking collection stage 1: the item list and art, the saved collection,
/// counting only time in use, where items land, how they ride windows and fade, and which pet fetches them and when.
enum CollectionChecks {
    static func run(_ check: Checker) {
        catalog(check)
        treasury(check)
        clock(check)
        dropping(check)
        itemMotion(check)
        fetching(check)
        hats(check)
        hatPlacement(check)
    }

    // MARK: - Setup

    private static func roster(seed: UInt64) -> PetRoster {
        PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: seed)), findingRandom: SeededRandomSource(seed: seed + 1000))
    }

    @discardableResult
    private static func pet(in roster: PetRoster, world: World, x: CGFloat, y: CGFloat = 80,
                            behavior: PetBehavior = IdleBehavior(duration: 999)) -> Pet {
        let pet = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        pet.position = CGPoint(x: x, y: y)
        pet.settle(in: world)
        pet.switchTo(behavior)
        return pet
    }

    private static func item(_ id: String = "acorn", x: CGFloat, y: CGFloat) -> DroppedItem {
        DroppedItem(id: "T-\(id)-\(Int(x))", kind: ItemCatalog.item(id)!, scale: 1.5, position: CGPoint(x: x, y: y))
    }

    private static func run(_ roster: PetRoster, in world: World, seconds: Double, idle: TimeInterval = 0,
                            each: (() -> Void)? = nil, until stop: (() -> Bool)? = nil) {
        for _ in 0..<Int(seconds * 60) {
            roster.step(dt: Sim.dt, in: world, cursor: nil, idleSeconds: idle)
            each?()
            if let stop, stop() { return }
        }
    }

    /// 바닥에 놓인 물건 하나와 그것을 셀 준비
    private static func collecting(_ roster: PetRoster) -> () -> [(ItemKind, String)] {
        var log: [(ItemKind, String)] = []
        roster.finding.onCollect = { log.append(($0, $1)) }
        return { log }
    }

    // MARK: - Checks

    private static func catalog(_ check: Checker) {
        check.section("수집: 물건 목록")
        let items = ItemCatalog.all
        check.expect(items.count == 12 && Set(items.map(\.id)).count == 12, "물건 12종(계절 2종 포함), ID 겹치지 않음")
        let shapes = items.filter { $0.rows.count == 8 && $0.rows.allSatisfy { $0.count == 8 } }
        check.expect(shapes.count == 12, "그림은 모두 8×8", "\(items.filter { !shapes.contains($0) }.map(\.id))")
        let painted = items.filter { item in item.rows.joined().allSatisfy { $0 == "." || item.palette[$0] != nil } }
        check.expect(painted.count == 12, "모든 도트에 색이 있음", "\(items.filter { !painted.contains($0) }.map(\.id))")
        let yearRound = items.filter { $0.months == nil }
        let common = yearRound.filter { $0.rarity == .common }.reduce(0) { $0 + $1.weight }
        let rare = yearRound.filter { $0.rarity == .rare }.reduce(0) { $0 + $1.weight }
        check.expect(common == 92 && rare == 8, "늘 나오는 물건은 흔함 92 : 드묾 8", "\(common) \(rare)")
        check.expect(ItemCatalog.pick(roll: 0, month: 7).id == "acorn" && ItemCatalog.pick(roll: 0.9999, month: 7).id == "golden_key", "비중 순서대로 고름")
        let random = SeededRandomSource(seed: 5)
        let rolls = (0..<5000).map { _ in ItemCatalog.pick(roll: random.next(), month: 7) }
        let rareShare = Double(rolls.filter { $0.rarity == .rare }.count) / Double(rolls.count)
        check.expect(abs(rareShare - 0.08) < 0.015, "드문 물건은 8% 안팎", "\(rareShare)")
        check.expect(items.allSatisfy { !$0.koreanName.isEmpty && $0.name(in: .korean) != $0.name(in: .english) }, "한국어 이름")

        check.section("수집: 계절 물건 (4단계)")
        func kinds(month: Int) -> [String: Int] {
            let random = SeededRandomSource(seed: 9)
            var counts: [String: Int] = [:]
            for _ in 0..<5300 { counts[ItemCatalog.pick(roll: random.next(), month: month).id, default: 0] += 1 }
            return counts
        }
        let january = kinds(month: 1), april = kinds(month: 4), july = kinds(month: 7)
        let snowShare = Double(january["snowflake"] ?? 0) / 5300
        check.expect(abs(snowShare - 6.0 / 106) < 0.012 && january["blossom"] == nil, "12~2월에는 눈송이(비중 6), 벚꽃은 안 나옴", "\(snowShare)")
        check.expect((april["blossom"] ?? 0) > 0 && april["snowflake"] == nil, "3~4월에는 벚꽃만")
        check.expect(july["snowflake"] == nil && july["blossom"] == nil, "그 밖의 달에는 계절 물건 없음")
        check.expect([12, 1, 2].allSatisfy { ItemCatalog.item("snowflake")!.isAvailable(inMonth: $0) } && !ItemCatalog.item("snowflake")!.isAvailable(inMonth: 3),
                     "눈송이 기간 경계 (2월까지)")
        check.expect(ItemCatalog.seasonLabel(of: ItemCatalog.item("snowflake")!, in: .korean) == "12~2월"
                     && ItemCatalog.seasonLabel(of: ItemCatalog.item("snowflake")!, in: .english) == "Dec–Feb"
                     && ItemCatalog.seasonLabel(of: ItemCatalog.item("blossom")!, in: .korean) == "3~4월"
                     && ItemCatalog.seasonLabel(of: ItemCatalog.item("acorn")!, in: .korean) == nil, "도감에 보일 기간 이름 (해 넘김 포함)")
        let world = Sim.world()
        let winter = FindingCoordinator(random: SeededRandomSource(seed: 3))
        winter.month = { 1 }
        let summer = FindingCoordinator(random: SeededRandomSource(seed: 3))
        summer.month = { 7 }
        for _ in 0..<300 {
            winter.drop(in: world, pets: [], screenID: nil)
            summer.drop(in: world, pets: [], screenID: nil)
        }
        check.expect(winter.items.contains { $0.kind.id == "snowflake" } && !summer.items.contains { $0.kind.months != nil },
                     "떨어뜨릴 때 그 달 기준으로 고름")
    }

    private static func treasury(_ check: Checker) {
        check.section("수집: 도감 저장")
        let acorn = ItemCatalog.item("acorn")!
        let shell = ItemCatalog.item("shell")!
        let box = Treasury()
        box.collect(acorn, on: "2026-11-20")
        box.collect(acorn, on: "2026-11-21")
        box.collect(shell, on: "2026-11-21")
        check.expect(box.count(of: acorn) == 2 && box.total == 3 && box.firstFound["acorn"] == "2026-11-20", "개수와 처음 찾은 날")
        let (restored, broken) = Treasury.restore(from: box.encoded())
        check.expect(!broken && restored.count(of: acorn) == 2 && restored.firstFound == box.firstFound, "저장했다 다시 읽어도 같음")
        let empty = Treasury.restore(from: nil)
        check.expect(!empty.broken && empty.treasury.total == 0, "저장이 없으면 빈 도감")
        check.expect(Treasury.restore(from: Data("oops".utf8)).broken, "깨진 저장은 broken (원본은 옮겨 둠)")
        let future = Data(#"{"version":2,"items":{"acorn":3},"firstFound":{}}"#.utf8)
        check.expect(Treasury.restore(from: future).broken, "모르는 버전도 broken")
        box.reset()
        check.expect(box.total == 0 && box.firstFound.isEmpty, "초기화하면 모두 지움")
        var date = DateComponents()
        date.year = 2026; date.month = 3; date.day = 7
        check.expect(Treasury.day(of: Calendar.current.date(from: date)!) == "2026-03-07", "날짜 문자열")

        var made = 0
        let make = { () -> String in made += 1; return "new\(made)" }
        check.expect(KeeperIDs.aligned(["a", "b"], count: 3, make: make) == ["a", "b", "new1"], "펫 ID: 모자라면 새로")
        check.expect(KeeperIDs.aligned(["a", "b", "c"], count: 2, make: make) == ["a", "b"], "펫 ID: 남으면 버림")
        check.expect(KeeperIDs.aligned(["a", "a", ""], count: 3, make: make) == ["a", "new2", "new3"], "펫 ID: 겹치거나 빈 ID는 새로")
    }

    private static func clock(_ check: Checker) {
        check.section("수집: 사용 중 시간만 셈")
        do {
            let world = Sim.world()
            let roster = roster(seed: 201)
            pet(in: roster, world: world, x: 400)
            var droppedAt: TimeInterval?
            run(roster, in: world, seconds: 9 * 60, each: {
                if droppedAt == nil && roster.finding.stats.dropped > 0 { droppedAt = roster.finding.activeTime }
            })
            check.expect(droppedAt.map { $0 >= 180 && $0 <= 480 } == true, "켠 뒤 첫 물건은 사용 3~8분 사이", "\(String(describing: droppedAt))")
            check.expect(roster.finding.stats.dropped == 1, "다음 물건은 6분 이상 뒤", "\(roster.finding.stats.dropped)")
        }
        do {
            let world = Sim.world()
            let roster = roster(seed: 202)
            pet(in: roster, world: world, x: 400)
            run(roster, in: world, seconds: 10 * 60, idle: 400)
            check.expect(roster.finding.activeTime == 0 && roster.finding.stats.dropped == 0, "입력이 5분 넘게 없으면 시계가 멈춤")
        }
        do {
            let world = Sim.world()
            let roster = roster(seed: 203)
            roster.isQuiet = true
            pet(in: roster, world: world, x: 400)
            run(roster, in: world, seconds: 10 * 60)
            check.expect(roster.finding.activeTime == 0 && roster.finding.stats.dropped == 0, "통화 중에는 멈춤")
        }
    }

    private static func dropping(_ check: Checker) {
        check.section("수집: 떨어지는 곳")
        // 창 7 위를 창 8이 일부 가림
        let windows = [Sim.window(8, 700, 300, 300, 400), Sim.window(7, 300, 200, 700, 300)]
        var landedRight = 0
        var clear = 0
        var visible = 0
        var tries = 0
        for seed in 0..<30 {
            let world = Sim.world(windows: windows)
            let roster = roster(seed: UInt64(300 + seed))
            let pets = [pet(in: roster, world: world, x: 450, y: 500), pet(in: roster, world: world, x: 1200)]
            pets.forEach { $0.switchTo(IdleBehavior(duration: 999, lookAtUser: true, name: "announcing")) }
            guard let item = roster.finding.drop(in: world, pets: pets, screenID: nil) else { continue }
            tries += 1
            let aimX = item.position.x
            for _ in 0..<(4 * 60) where !item.isResting { item.step(dt: Sim.dt, in: world) }
            if item.isResting && abs(item.position.x - aimX) < 1 { landedRight += 1 }
            if pets.allSatisfy({ abs($0.position.y - item.position.y) >= $0.bodyHeight || abs($0.position.x - item.position.x) >= $0.bodyHalfWidth + 40 }) {
                clear += 1
            }
            if world.ledge(atX: item.position.x, nearY: item.position.y, tolerance: 1) != nil { visible += 1 }
        }
        check.expect(tries == 30, "넓은 발판이 있으면 늘 떨어뜨림", "\(tries)")
        check.expect(landedRight == tries, "고른 자리 바로 아래 발판에 착지 (한 번 튀고 멈춤)", "\(landedRight)/\(tries)")
        check.expect(clear == tries, "펫 몸에서 40pt 이상 떨어진 곳", "\(clear)/\(tries)")
        check.expect(visible == tries, "앞 창에 가린 곳이 아닌 보이는 발판", "\(visible)/\(tries)")
    }

    private static func itemMotion(_ check: Checker) {
        check.section("수집: 물건 움직임")
        var windows = [Sim.window(7, 300, 200, 600, 300)]
        let world = Sim.world(windows: windows)
        let item = item(x: 500, y: 700)
        var bounced = false
        var lastY = item.position.y
        for _ in 0..<(3 * 60) {
            item.step(dt: Sim.dt, in: world)
            if item.state == .falling && item.position.y > lastY { bounced = true }
            lastY = item.position.y
        }
        check.expect(item.isResting && item.position.y == 500 && item.perchWindowID == 7 && bounced, "창 위에 떨어져 한 번 튀고 멈춤")
        windows = [Sim.window(7, 350, 200, 600, 300)]
        world.update(windows: windows)
        item.step(dt: Sim.dt, in: world)
        check.expect(abs(item.position.x - 550) < 0.5 && item.isResting, "창을 옮기면 같이 움직임", "\(item.position)")
        world.update(windows: [])
        for _ in 0..<(3 * 60) { item.step(dt: Sim.dt, in: world) }
        check.expect(item.isResting && item.position.y == 80, "창이 닫히면 바닥으로 떨어짐", "\(item.position)")

        let shaken = Self.item(x: 500, y: 600)
        world.update(windows: [Sim.window(7, 300, 200, 600, 300)])
        for _ in 0..<(3 * 60) { shaken.step(dt: Sim.dt, in: world) }
        let roster = roster(seed: 401)
        roster.finding.release(shaken)
        check.expect(roster.finding.perches == [7], "물건이 놓인 창도 흔들기 감지 대상")
        roster.finding.shake(windowID: 7, push: CGVector(dx: 400, dy: 0))
        check.expect(shaken.state == .falling, "창을 흔들면 튕겨 나감")

        let lonely = Self.item(x: 1200, y: 300)
        let floor = Sim.world()
        var blinked = false
        for _ in 0..<Int((DroppedItem.lifetime + 5) * 60) {
            lonely.step(dt: Sim.dt, in: floor)
            if lonely.isBlinkedOut { blinked = true }
        }
        check.expect(lonely.state == .expired && blinked, "3분 동안 아무도 안 주우면 깜빡이다 사라짐")
        let blinkStart = DroppedItem.lifetime - DroppedItem.blinkTime
        check.expect(blinkStart == 160, "마지막 20초만 깜빡임")
    }

    private static func fetching(_ check: Checker) {
        check.section("수집: 줍기")
        do {
            let world = Sim.world()
            let roster = roster(seed: 501)
            let near = pet(in: roster, world: world, x: 500)
            pet(in: roster, world: world, x: 1400)
            let found = collecting(roster)
            let acorn = item(x: 800, y: 300)
            roster.finding.release(acorn)
            var started: TimeInterval?
            var clock: TimeInterval = 0
            run(roster, in: world, seconds: 20, each: {
                clock += Sim.dt
                if started == nil && acorn.isResting { started = clock }
            }, until: { !found().isEmpty })
            check.expect(found().first?.1 == near.id && found().first?.0.id == "acorn", "같은 발판의 가장 가까운 펫이 주움",
                         "\(found().map(\.1))")
            check.expect(near.speech?.text == FetchBehavior.foundText, "주우면 ✨")
            check.expect(started.map { clock - $0 < 10 } == true, "10초 안에 주움", "\(clock - (started ?? 0))")
            run(roster, in: world, seconds: 1)
            check.expect(roster.finding.items.isEmpty && roster.finding.stats.collected == 1, "메뉴바 쪽으로 날아가 사라지고 한 번만 셈")
        }
        do {
            let world = Sim.world()
            let roster = roster(seed: 502)
            let finder = pet(in: roster, world: world, x: 500)
            let found = collecting(roster)
            roster.finding.release(item("star_shard", x: 700, y: 200))
            run(roster, in: world, seconds: 15, until: { !found().isEmpty })
            check.expect(!found().isEmpty && finder.speech?.text == FetchBehavior.rareText, "드문 물건이면 🌟")
        }
        // 드문 물건: 놓이면 가까운 펫들이 돌아보며 "!", 주운 펫은 공격 동작이 있어도 깡충
        do {
            let world = Sim.world()
            let roster = roster(seed: 510)
            let finder = roster.add(appearance: FakeAppearance(hasAction: true), scale: 1.5, in: world)
            finder.position = CGPoint(x: 500, y: 80)
            finder.settle(in: world)
            finder.switchTo(IdleBehavior(duration: 999))
            let others = [900, 1100].map { pet(in: roster, world: world, x: CGFloat($0)) }
            let found = collecting(roster)
            roster.finding.release(item("crown_piece", x: 700, y: 200))
            var noticed = Set<String>()
            var cheered = false
            run(roster, in: world, seconds: 15, each: {
                for pet in others where pet.behavior.name == "noticing" && pet.speech?.text == Chatter.surprised { noticed.insert(pet.id) }
                if !found().isEmpty && finder.behavior is AirborneBehavior { cheered = true }
            }, until: { cheered })
            check.expect(noticed.count == 2, "드문 물건이 놓이면 가까운 펫들이 돌아보며 !", "\(noticed)")
            check.expect(cheered && finder.speech?.text == FetchBehavior.rareText, "드문 물건을 주우면 🌟 하고 깡충")
        }
        do {
            let world = Sim.world()
            let roster = roster(seed: 503)
            let busy = pet(in: roster, world: world, x: 500)
            busy.announce(ScheduleNotice(topic: "m", text: "지금 · 회의"))
            let messenger = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world, role: .messenger)
            messenger.position = CGPoint(x: 1000, y: 80)
            messenger.settle(in: world)
            messenger.switchTo(IdleBehavior(duration: 999))
            let found = collecting(roster)
            roster.finding.release(item(x: 800, y: 200))
            run(roster, in: world, seconds: 25)
            check.expect(found().isEmpty, "알림을 든 펫·전령은 줍지 않음")
        }
        do {
            let world = Sim.world()
            let roster = roster(seed: 504)
            roster.vigor = .exhausted
            pet(in: roster, world: world, x: 500)
            let found = collecting(roster)
            roster.finding.release(item(x: 800, y: 200))
            run(roster, in: world, seconds: 25)
            check.expect(found().isEmpty, "지쳐 누운 펫은 줍지 않음")
        }
        // 창 위 물건: 30초 뒤 바닥 펫이 도약해 주움
        do {
            let world = Sim.world(windows: [Sim.window(7, 300, 80, 600, 250)])
            let roster = roster(seed: 505)
            let floorPet = pet(in: roster, world: world, x: 1100)
            let found = collecting(roster)
            let item = item(x: 700, y: 500)
            roster.finding.release(item)
            var leapt: TimeInterval?
            var clock: TimeInterval = 0
            run(roster, in: world, seconds: 60, each: {
                clock += Sim.dt
                if leapt == nil && floorPet.behavior is SkillLeapBehavior { leapt = clock }
            }, until: { !found().isEmpty })
            check.expect(leapt.map { $0 >= FindingCoordinator.callWait } == true && !found().isEmpty,
                         "다른 발판이면 30초 뒤 스킬 도약으로 올라가 주움", "leapt \(String(describing: leapt)) found \(found().count)")
        }
        do {
            let world = Sim.world(windows: [Sim.window(7, 300, 80, 600, 250)])
            let roster = roster(seed: 506)
            roster.skills.isEnabled = false
            pet(in: roster, world: world, x: 1100)
            let found = collecting(roster)
            roster.finding.release(item(x: 700, y: 500))
            run(roster, in: world, seconds: 70)
            check.expect(found().isEmpty, "Skill Jumps를 끄면 도약하지 않고 기다림")
        }
        do {
            let world = Sim.world(windows: [Sim.window(7, 300, 80, 600, 250)])
            let roster = roster(seed: 507)
            roster.skills.isEnabled = false
            pet(in: roster, world: world, x: 1100)
            let found = collecting(roster)
            let item = item(x: 700, y: 500)
            roster.finding.release(item)
            run(roster, in: world, seconds: 2)
            let clicked = roster.fetch(itemAt: CGPoint(x: item.position.x, y: item.position.y + 3), in: world)
            run(roster, in: world, seconds: 12, until: { !found().isEmpty })
            check.expect(clicked && !found().isEmpty, "물건을 클릭하면 바로 감 (필요하면 도약)")
            check.expect(!roster.fetch(itemAt: CGPoint(x: 100, y: 900), in: world), "빈 곳 클릭은 물건이 아님")
        }
        // 창 위 펫은 걸어 내려와 바닥 물건을 주움
        do {
            let world = Sim.world(windows: [Sim.window(7, 300, 80, 600, 250)])
            let roster = roster(seed: 508)
            pet(in: roster, world: world, x: 600, y: 330)
            let found = collecting(roster)
            roster.finding.release(item(x: 1200, y: 200))
            run(roster, in: world, seconds: 60, until: { !found().isEmpty })
            check.expect(!found().isEmpty, "위쪽 발판 펫은 30초 뒤 걸어 내려와 주움")
        }
        // 가는 길을 바쁜 펫이 막아도 겹치지 않고 결국 주움
        do {
            let world = Sim.world()
            let roster = roster(seed: 509)
            let finder = pet(in: roster, world: world, x: 300)
            let blocker = pet(in: roster, world: world, x: 600)
            blocker.announce(ScheduleNotice(topic: "m", text: "지금 · 회의"))
            let found = collecting(roster)
            roster.finding.release(item(x: 1000, y: 200))
            var worst: CGFloat = 0
            run(roster, in: world, seconds: 60, each: {
                if finder.support != nil && blocker.support != nil && abs(finder.position.y - blocker.position.y) < 1 {
                    worst = max(worst, finder.bodyHalfWidth + blocker.bodyHalfWidth - abs(finder.position.x - blocker.position.x))
                }
            }, until: { !found().isEmpty })
            check.expect(!found().isEmpty && worst <= 2.5, "막은 펫은 뛰어넘는 등 규칙대로 지나가 주움", "found \(found().count) overlap \(worst)")
        }
    }

    // MARK: - Hats (2단계)

    private static func hats(_ check: Checker) {
        check.section("수집: 모자 목록과 얻기")
        let hats = HatCatalog.all
        let sizes = Dictionary(uniqueKeysWithValues: hats.map { ($0.id, "\($0.width)x\($0.height)") })
        let planned = ["leaf_cap": "10x6", "acorn_cap": "10x6", "feather_band": "12x7", "bow": "10x5",
                       "flower_crown": "12x5", "candy_pin": "6x6", "star_hat": "10x9", "crown": "12x7"]
        check.expect(hats.count == 8 && sizes == planned, "모자 8종, 기획한 크기", "\(sizes)")
        check.expect(hats.allSatisfy { hat in hat.rows.allSatisfy { $0.count == hat.width } }, "줄 길이가 고름")
        check.expect(hats.allSatisfy { hat in hat.rows.joined().allSatisfy { $0 == "." || hat.palette[$0] != nil } }, "모든 도트에 색이 있음")
        check.expect(hats.allSatisfy { hat in
            if case .item(let id, _) = hat.condition { return ItemCatalog.item(id) != nil } else { return true }
        }, "조건의 물건이 목록에 있음")

        let acorn = ItemCatalog.item("acorn")!
        let shell = ItemCatalog.item("shell")!
        let box = Treasury()
        var results: [CollectResult] = []
        for _ in 0..<4 { results.append(box.collect(acorn, on: "d", by: "pet-a")) }
        check.expect(results.allSatisfy { $0.unlocked.isEmpty } && box.hat(of: "pet-a") == nil, "도토리 4개는 아직")
        let fifth = box.collect(acorn, on: "d", by: "pet-a")
        check.expect(fifth.unlocked.map(\.id) == ["acorn_cap"] && fifth.worn?.id == "acorn_cap" && box.hat(of: "pet-a")?.id == "acorn_cap",
                     "5개째에 도토리 모자를 얻고, 모자 없던 펫이 바로 씀")
        for _ in 0..<4 { box.collect(shell, on: "d", by: "pet-b") }
        check.expect(box.total == 9 && !box.isUnlocked(HatCatalog.hat("leaf_cap")!), "합계 9개는 나뭇잎 모자 아직")
        let tenth = box.collect(shell, on: "d", by: "pet-a")
        check.expect(tenth.unlocked.map(\.id) == ["leaf_cap"] && tenth.worn == nil && box.hat(of: "pet-a")?.id == "acorn_cap",
                     "합계 10개째에 나뭇잎 모자, 이미 쓴 펫은 그대로")
        check.expect(box.newHats == ["acorn_cap", "leaf_cap"], "새 모자 표시")
        check.expect(box.progress(toward: HatCatalog.hat("bow")!) == 0 && box.progress(toward: HatCatalog.hat("leaf_cap")!) == 10,
                     "조건까지 모은 수")
        check.expect(!box.wear(HatCatalog.hat("crown"), on: "pet-b") && box.hat(of: "pet-b") == nil, "못 얻은 모자는 쓸 수 없음")
        check.expect(box.wear(HatCatalog.hat("leaf_cap"), on: "pet-b") && box.hat(of: "pet-b")?.id == "leaf_cap", "얻은 모자는 펫마다 따로 씀")
        check.expect(box.wear(HatCatalog.hat("leaf_cap"), on: "pet-a") && box.hat(of: "pet-a")?.id == "leaf_cap", "같은 모자를 여러 펫이 씀")
        box.markHatsSeen()
        check.expect(box.newHats.isEmpty, "메뉴에서 보면 새 모자 표시가 사라짐")

        let (restored, broken) = Treasury.restore(from: box.encoded())
        check.expect(!broken && restored.hats == box.hats && restored.hat(of: "pet-b")?.id == "leaf_cap" && restored.newHats.isEmpty,
                     "모자·펫 기록도 저장했다 다시 읽음")
        let stageOne = Data(#"{"version":1,"items":{"acorn":6,"shell":5},"firstFound":{}}"#.utf8)
        let upgraded = Treasury.restore(from: stageOne).treasury
        check.expect(upgraded.isUnlocked(HatCatalog.hat("acorn_cap")!) && upgraded.isUnlocked(HatCatalog.hat("leaf_cap")!)
                     && upgraded.newHats.count == 2, "1단계 저장을 읽으면 그동안 모은 수로 모자를 얻음")
        restored.wear(nil, on: "pet-b")
        check.expect(restored.hat(of: "pet-b") == nil, "모자 벗기")
        restored.keepPets(["pet-b"])
        check.expect(restored.hat(of: "pet-a") == nil, "뺀 펫의 모자 기록은 지움")
        restored.reset()
        check.expect(restored.hats.isEmpty && restored.wearing.isEmpty, "초기화하면 모자도 지움")
    }

    private static func hatPlacement(_ check: Checker) {
        check.section("수집: 모자 자리")
        let world = Sim.world()
        let hat = HatCatalog.hat("acorn_cap")!
        let pet = Sim.pet(at: CGPoint(x: 500, y: 80), behavior: IdleBehavior(duration: 999))
        pet.facing = .west
        let west = HatPlacement.frame(of: hat, on: pet)
        let s = pet.scale
        check.expect(abs(west.rect.midX - 500) < 0.01 && abs(west.rect.minY - (80 + pet.bodyHeight - HatPlacement.sink * s)) < 0.01
                     && west.rect.width == 10 * s && !west.flipX && !west.flipY, "몸 꼭대기 가운데에 조금 얹힘", "\(west)")
        pet.facing = .east
        check.expect(HatPlacement.frame(of: hat, on: pet).flipX, "오른쪽을 보면 좌우 반전")
        // 창 아랫면에 거꾸로 붙은 펫 (발 y가 아랫변, 머리는 아래)
        let hanging = Sim.pet(at: CGPoint(x: 500, y: 600), behavior: CeilingWalkBehavior(windowID: 7))
        let below = HatPlacement.frame(of: hat, on: hanging)
        check.expect(hanging.pose.upsideDown && below.flipY && abs(below.rect.maxY - (600 - hanging.bodyHeight + HatPlacement.sink * s)) < 0.01,
                     "거꾸로 매달리면 머리 아래에 뒤집혀 붙음", "\(below)")
        _ = world

        final class Shifted: PetAppearance {
            let name = "Shifted"
            let body = BodyMetrics(footInset: 0, width: 24, height: 40, centerX: 24)
            let skillStyle: SkillStyle = .bigJump
            let hatAnchor = CGVector(dx: 2, dy: -1)
            func supports(_ kind: AnimationKind) -> Bool { true }
            func cycleDuration(of kind: AnimationKind, facing: Facing) -> TimeInterval { 0 }
        }
        let shifted = Sim.pet(at: CGPoint(x: 500, y: 80), appearance: Shifted(), behavior: IdleBehavior(duration: 999))
        shifted.facing = .east
        let moved = HatPlacement.frame(of: hat, on: shifted)
        check.expect(abs(moved.rect.midX - (500 + 2 * s)) < 0.01 && abs(moved.rect.minY - (80 + shifted.bodyHeight - 3 * s)) < 0.01,
                     "스킨별 hatAnchor로 얼굴 쪽·위아래 보정", "\(moved)")

        // metadata.json의 hatAnchor 읽기
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deskpet-hat-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data(#"{"states":[{"frames":{}}],"deskpet":{"hatAnchor":[3,-2]}}"#.utf8).write(to: folder.appendingPathComponent("metadata.json"))
        let skin = PetSkin<Int>(name: "T", directory: folder) { _ in nil }
        check.expect(skin.hatAnchor == CGVector(dx: 3, dy: -2), "스킨 metadata의 hatAnchor를 읽음", "\(skin.hatAnchor)")
        try? FileManager.default.removeItem(at: folder)
    }
}
