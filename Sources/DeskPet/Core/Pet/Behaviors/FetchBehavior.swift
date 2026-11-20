import Foundation

/// This object is responsible for a pet going to pick up an item: walking to it (running when far),
/// passing pets in the way by the usual rules, stopping in front of it for a short grab (attack frames, or a hop
/// without them), then saying ✨ (🌟 for a rare one) as the item flies off to the collection.
/// It gives up quietly when the item is gone, taken, or the way is blocked.
final class FetchBehavior: PetBehavior {
    let name = "fetching"
    let occupiesSpace = true
    private weak var item: DroppedItem?
    /// 주운 뒤 물건이 날아갈 곳
    private let deliverTo: CGPoint
    private var grabbing: TimeInterval?
    private var hasActionFrames = false
    private var speed: CGFloat = PetPhysics.walkSpeed

    /// 이보다 멀면 뜀 (기준 크기)
    static let runDistance: CGFloat = 80
    /// 줍기 동작 시간
    static let grabTime: TimeInterval = 0.3
    static let foundText = "✨"
    static let rareText = "🌟"

    init(item: DroppedItem, deliverTo: CGPoint) {
        self.item = item
        self.deliverTo = deliverTo
    }

    /// 이 물건을 가지러 가는 중인지
    func isFetching(_ other: DroppedItem) -> Bool { item === other }

    var animation: AnimationKind {
        guard grabbing != nil else { return .walk }
        return hasActionFrames ? .act : .idle
    }

    var animationSpeed: Double { grabbing == nil ? Double(speed / PetPhysics.walkSpeed) : 1 }
    var heading: Facing? { grabbing == nil ? direction : nil }
    private var direction: Facing?

    func begin(_ pet: Pet) {
        hasActionFrames = pet.appearance.supports(.act)
        pet.velocity = .zero
        if let item { pet.facing = item.position.x >= pet.position.x ? .east : .west }
        direction = pet.facing
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard pet.followSupport(in: world) else { return AirborneBehavior.falling() }
        guard let item, item.isResting || grabbing != nil else { return context.planner.rest() }

        if let held = grabbing {
            grabbing = held + dt
            guard held + dt >= Self.grabTime else { return nil }
            return pickUp(item, by: pet, context: context)
        }

        let sameLedge = abs(item.position.y - pet.position.y) <= 3 && item.support?.owner == pet.support?.owner
        let goal = sameLedge ? item.position.x : Self.dropOffX(for: pet, toward: item, in: world)
        let gap = goal - pet.position.x
        let reach = pet.bodyHalfWidth * 0.5 + item.halfWidth
        if sameLedge && abs(gap) <= reach {
            pet.facing = gap >= 0 ? .east : .west
            grabbing = 0
            return nil
        }

        pet.facing = gap > 0 ? .east : .west
        direction = pet.facing
        let k = pet.motionScale
        speed = abs(gap) > Self.runDistance * k ? PetPhysics.sprintSpeed : PetPhysics.walkSpeed
        let sign = pet.facing.sign
        let travel = sameLedge ? min(speed * k * CGFloat(dt), max(abs(gap) - reach * 0.5, 0)) : speed * k * CGFloat(dt)
        let nextX = pet.position.x + sign * travel
        let frontNow = pet.position.x + sign * pet.bodyHalfWidth
        let frontNext = nextX + sign * pet.bodyHalfWidth

        guard world.contains(CGPoint(x: frontNext, y: pet.position.y + 1)),
              world.wall(hitMovingEast: sign > 0, from: frontNow, to: frontNext,
                         bottom: pet.position.y, top: pet.position.y + pet.bodyHeight) == nil else {
            return context.planner.rest()
        }
        if let blocker = PersonalSpace.blocker(ahead: pet, toX: nextX, among: context.friends) {
            // 같은 쪽으로 가는 펫 뒤에서는 줍기를 그만두지 않고 그 자리에서 따라감
            if blocker.heading == pet.facing { return nil }
            pet.position.x = PersonalSpace.stopX(for: pet, before: blocker)
            return context.planner.pass(pet, blocker: blocker, targetX: item.position.x,
                                        hurried: speed > PetPhysics.walkSpeed, in: world, context: context)
        }
        pet.position.x = nextX
        if !pet.settle(in: world) {
            // 다른 발판의 물건: 끝에서 내려가 그쪽으로
            return AirborneBehavior.falling(drift: sign * speed * k * 0.5)
        }
        return nil
    }

    /// 아래 다른 발판의 물건: 물건이 지금 발판 밖이면 그쪽으로, 바로 밑이면 가까운 끝 너머로 걸어 내려감
    static func dropOffX(for pet: Pet, toward item: DroppedItem, in world: World) -> CGFloat {
        guard let ledge = world.ledge(atX: pet.position.x, nearY: pet.position.y, tolerance: 1),
              ledge.spans(item.position.x) else { return item.position.x }
        let overshoot = pet.bodyHalfWidth * 2
        return item.position.x - ledge.minX <= ledge.maxX - item.position.x ? ledge.minX - overshoot : ledge.maxX + overshoot
    }

    private func pickUp(_ item: DroppedItem, by pet: Pet, context: PetContext) -> PetBehavior {
        guard item.pickUp(by: pet.id, flyingTo: deliverTo) else { return context.planner.rest() }
        let rare = item.kind.rarity == .rare
        pet.say(rare ? Self.rareText : Self.foundText, for: rare ? 2.2 : 1.4)
        pet.note(.pickedUp)
        // 드문 물건은 늘 기뻐 깡충
        if hasActionFrames && !rare { return IdleBehavior(duration: 0.8, lookAtUser: true, name: "showingFind") }
        return AirborneBehavior.hop(name: "hopping", motionScale: pet.motionScale)
    }

    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        GroundReaction.poked(pet, streak: streak)
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        GroundReaction.announcing(pet, for: duration)
    }
}
