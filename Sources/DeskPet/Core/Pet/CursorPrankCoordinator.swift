import Foundation

/// This object is responsible for the cursor prank (off unless the user turns it on): when the mouse pointer has rested
/// right by a free pet for a couple of seconds, that pet may snatch it and dash off with it for about a second.
/// It says where the pointer should be while it is held, and gives it back the instant the user moves the mouse.
/// It never pranks during calls, right after typing, or more often than once every couple of minutes.
final class CursorPrankCoordinator {
    /// 포인터가 이만큼 멈춰 있어야 잡음
    static let stillTime: TimeInterval = 2
    /// 펫 몸에서 이 안에 포인터가 있어야 잡음 (기준 크기)
    static let reach: CGFloat = 30
    /// 멈춤 한 번에 잡을 확률
    static let grabChance = 0.5
    /// 다음 장난까지
    static let cooldown: TimeInterval = 120
    /// 키를 누른 뒤 이만큼은 장난치지 않음
    static let typingGrace: TimeInterval = 2
    /// 둔 자리에서 포인터가 이만큼 벗어나면 사용자가 움직인 것
    static let letGoDistance: CGFloat = 4
    /// 달아날 자리가 이만큼은 있어야 함 (기준 크기)
    static let minimumRoom: CGFloat = 60

    var isEnabled = false {
        didSet { if !isEnabled { release() } }
    }
    /// 이번 틱에 포인터를 둘 자리 (펫이 쥐고 있을 때만)
    private(set) var heldCursor: CGPoint?
    private var previousHeld: CGPoint?
    private weak var carrier: Pet?
    private var clock: TimeInterval = 0
    private var lastCursor: CGPoint?
    private var stillSince: TimeInterval = 0
    private var triedThisRest = false
    private var lastPrank: TimeInterval = -.infinity
    var onEvent: ((String) -> Void)?

    /// cursor: 이번 틱 실제 포인터. sinceTyping: 마지막 키 누름 뒤 지난 시간
    func step(dt: TimeInterval, pets: [Pet], cursor: CGPoint?, world: World, planner: BehaviorPlanner,
              quiet: Bool, sinceTyping: TimeInterval) {
        clock += dt
        if let carrier {
            hold(carrier, cursor: cursor)
            return
        }
        guard isEnabled, !quiet, let cursor else { return }
        if let lastCursor, hypot(cursor.x - lastCursor.x, cursor.y - lastCursor.y) <= 0.5 {
            // 그대로 멈춰 있음
        } else {
            stillSince = clock
            triedThisRest = false
        }
        lastCursor = cursor
        guard !triedThisRest, clock - stillSince >= Self.stillTime, clock - lastPrank >= Self.cooldown,
              sinceTyping >= Self.typingGrace else { return }
        triedThisRest = true
        guard let pet = pets.first(where: { Self.canGrab($0, cursor: cursor) }), planner.chance(Self.grabChance),
              let direction = Self.escape(for: pet, in: world, among: pets) else { return }
        pet.switchTo(CursorCarryBehavior(direction: direction, duration: planner.uniform(0.9, 1.4)))
        carrier = pet
        lastPrank = clock
        heldCursor = CursorCarryBehavior.hand(of: pet)
        onEvent?("😆 [\(pet.id)] snatched the pointer, running \(direction.rawValue)")
    }

    /// 쥐고 있는 동안: 사용자가 움직였으면 바로 돌려주고 펫은 깜짝, 펫이 다 달렸으면 놓음, 아니면 손 위치로
    private func hold(_ pet: Pet, cursor: CGPoint?) {
        guard pet.behavior is CursorCarryBehavior else {
            onEvent?("👋 [\(pet.id)] let the pointer go")
            return release()
        }
        // 포인터 위치가 한 틱 늦게 반영될 수 있어 지난 두 자리 모두에서 벗어나야 사용자가 움직인 것
        let placed = [heldCursor, previousHeld].compactMap { $0 }
        if let cursor, !placed.isEmpty, placed.allSatisfy({ hypot(cursor.x - $0.x, cursor.y - $0.y) > Self.letGoDistance }) {
            pet.say(Chatter.surprised, for: 1)
            pet.switchTo(IdleBehavior(duration: 1, lookAtUser: true))
            onEvent?("✋ [\(pet.id)] pointer taken back")
            return release()
        }
        previousHeld = heldCursor
        heldCursor = CursorCarryBehavior.hand(of: pet)
    }

    private func release() {
        carrier = nil
        heldCursor = nil
        previousHeld = nil
    }

    /// 쉬거나 바라보던 펫, 몸 가까이에 포인터
    private static func canGrab(_ pet: Pet, cursor: CGPoint) -> Bool {
        pet.support != nil && !pet.isShowingNotice && !pet.isDragged
            && (pet.behavior.isAtLeisure || pet.behavior.name == "lookingAtUser")
            && pet.bodyRect.insetBy(dx: -reach * pet.motionScale, dy: -reach * pet.motionScale).contains(cursor)
    }

    /// 발판 끝과 다른 펫까지 자리가 더 넓은 쪽 (양쪽 다 좁으면 nil). 포인터 곁에 펫이 모여 있어도 막히지 않는 쪽으로
    private static func escape(for pet: Pet, in world: World, among pets: [Pet]) -> Facing? {
        guard let ledge = world.ledge(atX: pet.position.x, nearY: pet.position.y, tolerance: 1) else { return nil }
        let others = pets.map(PersonalSpace.sighting(of:)).filter { friend in
            friend.id != pet.id && friend.isObstacle && friend.support == pet.support?.owner && abs(friend.position.y - pet.position.y) < 2
        }
        let room = { (side: Facing) -> CGFloat in
            let sign = side.sign
            let edge = (side == .east ? ledge.maxX - pet.position.x : pet.position.x - ledge.minX) - pet.bodyHalfWidth
            let nearest = others
                .map { sign * ($0.position.x - pet.position.x) - PersonalSpace.spacing(pet, $0) }
                .filter { $0 > -PersonalSpace.gap }
                .min() ?? .infinity
            return min(edge, nearest)
        }
        let east = room(.east)
        let west = room(.west)
        guard max(east, west) >= minimumRoom * pet.motionScale else { return nil }
        return east >= west ? .east : .west
    }
}
