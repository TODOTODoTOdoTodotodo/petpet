import Foundation

/// This object is responsible for checking the platform-free host side every shell shares:
/// the habitat loop's refresh rhythm and call order, and pointer gestures on pets.
enum HabitatChecks {
    static func run(_ check: Checker) {
        gestures(check)
        loopRhythm(check)
        loopQuietAndMouse(check)
    }

    // MARK: - Gestures

    private static func idlePet(in roster: PetRoster, world: World, x: CGFloat) -> Pet {
        let pet = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        pet.position = CGPoint(x: x, y: 80)
        pet.settle(in: world)
        pet.switchTo(IdleBehavior(duration: 999))
        return pet
    }

    private static func gestures(_ check: Checker) {
        check.section("포인터 몸짓 (공통)")
        let world = Sim.world()
        let roster = PetRoster()
        let pet = idlePet(in: roster, world: world, x: 400)
        let gesture = PetPointerGesture(roster: roster)
        var events: [String] = []
        var menus: [String] = []
        var itemClicks = 0
        gesture.onEvent = { events.append($0) }
        gesture.onContextMenu = { pet, _ in menus.append(pet.id) }
        gesture.onItemClick = { _ in itemClicks += 1; return false }
        let body = CGPoint(x: pet.grabRect.midX, y: pet.grabRect.midY)

        gesture.primaryDown(at: body)
        gesture.dragged(to: CGPoint(x: body.x + 2, y: body.y))
        check.expect(gesture.isHolding && !pet.isDragged, "임계값(4pt) 안의 움직임은 아직 끌기 아님")
        gesture.primaryUp(at: CGPoint(x: body.x + 2, y: body.y))
        check.expect(events.last?.hasPrefix("👆") == true && !gesture.isHolding, "움직이지 않고 떼면 쓰다듬기", "\(events)")

        gesture.primaryDown(at: body)
        gesture.dragged(to: CGPoint(x: body.x + 5, y: body.y + 30))
        check.expect(pet.isDragged && events.last?.hasPrefix("✋") == true, "4pt 넘게 움직이면 집어 듦")
        gesture.dragged(to: CGPoint(x: body.x + 60, y: body.y + 90))
        gesture.primaryUp(at: CGPoint(x: body.x + 60, y: body.y + 90))
        roster.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(!pet.isDragged && !gesture.isHolding && events.last?.hasPrefix("🫳") == true, "떼면 다음 틱에 놓여 던져짐")

        gesture.secondaryDown(at: CGPoint(x: pet.grabRect.midX, y: pet.grabRect.midY))
        gesture.secondaryDown(at: CGPoint(x: 1500, y: 900))
        check.expect(menus == [pet.id], "보조 누름은 펫 위에서만 그 펫의 메뉴", "\(menus)")
        gesture.primaryDown(at: CGPoint(x: 1500, y: 900))
        check.expect(itemClicks == 1 && !gesture.isHolding, "빈 곳 누름은 물건 클릭으로 넘김")
    }

    // MARK: - Loop

    private static func loopRhythm(_ check: Checker) {
        check.section("시뮬레이션 시계 (공통)")
        let desktop = ScriptedDesktop()
        let stage = RecordingStage()
        let loop = HabitatLoop(roster: PetRoster(), desktop: desktop, senses: ScriptedSenses(), stage: stage)
        loop.refreshDisplays()
        check.expect(stage.rebuilds == 1 && loop.world.screens.count == 1, "모니터 구성으로 무대를 만듦")

        var now = 100.0
        for _ in 0...60 {
            loop.tick(now: now)
            now += Sim.dt
        }
        let still = desktop.windowReads - 1
        check.expect((9...11).contains(still), "창이 가만있으면 0.1초마다 읽음 (1초에 약 10번)", "\(still)")
        check.expect(stage.renders == 61, "틱마다 그림", "\(stage.renders)")

        desktop.windowReads = 0
        desktop.moving = true
        for _ in 0..<30 {
            loop.tick(now: now)
            now += Sim.dt
        }
        check.expect((12...16).contains(desktop.windowReads), "창이 움직이면 1/30초마다 읽음 (0.5초에 약 15번)", "\(desktop.windowReads)")

        // 높이 800에서 떨어지는 펫: 30초 멈췄다 돌아와도 0.1초만큼만 떨어짐
        let faller = loop.roster.add(appearance: FakeAppearance(), scale: 1.5, in: loop.world)
        faller.position = CGPoint(x: 900, y: 800)
        loop.tick(now: now)
        loop.tick(now: now + 30)
        check.expect(faller.position.y > 700, "오래 멈췄다 돌아와도 한 틱은 최대 0.1초", "\(faller.position.y)")
    }

    private static func loopQuietAndMouse(_ check: Checker) {
        let senses = ScriptedSenses()
        senses.microphone = true
        let stage = RecordingStage()
        let roster = PetRoster()
        let loop = HabitatLoop(roster: roster, desktop: ScriptedDesktop(), senses: senses, stage: stage)
        loop.refreshDisplays()
        let pet = idlePet(in: roster, world: loop.world, x: 700)

        loop.tick(now: 0)
        check.expect(roster.isQuiet, "마이크가 쓰이면 조용히")
        loop.quietDuringCalls = false
        loop.tick(now: Sim.dt)
        check.expect(!roster.isQuiet, "끄면 바로 다음 틱에 풀림")

        senses.cursor = CGPoint(x: pet.grabRect.midX, y: pet.grabRect.midY)
        loop.tick(now: Sim.dt * 2)
        check.expect(stage.wantsMouse == true, "커서가 펫 위면 무대가 마우스를 받음")
        senses.cursor = CGPoint(x: 1500, y: 900)
        loop.tick(now: Sim.dt * 3)
        check.expect(stage.wantsMouse == false, "빈 곳이면 관통")
        senses.keys = 5
        loop.tick(now: Sim.dt * 4)
        check.expect(senses.keys == 0, "키 누른 수를 틱마다 가져감")
    }
}

/// This object is responsible for a scripted desktop with one window that can be made to keep moving.
final class ScriptedDesktop: DesktopSource {
    var windowReads = 0
    var moving = false
    private var x: CGFloat = 300

    func displays() -> [ScreenArea] { [Sim.main] }

    func windows() -> [WindowSnapshot] {
        windowReads += 1
        if moving { x += 3 }
        return [Sim.window(7, x, 300, 600, 300)]
    }

    func frontmostApp() -> FrontApp? { FrontApp(processID: 7, bundleID: "check.app") }
}

/// This object is responsible for host readings a check sets by hand.
final class ScriptedSenses: HostSenses {
    var cursor = CGPoint(x: 1500, y: 900)
    var microphone = false
    var keys = 0

    func secondsSinceUserInput() -> TimeInterval { 0 }

    func newKeyPresses() -> Int {
        defer { keys = 0 }
        return keys
    }

    func microphoneInUse() -> Bool { microphone }

    func moveCursor(to point: CGPoint) { cursor = point }
}

/// This object is responsible for recording what the loop asked a stage to do.
final class RecordingStage: PetStage {
    var rebuilds = 0
    var renders = 0
    var wantsMouse: Bool?

    func rebuild(for areas: [ScreenArea]) { rebuilds += 1 }

    func render(_ pets: [Pet], projectiles: [Projectile], items: [DroppedItem], discreet: Bool) { renders += 1 }

    func routeMouse(at cursor: CGPoint, toPets wantsMouse: Bool) { self.wantsMouse = wantsMouse }
}
