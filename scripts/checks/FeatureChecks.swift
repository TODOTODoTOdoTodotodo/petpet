import CoreGraphics
import Foundation

/// This object is responsible for a fixed list of schedule items used by checks.
final class FakeSchedule: ScheduleSource {
    var items: [ScheduleItem] = []
    func items(from start: Date, to end: Date) -> [ScheduleItem] {
        items.filter { $0.start >= start && $0.start <= end }
    }
}

/// This object is responsible for checking the added features: sleeping, click reactions,
/// pets greeting each other, and schedule speech bubbles.
enum FeatureChecks {
    static func run(_ check: Checker) {
        sleeping(check)
        poking(check)
        socializing(check)
        scheduling(check)
        lineup(check)
    }

    /// 이름만 다른 겉모습 (캐릭터 교체 확인용)
    private final class NamedAppearance: PetAppearance {
        let name: String
        let body = BodyMetrics(footInset: 0, width: 24, height: 40, centerX: 24)
        let skillStyle: SkillStyle = .bigJump
        init(_ name: String) { self.name = name }
        func supports(_ kind: AnimationKind) -> Bool { kind != .act }
        func cycleDuration(of kind: AnimationKind, facing: Facing) -> TimeInterval { 0 }
    }

    private static func lineup(_ check: Checker) {
        check.section("펫마다 캐릭터")
        let world = Sim.world()
        let roster = PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: 80)))
        let first = roster.add(appearance: NamedAppearance("Bolt"), scale: 1.5, in: world)
        let second = roster.add(appearance: NamedAppearance("Bolt"), scale: 1.5, in: world)
        roster.restyle(second, as: NamedAppearance("Nabi"))
        check.expect(first.appearance.name == "Bolt" && second.appearance.name == "Nabi", "한 마리만 다른 캐릭터로 바꿈")
        check.expect(roster.pet(withID: second.id) === second, "메뉴에서 아이디로 펫을 찾음")

        check.expect(roster.remove(first) && roster.residents.map(\.id) == [second.id], "고른 펫을 뺌")
        check.expect(!roster.remove(second) && roster.residents.count == 1, "마지막 한 마리는 빼지 않음")

        roster.restyle(NamedAppearance("Goblin"))
        check.expect(roster.residents.allSatisfy { $0.appearance.name == "Goblin" }, "전체 바꾸기도 그대로 됨")
    }

    private static func groundedPet(in world: World, x: CGFloat = 800, appearance: PetAppearance = FakeAppearance(),
                                    behavior: PetBehavior = IdleBehavior(duration: 999)) -> Pet {
        let pet = Sim.pet(at: CGPoint(x: x, y: 80), appearance: appearance, behavior: behavior)
        pet.settle(in: world)
        return pet
    }

    private static func sleeping(_ check: Checker) {
        check.section("잠들기")
        let world = Sim.world()
        let planner = BehaviorPlanner(random: SeededRandomSource(seed: 11))
        let pet = groundedPet(in: world, behavior: IdleBehavior(duration: 0.1))

        Sim.run(pet, in: world, planner: planner, seconds: 0.5, idleSeconds: 60)
        check.expect(!(pet.behavior is SleepBehavior), "입력이 최근이면 자지 않음", pet.behavior.name)

        pet.switchTo(IdleBehavior(duration: 0.1))
        Sim.run(pet, in: world, planner: planner, seconds: 0.5, idleSeconds: 400)
        check.expect(pet.behavior is SleepBehavior && pet.effect == .breathing, "3분 넘게 입력이 없으면 잠듦", pet.behavior.name)
        check.expect(pet.speech?.text == Chatter.drowsy, "처음엔 졸음 말풍선(…)", "\(String(describing: pet.speech))")

        Sim.run(pet, in: world, planner: planner, seconds: 8, idleSeconds: 400)
        check.expect(pet.speech?.text == Chatter.asleep, "조금 지나면 Zzz", "\(String(describing: pet.speech))")

        let names = Sim.run(pet, in: world, planner: planner, seconds: Sim.dt * 2, idleSeconds: 0.2)
        check.expect(names.contains("waking") && pet.speech?.text == Chatter.surprised, "입력이 생기면 깜짝 깨어남", "\(names)")
    }

    private static func poking(_ check: Checker) {
        check.section("클릭 반응")
        let world = Sim.world()
        let planner = BehaviorPlanner(random: SeededRandomSource(seed: 12))

        let pet = groundedPet(in: world)
        pet.poke()
        check.expect(pet.behavior.name == "hopping" && pet.speech?.text == Chatter.love, "한 번 클릭하면 깡충 + ♥", pet.behavior.name)
        Sim.run(pet, in: world, planner: planner, seconds: 1, until: { $0.behavior is IdleBehavior })
        pet.poke()
        Sim.run(pet, in: world, planner: planner, seconds: 1, until: { $0.behavior is IdleBehavior })
        pet.poke()
        check.expect(pet.behavior.name == "fleeing" && pet.speech?.text == Chatter.annoyed, "연달아 3번이면 💢 + 도망", pet.behavior.name)

        Sim.run(pet, in: world, planner: planner, seconds: 4)
        let calm = groundedPet(in: world)
        Sim.run(calm, in: world, planner: planner, seconds: 3)
        calm.switchTo(IdleBehavior(duration: 999))
        calm.poke()
        check.expect(calm.behavior.name == "hopping", "시간이 지나면 연속 클릭 수가 초기화됨", calm.behavior.name)

        let sleeper = groundedPet(in: world, behavior: SleepBehavior())
        sleeper.poke()
        check.expect(sleeper.behavior.name == "waking", "자는 펫을 클릭하면 깸", sleeper.behavior.name)

        let flyer = Sim.pet(at: CGPoint(x: 800, y: 600), behavior: AirborneBehavior.falling())
        flyer.poke()
        check.expect(flyer.behavior.name == "falling" && flyer.speech?.text == Chatter.love, "공중에서는 ♥만", flyer.behavior.name)

        let reader = groundedPet(in: world)
        reader.announce(ScheduleNotice(topic: "m", text: "지금 · 회의"))
        reader.poke()
        check.expect(reader.speech == nil && reader.behavior.name == "announcing", "알림이 떠 있으면 클릭은 말풍선만 닫음", reader.behavior.name)
    }

    private static func socializing(_ check: Checker) {
        check.section("펫끼리 어울리기")
        let world = Sim.world()
        let roster = PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: 15)))
        let first = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        let second = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        first.position = CGPoint(x: 700, y: 80)
        second.position = CGPoint(x: 740, y: 80)
        first.settle(in: world)
        second.settle(in: world)
        first.switchTo(IdleBehavior(duration: 999))
        second.switchTo(IdleBehavior(duration: 999))

        roster.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(first.behavior.name == "greeting" && second.behavior.name == "greeting", "가까이 있으면 서로 인사")
        check.expect(first.facing == .east && second.facing == .west && first.speech?.text == Chatter.hello, "서로 마주 보고 👋")

        for _ in 0..<120 { roster.step(dt: Sim.dt, in: world, cursor: nil) }
        first.switchTo(IdleBehavior(duration: 999))
        second.switchTo(IdleBehavior(duration: 999))
        first.position.x = 700
        second.position.x = 740
        roster.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(first.behavior.name != "greeting", "같은 짝은 20초 안에 다시 인사하지 않음", first.behavior.name)

        let planner = BehaviorPlanner(random: SeededRandomSource(seed: 14))
        let loner = groundedPet(in: world, x: 300)
        var context = PetContext(cursor: nil, planner: planner)
        context.friends = [FriendSighting(id: "Friend", position: CGPoint(x: 700, y: 80))]
        let choices = (0..<300).map { _ in planner.next(after: loner, in: world, context: context) }
        check.expect(choices.contains { $0.name == "followingFriend" }, "멀리 있는 친구를 따라가기도 함")
    }

    private static func scheduling(_ check: Checker) {
        check.section("일정 말풍선")
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let meeting = ScheduleItem(id: "m1", title: "주간 회의", start: base.addingTimeInterval(600), kind: .event, isAllDay: false)
        let holiday = ScheduleItem(id: "h1", title: "휴가", start: base.addingTimeInterval(600), kind: .event, isAllDay: true)
        let report = ScheduleItem(id: "r1", title: "보고서 제출", start: base.addingTimeInterval(1200), kind: .reminder, isAllDay: false)
        let items = [meeting, holiday, report]

        let announcer = ScheduleAnnouncer()
        let texts = { (at: TimeInterval) in announcer.announcements(for: items, at: base.addingTimeInterval(at)).map(\.text) }
        check.expect(texts(-30).isEmpty, "10분 전 시점 이전엔 말 없음")
        let soon = announcer.announcements(for: items, at: base.addingTimeInterval(5))
        check.expect(soon == [ScheduleNotice(topic: "m1", text: "10분 뒤 · 주간 회의", discreetText: "10분 뒤 일정")],
                     "10분 전 알림, 종일 일정 제외 (제목 없는 문구도 함께)", "\(soon)")
        check.expect(texts(35).isEmpty, "같은 시점은 한 번만")
        check.expect(texts(610) == ["지금 · 주간 회의"], "시작 시각 알림")
        check.expect(texts(1210) == ["할 일 · 보고서 제출"], "미리 알림 마감 알림")

        let late = ScheduleAnnouncer()
        check.expect(late.announcements(for: items, at: base.addingTimeInterval(200)).isEmpty, "90초 넘게 지난 시점은 몰아서 말하지 않음")

        let hidden = ScheduleAnnouncer()
        hidden.hidesTitles = true
        check.expect(hidden.announcements(for: items, at: base.addingTimeInterval(5)).map(\.text) == ["10분 뒤 일정"], "제목 숨김")

        check.expect(ScheduleAnnouncer.shorten(String(repeating: "가", count: 30)).count == 25, "긴 제목은 24자 + …")
        messengers(check, base: base, meeting: meeting)
    }

    /// 알림은 확인할 때까지 유지, 일정마다 펫 한 마리(바쁘면 전령), 같은 일정은 같은 펫
    private static func messengers(_ check: Checker, base: Date, meeting: ScheduleItem) {
        check.section("일정마다 펫 한 마리")
        let world = Sim.world()
        let roster = PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: 15)))
        let looks = [FakeAppearance(), FakeAppearance(hasAction: true)]
        var lookIndex = 0
        roster.messengerLook = { defer { lookIndex += 1 }; return looks[lookIndex % looks.count] }
        let resident = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        let step = { (seconds: Double) in for _ in 0..<Int(seconds * 60) { roster.step(dt: Sim.dt, in: world, cursor: nil) } }
        step(2)

        let lunch = ScheduleItem(id: "m2", title: "점심", start: base.addingTimeInterval(600), kind: .event, isAllDay: false)
        let review = ScheduleItem(id: "m3", title: "리뷰", start: base.addingTimeInterval(600), kind: .event, isAllDay: false)
        let schedule = FakeSchedule()
        schedule.items = [meeting, lunch, review]
        let announcer = ScheduleAnnouncer()
        let watcher = ScheduleWatcher(source: schedule, announcer: announcer) { roster.announce($0) }
        watcher.start()
        watcher.check(at: base.addingTimeInterval(5))
        step(Sim.dt)

        let holders = roster.pets.filter(\.isShowingNotice)
        check.expect(holders.count == 3 && roster.messengers.count == 2, "일정 3개면 기본 펫 1 + 전령 2가 하나씩 맡음",
                     "holders=\(holders.count) messengers=\(roster.messengers.count)")
        check.expect(Set(holders.compactMap(\.noticeTopic)) == ["m1", "m2", "m3"], "각자 다른 일정")
        check.expect(roster.messengers.first?.appearance !== roster.messengers.last?.appearance, "전령은 스킨을 돌아가며 씀")

        step(60)
        check.expect(roster.pets.filter(\.isShowingNotice).count == 3, "확인 전까지 1분이 지나도 계속 말함")

        // 시작 시각이 되면 같은 펫이 문구만 바꿈
        watcher.check(at: base.addingTimeInterval(605))
        step(Sim.dt)
        check.expect(roster.pets.count == 3 && resident.speech?.text == "지금 · 주간 회의",
                     "같은 일정의 다음 알림은 같은 펫이 이어서 말함", "\(roster.pets.count) \(String(describing: resident.speech))")

        // 전령을 클릭해 확인하면 인사하고 떠남, 기본 펫은 남음
        guard let messenger = roster.messengers.first else { return }
        messenger.poke()
        check.expect(messenger.speech?.text == Chatter.hello, "확인하면 전령이 👋")
        step(2)
        check.expect(!roster.pets.contains { $0 === messenger } && roster.messengers.count == 1, "인사 후 전령은 사라짐")
        resident.poke()
        step(2)
        check.expect(roster.pets.contains { $0 === resident } && !resident.isShowingNotice, "기본 펫은 확인 후에도 남음")
        resident.say(Chatter.love)
        check.expect(resident.speech?.kind == .chatter, "확인 뒤엔 다시 잡담 가능")
        roster.messengers.first?.say(Chatter.love)
        check.expect(roster.messengers.first?.speech?.kind == .notice, "알림은 잡담이 덮어쓰지 못함")
        watcher.stop()

        // 전령이 꽉 차면 줄을 서고, 자리가 나면 나옴
        let crowd = PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: 16)))
        crowd.messengerLook = { FakeAppearance() }
        crowd.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        (0..<7).forEach { crowd.announce(ScheduleNotice(topic: "t\($0)", text: "일정 \($0)")) }
        crowd.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(crowd.messengers.count == PetRoster.maxMessengers && crowd.pendingNotices.count == 2,
                     "전령은 최대 4, 나머지는 대기", "\(crowd.messengers.count) pending=\(crowd.pendingNotices.count)")
        crowd.messengers.first?.poke()
        for _ in 0..<120 { crowd.step(dt: Sim.dt, in: world, cursor: nil) }
        check.expect(crowd.messengers.count == PetRoster.maxMessengers && crowd.pendingNotices.count == 1, "전령이 떠나면 다음 알림이 나옴")

        // 메뉴 동작은 기본 펫만
        crowd.removeLast()
        check.expect(crowd.residents.count == 1 && crowd.messengers.count == PetRoster.maxMessengers,
                     "펫 삭제는 기본 펫만, 마지막 한 마리는 남김")
    }
}
