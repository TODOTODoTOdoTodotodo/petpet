import CoreGraphics
import Foundation

/// This object is responsible for checking what pets do when the user switches windows:
/// moving a grip to a same-height window, following to the new window without waiting,
/// turning to look, app-kind remarks, keeping quiet during calls and the work-rhythm nudges.
enum FocusChecks {
    static func run(_ check: Checker) {
        regripping(check)
        following(check)
        glancing(check)
        categories(check)
        quieting(check)
        rhythm(check)
        crossingDisplays(check)
        gatheringOnDisplay(check)
        visitingOften(check)
    }

    private static func roster(seed: UInt64) -> PetRoster {
        PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: seed)))
    }

    private static func restingPet(in roster: PetRoster, world: World, x: CGFloat, y: CGFloat = 80) -> Pet {
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

    private static func regripping(_ check: Checker) {
        check.section("창 갈아타기: 같은 높이 최대화 창")
        let first = Sim.window(8, 0, 80, 1600, 815)
        let world = Sim.world(windows: [first])
        let roster = Self.roster(seed: 41)
        let pet = restingPet(in: roster, world: world, x: 800)
        let other = restingPet(in: roster, world: world, x: 1500)
        world.focus(processID: 8)
        run(roster, in: world, seconds: 4, until: { pet.behavior is PeekBehavior || other.behavior is PeekBehavior })
        let peeker = pet.behavior is PeekBehavior ? pet : other
        let bystander = peeker === pet ? other : pet
        bystander.switchTo(IdleBehavior(duration: 999))
        check.expect(peeker.behavior is PeekBehavior && peeker.perchWindowID == 8, "최대화 창에서 빼꼼")

        // 30초 뒤 다른 최대화 창이 앞으로
        run(roster, in: world, seconds: SkillCoordinator.cooldown)
        peeker.switchTo(PeekBehavior(windowID: 8, offsetX: 700))
        bystander.switchTo(IdleBehavior(duration: 999))
        world.update(windows: [Sim.window(9, 0, 80, 1600, 815), first])
        world.focus(processID: 9)
        run(roster, in: world, seconds: 0.2)
        check.expect(peeker.behavior is PeekBehavior && peeker.perchWindowID == 9, "새 창 윗변으로 옮겨 가고 떨어지지 않음", peeker.behavior.name)
        check.expect(!(bystander.behavior is SkillLeapBehavior), "옮겨 잡은 펫이 있으니 다른 펫은 도약하지 않음", bystander.behavior.name)
    }

    private static func following(_ check: Checker) {
        check.section("창 갈아타기: 보던 창의 펫이 따라감")
        let windowA = Sim.window(7, 300, 300, 600, 300)   // top 600
        let world = Sim.world(windows: [windowA])
        let roster = Self.roster(seed: 42)
        let pet = restingPet(in: roster, world: world, x: 200)
        world.focus(processID: 7)
        run(roster, in: world, seconds: 5, until: { pet.support?.owner == .window(id: 7) && pet.behavior is IdleBehavior })
        check.expect(pet.support?.owner == .window(id: 7), "A 창에 올라섬")
        pet.switchTo(IdleBehavior(duration: 999))

        // 대기 시간 안에 더 높은 B 창으로 바꿈 (A의 펫 자리는 보임)
        let windowB = Sim.window(12, 700, 200, 600, 500)   // top 700
        world.update(windows: [windowB, windowA])
        world.focus(processID: 12)
        roster.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(pet.behavior is SkillLeapBehavior, "대기 시간과 상관없이 A에 있던 펫이 B로 따라감", pet.behavior.name)
        run(roster, in: world, seconds: 5, until: { pet.support?.owner == .window(id: 12) })
        check.expect(pet.support?.owner == .window(id: 12) && pet.position.y == 700, "B 창 위에 착지", "\(pet.position)")

        // 새 창이 펫 자리를 덮으면 떨어지는 순간 바로 건너뜀
        let covered = Self.roster(seed: 43)
        let world2 = Sim.world(windows: [windowA])
        let rider = restingPet(in: covered, world: world2, x: 400, y: 600)
        world2.focus(processID: 7)
        run(covered, in: world2, seconds: 0.5)
        rider.switchTo(IdleBehavior(duration: 999))
        let cover = Sim.window(13, 200, 100, 500, 650)   // top 750, 펫 자리(x 400)를 덮음
        world2.update(windows: [cover, windowA])
        world2.focus(processID: 13)
        covered.step(dt: Sim.dt, in: world2, cursor: nil)
        check.expect(rider.behavior is SkillLeapBehavior, "발판이 가려져도 떨어지지 않고 새 창으로 도약", rider.behavior.name)
        run(covered, in: world2, seconds: 5, until: { rider.support?.owner == .window(id: 13) })
        check.expect(rider.support?.owner == .window(id: 13), "덮은 창 위에 착지", "\(rider.position) \(rider.behavior.name)")
    }

    private static func glancing(_ check: Checker) {
        check.section("다른 펫들이 돌아봄")
        let chat = WindowSnapshot(id: 20, owner: "Slack", frame: CGRect(x: 1000, y: 300, width: 500, height: 400), processID: 20)
        let player = WindowSnapshot(id: 21, owner: "IINA", frame: CGRect(x: 100, y: 300, width: 500, height: 400), processID: 21)
        let world = Sim.world(windows: [chat, player])
        let roster = Self.roster(seed: 44)
        roster.skills.isEnabled = false
        let near = restingPet(in: roster, world: world, x: 900)
        let far = restingPet(in: roster, world: world, x: 300)
        near.facing = .west
        far.facing = .west

        world.focus(processID: 20, bundleID: "com.tinyspeck.slackmacgap")
        roster.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(near.behavior is GlanceBehavior && far.behavior is GlanceBehavior, "쉬던 펫들이 새 창 쪽을 돌아봄")
        check.expect(near.facing == .east && far.facing == .east, "새 창이 있는 오른쪽을 봄")
        check.expect(near.speech?.text == "💬" && far.speech == nil, "가까운 펫만 메신저에 💬", "\(String(describing: near.speech?.text))")

        run(roster, in: world, seconds: 3)
        near.clearSpeech()
        near.switchTo(IdleBehavior(duration: 999))
        far.switchTo(IdleBehavior(duration: 999))
        world.focus(processID: 21, bundleID: "com.colliderli.iina")
        roster.step(dt: Sim.dt, in: world, cursor: nil)
        let watcher = [near, far].first { $0.behavior.name == "watching" }
        check.expect(watcher === far && far.speech?.text == "🍿", "영상 앱은 가까운 펫이 🍿 구경", "\(near.behavior.name) \(far.behavior.name)")

        run(roster, in: world, seconds: 1)
        near.switchTo(IdleBehavior(duration: 999))
        world.focus(processID: 20, bundleID: "com.tinyspeck.slackmacgap")
        roster.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(near.speech?.text != "💬", "같은 종류 앱은 1분 안에 다시 말하지 않음")
        check.expect(near.behavior is IdleBehavior, "15초 안에는 다시 돌아보지 않음", near.behavior.name)

        // 혼자일 때는 도약한 펫이 말함
        let solo = Self.roster(seed: 45)
        let world2 = Sim.world(windows: [Sim.window(7, 300, 300, 600, 300)])
        let jumper = restingPet(in: solo, world: world2, x: 200)
        world2.focus(processID: 7, bundleID: "com.apple.dt.Xcode")
        solo.step(dt: Sim.dt, in: world2, cursor: nil)
        check.expect(jumper.behavior is SkillLeapBehavior && jumper.speech?.text == "⌨️", "도약한 펫이 앱 종류 한마디")
    }

    private static func categories(_ check: Checker) {
        check.section("앱 종류 규칙표")
        check.expect(AppCategory(bundleID: "com.microsoft.teams2") == .chat, "Teams는 메신저")
        check.expect(AppCategory(bundleID: "com.jetbrains.intellij") == .code, "JetBrains 계열은 접두사로 개발 도구")
        check.expect(AppCategory(bundleID: "com.apple.mail") == .mail, "메일")
        check.expect(AppCategory(bundleID: "com.apple.mailx") == .other, "비슷한 이름은 정확히 같아야 함")
        check.expect(AppCategory(bundleID: nil) == .other && AppCategory.other.remark == nil, "모르는 앱은 말 없음")
    }

    private static func quieting(_ check: Checker) {
        check.section("통화 중 조용히")
        let world = Sim.world(windows: [Sim.window(7, 300, 300, 600, 300)])
        let roster = Self.roster(seed: 46)
        roster.isQuiet = true
        let pet = restingPet(in: roster, world: world, x: 200)
        let friend = restingPet(in: roster, world: world, x: 230)
        world.focus(processID: 7, bundleID: "com.tinyspeck.slackmacgap")
        roster.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(!(pet.behavior is SkillLeapBehavior) && !(friend.behavior is SkillLeapBehavior), "통화 중엔 도약하지 않음")
        check.expect(pet.speech == nil && friend.speech == nil, "통화 중엔 인사·한마디 없음", "\(String(describing: pet.speech))")

        let announcer = ScheduleAnnouncer()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let item = ScheduleItem(id: "q1", title: "1:1 면담", start: start, kind: .event, isAllDay: false)
        guard let notice = announcer.announcements(for: [item], at: start.addingTimeInterval(1)).first else {
            check.expect(false, "일정 알림 생성")
            return
        }
        pet.announce(notice)
        check.expect(pet.speech?.text == "지금 · 1:1 면담" && pet.speech?.discreet.text == "지금 일정",
                     "통화 중엔 일정 말풍선이 제목 없이 보임", "\(String(describing: pet.speech?.discreet.text))")
        check.expect(pet.speech?.discreet.kind == .notice, "제목만 숨기고 확인 전까지 유지")
    }

    private static func rhythm(_ check: Checker) {
        check.section("작업 리듬 (켰을 때만)")
        let world = Sim.world()
        let roster = Self.roster(seed: 47)
        let pet = restingPet(in: roster, world: world, x: 500)
        let rhythm = WorkRhythmCoordinator()

        for _ in 0..<Int(WorkRhythmCoordinator.breakAfter) {
            rhythm.step(dt: 1, pets: [pet], idleSeconds: 0, shift: nil)
        }
        check.expect(pet.speech == nil, "기본은 꺼져 있음")

        rhythm.isEnabled = true
        for _ in 0..<Int(WorkRhythmCoordinator.breakAfter - 60) {
            rhythm.step(dt: 1, pets: [pet], idleSeconds: 2, shift: nil)
        }
        rhythm.step(dt: 1, pets: [pet], idleSeconds: WorkRhythmCoordinator.restResets, shift: nil)
        for _ in 0..<120 {
            rhythm.step(dt: 1, pets: [pet], idleSeconds: 2, shift: nil)
        }
        check.expect(pet.speech == nil, "5분 쉬면 처음부터 다시 셈")
        for _ in 0..<Int(WorkRhythmCoordinator.breakAfter) {
            rhythm.step(dt: 1, pets: [pet], idleSeconds: 2, shift: nil)
        }
        check.expect(pet.speech?.text == WorkRhythmCoordinator.stretchText, "50분 쉬지 않으면 기지개 권유")

        pet.clearSpeech()
        let shift = FocusShift(from: 1, to: 2, frame: .zero, category: .other)
        for _ in 0..<5 {
            rhythm.step(dt: 2, pets: [pet], idleSeconds: 0, shift: shift)
        }
        check.expect(pet.speech == nil, "창을 5번 바꾼 정도는 그냥 둠")
        rhythm.step(dt: 2, pets: [pet], idleSeconds: 0, shift: shift)
        check.expect(pet.speech?.text == WorkRhythmCoordinator.dizzyText, "20초 안에 6번 바꾸면 😵")
    }

    private static func crossingDisplays(_ check: Checker) {
        check.section("모니터 건너가기")
        let upper = ScreenArea(id: 2, name: "Upper", frame: CGRect(x: 0, y: 1000, width: 1600, height: 900),
                               visibleFrame: CGRect(x: 0, y: 1000, width: 1600, height: 875), backingScale: 2)
        let upperWindow = Sim.window(30, 0, 1000, 1600, 875)   // 위 모니터 최대화, top 1875
        let mainWindow = Sim.window(31, 0, 80, 1600, 815)      // 아래 모니터 최대화, top 895
        let world = Sim.world(screens: [Sim.main, upper], windows: [upperWindow, mainWindow])
        let roster = Self.roster(seed: 48)
        let pet = restingPet(in: roster, world: world, x: 800)
        check.expect(LeapPlanner.plan(for: pet, to: 30, in: world) == nil, "메뉴바가 천장이라 위 모니터 창으로 바로 도약하지 못함")

        world.focus(processID: 30)
        roster.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(pet.behavior is ScreenHopBehavior, "그 모니터에 펫이 없으면 건너가기 시작", pet.behavior.name)
        run(roster, in: world, seconds: ScreenHopBehavior.fadeOut + 0.1)
        check.expect(pet.opacity == 0 && roster.pet(at: CGPoint(x: 800, y: 100)) == nil, "건너가는 동안은 사라지고 잡히지 않음")
        run(roster, in: world, seconds: 0.3)
        check.expect(pet.support?.owner == .ground(screenID: 2) && pet.position.y == 1000, "위 모니터 바닥에 나타남", "\(pet.position)")
        run(roster, in: world, seconds: 6, until: { pet.behavior is PeekBehavior })
        check.expect(pet.perchWindowID == 30 && pet.opacity == 1, "이어서 스킬로 위 모니터 창에서 빼꼼", pet.behavior.name)

        // 바로 아래 모니터 창으로 바꾸면, 아래에 기본 펫이 없으니 대기 없이 따라 내려감
        world.focus(processID: 31)
        roster.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(pet.behavior is ScreenHopBehavior, "보던 창의 펫은 대기 시간 없이 다른 모니터로 따라감", pet.behavior.name)
        run(roster, in: world, seconds: 6, until: { pet.perchWindowID == 31 })
        check.expect(pet.perchWindowID == 31, "아래 모니터 창에서 빼꼼", "\(pet.position) \(pet.behavior.name)")

        // 그 모니터에 이미 기본 펫이 있으면 건너가지 않음
        let shared = Self.roster(seed: 49)
        let world2 = Sim.world(screens: [Sim.main, upper], windows: [upperWindow, mainWindow])
        let below = restingPet(in: shared, world: world2, x: 800)
        let above = restingPet(in: shared, world: world2, x: 300, y: 1000)
        above.switchTo(WalkBehavior(direction: .east, duration: 999))
        world2.focus(processID: 30)
        shared.step(dt: Sim.dt, in: world2, cursor: nil)
        check.expect(!(below.behavior is ScreenHopBehavior), "그 모니터에 펫이 있으면 건너가지 않음", below.behavior.name)
    }

    private static func gatheringOnDisplay(_ check: Checker) {
        check.section("나머지 펫도 보는 모니터로")
        let upper = ScreenArea(id: 2, name: "Upper", frame: CGRect(x: 0, y: 1000, width: 1600, height: 900),
                               visibleFrame: CGRect(x: 0, y: 1000, width: 1600, height: 875), backingScale: 2)
        let world = Sim.world(screens: [Sim.main, upper], windows: [Sim.window(30, 200, 1100, 1000, 500)])
        let roster = Self.roster(seed: 50)
        let pets = [300, 700, 1100, 1400].map { restingPet(in: roster, world: world, x: CGFloat($0)) }
        let onUpper = { pets.filter { world.screen(containing: CGPoint(x: $0.position.x, y: $0.position.y + 1))?.id == 2 }.count }

        world.focus(processID: 30)
        var hops: [Double] = []
        var time = 0.0
        var seen = Set<String>()
        while time < 40 {
            roster.step(dt: Sim.dt, in: world, cursor: nil)
            time += Sim.dt
            for pet in pets where pet.behavior is ScreenHopBehavior && !seen.contains(pet.id) {
                seen.insert(pet.id)
                hops.append(time)
            }
        }
        check.expect(onUpper() == 4, "40초 안에 펫 4마리가 모두 위 모니터로 옴", "\(onUpper())")
        check.expect(hops.count == 4 && hops[0] < 0.1, "첫 펫은 바로 건너감 (스킬)", "\(hops)")
        let gaps = zip(hops.dropFirst(), hops.dropFirst(2)).map { $1 - $0 }
        check.expect(hops.count == 4 && hops[1] >= DisplayFollowCoordinator.settleDelay - 0.1
                        && gaps.allSatisfy { $0 >= DisplayFollowCoordinator.interval - 0.1 },
                     "나머지는 5초 머문 뒤 8초 간격으로 한 마리씩", "\(hops.map { String(format: "%.1f", $0) })")
        let xs = pets.filter { $0.support?.owner == .ground(screenID: 2) }.map(\.position.x).sorted()
        check.expect(zip(xs, xs.dropFirst()).allSatisfy { $1 - $0 >= 40 }, "나타난 펫끼리 겹치지 않게 벌려 섬", "\(xs)")

        // 잠깐 들른 모니터로는 옮기지 않음
        let brief = Self.roster(seed: 51)
        let world2 = Sim.world(screens: [Sim.main, upper], windows: [Sim.window(30, 200, 1100, 1000, 500), Sim.window(31, 300, 300, 600, 300)])
        brief.skills.isEnabled = false
        let stay = [400, 900].map { restingPet(in: brief, world: world2, x: CGFloat($0)) }
        world2.focus(processID: 30)
        for _ in 0..<Int(3 * 60) { brief.step(dt: Sim.dt, in: world2, cursor: nil) }
        world2.focus(processID: 31)
        for _ in 0..<Int(10 * 60) { brief.step(dt: Sim.dt, in: world2, cursor: nil) }
        check.expect(stay.allSatisfy { $0.position.y < 1000 }, "3초만 본 모니터로는 따라가지 않음")

        let off = Self.roster(seed: 52)
        off.follow.isEnabled = false
        off.skills.isEnabled = false
        let world3 = Sim.world(screens: [Sim.main, upper], windows: [Sim.window(30, 200, 1100, 1000, 500)])
        let lazy = restingPet(in: off, world: world3, x: 500)
        world3.focus(processID: 30)
        for _ in 0..<Int(20 * 60) { off.step(dt: Sim.dt, in: world3, cursor: nil) }
        check.expect(lazy.position.y < 1000, "메뉴에서 끄면 따라가지 않음")

        // 전령은 보고 있는 모니터에 나타남
        let messengers = Self.roster(seed: 53)
        let world4 = Sim.world(screens: [Sim.main, upper], windows: [Sim.window(30, 200, 1100, 1000, 500)])
        messengers.skills.isEnabled = false
        messengers.follow.isEnabled = false
        messengers.messengerLook = { FakeAppearance() }
        let holder = restingPet(in: messengers, world: world4, x: 500)
        world4.focus(processID: 30)
        messengers.step(dt: Sim.dt, in: world4, cursor: nil)
        holder.announce(ScheduleNotice(topic: "a", text: "일정 a"))
        messengers.announce(ScheduleNotice(topic: "b", text: "일정 b"))
        messengers.step(dt: Sim.dt, in: world4, cursor: nil)
        let messenger = messengers.messengers.first
        check.expect(messenger.map { world4.screen(containing: $0.position)?.id == 2 } == true,
                     "전령 펫은 보고 있는 모니터에서 나타남", "\(String(describing: messenger?.position))")
    }

    private static func visitingOften(_ check: Checker) {
        check.section("보고 있는 창 자주 찾아가기")
        let world = Sim.world(windows: [Sim.window(7, 300, 300, 600, 300)])   // top 600, 올라설 자리 있음
        let planner = BehaviorPlanner(random: SeededRandomSource(seed: 60))
        let pet = Sim.pet(at: CGPoint(x: 200, y: 80), behavior: IdleBehavior(duration: 999))
        pet.settle(in: world)
        var context = PetContext(cursor: nil, planner: planner)
        let leaps = { (context: PetContext) in
            (0..<400).map { _ in planner.next(after: pet, in: world, context: context) }.filter { $0 is SkillLeapBehavior }.count
        }
        check.expect(leaps(context) == 0, "보는 창이 없으면 도약 선택지 없음")
        context.skillTarget = 7
        let share = leaps(context)
        check.expect((40...140).contains(share), "보는 창이 있으면 다음 행동의 약 2할이 그 창으로 스킬 도약", "\(share)/400")
        context.visitorsOnTarget = BehaviorPlanner.maxVisitors
        check.expect(leaps(context) == 0, "그 창에 이미 3마리면 더 가지 않음")

        let roster = Self.roster(seed: 61)
        let walker = restingPet(in: roster, world: world, x: 200)
        world.focus(processID: 7)
        var visits = 0
        var wasLeaping = false
        for _ in 0..<Int(120 * 60) {
            roster.step(dt: Sim.dt, in: world, cursor: nil)
            let leaping = walker.behavior is SkillLeapBehavior
            if leaping && !wasLeaping { visits += 1 }
            wasLeaping = leaping
        }
        check.expect(visits >= 3, "2분 동안 창이 바뀌지 않아도 여러 번 다시 올라감 (30초 대기와 무관)", "\(visits)")

        let quiet = Self.roster(seed: 62)
        quiet.isQuiet = true
        let hush = restingPet(in: quiet, world: world, x: 200)
        var hushLeaps = 0
        for _ in 0..<Int(60 * 60) {
            quiet.step(dt: Sim.dt, in: world, cursor: nil)
            if hush.behavior is SkillLeapBehavior { hushLeaps += 1 }
        }
        check.expect(hushLeaps == 0, "통화 중에는 찾아가지 않음")
    }
}
