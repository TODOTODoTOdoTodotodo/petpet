import Foundation

/// This object is responsible for checking notices left unanswered: the bubble growing in capped steps only while the
/// user is around (and not during calls), the pet holding one staying busy, the pet crumpling it after a while and
/// tossing it to a pile on its side of the floor (not during calls or when turned off, messengers leaving after),
/// a click on a ball announcing it again, withdrawn notices leaving the pile, and the pile's size limit.
enum NoticePileChecks {
    static func run(_ check: Checker) {
        swelling(check)
        aging(check)
        busy(check)
        tossing(check)
        reopening(check)
        withdrawing(check)
        holding(check)
        messenger(check)
        pileLimit(check)
    }

    private static func notice(_ topic: String) -> ScheduleNotice {
        ScheduleNotice(topic: topic, text: "회의 \(topic)", discreetText: "일정")
    }

    /// 펫 하나를 바닥에 세운 명단 (던지기까지 2초)
    private static func setup(seed: UInt64 = 11, x: CGFloat = 300) -> (PetRoster, World, Pet) {
        let world = Sim.world()
        let roster = PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: seed)))
        roster.skills.isEnabled = false
        roster.notices.tossAfter = 2
        let pet = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        pet.position = CGPoint(x: x, y: 80)
        pet.settle(in: world)
        run(roster, in: world, seconds: 1)
        pet.switchTo(IdleBehavior(duration: 30))
        return (roster, world, pet)
    }

    private static func run(_ roster: PetRoster, in world: World, seconds: Double, idle: TimeInterval = 0) {
        for _ in 0..<max(Int(seconds * 60), 1) { roster.step(dt: Sim.dt, in: world, cursor: nil, idleSeconds: idle) }
    }

    private static func swelling(_ check: Checker) {
        check.section("오래 둔 알림: 말풍선 커짐")
        func speech(_ kind: Speech.Kind, age: TimeInterval) -> Speech {
            Speech(text: "회의", kind: kind, remaining: .infinity, topic: "t", discreetText: "일정", age: age)
        }
        let scales = [0, 299, 300, 900, 5000].map { speech(.notice, age: $0).swell }
        check.expect(scales == [1, 1, 1.15, 1.3, 1.3], "5분 1.15배, 15분 1.3배에서 멈춤", "\(scales)")
        check.expect(speech(.chatter, age: 5000).swell == 1, "잡담은 커지지 않음")
        check.expect(speech(.notice, age: 5000).discreet.swell == 1, "통화 중 말풍선은 커지지 않음")
        let notice = speech(.notice, age: 10).notice
        check.expect(notice == ScheduleNotice(topic: "t", text: "회의", discreetText: "일정"), "알림 말풍선은 다시 띄울 알림 내용을 지님")
        check.expect(speech(.chatter, age: 0).notice == nil, "잡담은 알림 내용이 없음")

        let placed = SpeechBubbleLayout.place(body: CGSize(width: 40, height: 20), pointingAt: CGPoint(x: 500, y: 100),
                                              within: 0...1000, swell: 1.3)
        check.expect(abs(placed.body.width - 52) < 0.01 && abs(placed.body.minY - (100 + SpeechBubbleLayout.tailHeight * 1.3)) < 0.01
                     && abs(placed.tailX - 20) < 0.01, "커진 말풍선은 꼬리 끝 위로 커진 크기로 놓임 (꼬리 거리는 원래 크기 기준)",
                     "\(placed)")
    }

    private static func aging(_ check: Checker) {
        check.section("오래 둔 알림: 자리에 있을 때만 나이 셈")
        let world = Sim.world()
        let planner = BehaviorPlanner(random: SeededRandomSource(seed: 3))
        let pet = Sim.pet(at: CGPoint(x: 400, y: 80), behavior: IdleBehavior(duration: 60))
        pet.settle(in: world)
        pet.announce(notice("a"))
        Sim.run(pet, in: world, planner: planner, seconds: 2)
        let present = pet.speech?.age ?? 0
        Sim.run(pet, in: world, planner: planner, seconds: 2, idleSeconds: Speech.presenceLimit + 1)
        let away = pet.speech?.age ?? 0
        check.expect(abs(present - 2) < 0.05, "입력이 있는 동안은 나이가 늚", "\(present)")
        check.expect(abs(away - present) < 0.001, "자리를 비운 동안은 늘지 않음", "\(present) → \(away)")
    }

    private static func busy(_ check: Checker) {
        check.section("오래 둔 알림: 든 펫은 분주함")
        let world = Sim.world()
        let pet = Sim.pet(at: CGPoint(x: 400, y: 80), behavior: IdleBehavior(duration: 1))
        pet.settle(in: world)
        let context = PetContext(cursor: nil, planner: BehaviorPlanner(random: FixedRandom(0.1)))
        let busyNames: Set<String> = ["pacing", "fidgeting", "fidgetHop"]
        let calm = BehaviorPlanner(random: FixedRandom(0.1)).next(after: pet, in: world, context: context).name
        pet.announce(notice("b"))
        let holding = BehaviorPlanner(random: FixedRandom(0.1)).next(after: pet, in: world, context: context)
        check.expect(!busyNames.contains(calm) && holding.name == "pacing", "알림을 들면 종종걸음 (없으면 평소 동작)", "\(calm) → \(holding.name)")
        let sometimes = BehaviorPlanner(random: FixedRandom(0.9)).next(after: pet, in: world, context: context).name
        check.expect(!busyNames.contains(sometimes), "가끔은 평소 동작도 함", sometimes)

        var names = Set<String>()
        let planner = BehaviorPlanner(random: SeededRandomSource(seed: 5))
        for _ in 0..<60 { names.insert(planner.next(after: pet, in: world, context: PetContext(cursor: nil, planner: planner)).name) }
        check.expect(names.isSuperset(of: busyNames), "종종걸음·두리번·깡충을 섞음", "\(names.sorted())")
    }

    private static func tossing(_ check: Checker) {
        check.section("오래 둔 알림: 구겨 던져 더미에")
        let (roster, world, pet) = setup()
        roster.announce(notice("c"))
        run(roster, in: world, seconds: 1)
        check.expect(pet.noticeTopic == "c" && roster.notices.crumples.isEmpty, "정한 시간 전에는 들고 있음")
        var tossed = false
        for _ in 0..<(4 * 60) {
            roster.step(dt: Sim.dt, in: world, cursor: nil)
            if pet.behavior is TossNoticeBehavior { tossed = true }
        }
        let ball = roster.notices.crumples.first
        check.expect(tossed && !pet.isShowingNotice && roster.notices.crumples.count == 1, "정한 시간이 지나면 던지는 동작 뒤 말풍선이 사라짐")
        check.expect(ball.map { !$0.isFlying && abs($0.position.y - 80) < 0.01
                         && abs($0.position.x - (NoticePileChecks.edge + $0.side / 2)) < 0.01 } == true,
                     "뭉치는 가까운 쪽(왼쪽) 바닥 끝에 놓임", "\(String(describing: ball?.position))")
        check.expect(roster.holds(topic: "c"), "더미에 있는 알림도 들고 있는 것으로 봄")
        check.expect(SceneComposer<String> { _ in nil }.compose([], notes: roster.notices.crumples).items.map(\.kind) == [.crumpledNotice],
                     "뭉치는 물건처럼 그림")
        check.expect(roster.hasItem(at: CGPoint(x: ball?.rect.midX ?? 0, y: ball?.rect.midY ?? 0)), "뭉치 위에서는 마우스를 받음")

        let (quietRoster, quietWorld, quietPet) = setup()
        quietRoster.isQuiet = true
        quietRoster.announce(notice("d"))
        run(quietRoster, in: quietWorld, seconds: 5)
        check.expect(quietPet.noticeTopic == "d" && quietRoster.notices.crumples.isEmpty, "통화 중에는 던지지 않음")

        let (offRoster, offWorld, offPet) = setup()
        offRoster.notices.isEnabled = false
        offRoster.announce(notice("e"))
        run(offRoster, in: offWorld, seconds: 5)
        check.expect(offPet.noticeTopic == "e" && offRoster.notices.crumples.isEmpty, "끄면 던지지 않음")

        let (awayRoster, awayWorld, awayPet) = setup()
        awayRoster.announce(notice("f"))
        run(awayRoster, in: awayWorld, seconds: 5, idle: Speech.presenceLimit + 1)
        check.expect(awayPet.noticeTopic == "f" && awayRoster.notices.crumples.isEmpty, "자리를 비운 동안에는 던지지 않음")

        let (eastRoster, eastWorld, _) = setup(x: 1300)
        eastRoster.announce(notice("g"))
        run(eastRoster, in: eastWorld, seconds: 5)
        let eastX = eastRoster.notices.crumples.first?.position.x ?? 0
        check.expect(eastX > Sim.main.visibleFrame.maxX - 40, "오른쪽 펫은 오른쪽 끝에 쌓음", "\(eastX)")
    }

    private static var edge: CGFloat { Sim.main.visibleFrame.minX + NoticePileCoordinator.edgeMargin }

    private static func reopening(_ check: Checker) {
        check.section("오래 둔 알림: 뭉치를 누르면 다시 띄움")
        let (roster, world, _) = setup()
        roster.announce(notice("h"))
        run(roster, in: world, seconds: 5)
        guard let ball = roster.notices.crumples.first else {
            check.expect(false, "뭉치가 있음")
            return
        }
        let clicked = roster.fetch(itemAt: CGPoint(x: ball.rect.midX, y: ball.rect.midY), in: world)
        roster.step(dt: Sim.dt, in: world, cursor: nil)
        let holder = roster.pets.first { $0.noticeTopic == "h" }
        check.expect(clicked && roster.notices.crumples.isEmpty && holder != nil, "누르면 더미에서 꺼내 펫이 다시 알림")
        check.expect((holder?.speech?.age ?? 99) < 0.1 && holder?.speech?.swell == 1, "다시 띄운 알림은 처음 크기부터")
        check.expect(!roster.fetch(itemAt: CGPoint(x: 1500, y: 600), in: world), "빈 곳을 누르면 아무 일 없음")
    }

    private static func withdrawing(_ check: Checker) {
        check.section("오래 둔 알림: 거둔 알림은 더미에서도 치움")
        let (roster, world, _) = setup()
        roster.announce(notice("i"))
        run(roster, in: world, seconds: 5)
        let piled = roster.notices.crumples.count == 1
        roster.withdraw(topic: "i")
        check.expect(piled && roster.notices.crumples.isEmpty && !roster.holds(topic: "i"), "거두면 뭉치도 사라짐")

        roster.announce(notice("j"))
        run(roster, in: world, seconds: 5)
        let again = roster.notices.crumples.count == 1
        roster.announce(ScheduleNotice(topic: "j", text: "지금 · 회의"))
        run(roster, in: world, seconds: 0.1)
        check.expect(again && roster.notices.crumples.isEmpty && roster.pets.first?.speech?.text == "지금 · 회의",
                     "같은 알림이 새 문구로 오면 뭉치 대신 새로 알림")
    }

    private static func holding(_ check: Checker) {
        check.section("오래 둔 알림: 던지기 전에 누르면 확인")
        let (roster, world, pet) = setup()
        roster.announce(notice("k"))
        var poked = false
        for _ in 0..<(5 * 60) {
            roster.step(dt: Sim.dt, in: world, cursor: nil)
            if !poked, pet.behavior is TossNoticeBehavior {
                pet.poke()
                poked = true
            }
        }
        check.expect(poked && roster.notices.crumples.isEmpty && !pet.isShowingNotice, "손을 놓기 전에 누르면 던지지 않고 확인으로 닫음")
    }

    private static func messenger(_ check: Checker) {
        check.section("오래 둔 알림: 전령은 던지고 떠남")
        let (roster, world, pet) = setup()
        roster.announce(notice("l"))
        roster.announce(notice("m"))
        run(roster, in: world, seconds: 0.1)
        let arrived = roster.messengers.count == 1 && pet.noticeTopic == "l"
        var left = false
        for _ in 0..<(20 * 60) {
            roster.step(dt: Sim.dt, in: world, cursor: nil)
            if roster.notices.crumples.count == 2 && roster.messengers.isEmpty {
                left = true
                break
            }
        }
        check.expect(arrived && left, "두 알림 모두 더미로, 전령은 할 일을 마치고 떠남",
                     "\(roster.notices.crumples.map(\.notice.topic)) messengers \(roster.messengers.count)")
    }

    private static func pileLimit(_ check: Checker) {
        check.section("오래 둔 알림: 더미 자리와 상한")
        let world = Sim.world()
        let spots = (0..<NoticePileCoordinator.maxPile).map {
            NoticePileCoordinator.spot($0, side: .west, on: Sim.main, scale: 1.5, in: world)
        }
        let ball: CGFloat = 12
        check.expect(spots[0].y == 80 && spots[3].y == 80 && spots[1].x - spots[0].x == ball,
                     "아랫줄 넷은 바닥에 한 칸씩", "\(spots.prefix(4))")
        check.expect(spots[4].y > 80 && spots[4].x == spots[0].x + ball / 2 && spots[9].y > spots[7].y,
                     "윗줄은 반 칸 안쪽으로 얹혀 위로 쌓임", "\(spots)")
        let east = NoticePileCoordinator.spot(0, side: .east, on: Sim.main, scale: 1.5, in: world)
        check.expect(east.x == Sim.main.visibleFrame.maxX - NoticePileCoordinator.edgeMargin - ball / 2, "오른쪽 더미는 오른쪽 끝에서", "\(east)")

        let (roster, simWorld, _) = setup()
        for index in 0...NoticePileCoordinator.maxPile {
            roster.announce(notice("p\(index)"))
            run(roster, in: simWorld, seconds: 4)
        }
        let topics = roster.notices.crumples.map(\.notice.topic)
        check.expect(topics.count == NoticePileCoordinator.maxPile && !topics.contains("p0") && topics.last == "p\(NoticePileCoordinator.maxPile)",
                     "더미가 차면 가장 오래된 뭉치를 치움", "\(topics)")
    }
}
