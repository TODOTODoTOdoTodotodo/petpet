import Foundation

/// This object is responsible for a pet using its character skill to leap onto the window the user is looking at:
/// a short wind-up in place, then a planned ballistic flight that either lands on the window top
/// or reaches the top edge at the peak and slips behind it to peek upside down,
/// or reaches a window's underside at the peak and clings to it upside down.
final class SkillLeapBehavior: PetBehavior {
    let name: String
    private let plan: LeapPlan
    private let style: SkillStyle
    private var flight: AirborneBehavior?
    private var elapsed: TimeInterval = 0
    private var flightElapsed: TimeInterval = 0
    private let windup: TimeInterval
    private let usesActionWindup: Bool

    init(plan: LeapPlan, style: SkillStyle, hasActionFrames: Bool) {
        self.plan = plan
        self.style = style
        self.name = "skill:\(style.rawValue)"
        // 공격 동작이 있는 스킨은 그 동작으로 준비 (몽둥이 짚기, 칼 휘두르기)
        self.usesActionWindup = hasActionFrames && style != .flameRocket
        self.windup = style == .flameRocket ? 0.7 : 0.45
    }

    var animation: AnimationKind {
        guard flight == nil else { return .airborne }
        return usesActionWindup ? .act : .idle
    }

    var effect: VisualEffect {
        switch (style, flight != nil) {
        case (.flameRocket, _):
            // 준비 중에도 불꽃을 모음
            return .trail(style)
        case (.poleVault, true), (.bigJump, true):
            // 도약 순간의 흙먼지만
            return flightElapsed < 0.3 ? .trail(style) : .none
        case (.slashJump, true):
            return flightElapsed < 0.6 ? .trail(style) : .none
        default:
            return .none
        }
    }

    func begin(_ pet: Pet) {
        pet.velocity = .zero
        pet.facing = plan.launch.dx >= 0 ? .east : .west
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard let flight else {
            // 발판 위면 제자리에서 준비, 공중이나 떨어지는 중이면 바로 출발
            if pet.support != nil {
                guard pet.followSupport(in: world) else { return AirborneBehavior.falling() }
                elapsed += dt
                guard elapsed >= windup else { return nil }
            }
            launch(pet)
            return nil
        }

        flightElapsed += dt
        let landed = flight.step(pet, in: world, context: context, dt: dt)
        if case .peek(let windowID, _, let footY) = plan.target,
           pet.velocity.dy <= 0 || pet.position.y >= footY - 1 {
            return grab(pet, windowID: windowID, footY: footY, in: world) ?? landed
        }
        if case .cling(let windowID, _, let footY) = plan.target,
           pet.velocity.dy <= 0 || pet.position.y >= footY - 1 {
            return cling(pet, windowID: windowID, footY: footY, in: world) ?? landed
        }
        return landed
    }

    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        pet.say(Chatter.surprised)
        return nil
    }

    private func launch(_ pet: Pet) {
        let airborne = AirborneBehavior(name: name, launch: plan.launch)
        airborne.begin(pet)
        flight = airborne
    }

    /// 최고점에서 아랫변에 거꾸로 달라붙음 (같은 자리에서 뒤집혀 발이 아랫변에). 못 미쳤거나 가려졌으면 그냥 떨어짐
    private func cling(_ pet: Pet, windowID: UInt32, footY: CGFloat, in world: World) -> PetBehavior? {
        guard let window = world.window(id: windowID), pet.position.y >= footY - 30,
              let edge = world.underside(atX: pet.position.x, nearY: window.frame.minY, tolerance: 1),
              edge.owner == .window(id: windowID) else { return nil }
        let x = min(max(pet.position.x, edge.minX + pet.bodyHalfWidth), edge.maxX - pet.bodyHalfWidth)
        pet.position = CGPoint(x: x, y: window.frame.minY)
        pet.velocity = .zero
        return CeilingWalkBehavior(windowID: windowID)
    }

    /// 최고점에서 윗변에 닿아 빼꼼을 시작함. 창이 사라졌으면 그냥 떨어짐
    private func grab(_ pet: Pet, windowID: UInt32, footY: CGFloat, in world: World) -> PetBehavior? {
        // 천장·벽에 막혀 목표 높이에 못 미쳤으면 숨지 않고 그대로 떨어짐
        guard let window = world.window(id: windowID), pet.position.y >= footY - 30 else { return nil }
        let x = min(max(pet.position.x, window.frame.minX + pet.bodyHalfWidth), window.frame.maxX - pet.bodyHalfWidth)
        pet.position = CGPoint(x: x, y: window.frame.maxY - pet.bodyHeight - LeapPlanner.gripGap)
        pet.velocity = .zero
        return PeekBehavior(windowID: windowID, offsetX: x - window.frame.minX)
    }
}
