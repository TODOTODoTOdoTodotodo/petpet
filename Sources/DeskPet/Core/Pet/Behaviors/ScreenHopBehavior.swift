import Foundation

/// This object is responsible for a pet crossing to the display where the user is now looking:
/// it fades out in place with its skill effect, reappears on that display's floor,
/// then (when given a window) leaps onto it with its skill if it can; otherwise it rests on that display.
final class ScreenHopBehavior: PetBehavior {
    let name = "screenHop"
    let animation: AnimationKind = .idle
    /// 나타난 뒤 도약할 창 (없으면 그 자리에서 쉼)
    private let windowID: UInt32?
    private let arrival: CGPoint
    private let style: SkillStyle
    private let hasActionFrames: Bool
    private var elapsed: TimeInterval = 0
    private var arrived = false

    static let fadeOut: TimeInterval = 0.5
    static let travel: TimeInterval = 0.25
    static let fadeIn: TimeInterval = 0.5
    static var duration: TimeInterval { fadeOut + travel + fadeIn }

    init(windowID: UInt32?, arrival: CGPoint, style: SkillStyle, hasActionFrames: Bool) {
        self.windowID = windowID
        self.arrival = arrival
        self.style = style
        self.hasActionFrames = hasActionFrames
    }

    var opacity: CGFloat {
        if elapsed < Self.fadeOut { return CGFloat(1 - elapsed / Self.fadeOut) }
        if elapsed < Self.fadeOut + Self.travel { return 0 }
        return CGFloat(min(1, (elapsed - Self.fadeOut - Self.travel) / Self.fadeIn))
    }

    var effect: VisualEffect { opacity > 0 ? .trail(style) : .none }

    func begin(_ pet: Pet) {
        pet.velocity = .zero
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        elapsed += dt
        guard arrived else {
            // 사라지는 동안 딛던 창이 움직이면 따라감 (실패해도 곧 떠나므로 무시)
            if pet.support != nil { _ = pet.followSupport(in: world) }
            if elapsed >= Self.fadeOut + Self.travel { arrive(pet, in: world) }
            return nil
        }
        guard pet.support != nil else { return AirborneBehavior.falling() }
        guard elapsed >= Self.duration else { return nil }
        if let windowID, let plan = LeapPlanner.plan(for: pet, to: windowID, in: world) {
            return SkillLeapBehavior(plan: plan, style: style, hasActionFrames: hasActionFrames)
        }
        return context.planner.rest()
    }

    /// 사라진 상태에서는 클릭을 받지 않음
    func poked(_ pet: Pet, streak: Int) -> PetBehavior? { nil }

    private func arrive(_ pet: Pet, in world: World) {
        arrived = true
        pet.support = nil
        pet.position = arrival
        if let window = windowID.flatMap(world.window(id:)) {
            pet.facing = window.frame.midX >= arrival.x ? .east : .west
        }
        pet.settle(in: world)
    }
}

/// This object is responsible for choosing where a pet reappears when it crosses to another display:
/// on that display's floor, as close to the wanted spot (under the window) as the floor allows. Pure calculation.
enum ScreenHopPlanner {
    static func arrival(for pet: Pet, to window: WindowSnapshot, in world: World) -> CGPoint? {
        guard let target = world.screen(of: window) else { return nil }
        return arrival(for: pet, on: target, nearX: window.frame.midX, in: world)
    }

    /// 펫이 이미 그 모니터에 있으면 nil
    static func arrival(for pet: Pet, on target: ScreenArea, nearX x: CGFloat, in world: World) -> CGPoint? {
        guard world.screen(containing: CGPoint(x: pet.position.x, y: pet.position.y + 1))?.id != target.id else { return nil }
        let margin = pet.bodyHalfWidth + 6
        let floors = world.ledges.filter { $0.owner == .ground(screenID: target.id) && $0.maxX - $0.minX >= margin * 2 }
        let spots = floors.map { ledge in
            CGPoint(x: min(max(x, ledge.minX + margin), ledge.maxX - margin), y: ledge.y)
        }
        return spots.min { abs($0.x - x) < abs($1.x - x) }
    }
}
