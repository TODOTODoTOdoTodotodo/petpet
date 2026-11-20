import CoreGraphics
import Foundation

/// This object is responsible for checking the pet train: the front-most free pet becomes the engine toward
/// the open side, the others line up behind it in order with a small gap, catch up, never overlap,
/// and the line comes apart cleanly when the engine stops, arrives, is clicked or something is in the way.
enum TrainChecks {
    static func run(_ check: Checker) {
        forming(check)
        riding(check)
        breaking(check)
    }

    private static func roster(seed: UInt64) -> PetRoster {
        PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: seed)))
    }

    private static func pet(in roster: PetRoster, world: World, x: CGFloat, y: CGFloat = 80,
                            behavior: PetBehavior = IdleBehavior(duration: 999)) -> Pet {
        let pet = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        pet.position = CGPoint(x: x, y: y)
        pet.settle(in: world)
        pet.switchTo(behavior)
        return pet
    }

    private static func run(_ roster: PetRoster, in world: World, seconds: Double, each: (() -> Void)? = nil, until stop: (() -> Bool)? = nil) {
        for _ in 0..<Int(seconds * 60) {
            roster.step(dt: Sim.dt, in: world, cursor: nil)
            each?()
            if let stop, stop() { return }
        }
    }

    /// 같은 발판에서 몸이 겹친 가장 큰 깊이
    private static func overlap(_ pets: [Pet]) -> CGFloat {
        var worst: CGFloat = 0
        for (index, a) in pets.enumerated() {
            for b in pets[(index + 1)...] where a.support?.owner == b.support?.owner && a.support != nil && abs(a.position.y - b.position.y) < 2 {
                worst = max(worst, a.bodyHalfWidth + b.bodyHalfWidth - abs(a.position.x - b.position.x))
            }
        }
        return worst
    }

    private static func forming(_ check: Checker) {
        check.section("기차놀이: 줄 세우기")
        let world = Sim.world()
        let roster = Self.roster(seed: 101)
        let pets = [600, 700, 800].map { pet(in: roster, world: world, x: CGFloat($0)) }
        check.expect(roster.trains.depart(pets, world: world, planner: BehaviorPlanner(random: SeededRandomSource(seed: 1))), "한가한 펫 셋이면 출발")
        check.expect(pets[2].behavior is TrainLeadBehavior && pets[2].speech?.text == TrainLeadBehavior.whistleText,
                     "넓은 쪽 맨 앞 펫이 기관차 🚂", pets[2].behavior.name)
        check.expect(pets[1].behavior.trainRank == 1 && pets[0].behavior.trainRank == 2, "가까운 순서로 뒤 칸")
        check.expect(TrainCoordinator.train(led: pets[2], among: roster.pets).map(\.id) == [pets[2].id, pets[1].id, pets[0].id], "앞 펫을 하나씩 따름")

        let narrow = Sim.world(windows: [Sim.window(7, 700, 300, 160, 300)])
        let small = Self.roster(seed: 102)
        let two = [740, 800].map { pet(in: small, world: narrow, x: CGFloat($0), y: 600) }
        check.expect(!small.trains.depart(two, world: narrow, planner: BehaviorPlanner(random: SeededRandomSource(seed: 1))),
                     "앞쪽 자리가 모자라면 출발하지 않음")

        // 스스로 가끔 출발
        let free = Sim.world()
        let auto = Self.roster(seed: 103)
        let group = [300, 450, 600].map { pet(in: auto, world: free, x: CGFloat($0), behavior: IdleBehavior(duration: 0.5)) }
        var started = false
        run(auto, in: free, seconds: 180, until: {
            started = group.contains { $0.behavior is TrainLeadBehavior }
            return started
        })
        check.expect(started, "한가한 펫들이 가끔 스스로 기차놀이")
    }

    private static func riding(_ check: Checker) {
        check.section("기차놀이: 달리기")
        let world = Sim.world()
        let roster = Self.roster(seed: 104)
        // 맨 뒤 칸은 멀리서 따라잡음
        let pets = [440, 700, 800].map { pet(in: roster, world: world, x: CGFloat($0)) }
        roster.trains.depart(pets, world: world, planner: BehaviorPlanner(random: SeededRandomSource(seed: 1)))
        let engineStart = pets[2].position.x
        var worst: CGFloat = 0
        var ordered = true
        var sprinted = false
        run(roster, in: world, seconds: 5, each: {
            worst = max(worst, overlap(pets))
            if !(pets[0].position.x < pets[1].position.x && pets[1].position.x < pets[2].position.x) { ordered = false }
            if pets[0].behavior.animationSpeed > 1.5 { sprinted = true }
        })
        let gap = pets[2].position.x - pets[1].position.x
        let expected = 2 * pets[1].bodyHalfWidth + PersonalSpace.gap + TrainCarBehavior.gap
        check.expect(pets[2].position.x - engineStart > 150, "기관차가 천천히 나아감", "\(pets[2].position.x - engineStart)")
        check.expect(abs(gap - expected) < 2 && abs(pets[1].position.x - pets[0].position.x - expected) < 2,
                     "칸마다 같은 간격으로 붙어 감", "\(gap) \(pets[1].position.x - pets[0].position.x)")
        check.expect(sprinted, "멀리 있던 칸은 뛰어서 따라잡음")
        check.expect(ordered && worst <= 0.01, "순서를 지키며 겹치지 않음", "\(worst)")
        check.expect(pets.allSatisfy { $0.facing == .east && $0.animation == .walk }, "모두 같은 쪽을 보고 걸음")

        var arrived = false
        run(roster, in: world, seconds: 10, until: {
            arrived = pets[2].speech?.text == TrainLeadBehavior.arrivalText
            return arrived
        })
        run(roster, in: world, seconds: 0.2)
        check.expect(arrived && pets.allSatisfy { $0.behavior.trainRank == nil }, "시간이 다 되면 🎉 하고 해산")

        // 창 위에서는 끝 앞에서 멈춤
        let ledge = Sim.world(windows: [Sim.window(7, 300, 300, 600, 300)])
        let onWindow = Self.roster(seed: 105)
        let riders = [400, 480, 560].map { pet(in: onWindow, world: ledge, x: CGFloat($0), y: 600) }
        onWindow.trains.depart(riders, world: ledge, planner: BehaviorPlanner(random: SeededRandomSource(seed: 1)))
        var end = false
        run(onWindow, in: ledge, seconds: 15, until: {
            end = riders.allSatisfy { $0.behavior.trainRank == nil }
            return end
        })
        check.expect(end && riders.allSatisfy { $0.perchWindowID == 7 } && riders[2].position.x <= 900 - riders[2].bodyHalfWidth,
                     "창 끝 앞에서 멈추고 아무도 떨어지지 않음", riders.map { "\($0.behavior.name)@\(Int($0.position.x))" }.joined(separator: " "))
    }

    private static func breaking(_ check: Checker) {
        check.section("기차놀이: 멈추기")
        do {
            let world = Sim.world()
            let roster = Self.roster(seed: 106)
            let pets = [600, 700, 800].map { pet(in: roster, world: world, x: CGFloat($0)) }
            roster.trains.depart(pets, world: world, planner: BehaviorPlanner(random: SeededRandomSource(seed: 1)))
            run(roster, in: world, seconds: 2)
            pets[2].poke()
            run(roster, in: world, seconds: 0.2)
            check.expect(pets.allSatisfy { $0.behavior.trainRank == nil }, "기관차를 클릭하면 기차가 멈춤")
        }
        do {
            let world = Sim.world()
            let roster = Self.roster(seed: 107)
            let pets = [500, 600, 700, 800].map { pet(in: roster, world: world, x: CGFloat($0)) }
            roster.trains.depart(pets, world: world, planner: BehaviorPlanner(random: SeededRandomSource(seed: 1)))
            run(roster, in: world, seconds: 2)
            pets[1].poke()
            run(roster, in: world, seconds: 0.2)
            check.expect(pets[3].behavior is TrainLeadBehavior && pets[2].behavior.trainRank == 1 && pets[0].behavior.trainRank == nil,
                         "가운데 칸을 클릭하면 그 뒤만 빠지고 앞은 계속 감",
                         pets.map(\.behavior.name).joined(separator: ","))
        }
        do {
            // 줄에 없는 펫이 앞을 막으면 멈춤 (겹치지 않음)
            let world = Sim.world()
            let roster = Self.roster(seed: 108)
            let pets = [600, 700].map { pet(in: roster, world: world, x: CGFloat($0)) }
            let stranger = pet(in: roster, world: world, x: 860, behavior: IdleBehavior(duration: 999, lookAtUser: true))
            roster.trains.depart(pets, world: world, planner: BehaviorPlanner(random: SeededRandomSource(seed: 1)))
            var worst: CGFloat = 0
            run(roster, in: world, seconds: 4, each: { worst = max(worst, overlap(roster.pets)) })
            check.expect(!(pets[1].behavior is TrainLeadBehavior) && worst <= 0.01 && stranger.behavior.name == "lookingAtUser",
                         "앞을 다른 펫이 막으면 멈추고 겹치지 않음", "\(pets[1].behavior.name) \(worst)")
        }
    }
}
