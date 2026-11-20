import CoreGraphics
import Foundation

/// This object is responsible for checking the typing reactions: the pace measured from key-press counts,
/// free pets drumming along faster the faster the user types, stopping when typing calms down, and the 🔥 burst.
enum TypingChecks {
    static func run(_ check: Checker) {
        meter(check)
        drumming(check)
        cheering(check)
    }

    /// 초당 rate번 누르는 것을 틱마다 나눈 수
    private final class Typist {
        private var carry = 0.0
        func presses(rate: Double) -> Int {
            carry += rate * Sim.dt
            let whole = Int(carry)
            carry -= Double(whole)
            return whole
        }
    }

    private static func roster(seed: UInt64) -> (PetRoster, World, [Pet]) {
        let world = Sim.world()
        let roster = PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: seed)))
        let pets = [300, 700, 1100].map { x -> Pet in
            let pet = roster.add(appearance: FakeAppearance(hasAction: x == 300), scale: 1.5, in: world)
            pet.position = CGPoint(x: CGFloat(x), y: 80)
            pet.settle(in: world)
            pet.switchTo(IdleBehavior(duration: 999))
            return pet
        }
        return (roster, world, pets)
    }

    /// seconds 동안 rate로 치며 진행. each는 틱마다
    private static func type(_ roster: PetRoster, in world: World, rate: Double, seconds: Double, each: (() -> Void)? = nil) {
        let typist = Typist()
        for _ in 0..<Int(seconds * 60) {
            roster.step(dt: Sim.dt, in: world, cursor: nil, keyPresses: typist.presses(rate: rate))
            each?()
        }
    }

    private static func meter(_ check: Checker) {
        check.section("타이핑: 빠르기 재기")
        var meter = TypingMeter()
        let typist = Typist()
        for _ in 0..<(4 * 60) { meter.record(typist.presses(rate: 6), dt: Sim.dt) }
        check.expect(abs(meter.rate - 6) <= 0.6, "초당 누른 수", "\(meter.rate)")
        check.expect(abs(meter.streak - 4) < 0.2, "쉬지 않고 친 시간", "\(meter.streak)")
        for _ in 0..<(2 * 60) { meter.record(0, dt: Sim.dt) }
        check.expect(meter.rate == 0 && meter.streak == 0, "멈추면 0으로", "\(meter.rate) \(meter.streak)")
    }

    private static func drumming(_ check: Checker) {
        check.section("타이핑: 따라 두드리기")
        do {
            let (roster, world, pets) = roster(seed: 78)
            var joined = Set<String>()
            var speeds: [Double] = []
            var actOnly = true
            type(roster, in: world, rate: 6, seconds: 20) {
                for pet in pets where pet.behavior is DrummingBehavior {
                    joined.insert(pet.id)
                    speeds.append(pet.behavior.animationSpeed)
                    if pet.animation != (pet.appearance.supports(.act) ? .act : .walk) { actOnly = false }
                }
            }
            check.expect(joined.count >= 2, "빠르게 치면 한가한 펫들이 따라 두드림", "\(joined)")
            check.expect(actOnly, "공격 동작이 있으면 공격, 없으면 제자리 걸음으로")
            let late = speeds.suffix(60)
            check.expect(!late.isEmpty && late.allSatisfy { abs($0 - 1) < 0.15 }, "초당 6번이면 평소 빠르기", "\(late.last ?? 0)")

            type(roster, in: world, rate: 12, seconds: 3)
            let fast = pets.filter { $0.behavior is DrummingBehavior }.map(\.behavior.animationSpeed)
            check.expect(fast.allSatisfy { $0 > 1.6 }, "더 빨리 치면 더 빨리 두드림", "\(fast)")

            var stopped = false
            type(roster, in: world, rate: 0, seconds: 2) {
                if !pets.contains(where: { $0.behavior is DrummingBehavior }) { stopped = true }
            }
            check.expect(stopped, "멈추면 곧 그만둠")
            check.expect(pets.allSatisfy { $0.support != nil && !$0.isLost(in: world) }, "제자리에서 두드림")
        }
        do {
            let (roster, world, pets) = roster(seed: 72)
            var drummed = false
            type(roster, in: world, rate: 2, seconds: 20) { if pets.contains(where: { $0.behavior is DrummingBehavior }) { drummed = true } }
            check.expect(!drummed, "천천히 치면 따라 하지 않음")
        }
        do {
            let (roster, world, pets) = roster(seed: 73)
            roster.typing.isEnabled = false
            var drummed = false
            type(roster, in: world, rate: 8, seconds: 20) { if pets.contains(where: { $0.behavior is DrummingBehavior }) { drummed = true } }
            check.expect(!drummed && roster.typing.rate == 0, "React To Typing을 끄면 하지 않음")
        }
        do {
            let (roster, world, pets) = roster(seed: 74)
            roster.vigor = .exhausted
            var drummed = false
            type(roster, in: world, rate: 8, seconds: 20) { if pets.contains(where: { $0.behavior is DrummingBehavior }) { drummed = true } }
            check.expect(!drummed, "지쳐 누운 펫은 따라 하지 않음")
        }
        do {
            let (roster, world, pets) = roster(seed: 75)
            pets[1].announce(ScheduleNotice(topic: "m", text: "지금 · 회의"))
            var noticeDrummed = false
            type(roster, in: world, rate: 8, seconds: 20) { if pets[1].behavior is DrummingBehavior { noticeDrummed = true } }
            check.expect(!noticeDrummed, "일정 알림을 든 펫은 따라 하지 않음")
        }
    }

    private static func cheering(_ check: Checker) {
        check.section("타이핑: 아주 빠르면 🔥")
        let (roster, world, pets) = roster(seed: 76)
        var fires = 0
        var hadFire = Set<String>()
        type(roster, in: world, rate: 10, seconds: 30) {
            for pet in pets where pet.speech?.text == TypingCoordinator.fireText && !hadFire.contains(pet.id) {
                hadFire.insert(pet.id)
                fires += 1
            }
            for pet in pets where pet.speech?.text != TypingCoordinator.fireText { hadFire.remove(pet.id) }
        }
        check.expect(fires == 1, "아주 빠르게 이어 치면 한 마리가 🔥, 45초에 한 번", "\(fires)")

        let (quietRoster, quietWorld, quietPets) = Self.roster(seed: 77)
        quietRoster.isQuiet = true
        var quietFire = false
        var quietDrum = false
        type(quietRoster, in: quietWorld, rate: 10, seconds: 20) {
            if quietPets.contains(where: { $0.speech?.text == TypingCoordinator.fireText }) { quietFire = true }
            if quietPets.contains(where: { $0.behavior is DrummingBehavior }) { quietDrum = true }
        }
        check.expect(!quietFire && quietDrum, "통화 중에는 🔥 없이 두드리기만")
    }
}
