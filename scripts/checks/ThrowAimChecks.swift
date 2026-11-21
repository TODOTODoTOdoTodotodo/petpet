import Foundation

/// This object is responsible for checking how pets aim their throws: each accuracy step's hit rate, how far a miss
/// lands and that it stays on screen, a character's aim nudging the rate (but never past its floor or ceiling,
/// and never on "always hit"), a thrown weapon remembering it missed, and the setting's default and saved value.
enum ThrowAimChecks {
    /// 던지기 성격만 다른 모습
    private final class Aimed: PetAppearance {
        let name = "Aimed"
        let body = BodyMetrics(footInset: 0, width: 24, height: 40, centerX: 24)
        let skillStyle: SkillStyle = .bigJump
        let aimBias: Double
        init(_ bias: Double) { aimBias = bias }
        func supports(_ kind: AnimationKind) -> Bool { true }
        func cycleDuration(of kind: AnimationKind, facing: Facing) -> TimeInterval { 0 }
    }

    static func run(_ check: Checker) {
        check.section("던지기 정확도")
        let world = Sim.world()
        let pointer = CGPoint(x: 800, y: 600)
        func rate(_ level: ThrowAccuracy, bias: Double = 0, seed: UInt64 = 1) -> (hit: Double, far: ClosedRange<CGFloat>?, onScreen: Bool) {
            let aim = ThrowAim(random: SeededRandomSource(seed: seed))
            aim.accuracy = level
            let pet = Sim.pet(at: CGPoint(x: 500, y: 80), appearance: Aimed(bias), behavior: IdleBehavior(duration: 9))
            var hits = 0, low = CGFloat.infinity, high: CGFloat = 0, onScreen = true
            for _ in 0..<4000 {
                let shot = aim.shot(at: pointer, by: pet, in: world)
                if !shot.missed { hits += 1; continue }
                let distance = hypot(shot.target.x - pointer.x, shot.target.y - pointer.y)
                low = min(low, distance); high = max(high, distance)
                if !world.contains(shot.target) { onScreen = false }
            }
            return (Double(hits) / 4000, high > 0 ? low...high : nil, onScreen)
        }
        let always = rate(.always), often = rate(.often), sometimes = rate(.sometimes), wild = rate(.wild)
        check.expect(always.hit == 1, "늘 명중은 빗나가지 않음")
        check.expect(abs(often.hit - 0.65) < 0.03 && abs(sometimes.hit - 0.35) < 0.03 && abs(wild.hit - 0.1) < 0.03,
                     "자주 65%·가끔 35%·엉망 10% 명중", "\(often.hit) \(sometimes.hit) \(wild.hit)")
        let k: CGFloat = 1.5 / 1.5
        check.expect(often.far.map { $0.lowerBound >= 30 * k - 0.01 && $0.upperBound <= 80 * k + 0.01 } == true
                     && wild.far.map { $0.lowerBound >= 60 * k - 0.01 && $0.upperBound <= 200 * k + 0.01 } == true,
                     "빗나간 거리: 자주 30~80, 엉망 60~200", "\(String(describing: often.far)) \(String(describing: wild.far))")
        check.expect(often.onScreen && wild.onScreen, "빗나가도 화면 안")
        check.expect(abs(rate(.often, bias: 0.15).hit - 0.80) < 0.03, "닌자처럼 +0.15면 자주 명중이 80%")
        check.expect(abs(rate(.wild, bias: -0.15).hit - ThrowAim.chanceFloor) < 0.02, "아무리 못해도 5%는 맞힘")
        check.expect(abs(rate(.often, bias: 0.5).hit - ThrowAim.chanceCeiling) < 0.02, "아무리 잘해도 95%까지")
        check.expect(rate(.always, bias: -0.5).hit == 1, "늘 명중은 성격과 상관없음")

        // 화면 구석의 포인터: 빗나가도 화면 밖으로 나가지 않음
        let corner = ThrowAim(random: SeededRandomSource(seed: 4))
        corner.accuracy = .wild
        let thrower = Sim.pet(at: CGPoint(x: 500, y: 80), behavior: IdleBehavior(duration: 9))
        let edge = CGPoint(x: 3, y: 997)
        check.expect((0..<500).allSatisfy { _ in world.contains(corner.shot(at: edge, by: thrower, in: world).target) }, "구석에서도 화면 안")

        // 던지기 동작: 빗나가면 무기도 빗나간 것으로 기억
        let missAll = ThrowAim(random: FixedRandom(0.99))
        missAll.accuracy = .wild
        let pet = Sim.pet(at: CGPoint(x: 500, y: 80), behavior: ThrowBehavior(at: pointer))
        pet.settle(in: world)
        var context = PetContext(cursor: pointer, planner: BehaviorPlanner(random: SeededRandomSource(seed: 2)))
        context.pointer = pointer
        context.aim = missAll
        var requests: [ThrowRequest] = []
        for _ in 0..<40 { pet.step(dt: Sim.dt, in: world, context: context); requests += pet.takeThrows() }
        check.expect(requests.count == 1 && requests[0].missed && requests[0].to != pointer, "빗나가게 던지면 포인터 옆으로", "\(requests)")
        let projectile = Projectile(id: "p", kind: .rock, throwerID: "x", from: .zero, to: CGPoint(x: 100, y: 100), scale: 1.5, missed: true)
        check.expect(projectile.missed && ProjectileDrawing(projectile).missed, "빗나간 무기는 닿은 자리에 먼지로 그림")
        let exact = Sim.pet(at: CGPoint(x: 500, y: 80), behavior: ThrowBehavior(at: pointer))
        exact.settle(in: world)
        context.aim = nil
        var plain: [ThrowRequest] = []
        for _ in 0..<40 { exact.step(dt: Sim.dt, in: world, context: context); plain += exact.takeThrows() }
        check.expect(plain.count == 1 && !plain[0].missed && plain[0].to == pointer, "겨냥 정보가 없으면 지금처럼 정확히")

        // 설정
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("deskpet-aim-\(UUID().uuidString).json")
        let settings = PetSettings(store: JSONFileSettingsStore(fileURL: file))
        check.expect(settings.throwAccuracy == .often, "기본은 자주 명중")
        settings.throwAccuracy = .wild
        check.expect(PetSettings(store: JSONFileSettingsStore(fileURL: file)).throwAccuracy == .wild, "고른 단계를 저장")
        check.expect(Set(ThrowAccuracy.allCases.map { MenuText.accuracy($0, in: .korean) }).count == 4
                     && MenuText.accuracy(.always, in: .korean) == "늘 명중", "단계 이름 (한국어)")
        try? FileManager.default.removeItem(at: file)

        // 스킨 metadata의 aim
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deskpet-aim-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Data(#"{"states":[{"frames":{}}],"deskpet":{"aim":0.9}}"#.utf8).write(to: folder.appendingPathComponent("metadata.json"))
        let skin = PetSkin<Int>(name: "T", directory: folder) { _ in nil }
        check.expect(skin.aimBias == 0.5, "스킨 aim 읽기 (-0.5~0.5로 자름)", "\(skin.aimBias)")
        try? FileManager.default.removeItem(at: folder)
    }
}
