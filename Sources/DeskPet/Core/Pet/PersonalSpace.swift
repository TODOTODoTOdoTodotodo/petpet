import Foundation

/// This object is responsible for the rule that pets standing on the same ledge never overlap:
/// it finds the pet blocking a walker's next step and where the walker stops in front of it.
enum PersonalSpace {
    /// 나란히 설 때 몸 사이 틈
    static let gap: CGFloat = 2

    /// 이 펫(자리 차지하는 펫)이 보는 친구 모습
    static func sighting(of pet: Pet) -> FriendSighting {
        FriendSighting(
            id: pet.id, position: pet.position, halfWidth: pet.bodyHalfWidth, height: pet.bodyHeight,
            support: pet.support?.owner,
            isObstacle: pet.behavior.occupiesSpace && pet.support != nil && !pet.isDragged,
            isJumpable: pet.behavior.towerLevel == nil,
            heading: pet.behavior.heading
        )
    }

    /// 두 펫이 나란히 설 때 중심 사이 거리
    static func spacing(_ pet: Pet, _ friend: FriendSighting) -> CGFloat {
        pet.bodyHalfWidth + friend.halfWidth + gap
    }

    /// pet이 nextX로 한 걸음 가면 몸이 겹치는 앞쪽 가장 가까운 펫 (같은 발판, 같은 높이)
    static func blocker(ahead pet: Pet, toX nextX: CGFloat, among friends: [FriendSighting]) -> FriendSighting? {
        blocker(for: pet, sign: pet.facing.sign, toX: nextX, among: friends)
    }

    /// sign 쪽(+1 동, -1 서)으로 nextX까지 움직이면 몸이 겹치는 가장 가까운 펫
    static func blocker(for pet: Pet, sign: CGFloat, toX nextX: CGFloat, among friends: [FriendSighting]) -> FriendSighting? {
        guard let support = pet.support?.owner else { return nil }
        return friends
            .filter { friend in
                friend.id != pet.id && friend.isObstacle && friend.support == support
                    && abs(friend.position.y - pet.position.y) < 2
                    && sign * (friend.position.x - pet.position.x) > 0
                    && sign * (friend.position.x - nextX) < spacing(pet, friend)
            }
            .min { abs($0.position.x - pet.position.x) < abs($1.position.x - pet.position.x) }
    }

    /// 막은 펫 앞에 멈출 x. 이미 그보다 들어가 있으면(겹쳐 있으면) 지금 자리
    static func stopX(for pet: Pet, before friend: FriendSighting) -> CGFloat {
        stopX(for: pet, sign: pet.facing.sign, before: friend)
    }

    static func stopX(for pet: Pet, sign: CGFloat, before friend: FriendSighting) -> CGFloat {
        let contact = friend.position.x - sign * spacing(pet, friend)
        return sign * (contact - pet.position.x) >= 0 ? contact : pet.position.x
    }

    /// pet이 x에 서도 except 말고 다른 펫과 겹치지 않는지
    static func isFree(_ x: CGFloat, for pet: Pet, among friends: [FriendSighting], except ids: Set<String>) -> Bool {
        !friends.contains { friend in
            !ids.contains(friend.id) && friend.id != pet.id && friend.isObstacle && friend.support == pet.support?.owner
                && abs(friend.position.y - pet.position.y) < 2 && abs(friend.position.x - x) < spacing(pet, friend)
        }
    }
}

/// This object is responsible for settling pets that already overlap on a ledge (one landed or appeared on another):
/// the freer one walks aside, or hops over when there is no room on its side,
/// and for answering a pet's challenge to a duel when the pet in its way is free to fight.
final class PersonalSpaceCoordinator {
    /// 이만큼 넘게 겹치면 비켜 섬
    static let overlapTolerance: CGFloat = 2
    /// 결투를 받아 줄 수 있는 거리 (기준 크기)
    static let duelReach: CGFloat = 80

    var onEvent: ((String) -> Void)?

    /// 비켜 설 수 없는 겹친 펫끼리 서로 밀어내는 속도 (기준 크기, 한 마리당)
    static let pushSpeed: CGFloat = 40

    func step(dt: TimeInterval, pets: [Pet], world: World, planner: BehaviorPlanner, social: PetSocialCoordinator, allowsDuels: Bool) {
        answerChallenges(pets: pets, planner: planner, social: social, allowsDuels: allowsDuels)
        makeRoom(dt: dt, pets: pets, world: world, planner: planner)
    }

    /// 결투를 건 펫과 막은 펫이 둘 다 대결할 수 있으면 대결 시작. 아니면 건 펫이 기다리다 뛰어넘음
    private func answerChallenges(pets: [Pet], planner: BehaviorPlanner, social: PetSocialCoordinator, allowsDuels: Bool) {
        guard allowsDuels else { return }
        for challenger in pets {
            guard let id = challenger.behavior.challengedID,
                  let opponent = pets.first(where: { $0.id == id }), Self.canAccept(opponent),
                  opponent.support?.owner == challenger.support?.owner,
                  abs(opponent.position.x - challenger.position.x) <= Self.duelReach * challenger.motionScale else { continue }
            social.duel(challenger, opponent, planner: planner)
        }
    }

    /// 깨어 있고 가만히 있거나 걷는 중이며 알림을 들고 있지 않아야 결투를 받음
    private static func canAccept(_ pet: Pet) -> Bool {
        !pet.isShowingNotice && !pet.isDragged && pet.support != nil && !(pet.behavior is SleepBehavior)
            && (pet.behavior.isAtLeisure || pet.behavior is IdleBehavior || pet.behavior is GlanceBehavior)
    }

    private func makeRoom(dt: TimeInterval, pets: [Pet], world: World, planner: BehaviorPlanner) {
        let friends = pets.map(PersonalSpace.sighting(of:))
        for (index, first) in pets.enumerated() {
            for second in pets[(index + 1)...] where overlap(first, second) {
                // 나중에 온 쪽(목록 뒤쪽)부터, 비킬 수 있는 펫이 걸어서 비킴. 그럴 수 없으면 서로 천천히 밀어냄
                if let mover = [second, first].first(where: Self.canStepAside) {
                    let other = mover === second ? first : second
                    if let move = aside(mover, from: other, world: world, planner: planner, friends: friends) {
                        mover.switchTo(move)
                        onEvent?("↔️ [\(mover.id)] makes room for [\(other.id)]")
                        continue
                    }
                }
                push(first, second, dt: dt, world: world)
            }
        }
    }

    /// 겹친 두 펫을 서로 반대쪽으로 조금씩 밀어냄. 한쪽이 발판 끝·다른 펫에 막히면 다른 쪽이 더 감
    private func push(_ first: Pet, _ second: Pet, dt: TimeInterval, world: World) {
        let away: CGFloat = first.position.x == second.position.x ? (first.id < second.id ? -1 : 1)
                                                                  : (first.position.x > second.position.x ? 1 : -1)
        let step = Self.pushSpeed * first.motionScale * CGFloat(dt)
        let movedFirst = nudge(first, by: away * step, world: world)
        let movedSecond = nudge(second, by: -away * step, world: world)
        if !movedFirst { nudge(second, by: -away * step, world: world) }
        if !movedSecond { nudge(first, by: away * step, world: world) }
    }

    /// 펫을 dx만큼 옆으로. 발판·화면을 벗어나면 움직이지 않음. 자는 펫은 밀리지 않음.
    /// 탑 맨 아래는 밀리며 위 펫들이 머리를 따라옴 (두 탑이 겹쳐 시작해도 벌어짐).
    /// 그 너머 펫과 새로 겹치면 그 둘이 다음 틱에 또 밀어내어, 붐비는 곳은 바깥쪽부터 차례로 벌어짐
    @discardableResult
    private func nudge(_ pet: Pet, by dx: CGFloat, world: World) -> Bool {
        guard !(pet.behavior is SleepBehavior), (pet.behavior.towerLevel ?? 0) == 0, !(pet.behavior is WalkBehavior) else { return false }
        let x = pet.position.x + dx
        guard world.ledge(atX: x, nearY: pet.position.y, tolerance: 1, margin: pet.bodyHalfWidth * 0.6) != nil,
              world.contains(CGPoint(x: x + (dx > 0 ? 1 : -1) * pet.bodyHalfWidth, y: pet.position.y + 1)) else { return false }
        pet.position.x = x
        return true
    }

    /// 같은 발판 같은 높이에서 둘 다 자리를 차지하며 몸이 겹침 (걷는 펫은 스스로 멈추므로 제외)
    private func overlap(_ first: Pet, _ second: Pet) -> Bool {
        let a = PersonalSpace.sighting(of: first)
        let b = PersonalSpace.sighting(of: second)
        guard a.isObstacle, b.isObstacle, a.support == b.support, abs(a.position.y - b.position.y) < 2,
              !(first.behavior is WalkBehavior), !(second.behavior is WalkBehavior) else { return false }
        return abs(a.position.x - b.position.x) < a.halfWidth + b.halfWidth - Self.overlapTolerance
    }

    /// 쉬거나 바라보는 중인 펫만 비킴 (잠·알림·대결·탑 맨 아래는 그대로)
    private static func canStepAside(_ pet: Pet) -> Bool {
        !pet.isShowingNotice && (pet.behavior is IdleBehavior || pet.behavior is GlanceBehavior)
    }

    /// 겹친 펫 옆 빈자리로 비킴: 내 쪽이 비었으면 걸어가고, 반대쪽만 비었으면 뛰어넘음. 둘 다 막혔으면 nil
    private func aside(_ mover: Pet, from other: Pet, world: World, planner: BehaviorPlanner, friends: [FriendSighting]) -> PetBehavior? {
        let friend = PersonalSpace.sighting(of: other)
        let away: CGFloat = mover.position.x == other.position.x ? (mover.id < other.id ? -1 : 1)
                                                                  : (mover.position.x > other.position.x ? 1 : -1)
        let reach = PersonalSpace.spacing(mover, friend) + 14 * mover.motionScale
        let roomy = { (x: CGFloat, side: CGFloat) -> Bool in
            world.ledge(atX: x, nearY: mover.position.y, tolerance: 1, margin: mover.bodyHalfWidth * 0.6) != nil
                && world.contains(CGPoint(x: x + side * mover.bodyHalfWidth, y: mover.position.y + 1))
                && PersonalSpace.isFree(x, for: mover, among: friends, except: [other.id])
        }
        let near = other.position.x + away * reach
        if roomy(near, away) {
            let speed = PetPhysics.walkSpeed * 0.8
            return WalkBehavior(name: "makingRoom", direction: away > 0 ? .east : .west, speed: speed,
                                duration: TimeInterval(abs(near - mover.position.x) / (speed * mover.motionScale)) + 1, targetX: near)
        }
        guard roomy(other.position.x - away * reach, -away) else { return nil }
        mover.facing = away > 0 ? .west : .east
        return planner.leapfrog(mover, over: friend, in: world)
    }
}
