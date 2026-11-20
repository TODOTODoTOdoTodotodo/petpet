import Foundation

/// This object is responsible for checking play-fights between pets and how Claude usage drains their energy:
/// the sparring script, reading the status line's usage file, vigor levels and what tired pets stop doing.
enum MoodChecks {
    static func run(_ check: Checker) {
        sparring(check)
        usageFile(check)
        vigor(check)
    }

    private static func pair(seed: UInt64, sparChanceForced: Bool) -> (PetRoster, World, Pet, Pet) {
        let world = Sim.world()
        let roster = PetRoster(planner: BehaviorPlanner(random: sparChanceForced ? FixedRandom(0.1) : SeededRandomSource(seed: seed)))
        let first = roster.add(appearance: FakeAppearance(hasAction: true), scale: 1.5, in: world)
        let second = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        first.position = CGPoint(x: 700, y: 80)
        second.position = CGPoint(x: 740, y: 80)
        first.settle(in: world)
        second.settle(in: world)
        first.switchTo(IdleBehavior(duration: 999))
        second.switchTo(IdleBehavior(duration: 999))
        return (roster, world, first, second)
    }

    private static func sparring(_ check: Checker) {
        check.section("마주치면 티격태격")
        let (roster, world, first, second) = pair(seed: 0, sparChanceForced: true)
        roster.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(first.behavior is SparBehavior && second.behavior is SparBehavior, "인사 대신 대결을 고르기도 함")
        check.expect(first.facing == .east && second.facing == .west, "서로 마주 봄")

        var attackAnimations = Set<AnimationKind>()
        var finale: [String: String] = [:]
        let start = (first.position.x, second.position.x)
        for _ in 0..<Int(5 * 60) {
            roster.step(dt: Sim.dt, in: world, cursor: nil)
            for pet in [first, second] where pet.behavior is SparBehavior {
                if pet.animation != .idle { attackAnimations.insert(pet.animation) }
                if let text = pet.speech?.text, [SparBehavior.winText, SparBehavior.loseText].contains(text) { finale[pet.id] = text }
            }
        }
        check.expect(attackAnimations.contains(.act) && attackAnimations.contains(.walk),
                     "공격 동작이 있으면 휘두르고, 없으면 돌진", "\(attackAnimations)")
        check.expect(first.position.x < start.0 && second.position.x > start.1, "맞으면 뒤로 밀려남",
                     "\(start) → \(first.position.x), \(second.position.x)")
        check.expect(Set(finale.values) == [SparBehavior.winText, SparBehavior.loseText], "끝나면 ✌️ 와 🏳️", "\(finale)")
        check.expect(!(first.behavior is SparBehavior) && !(second.behavior is SparBehavior), "몇 초 뒤 끝나고 평소대로")

        let (roster2, world2, a, b) = pair(seed: 0, sparChanceForced: true)
        roster2.step(dt: Sim.dt, in: world2, cursor: nil)
        a.poke()
        roster2.step(dt: Sim.dt, in: world2, cursor: nil)
        check.expect(!(a.behavior is SparBehavior) && !(b.behavior is SparBehavior), "한쪽을 클릭하면 둘 다 그만둠")

        // 무작위로는 인사와 대결이 섞임
        var greets = 0, spars = 0
        for seed in 0..<40 {
            let (r, w, p, _) = pair(seed: UInt64(seed + 100), sparChanceForced: false)
            r.step(dt: Sim.dt, in: w, cursor: nil)
            if p.behavior is SparBehavior { spars += 1 } else if p.behavior.name == "greeting" { greets += 1 }
        }
        check.expect(spars >= 8 && greets >= 12, "인사와 대결이 섞여 나옴 (대결 약 4할)", "인사 \(greets) 대결 \(spars)")

        let (tiredRoster, tiredWorld, t1, _) = pair(seed: 0, sparChanceForced: true)
        tiredRoster.vigor = .weary
        tiredRoster.step(dt: Sim.dt, in: tiredWorld, cursor: nil)
        check.expect(t1.behavior.name == "greeting", "지치면 대결 없이 인사만", t1.behavior.name)
    }

    private static func usageFile(_ check: Checker) {
        check.section("Claude 사용량 파일")
        let json = #"{"five_hour":{"used_percentage":63.5,"resets_at":2000},"seven_day":{"used_percentage":41,"resets_at":9000}}"#
        let usage = ClaudeUsage.parse(Data(json.utf8))
        check.expect(usage?.fiveHour?.usedPercent == 63.5 && usage?.sevenDay?.resetsAt == Date(timeIntervalSince1970: 9000),
                     "상태줄이 남긴 rate_limits를 읽음")
        check.expect(usage?.effectivePercent(at: Date(timeIntervalSince1970: 1000)) == 63.5, "두 한도 중 더 많이 쓴 쪽 기준")
        check.expect(usage?.effectivePercent(at: Date(timeIntervalSince1970: 3000)) == 41, "5시간 한도가 초기화되면 7일 한도만")
        check.expect(usage?.effectivePercent(at: Date(timeIntervalSince1970: 10000)) == nil, "모두 초기화되면 모름")
        check.expect(usage?.summary(at: Date(timeIntervalSince1970: 1000)) == "5h 64% · 7d 41%", "메뉴 요약",
                     "\(String(describing: usage?.summary(at: Date(timeIntervalSince1970: 1000))))")
        check.expect(usage?.summary(at: Date(timeIntervalSince1970: 10000)) == nil, "모두 초기화되면 요약 없음 (메뉴 언어로 표시)")
        check.expect(ClaudeUsage.parse(Data(#"{"five_hour":null,"seven_day":null}"#.utf8)) == nil, "한도 값이 없으면 nil")
        check.expect(ClaudeUsage.parse(Data("oops".utf8)) == nil, "깨진 파일은 무시")
    }

    private static func vigor(_ check: Checker) {
        check.section("사용량에 따라 기력 감소")
        check.expect(Vigor(usedPercent: nil) == .fresh && Vigor(usedPercent: 49) == .fresh, "50% 미만·모름은 평소대로")
        check.expect(Vigor(usedPercent: 50) == .slowing && Vigor(usedPercent: 80) == .weary && Vigor(usedPercent: 95) == .exhausted,
                     "50·80·95%에서 단계가 바뀜")

        let world = Sim.world(windows: [Sim.window(7, 300, 300, 600, 300)])
        let pet = Sim.pet(at: CGPoint(x: 200, y: 80), appearance: FakeAppearance(hasAction: true), behavior: IdleBehavior(duration: 999))
        pet.settle(in: world)
        let planner = BehaviorPlanner(random: SeededRandomSource(seed: 70))
        func choices(_ vigor: Vigor) -> [PetBehavior] {
            var context = PetContext(cursor: nil, planner: planner)
            context.vigor = vigor
            context.skillTarget = 7
            return (0..<400).map { _ in planner.next(after: pet, in: world, context: context) }
        }
        let fresh = choices(.fresh), slowing = choices(.slowing), weary = choices(.weary)
        let lively = { (list: [PetBehavior]) in list.filter { $0 is SkillLeapBehavior || $0.name == "jumping" || $0.name == "sprinting" || $0 is ActBehavior }.count }
        check.expect(lively(slowing) < lively(fresh) && lively(slowing) > 0, "50% 넘으면 점프·도약이 줄어듦", "\(lively(fresh)) → \(lively(slowing))")
        check.expect(lively(weary) == 0, "80% 넘으면 점프·도약·공격 안 함", "\(lively(weary))")
        let rests = { (list: [PetBehavior]) in list.filter { $0.name == "idle" }.count }
        check.expect(rests(weary) > rests(fresh), "지치면 더 자주 쉼", "\(rests(fresh)) → \(rests(weary))")
        check.expect(choices(.exhausted).allSatisfy { $0 is ExhaustedBehavior }, "95% 넘으면 누워서 🪫")

        // 걷는 속도
        let walker = Sim.pet(at: CGPoint(x: 800, y: 80), behavior: IdleBehavior(duration: 999))
        walker.settle(in: world)
        func distance(_ vigor: Vigor) -> CGFloat {
            walker.position.x = 800
            walker.switchTo(IdleBehavior(duration: 999))
            var context = PetContext(cursor: nil, planner: planner)
            context.vigor = vigor
            let walk = (0..<200).lazy.map { _ in planner.next(after: walker, in: world, context: context) }.first { $0.name == "walking" }!
            walker.switchTo(walk)
            for _ in 0..<30 { walker.step(dt: Sim.dt, in: world, context: context) }
            return abs(walker.position.x - 800)
        }
        let normal = distance(.fresh), slow = distance(.weary)
        check.expect(abs(slow / normal - 0.5) < 0.05, "80% 넘으면 걸음이 절반 속도", "\(normal) vs \(slow)")

        // 초기화되면 ⚡
        let roster = PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: 71)))
        let napper = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        napper.position = CGPoint(x: 1200, y: 80)
        napper.settle(in: world)
        roster.vigor = .exhausted
        napper.switchTo(ExhaustedBehavior())
        roster.step(dt: Sim.dt, in: world, cursor: nil)
        roster.vigor = .fresh
        check.expect(napper.speech?.text == Vigor.rechargedText && napper.behavior.name == "recharged", "한도가 초기화되면 ⚡ 하고 벌떡")

        let skillRoster = PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: 72)))
        skillRoster.vigor = .weary
        let lazy = skillRoster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        lazy.position = CGPoint(x: 200, y: 80)
        lazy.settle(in: world)
        lazy.switchTo(IdleBehavior(duration: 999))
        world.focus(processID: 7)
        skillRoster.step(dt: Sim.dt, in: world, cursor: nil)
        check.expect(!(lazy.behavior is SkillLeapBehavior), "지치면 창을 바꿔도 스킬 도약 안 함")
    }
}
