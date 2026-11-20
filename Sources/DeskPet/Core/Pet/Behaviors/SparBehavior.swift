import Foundation

/// This object is responsible for the shared script of one play-fight between two pets:
/// how many exchanges, who strikes first, who gives up at the end, and whether it was called off.
final class SparMatch {
    /// 한 번 주고받는 시간
    static let roundTime: TimeInterval = 0.9
    /// 공격이 닿는 순간 (라운드 안)
    static let hitAt: TimeInterval = 0.35
    /// 끝인사 시간
    static let finaleTime: TimeInterval = 1.4

    let rounds: Int
    let firstAttacker: Int
    let winner: Int
    /// 클릭·일정 알림 등으로 중단됨
    private(set) var isCalledOff = false

    init(rounds: Int, firstAttacker: Int, winner: Int) {
        self.rounds = rounds
        self.firstAttacker = firstAttacker
        self.winner = winner
    }

    var duration: TimeInterval { Double(rounds) * Self.roundTime + Self.finaleTime }

    func attacker(inRound round: Int) -> Int {
        (firstAttacker + round) % 2
    }

    func callOff() {
        isCalledOff = true
    }
}

/// This object is responsible for one pet's side of a play-fight: facing the other pet,
/// taking turns swinging its attack (or lunging when it has no attack frames), getting knocked back with 💥,
/// and ending with ✌️ or 🏳️. It is friendly sparring, never damage.
final class SparBehavior: PetBehavior {
    let name = "sparring"
    let occupiesSpace = true
    private let match: SparMatch
    private let side: Int
    private let opponentX: CGFloat
    private let hasActionFrames: Bool
    /// 길을 지나가려고 건 결투면 상대 ID (이기면 뛰어넘고, 지면 돌아섬)
    private let passingID: String?
    private var elapsed: TimeInterval = 0
    private var round = -1
    private var attacking = false
    private var wasHit = false
    private var finaleShown = false
    /// 남은 밀려남 시간
    private var knockback: TimeInterval = 0
    /// 시작할 때 너무 붙어 있으면 물러설 남은 거리
    private var backOff: CGFloat = 0

    static let knockbackTime: TimeInterval = 0.2
    /// 한 번 맞을 때 밀려나는 거리 (펫 크기 1.5배 기준)
    static let knockbackDistance: CGFloat = 12
    static let hitText = "💥"
    static let winText = "✌️"
    static let loseText = "🏳️"

    init(match: SparMatch, side: Int, opponentX: CGFloat, hasActionFrames: Bool, passingID: String? = nil) {
        self.match = match
        self.side = side
        self.opponentX = opponentX
        self.hasActionFrames = hasActionFrames
        self.passingID = passingID
    }

    var animation: AnimationKind {
        guard attacking else { return .idle }
        return hasActionFrames ? .act : .walk
    }

    /// 대결할 때 두 몸 사이 틈 (기준 크기)
    static let fightingGap: CGFloat = 8
    /// 물러서는 속도 (기준 크기)
    static let backOffSpeed: CGFloat = 120

    func begin(_ pet: Pet) {
        pet.velocity = .zero
        pet.facing = opponentX >= pet.position.x ? .east : .west
        // 상대도 같은 만큼 물러서므로 모자란 틈의 절반만
        let needed = 2 * pet.bodyHalfWidth + Self.fightingGap * pet.motionScale
        backOff = max(needed - abs(opponentX - pet.position.x), 0) / 2
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard pet.followSupport(in: world) else {
            match.callOff()
            return AirborneBehavior.falling()
        }
        guard !match.isCalledOff else { return context.planner.rest() }
        if backOff > 0 {
            let step = min(backOff, Self.backOffSpeed * pet.motionScale * CGFloat(dt))
            backOff -= step
            if !retreat(pet, by: step, in: world, friends: context.friends) { backOff = 0 }
            return nil
        }
        elapsed += dt

        let current = Int(elapsed / SparMatch.roundTime)
        if current < match.rounds {
            if current != round {
                round = current
                attacking = match.attacker(inRound: current) == side
                wasHit = false
                if attacking { pet.restartAnimation() }
            }
            let local = elapsed - Double(current) * SparMatch.roundTime
            if !attacking, !wasHit, local >= SparMatch.hitAt {
                wasHit = true
                knockback = Self.knockbackTime
                pet.say(Self.hitText, for: 0.5)
            }
        } else if !finaleShown {
            finaleShown = true
            attacking = false
            pet.say(side == match.winner ? Self.winText : Self.loseText, for: SparMatch.finaleTime)
            if side == match.winner { pet.note(.wonDuel) }
        }

        if knockback > 0, !slide(pet, dt: dt, in: world, friends: context.friends) {
            match.callOff()
            return AirborneBehavior.falling()
        }
        return elapsed >= match.duration ? finish(pet, in: world, context: context) : nil
    }

    /// 끝난 뒤: 지나가려던 펫이 이겼으면 상대를 뛰어넘고, 졌으면 돌아섬. 그 밖에는 쉼
    private func finish(_ pet: Pet, in world: World, context: PetContext) -> PetBehavior {
        guard let passingID, let opponent = context.friends.first(where: { $0.id == passingID }) else { return context.planner.rest() }
        if side == match.winner {
            pet.facing = opponent.position.x >= pet.position.x ? .east : .west
            return context.planner.leapfrog(pet, over: opponent, in: world) ?? context.planner.rest()
        }
        let away: Facing = opponent.position.x >= pet.position.x ? .west : .east
        return WalkBehavior(direction: away, duration: context.planner.strollDuration())
    }

    /// 클릭하면 대결을 그만두고 평소 반응
    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        match.callOff()
        return GroundReaction.poked(pet, streak: streak)
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        match.callOff()
        return GroundReaction.announcing(pet, for: duration)
    }

    /// 상대 반대쪽으로 밀려남. 발판 끝을 벗어나면 false. 뒤에 다른 펫이 있으면 거기서 멈춤
    private func slide(_ pet: Pet, dt: TimeInterval, in world: World, friends: [FriendSighting]) -> Bool {
        let step = min(dt, knockback)
        knockback -= step
        let speed = Self.knockbackDistance / CGFloat(Self.knockbackTime) * pet.motionScale
        return retreat(pet, by: speed * CGFloat(step), in: world, friends: friends) || pet.support != nil
    }

    /// 상대 반대쪽으로 distance만큼 물러섬. 뒤에 다른 펫이 있으면 그 앞까지만. 발판 끝을 벗어나면 false
    @discardableResult
    private func retreat(_ pet: Pet, by distance: CGFloat, in world: World, friends: [FriendSighting]) -> Bool {
        let sign = -pet.facing.sign
        let nextX = pet.position.x + sign * distance
        if let behind = PersonalSpace.blocker(for: pet, sign: sign, toX: nextX, among: friends) {
            pet.position.x = PersonalSpace.stopX(for: pet, sign: sign, before: behind)
            return false
        }
        guard world.contains(CGPoint(x: nextX + sign * pet.bodyHalfWidth, y: pet.position.y + 1)) else { return false }
        pet.position.x = nextX
        return pet.settle(in: world)
    }
}
