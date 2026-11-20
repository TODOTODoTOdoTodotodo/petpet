import CoreGraphics
import Foundation

/// This object is responsible for checking the pets' entrance: hidden until their turn, dropping one after another
/// from just under the menu bar onto the window the user is looking at, side by side, and waving on landing.
enum EntranceChecks {
    static func run(_ check: Checker) {
        startup(check)
        fallbacks(check)
    }

    private static func roster(seed: UInt64) -> PetRoster {
        PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: seed)))
    }

    /// 보는 창(7)이 있는 화면
    private static func world(windows: [WindowSnapshot], focus: UInt32?) -> World {
        let world = Sim.world(windows: windows)
        world.focus(processID: focus.map(Int32.init))
        return world
    }

    /// 내려앉아 👋 하는 순간의 펫 모습
    private struct Landing {
        let x: CGFloat
        let windowID: UInt32?
        let support: SurfaceOwner?
    }

    /// seconds 동안 진행하며 펫마다 처음 내려앉은 순간을 기록. each는 틱마다 펫과 지난 시간을 받음
    private static func landings(_ roster: PetRoster, in world: World, pets: [Pet], seconds: Double, startingAt start: Double = 0,
                                 each: ((Pet, Double) -> Void)? = nil) -> [String: Landing] {
        var found: [String: Landing] = [:]
        for tick in 1...Int(seconds * 60) {
            roster.step(dt: Sim.dt, in: world, cursor: nil)
            for pet in pets {
                each?(pet, start + Double(tick) * Sim.dt)
                if pet.behavior.name == "greetingUser" && found[pet.id] == nil {
                    found[pet.id] = Landing(x: pet.position.x, windowID: pet.perchWindowID, support: pet.support?.owner)
                }
            }
            if found.count == pets.count { break }
        }
        return found
    }

    private static func startup(_ check: Checker) {
        check.section("첫 실행: 보는 창 위로 차례로 떨어지기")
        let world = Self.world(windows: [Sim.window(7, 400, 300, 800, 300)], focus: 7)
        let roster = Self.roster(seed: 61)
        let pets = (0..<3).map { roster.add(appearance: FakeAppearance(), scale: 1.5, in: world, entrance: .startup(order: $0)) }

        roster.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(pets.allSatisfy { $0.behavior is EntranceBehavior && $0.opacity == 0 && !$0.isTangible },
                     "차례가 오기 전에는 보이지 않고 잡히지 않음")
        check.expect(roster.pet(at: pets[0].position) == nil, "숨은 펫은 클릭되지 않음")

        var startedAt: [String: Double] = [:]
        var startY: [String: CGFloat] = [:]
        var waved = Set<String>()
        let landed = landings(roster, in: world, pets: pets, seconds: 6, startingAt: Sim.dt) { pet, time in
            if pet.behavior.name == "droppingIn" && startedAt[pet.id] == nil {
                startedAt[pet.id] = time
                startY[pet.id] = pet.position.y
            }
            if pet.speech?.text == Chatter.hello && pet.displayFacing == .south { waved.insert(pet.id) }
        }
        let times = pets.compactMap { startedAt[$0.id] }
        check.expect(times.count == 3 && times[0] >= EntranceBehavior.firstDelay - 0.05 && times[0] < times[1] && times[1] < times[2]
                     && abs(times[1] - times[0] - EntranceBehavior.stagger) < 0.05,
                     "앱을 켜고 잠시 뒤 한 마리씩 차례로", "\(times)")
        let top = Sim.main.visibleFrame.maxY - pets[0].bodyHeight - EntranceBehavior.dropGap
        check.expect(pets.allSatisfy { abs((startY[$0.id] ?? 0) - top) < 1 }, "메뉴바 바로 밑에서 떨어지기 시작", "\(startY)")
        check.expect(landed.count == 3 && landed.values.allSatisfy { $0.windowID == 7 }, "보고 있는 창 위에 내려앉음", "\(landed)")
        check.expect(waved.count == 3, "내려와서 사용자를 보며 👋", "\(waved)")
        let xs = landed.values.map(\.x).sorted()
        check.expect(zip(xs, xs.dropFirst()).allSatisfy { $1 - $0 >= 2 * pets[0].bodyHalfWidth }, "나란히 떨어져 겹치지 않음", "\(xs)")
        check.expect(abs((landed[pets[0].id]?.x ?? 0) - 800) < 40, "첫 펫은 창 가운데쯤", "\(landed[pets[0].id]?.x ?? 0)")

        // 나중에 더한 펫도 같은 방식으로, 빈자리에 (다른 펫들은 그 자리에 세워 둠)
        pets.forEach { $0.switchTo(IdleBehavior(duration: 999, lookAtUser: true)) }
        let added = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world, entrance: EntranceBehavior(order: 3, delay: 0))
        let addedLanding = landings(roster, in: world, pets: [added], seconds: 3)[added.id]
        let all = (pets.map(\.position.x) + [addedLanding?.x ?? 0]).sorted()
        check.expect(addedLanding?.windowID == 7 && zip(all, all.dropFirst()).allSatisfy { $1 - $0 >= 2 * added.bodyHalfWidth },
                     "더한 펫도 보는 창 위 빈자리에 내려앉음", "\(all)")
    }

    private static func fallbacks(_ check: Checker) {
        check.section("첫 실행: 내려앉을 창이 마땅치 않을 때")
        do {
            // 보는 창 윗변 가운데를 앞 창이 가림 → 보이는 윗변으로만
            let world = Self.world(windows: [Sim.window(8, 650, 250, 300, 400), Sim.window(7, 400, 300, 800, 300)], focus: 7)
            let roster = Self.roster(seed: 62)
            let pets = (0..<3).map { roster.add(appearance: FakeAppearance(), scale: 1.5, in: world, entrance: .startup(order: $0)) }
            let landed = landings(roster, in: world, pets: pets, seconds: 5)
            check.expect(landed.count == 3 && landed.values.allSatisfy { $0.windowID == 7 }, "가려진 곳을 피해 보는 창 위에 내려앉음", "\(landed)")
        }
        do {
            let world = Self.world(windows: [], focus: nil)
            let roster = Self.roster(seed: 63)
            let pet = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world, entrance: .startup(order: 0))
            let landed = landings(roster, in: world, pets: [pet], seconds: 4)[pet.id]
            check.expect(landed?.support == .ground(screenID: 1) && abs((landed?.x ?? 0) - Sim.main.visibleFrame.midX) < 1,
                         "보는 창이 없으면 화면 가운데 바닥", "\(String(describing: landed))")
        }
        do {
            // 최대화 창(윗변이 메뉴바에 닿음) → 바닥으로
            let world = Self.world(windows: [Sim.window(7, 0, 80, 1600, 815)], focus: 7)
            let roster = Self.roster(seed: 64)
            let pets = (0..<2).map { roster.add(appearance: FakeAppearance(), scale: 1.5, in: world, entrance: .startup(order: $0)) }
            let landed = landings(roster, in: world, pets: pets, seconds: 4)
            check.expect(landed.count == 2 && landed.values.allSatisfy { $0.support == .ground(screenID: 1) }, "최대화 창이면 바닥에 내려앉음", "\(landed)")
        }
    }
}
