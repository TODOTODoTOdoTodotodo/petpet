import Foundation

/// This object is responsible for checking AI agent signals: reading only the allowed fields from a signal file,
/// the inbox taking fresh files in order and dropping stale or oversized ones, and the pets' bubbles with the app icon —
/// done → ✅ and a trip to the app's Dock icon (knocking on it) or window, or a hop in place, waiting → ✋ held until
/// poked, the session moves on, or the user returns to that app — and a click on such a pet bringing the app forward.
enum AgentSignalChecks {
    static func run(_ check: Checker) {
        parsing(check)
        inbox(check)
        done(check)
        waiting(check)
        returningToApp(check)
        messenger(check)
        dockVisit(check)
        bringForward(check)
    }

    private static let badge = SpeechBadge(id: "app.check", pixels: SpritePixels(width: 1, height: 1, rgba: [255, 0, 0, 255]))
    private static let host = AgentHost(processID: 7, badge: badge)

    private static func signal(_ kind: AgentSignal.Kind, pid: Int32 = 4242) -> AgentSignal {
        AgentSignal(kind: kind, source: "claude", processID: pid)
    }

    private static func setup(seed: UInt64) -> (PetRoster, World, Pet) {
        let world = Sim.world(windows: [Sim.window(7, 300, 300, 600, 300), Sim.window(9, 1000, 300, 400, 250)])
        world.focus(processID: 9)
        let roster = PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: seed)))
        // 보는 창으로 뛰는 스킬 도약은 이 검사와 무관해서 끔
        roster.skills.isEnabled = false
        let pet = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        pet.position = CGPoint(x: 150, y: 80)
        pet.settle(in: world)
        // 처음 본 창에 돌아보는 반응이 지나간 뒤 쉬는 상태에서 시작
        run(roster, in: world, seconds: 1)
        pet.switchTo(IdleBehavior(duration: 30))
        return (roster, world, pet)
    }

    private static func run(_ roster: PetRoster, in world: World, seconds: Double) {
        for _ in 0..<max(Int(seconds * 60), 1) { roster.step(dt: Sim.dt, in: world, cursor: nil) }
    }

    private static func parsing(_ check: Checker) {
        check.section("AI 신호: 파일 읽기")
        let json = #"{"kind":"Done","source":"Claude Code!","pid":1234,"message":"비밀","cwd":"/x"}"#
        let parsed = AgentSignal.parse(Data(json.utf8))
        check.expect(parsed == AgentSignal(kind: .done, source: "claudecode", processID: 1234),
                     "kind·source·pid만 읽고 이름은 영문 소문자로 (다른 칸 무시)", "\(String(describing: parsed))")
        check.expect(parsed?.sessionTopic == "agent:claudecode:1234", "세션 이름은 도구와 프로세스로")
        check.expect(AgentSignal.parse(Data(#"{"kind":"dance"}"#.utf8)) == nil, "모르는 kind는 버림")
        check.expect(AgentSignal.parse(Data("not json".utf8)) == nil, "JSON이 아니면 버림")
        let bare = AgentSignal.parse(Data(#"{"kind":"waiting","pid":-3}"#.utf8))
        check.expect(bare == AgentSignal(kind: .waiting, source: "agent", processID: nil), "이름 없으면 agent, 잘못된 pid는 없음", "\(String(describing: bare))")
        let huge = Data((#"{"kind":"done","pad":""# + String(repeating: "x", count: AgentSignal.maxBytes) + #""}"#).utf8)
        check.expect(AgentSignal.parse(huge) == nil, "너무 큰 파일은 읽지 않음")
        check.expect(AgentSignal.Kind.allCases.map(\.rawValue) == ["working", "done", "waiting", "limit"], "신호 종류 넷")
    }

    private static func inbox(_ check: Checker) {
        check.section("AI 신호: 받은 편지함 폴더")
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent("deskpet-signals-\(UUID().uuidString)", isDirectory: true)
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: folder) }
        let now = Date()
        func put(_ name: String, _ text: String, age: TimeInterval) {
            let url = folder.appendingPathComponent(name)
            try? Data(text.utf8).write(to: url)
            try? manager.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
        }
        put("b.json", #"{"kind":"done","source":"claude","pid":2}"#, age: 5)
        put("a.json", #"{"kind":"waiting","source":"claude","pid":1}"#, age: 10)
        put("old.json", #"{"kind":"done","source":"claude","pid":3}"#, age: AgentSignal.maxAge + 30)
        put("big.json", String(repeating: " ", count: AgentSignal.maxBytes + 1), age: 1)
        put("bad.json", "{", age: 1)
        put(".writing", #"{"kind":"done"}"#, age: 1)
        put("note.txt", "hello", age: 1)

        let inbox = AgentSignalInbox(folder: folder)
        var received: [AgentSignal] = []
        inbox.onSignal = { received.append($0) }
        inbox.check(now: now)
        check.expect(received.map(\.processID) == [1, 2], "새 신호만 오래된 순서로 받음 (오래된·큰·깨진 파일 제외)", "\(received)")
        let left = ((try? manager.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        check.expect(left == [".writing", "note.txt"], "읽은·버린 .json은 지우고, 쓰는 중인 파일은 둠", "\(left)")
        received.removeAll()
        inbox.check(now: now)
        check.expect(received.isEmpty, "같은 신호를 두 번 받지 않음")
    }

    private static func done(_ check: Checker) {
        check.section("AI 신호: 끝남 → 앱 아이콘과 ✅")
        var (roster, world, pet) = setup(seed: 31)
        roster.agents.receive(signal(.done), from: host)
        run(roster, in: world, seconds: Sim.dt)
        check.expect(pet.speech?.text == AgentSignalCoordinator.doneText && pet.speech?.badge?.id == "app.check"
                     && pet.speech?.kind == .chatter && pet.speech?.appProcessID == 7, "쉬던 펫이 앱 아이콘과 ✅", "\(String(describing: pet.speech))")
        check.expect(pet.behavior is SkillLeapBehavior, "그 앱(프로세스 7)의 창으로 도약", pet.behavior.name)
        run(roster, in: world, seconds: 4)
        check.expect(pet.perchWindowID == 7, "그 앱 창 위에 섬", "\(String(describing: pet.perchWindowID))")

        (roster, world, pet) = setup(seed: 34)
        roster.agents.receive(signal(.done), from: AgentHost(processID: 99, badge: badge))
        run(roster, in: world, seconds: Sim.dt)
        check.expect(pet.behavior is AirborneBehavior, "창이 없는 앱이면 제자리에서 깡충", pet.behavior.name)
        run(roster, in: world, seconds: AgentSignalCoordinator.cheerTime + 0.2)
        check.expect(pet.speech == nil, "잠시 뒤 말풍선 닫힘")

        roster.agents.receive(signal(.limit), from: nil)
        run(roster, in: world, seconds: Sim.dt)
        check.expect(pet.speech?.text == AgentSignalCoordinator.limitText && pet.speech?.badge == nil,
                     "앱을 못 찾으면 아이콘 없이 기호만 (한도 💤)", "\(String(describing: pet.speech))")

        (roster, world, pet) = setup(seed: 32)
        roster.isQuiet = true
        roster.agents.receive(signal(.done), from: host)
        run(roster, in: world, seconds: Sim.dt)
        check.expect(pet.speech == nil, "통화 중에는 끝남을 알리지 않음")

        (roster, world, pet) = setup(seed: 33)
        roster.agents.isEnabled = false
        roster.agents.receive(signal(.done), from: host)
        run(roster, in: world, seconds: Sim.dt)
        check.expect(pet.speech == nil, "AI 작업 알림을 끄면 신호를 버림")
    }

    private static func waiting(_ check: Checker) {
        check.section("AI 신호: 기다림 → ✋, 다음 신호·클릭까지")
        var (roster, world, pet) = setup(seed: 41)
        roster.agents.receive(signal(.waiting), from: host)
        run(roster, in: world, seconds: 0.2)
        check.expect(pet.isShowingNotice && pet.speech?.text == AgentSignalCoordinator.waitingText && pet.speech?.badge?.id == "app.check",
                     "펫이 앱 아이콘과 ✋를 들고 있음", "\(String(describing: pet.speech))")
        check.expect(pet.speech?.discreet.badge?.id == "app.check", "통화 중 모습에도 아이콘 유지")
        run(roster, in: world, seconds: 30)
        check.expect(pet.isShowingNotice, "시간이 지나도 닫히지 않음")
        roster.agents.receive(signal(.waiting, pid: 5555), from: host)
        roster.agents.receive(signal(.working), from: host)
        run(roster, in: world, seconds: Sim.dt)
        check.expect(!roster.holds(topic: signal(.working).sessionTopic) && roster.holds(topic: signal(.waiting, pid: 5555).sessionTopic),
                     "같은 세션이 다시 일하면 그 세션 ✋만 거둠")

        (roster, world, pet) = setup(seed: 42)
        roster.agents.receive(signal(.waiting), from: host)
        run(roster, in: world, seconds: 0.2)
        roster.agents.receive(signal(.done), from: host)
        run(roster, in: world, seconds: Sim.dt)
        check.expect(!pet.isShowingNotice && pet.speech?.text == AgentSignalCoordinator.doneText, "끝나면 ✋ 대신 ✅", "\(String(describing: pet.speech))")

        (roster, world, pet) = setup(seed: 43)
        roster.agents.receive(signal(.waiting), from: host)
        run(roster, in: world, seconds: 0.2)
        pet.poke()
        run(roster, in: world, seconds: Sim.dt)
        check.expect(!pet.isShowingNotice && !roster.holds(topic: signal(.waiting).sessionTopic), "펫을 누르면 확인으로 닫힘")
        roster.agents.receive(signal(.waiting), from: host)
        run(roster, in: world, seconds: 0.2)
        roster.agents.isEnabled = false
        run(roster, in: world, seconds: Sim.dt)
        check.expect(!pet.isShowingNotice, "알림을 끄면 떠 있던 ✋도 거둠")
    }

    private static func returningToApp(_ check: Checker) {
        check.section("AI 신호: 그 앱으로 돌아가면 ✋ 거둠")
        let (roster, world, pet) = setup(seed: 51)
        roster.agents.receive(signal(.waiting), from: host)
        run(roster, in: world, seconds: 1)
        check.expect(pet.isShowingNotice, "다른 앱을 보는 동안 유지")
        world.focus(processID: 7)
        run(roster, in: world, seconds: Sim.dt * 2)
        check.expect(!pet.isShowingNotice, "신호를 보낸 앱(프로세스 7)으로 가면 거둠")

        world.focus(processID: 7)
        roster.agents.receive(signal(.waiting), from: host)
        run(roster, in: world, seconds: 1)
        check.expect(pet.isShowingNotice, "이미 그 앱을 보고 있었으면 바로 거두지 않음")
        world.focus(processID: 9)
        run(roster, in: world, seconds: 0.2)
        world.focus(processID: 7)
        run(roster, in: world, seconds: Sim.dt * 2)
        check.expect(!pet.isShowingNotice, "다른 앱에 갔다가 돌아오면 거둠")
    }

    private static func messenger(_ check: Checker) {
        check.section("AI 신호: 펫이 모두 바쁘면 전령")
        let (roster, world, pet) = setup(seed: 61)
        roster.announce(ScheduleNotice(topic: "schedule-1", text: "📅 회의"))
        run(roster, in: world, seconds: 0.2)
        roster.agents.receive(signal(.waiting), from: host)
        run(roster, in: world, seconds: 0.2)
        let messenger = roster.messengers.first
        check.expect(pet.noticeTopic == "schedule-1" && messenger?.noticeTopic == signal(.waiting).sessionTopic,
                     "일정을 든 펫 대신 전령이 ✋를 듦")
        roster.agents.receive(signal(.working), from: host)
        run(roster, in: world, seconds: 2)
        check.expect(roster.messengers.isEmpty && pet.noticeTopic == "schedule-1", "세션이 다시 일하면 전령은 인사하고 떠남, 일정은 그대로")
    }

    private static func dockVisit(_ check: Checker) {
        check.section("AI 신호: 끝난 앱의 Dock 아이콘으로")
        // 주 모니터 바닥(보이는 영역 아래 80pt)이 Dock, 아이콘은 x 1200 언저리
        let icon = CGRect(x: 1180, y: 12, width: 40, height: 56)
        check.expect(AgentSignalCoordinator.dockSpot(icon, in: Sim.world()) == CGPoint(x: 1200, y: 80), "Dock 아이콘 바로 위 바닥 자리")
        check.expect(AgentSignalCoordinator.dockSpot(CGRect(x: 2, y: 400, width: 40, height: 40), in: Sim.world()) == nil,
                     "옆에 붙은 Dock(보이는 영역 옆)이면 가지 않음")
        check.expect(AgentSignalCoordinator.dockSpot(nil, in: Sim.world()) == nil, "아이콘을 모르면 가지 않음")

        for hasAction in [true, false] {
            let world = Sim.world(windows: [Sim.window(9, 1000, 300, 400, 250)])
            world.focus(processID: 9)
            let roster = PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: 71)))
            roster.skills.isEnabled = false
            let pet = roster.add(appearance: FakeAppearance(hasAction: hasAction), scale: 1.5, in: world)
            pet.position = CGPoint(x: 300, y: 80)
            pet.settle(in: world)
            run(roster, in: world, seconds: 1)
            pet.switchTo(IdleBehavior(duration: 30))
            roster.agents.receive(signal(.done), from: AgentHost(processID: 7, badge: badge, dockIcon: icon))
            run(roster, in: world, seconds: Sim.dt)
            check.expect(pet.behavior is VisitBehavior && pet.speech?.text == AgentSignalCoordinator.doneText,
                         "끝나면 ✅를 띄우고 Dock 아이콘으로 출발" + (hasAction ? "" : " (동작 없는 캐릭터)"), pet.behavior.name)
            var knocked = false
            var arrivedX: CGFloat = 0
            for _ in 0..<Int(VisitBehavior.timeout * 60) {
                roster.step(dt: Sim.dt, in: world, cursor: nil)
                if pet.behavior.name == "knocked" || pet.behavior.name == "knocking" {
                    knocked = true
                    arrivedX = pet.position.x
                    break
                }
            }
            check.expect(knocked && abs(arrivedX - 1200) <= 6 && pet.speech?.badge?.id == "app.check",
                         "아이콘 위에 도착해 두드리고 아이콘 말풍선" + (hasAction ? " (휘두르기 두 번)" : " (깡충)"), "\(arrivedX) \(pet.behavior.name)")
        }

        // 창 위에 있던 펫은 창 끝에서 내려가 아이콘으로
        let world = Sim.world(windows: [Sim.window(9, 900, 300, 600, 250)])
        world.focus(processID: 9)
        let roster = PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: 72)))
        roster.skills.isEnabled = false
        let pet = roster.add(appearance: FakeAppearance(hasAction: true), scale: 1.5, in: world)
        pet.position = CGPoint(x: 1150, y: 550)
        pet.settle(in: world)
        run(roster, in: world, seconds: 1)
        pet.switchTo(IdleBehavior(duration: 30))
        roster.agents.receive(signal(.done), from: AgentHost(processID: 7, badge: badge, dockIcon: icon))
        var arrived = false
        for _ in 0..<Int(VisitBehavior.timeout * 60) {
            roster.step(dt: Sim.dt, in: world, cursor: nil)
            if pet.behavior.name == "knocked" { arrived = abs(pet.position.x - 1200) <= 6 && abs(pet.position.y - 80) <= 1; break }
        }
        check.expect(arrived, "창 위의 펫도 내려가서 아이콘 위에 도착", "\(pet.position) \(pet.behavior.name)")
    }

    private static func bringForward(_ check: Checker) {
        check.section("AI 신호: 펫을 누르면 그 앱을 앞으로")
        let (roster, world, pet) = setup(seed: 81)
        var opened: [Int32] = []
        roster.agents.onBringForward = { opened.append($0) }
        let gesture = PetPointerGesture(roster: roster)
        roster.agents.receive(signal(.waiting), from: host)
        run(roster, in: world, seconds: 0.2)
        let spot = CGPoint(x: pet.position.x, y: pet.position.y + pet.bodyHeight / 2)
        gesture.primaryDown(at: spot)
        gesture.primaryUp(at: spot)
        check.expect(opened == [7] && !pet.isShowingNotice, "✋ 든 펫을 누르면 닫히고 그 앱(7)을 앞으로", "\(opened)")
        pet.say("❤️", for: 1)
        gesture.primaryDown(at: spot)
        gesture.primaryUp(at: spot)
        check.expect(opened == [7], "보통 말풍선이면 앱을 부르지 않음")
    }
}
