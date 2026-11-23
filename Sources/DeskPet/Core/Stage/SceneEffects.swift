import Foundation

/// 무대가 그릴 반짝임·입자 하나 (전역 좌표)
struct EffectSpark: Equatable {
    enum Look: Equatable {
        /// 노란 반짝임 (발자국 색 단계: 0 기본, 1 분홍, 2 금색)
        case burst(tier: Int)
        /// 둥근 입자 (꼬리), 색 0xRRGGBB
        case dot(rgb: UInt32)
    }

    let look: Look
    let center: CGPoint
    let side: CGFloat
    let alpha: CGFloat
    /// 펫보다 앞에 그리는지 (드문 물건 꼬리). 아니면 펫 뒤 (발자국·도약 꼬리)
    let front: Bool
}

/// This object is responsible for the short-lived sparkles a software stage adds to the scene, the same way the macOS
/// stage's SpriteKit actions and emitters do: footstep glints while a Lv.5 pet walks, glints behind a rare item flying
/// to the menu bar, and the dust, flame or slash-wind trail behind a skill leap. Particles stay where they were emitted.
/// Each `step` is one 1/60 s tick; randomness is injected so checks can repeat it.
final class SceneEffects {
    /// 한 번에 남길 입자 수 상한 (느린 PC에서 그리기가 밀리지 않게)
    static let maxSparks = 400

    private struct Particle {
        var look: EffectSpark.Look
        var position: CGPoint
        var velocity: CGVector
        var age: TimeInterval = 0
        let lifetime: TimeInterval
        var side: CGFloat
        let sideSpeed: CGFloat
        var alpha: CGFloat
        let alphaSpeed: CGFloat
        /// 수명 비율에 따라 바뀌는 색 (꼬리 불꽃)
        let colors: [(time: Double, rgb: UInt32)]
        let front: Bool
    }

    private let random: () -> Double
    private var particles: [Particle] = []
    /// 펫별 다음 발자국까지 남은 시간
    private var stepClock: [String: TimeInterval] = [:]
    /// 펫별 꼬리 입자 뿜기에서 남은 몫
    private var trailDebt: [String: Double] = [:]

    init(random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.random = random
    }

    var sparks: [EffectSpark] {
        particles.map { particle in
            var look = particle.look
            if case .dot = look, !particle.colors.isEmpty { look = .dot(rgb: Self.color(in: particle.colors, at: particle.age / particle.lifetime)) }
            return EffectSpark(look: look, center: particle.position, side: particle.side, alpha: particle.alpha, front: particle.front)
        }
    }

    /// 한 틱 진행: 있던 입자를 움직이고 다 된 것을 지운 뒤, 이번 장면에서 새 입자를 뿜음
    func step<Frame>(_ scene: Scene<Frame>) {
        let dt = 1.0 / 60
        for index in particles.indices {
            particles[index].age += dt
            particles[index].position.x += particles[index].velocity.dx * CGFloat(dt)
            particles[index].position.y += particles[index].velocity.dy * CGFloat(dt)
            particles[index].side = max(particles[index].side + particles[index].sideSpeed * CGFloat(dt), 0)
            particles[index].alpha = max(particles[index].alpha + particles[index].alphaSpeed * CGFloat(dt), 0)
        }
        particles.removeAll { $0.age >= $0.lifetime || $0.alpha <= 0 || $0.side <= 0 }

        let live = Set(scene.pets.map(\.id))
        stepClock = stepClock.filter { live.contains($0.key) }
        trailDebt = trailDebt.filter { live.contains($0.key) }
        for pet in scene.pets {
            footstep(pet)
            trail(pet, dt: dt)
        }
        for item in scene.items where item.trail && random() < 0.5 {
            // 날아간 자리에 0.5초 남아 작아지며 사라짐
            add(Particle(look: .burst(tier: 0),
                         position: CGPoint(x: item.rect.midX + jitter(3), y: item.rect.midY + jitter(3)),
                         velocity: CGVector(dx: 0, dy: 0), lifetime: 0.5, side: item.rect.width, sideSpeed: -item.rect.width * 0.7 / 0.5,
                         alpha: 0.8, alphaSpeed: -0.8 / 0.5, colors: [], front: true))
        }
    }

    /// 걸을 때 0.15초마다 반반 확률로 발밑에 옅은 반짝임 (0.6초 동안 떠오르며 사라짐)
    private func footstep<Frame>(_ pet: PetDrawing<Frame>) {
        guard pet.sparkles else { return }
        let left = (stepClock[pet.id] ?? 0) - 1.0 / 60
        guard left <= 0 else {
            stepClock[pet.id] = left
            return
        }
        stepClock[pet.id] = 0.15
        guard random() < 0.5 else { return }
        let alpha = 0.55 * pet.alpha
        add(Particle(look: .burst(tier: pet.sparkleTier), position: CGPoint(x: pet.foot.x + jitter(4), y: pet.foot.y + 2),
                     velocity: CGVector(dx: 0, dy: 6 / 0.6), lifetime: 0.6, side: pet.rect.width / 48 * 6, sideSpeed: 0,
                     alpha: alpha, alphaSpeed: -alpha / 0.6, colors: [], front: false))
    }

    /// 스킬 도약 꼬리: 맥 SkillTrailNode의 입자 설정 그대로 (발 또는 몸 가운데에서 뿜음)
    private func trail<Frame>(_ pet: PetDrawing<Frame>, dt: TimeInterval) {
        guard let style = pet.trail else {
            trailDebt[pet.id] = nil
            return
        }
        let recipe = TrailRecipe(style)
        var debt = (trailDebt[pet.id] ?? 0) + recipe.birthRate * dt
        let origin = CGPoint(x: pet.foot.x, y: pet.foot.y + (style == .slashJump ? pet.bodyHeight * 0.55 : 2))
        while debt >= 1 {
            debt -= 1
            let angle = recipe.angle + (random() - 0.5) * recipe.angleRange
            let speed = recipe.speed + (random() - 0.5) * recipe.speedRange
            add(Particle(look: .dot(rgb: recipe.colors.first?.rgb ?? 0xFFFFFF), position: origin,
                         velocity: CGVector(dx: CGFloat(cos(angle) * speed), dy: CGFloat(sin(angle) * speed)),
                         lifetime: recipe.lifetime, side: 8 * recipe.scale, sideSpeed: 8 * recipe.scaleSpeed,
                         alpha: 1, alphaSpeed: recipe.alphaSpeed, colors: recipe.colors.count > 1 ? recipe.colors : [], front: false))
        }
        trailDebt[pet.id] = debt
    }

    private func add(_ particle: Particle) {
        guard particles.count < Self.maxSparks else { return }
        particles.append(particle)
    }

    private func jitter(_ reach: Double) -> CGFloat {
        CGFloat((random() * 2 - 1) * reach)
    }

    /// 수명 비율 t의 색 (앞뒤 열쇠 색 사이를 곧게 섞음)
    private static func color(in keys: [(time: Double, rgb: UInt32)], at t: Double) -> UInt32 {
        guard let last = keys.last else { return 0xFFFFFF }
        guard let next = keys.firstIndex(where: { $0.time >= t }) else { return last.rgb }
        guard next > 0 else { return keys[0].rgb }
        let from = keys[next - 1], to = keys[next]
        let share = (t - from.time) / max(to.time - from.time, 0.0001)
        var mixed: UInt32 = 0
        for shift in [16, 8, 0] as [UInt32] {
            let a = Double((from.rgb >> shift) & 0xFF), b = Double((to.rgb >> shift) & 0xFF)
            mixed |= UInt32((a + (b - a) * share).rounded()) << shift
        }
        return mixed
    }
}

/// 스킬 도약 꼬리 입자 설정 (맥 SkillTrailNode와 같은 값, 각도는 라디안·위로 +y)
struct TrailRecipe {
    let birthRate: Double
    let lifetime: Double
    let speed: Double
    let speedRange: Double
    let angle: Double
    let angleRange: Double
    let scale: CGFloat
    let scaleSpeed: CGFloat
    let alphaSpeed: CGFloat
    let colors: [(time: Double, rgb: UInt32)]

    init(_ style: SkillStyle) {
        switch style {
        case .flameRocket:
            (birthRate, lifetime, speed, speedRange, angle, angleRange) = (140, 0.45, 70, 30, -.pi / 2, 0.7)
            (scale, scaleSpeed, alphaSpeed) = (0.9, -1.6, -1.8)
            colors = [(0, 0xFFF280), (0.4, 0xFF731A), (1, 0x991A0D)]
        case .slashJump:
            (birthRate, lifetime, speed, speedRange, angle, angleRange) = (110, 0.35, 90, 40, 0, .pi * 2)
            (scale, scaleSpeed, alphaSpeed) = (0.7, -1.5, -2.6)
            colors = [(0, 0xD9F2FF)]
        case .poleVault, .bigJump:
            (birthRate, lifetime, speed, speedRange, angle, angleRange) = (220, 0.6, 55, 35, .pi / 2, .pi)
            (scale, scaleSpeed, alphaSpeed) = (1.0, -1.2, -1.5)
            colors = [(0, 0xB89E80)]
        }
    }
}
