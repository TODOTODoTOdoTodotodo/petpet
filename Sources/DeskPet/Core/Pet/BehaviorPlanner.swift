import Foundation

/// This object is responsible for choosing what a pet does next, from weighted options
/// limited to what the pet's look and surroundings actually allow. Leaping onto the window the pets chase
/// (the one the user is looking at, or the one under the mouse pointer) is one of those options, so pets keep visiting it,
/// not only when it changes. In pointer mode, heading toward the pointer comes first.
final class BehaviorPlanner {
    private let random: RandomSource

    init(random: RandomSource = SystemRandomSource()) {
        self.random = random
    }

    // MARK: - Durations

    func restDuration() -> TimeInterval { random.uniform(1.2, 3.2) }
    func strollDuration() -> TimeInterval { random.uniform(2.0, 5.0) }

    func rest() -> PetBehavior {
        IdleBehavior(duration: restDuration())
    }

    /// 확률 판정 (다른 조정자가 같은 난수를 쓰도록)
    func chance(_ probability: Double) -> Bool {
        random.chance(probability)
    }

    /// 범위 안 임의 값 (다른 조정자가 같은 난수를 쓰도록)
    func uniform(_ low: Double, _ high: Double) -> Double {
        random.uniform(low, high)
    }

    // MARK: - Choices

    /// 사용자가 이만큼 입력이 없으면 잠듦
    static let sleepAfterIdleSeconds: TimeInterval = 180
    /// 보고 있는 창으로 스킬 도약하는 선택지의 비중 (걷기 40 기준)
    static let focusLeapWeight: Double = 22
    /// 보고 있는 창에 이만큼 펫이 있으면 더 가지 않음
    static let maxVisitors = 3
    /// 머리 위 창 아랫변에 거꾸로 붙으러 가는 선택지의 비중 (걷기 40 기준)
    static let clingWeight: Double = 6
    /// 이 가로 거리 안의 머리 위 아랫변까지 봄 (기준 크기)
    static let clingSearchWidth: CGFloat = 200
    /// 포인터 모드: 포인터 아래 창으로 도약할 확률, 포인터 쪽으로 걸어갈 확률
    static let pointerLeapChance = 0.6
    static let pointerWalkChance = 0.8
    /// 포인터가 머리 위로 이만큼 넘게 높으면 걸어서는 닿지 않는 것으로 봄 (기준 크기)
    static let pointerOverhead: CGFloat = 30
    /// 이 가로 거리 안에서 닿지 않으면 뛰어오르거나 던짐 (기준 크기)
    static let pointerReachWidth: CGFloat = 160
    /// 닿을 높이면 뛰어오를 확률, 무기를 던질 확률, 닿지 않아도 한번 뛰어 볼 확률
    static let pounceChance = 0.5
    static let throwChance = 0.45
    static let hopelessPounceChance = 0.15
    /// 포인터 곁에 온 펫이 그 자리에서 머물 확률
    static let pointerStayChance = 0.7
    /// 포인터와 이보다 가까우면 쫓지 않음 (기준 크기)
    static let pointerNear: CGFloat = 40
    /// 포인터가 이보다 멀면 뛰어감 (기준 크기)
    static let pointerFar: CGFloat = 400

    /// 대기가 끝난 펫의 다음 행동
    func next(after pet: Pet, in world: World, context: PetContext) -> PetBehavior {
        if context.idleSeconds >= Self.sleepAfterIdleSeconds {
            return SleepBehavior()
        }
        let vigor = context.vigor
        if vigor == .exhausted {
            return ExhaustedBehavior()
        }
        let walkSpeed = PetPhysics.walkSpeed * vigor.speedFactor
        if let pointer = context.pointer {
            if let cling = clingLeap(for: pet, to: context.clingTarget, in: world, context: context),
               random.chance(Self.pointerLeapChance) {
                return cling
            }
            if let leap = focusLeap(for: pet, in: world, context: context) {
                if random.chance(Self.pointerLeapChance) { return leap }
            } else if let approach = approachTarget(for: pet, in: world, context: context, vigor: vigor),
                      random.chance(Self.pointerWalkChance) {
                return approach
            }
            if let reach = outOfReach(for: pet, pointer: pointer, in: world) {
                return reach
            }
            if let chase = pointerWalk(for: pet, toward: pointer, in: world, vigor: vigor) {
                if random.chance(Self.pointerWalkChance) { return chase }
            } else if random.chance(Self.pointerStayChance) {
                // 포인터 곁에 모여 바라봄
                return IdleBehavior(duration: random.uniform(1.5, 3.0), lookAtUser: true)
            }
        } else if let targetX = cursorTarget(for: pet, cursor: context.cursor), random.chance(0.35) {
            let direction: Facing = targetX > pet.position.x ? .east : .west
            return WalkBehavior(name: "followingCursor", direction: direction, speed: walkSpeed, duration: 8, targetX: targetX)
        }
        if let friendX = friendTarget(for: pet, friends: context.friends), random.chance(0.2) {
            let direction: Facing = friendX > pet.position.x ? .east : .west
            return WalkBehavior(name: "followingFriend", direction: direction, speed: walkSpeed, duration: 10, targetX: friendX)
        }

        var options: [(weight: Double, make: () -> PetBehavior)] = [
            (40, { WalkBehavior(direction: self.strollDirection(for: pet, in: world), speed: walkSpeed, duration: self.strollDuration()) }),
            (8 * vigor.leapFactor, { WalkBehavior(name: "sprinting", direction: self.strollDirection(for: pet, in: world),
                                                  speed: PetPhysics.sprintSpeed, duration: self.random.uniform(0.8, 1.6)) }),
            (14, { IdleBehavior(duration: self.random.uniform(1.5, 3.0), lookAtUser: true) }),
            (12 * vigor.restFactor, { self.tiredRest(for: pet, vigor: vigor) }),
        ]
        if canJump(pet, in: world) {
            options.append((12 * vigor.leapFactor, {
                // 친밀도 Lv.3부터 가끔 공중제비 (레벨이 낮으면 난수를 쓰지 않음)
                let flip = pet.level >= Self.somersaultLevel && self.random.chance(Self.somersaultChance)
                return AirborneBehavior.jumping(toward: pet.facing, motionScale: pet.motionScale, somersault: flip)
            }))
        }
        if pet.level >= Self.spinLevel {
            options.append((Self.spinWeight, { SpinBehavior() }))
        }
        if pet.appearance.supports(.act) {
            options.append((10 * vigor.leapFactor, { ActBehavior() }))
        }
        if let leap = focusLeap(for: pet, in: world, context: context) {
            options.append((Self.focusLeapWeight * vigor.leapFactor, { leap }))
        }
        if let cling = clingLeap(for: pet, to: overheadUnderside(of: pet, in: world), in: world, context: context) {
            options.append((Self.clingWeight * vigor.leapFactor, { cling }))
        }
        return pick(options.filter { $0.weight > 0 })
    }

    /// 친밀도 레벨별 동작: Lv.2 한 바퀴(비중), Lv.3 공중제비(점프 중 확률)
    static let spinLevel = 2
    static let spinWeight: Double = 4
    static let somersaultLevel = 3
    static let somersaultChance = 0.35

    // MARK: - Passing

    /// 목적지가 막은 펫 바로 옆이면 거기서 멈춤 (기준 크기 여유)
    static let besideSlack: CGFloat = 40
    /// 막은 펫이 서 있고 목적지가 이 안이면 무리에 끼어 멈춤 (포인터 곁에 모일 때 서로 넘지 않도록, 기준 크기)
    static let crowdSlack: CGFloat = 110
    /// 뛰어넘을 때 막은 펫 머리 위로 넘는 높이 (기준 크기)
    static let leapfrogClearance: CGFloat = 14
    /// 길이 막혔을 때 뛰어넘기·결투·돌아서기 비중
    static let leapfrogWeight: Double = 5
    static let duelWeight: Double = 3
    static let turnBackWeight: Double = 2
    /// 목적지가 있는 걸음(포인터·친구 쫓기)이 서 있는 펫에 막혔을 때 그 자리에 멈춰 바라보는 비중
    static let settleWeight: Double = 9
    /// 서두르는 중(질주·도망·뛰어 쫓기)일 때 고르지 않고 바로 뛰어넘을 확률
    static let hurriedLeapChance = 0.5

    /// 걷다가 다른 펫에게 길이 막힘. 그 옆(서 있는 무리면 조금 더 넓게)이 목적지면 멈추고,
    /// 같은 쪽으로 가는 펫 뒤면 기다리고, 마주 오는 펫이면 한쪽이 기다리고,
    /// 아니면 뛰어넘기·결투 걸기·돌아서기(목적지가 있으면 그 자리에 멈추기) 중 고름 (서두르는 중이면 절반은 바로 뛰어넘음)
    func pass(_ pet: Pet, blocker: FriendSighting, targetX: CGFloat?, hurried: Bool, in world: World, context: PetContext) -> PetBehavior {
        if let targetX {
            let slack = blocker.heading == nil ? Self.crowdSlack : Self.besideSlack
            if abs(targetX - blocker.position.x) <= PersonalSpace.spacing(pet, blocker) + slack * pet.motionScale { return rest() }
        }
        // 같은 쪽으로 가는 펫 뒤에서는 넘지 않고 잠깐 따라감
        if blocker.heading == pet.facing {
            return IdleBehavior(duration: 0.6, name: "waiting")
        }
        // 마주 오면 ID가 뒤인 쪽이 잠깐 기다림
        if blocker.heading == pet.facing.opposite && pet.id > blocker.id {
            return IdleBehavior(duration: 0.6, name: "waiting")
        }
        let hop = leapfrog(pet, over: blocker, in: world)
        if hurried, let hop, random.chance(Self.hurriedLeapChance) { return hop }
        var options: [(weight: Double, make: () -> PetBehavior)] = []
        if let hop { options.append((Self.leapfrogWeight, { hop })) }
        if context.allowsDuels && blocker.isJumpable && blocker.heading == nil {
            options.append((Self.duelWeight, { ChallengeBehavior(opponent: blocker, fallback: hop) }))
        }
        if targetX == nil {
            options.append((Self.turnBackWeight, {
                WalkBehavior(direction: pet.facing.opposite, speed: PetPhysics.walkSpeed * context.vigor.speedFactor, duration: self.strollDuration())
            }))
        } else {
            // 쫓던 곳이 아직 멀어도 앞 펫 뒤에서 멈춰 바라보기도 함 (모두가 넘어가지 않도록)
            options.append((Self.settleWeight, { IdleBehavior(duration: self.random.uniform(2.0, 4.0), lookAtUser: true) }))
        }
        return options.isEmpty ? rest() : pick(options)
    }

    /// 앞을 막은 펫을 깡충 뛰어넘어 그 너머 같은 높이에 내려섬. 머리 위 공간이나 내려설 곳이 없으면 nil
    func leapfrog(_ pet: Pet, over blocker: FriendSighting, in world: World) -> PetBehavior? {
        guard blocker.isJumpable else { return nil }
        let k = pet.motionScale
        let sign: CGFloat = blocker.position.x >= pet.position.x ? 1 : -1
        let landingX = blocker.position.x + sign * (PersonalSpace.spacing(pet, blocker) + 4 * k)
        guard world.contains(CGPoint(x: landingX + sign * pet.bodyHalfWidth, y: pet.position.y + 1)),
              world.ledge(atX: landingX, nearY: pet.position.y, tolerance: 1, margin: pet.bodyHalfWidth * 0.6) != nil else { return nil }
        // 내 몸 중심이 앞 펫 몸 위를 지나는 동안 발이 그 머리보다 높게 (포물선 높이 = 최고점 × (1 - (x/반폭)²))
        let half = abs(landingX - pet.position.x) / 2
        let overBody = min(blocker.halfWidth / max(half, 1), 0.9)
        let rise = blocker.height / (1 - overBody * overBody) + Self.leapfrogClearance * k
        var roof = world.ceiling(atX: blocker.position.x, above: pet.position.y) ?? -.infinity
        if let underside = world.underside(above: CGPoint(x: blocker.position.x, y: pet.position.y)) { roof = min(roof, underside.y) }
        guard pet.position.y + rise + pet.bodyHeight <= roof - 2 else { return nil }
        let g = PetPhysics.gravity * k
        let vy = sqrt(2 * g * rise)
        let time = 2 * vy / g
        return AirborneBehavior(name: "leapfrogging", launch: CGVector(dx: (landingX - pet.position.x) / time, dy: vy))
    }

    /// 부딪힌 벽을 오를지. 꼭대기까지 보이고 올라설 자리와 머리 위 공간이 있을 때만 65%
    func wantsToClimb(_ wall: Wall, pet: Pet, in world: World) -> Bool {
        guard let window = world.window(id: wall.windowID) else { return false }
        let top = window.frame.maxY
        guard wall.minY <= pet.position.y + pet.bodyHeight * 0.5, wall.maxY >= top - 1 else { return false }
        guard let ceiling = world.ceiling(atX: wall.x, above: pet.position.y), top + pet.bodyHeight + 4 <= ceiling else { return false }
        let mountX = wall.x - wall.face.outwardSign * (pet.bodyHalfWidth + 2)
        guard world.ledge(atX: mountX, nearY: top, tolerance: 1) != nil else { return false }
        return random.chance(0.65)
    }

    // MARK: - Helpers

    /// 지친 펫은 가끔 한숨 쉬며 쉼
    private func tiredRest(for pet: Pet, vigor: Vigor) -> PetBehavior {
        if vigor >= .weary, random.chance(0.25) {
            pet.say(Vigor.sighText, for: 1.6)
        }
        return rest()
    }

    /// 보고 있는 창에 아직 없고 닿을 수 있으면 그 창으로 가는 스킬 도약
    private func focusLeap(for pet: Pet, in world: World, context: PetContext) -> PetBehavior? {
        guard let target = context.skillTarget, pet.perchWindowID != target,
              context.visitorsOnTarget < Self.maxVisitors, !pet.isShowingNotice,
              let plan = LeapPlanner.plan(for: pet, to: target, in: world) else { return nil }
        return SkillLeapBehavior(plan: plan, style: pet.appearance.skillStyle, hasActionFrames: pet.appearance.supports(.act))
    }

    /// 그 창 아랫변에 거꾸로 붙으러 가는 스킬 도약 (스킬을 쓸 수 있을 때만)
    private func clingLeap(for pet: Pet, to windowID: UInt32?, in world: World, context: PetContext) -> PetBehavior? {
        guard context.allowsSkills, let windowID, pet.perchWindowID != windowID, !pet.isShowingNotice,
              let plan = LeapPlanner.clingPlan(for: pet, to: windowID, in: world) else { return nil }
        return SkillLeapBehavior(plan: plan, style: pet.appearance.skillStyle, hasActionFrames: pet.appearance.supports(.act))
    }

    /// 머리 위 가까이에서 가장 낮은 창 아랫변의 창
    private func overheadUnderside(of pet: Pet, in world: World) -> UInt32? {
        let head = pet.position.y + pet.bodyHeight
        let width = Self.clingSearchWidth * pet.motionScale
        return world.undersides
            .filter { $0.y > head && $0.maxX >= pet.position.x - width && $0.minX <= pet.position.x + width }
            .min { $0.y < $1.y }?.owner.windowID
    }

    /// 포인터가 머리 위 높은 곳이라 걸어서 닿지 않으면: 닿을 높이면 뛰어오르고, 아니면 무기를 던지거나 한번 뛰어 봄.
    /// 그것도 아니면 올려다보며 기다림
    private func outOfReach(for pet: Pet, pointer: CGPoint, in world: World) -> PetBehavior? {
        let k = pet.motionScale
        guard pet.support != nil, abs(pointer.x - pet.position.x) <= Self.pointerReachWidth * k,
              pointer.y - (pet.position.y + pet.bodyHeight) > Self.pointerOverhead * k else { return nil }
        let pounce = PounceBehavior.plan(for: pet, toward: pointer, in: world)
        if let pounce, pounce.reaches, random.chance(Self.pounceChance) {
            return PounceBehavior(launch: pounce.launch)
        }
        if random.chance(Self.throwChance) {
            return ThrowBehavior(at: pointer)
        }
        if let pounce, random.chance(Self.hopelessPounceChance) {
            return PounceBehavior(launch: pounce.launch)
        }
        return IdleBehavior(duration: random.uniform(1.0, 2.0), lookAtUser: true)
    }

    /// 쫓는 창으로 바로 도약할 수 없으면(창 밑이라 천장에 막힘, 너무 멂) 창 옆 바깥 가까운 쪽으로 걸어감
    private func approachTarget(for pet: Pet, in world: World, context: PetContext, vigor: Vigor) -> PetBehavior? {
        guard let id = context.skillTarget, pet.perchWindowID != id, context.visitorsOnTarget < Self.maxVisitors,
              !pet.isShowingNotice, pet.support != nil, let window = world.window(id: id),
              window.frame.maxY > pet.position.y + 20 else { return nil }
        let margin = pet.bodyHalfWidth + 30 * pet.motionScale
        let sides = [window.frame.minX - margin, window.frame.maxX + margin]
            .filter { world.contains(CGPoint(x: $0, y: pet.position.y + 1)) }
        guard let side = sides.min(by: { abs($0 - pet.position.x) < abs($1 - pet.position.x) }),
              abs(side - pet.position.x) > 12 else { return nil }
        let direction: Facing = side > pet.position.x ? .east : .west
        let base = abs(side - pet.position.x) > Self.pointerFar * pet.motionScale ? PetPhysics.sprintSpeed : PetPhysics.walkSpeed
        let speed = base * vigor.speedFactor
        let duration = TimeInterval(abs(side - pet.position.x) / (speed * pet.motionScale)) + 2
        return WalkBehavior(name: "chasingPointer", direction: direction, speed: speed, duration: duration, targetX: side)
    }

    /// 포인터 바로 아래 쪽으로 걸어감 (멀면 뜀). 발판 끝을 넘으면 떨어져 아래 발판에서 이어감.
    /// 포인터 앞에서 조금 떨어져 멈춤. 이미 포인터 위쪽에 있는데 포인터 바닥이 더 낮으면 가까운 발판 끝으로 걸어 내려감
    private func pointerWalk(for pet: Pet, toward pointer: CGPoint, in world: World, vigor: Vigor) -> PetBehavior? {
        let dx = pointer.x - pet.position.x
        if abs(dx) <= Self.pointerNear * pet.motionScale {
            return stepDown(pet, toward: pointer, in: world, vigor: vigor)
        }
        let direction: Facing = dx > 0 ? .east : .west
        let base = abs(dx) > Self.pointerFar * pet.motionScale ? PetPhysics.sprintSpeed : PetPhysics.walkSpeed
        let speed = base * vigor.speedFactor
        let targetX = pointer.x - direction.sign * Self.pointerNear * 0.5 * pet.motionScale
        let duration = TimeInterval(abs(dx) / (speed * pet.motionScale)) + 2
        return WalkBehavior(name: "chasingPointer", direction: direction, speed: speed, duration: duration, targetX: targetX)
    }

    /// 포인터 바닥이 지금 발판보다 낮으면 가까운 발판 끝으로 걸어가 떨어짐
    private func stepDown(_ pet: Pet, toward pointer: CGPoint, in world: World, vigor: Vigor) -> PetBehavior? {
        guard let floor = world.ledge(under: pointer), floor.y < pet.position.y - 20,
              let mine = world.ledge(atX: pet.position.x, nearY: pet.position.y) else { return nil }
        let eastGap = mine.maxX - pet.position.x
        let westGap = pet.position.x - mine.minX
        let speed = PetPhysics.walkSpeed * vigor.speedFactor
        let duration = TimeInterval(min(eastGap, westGap) / (speed * pet.motionScale)) + 2
        return WalkBehavior(name: "chasingPointer", direction: eastGap < westGap ? .east : .west, speed: speed, duration: duration)
    }

    private func cursorTarget(for pet: Pet, cursor: CGPoint?) -> CGFloat? {
        guard let cursor else { return nil }
        let dx = abs(cursor.x - pet.position.x)
        let dy = cursor.y - pet.position.y
        guard (80...700).contains(dx), dy >= -40, dy <= 250 else { return nil }
        return cursor.x
    }

    /// 같은 높이에서 80~600pt 떨어진 가장 가까운 친구 옆자리
    private func friendTarget(for pet: Pet, friends: [FriendSighting]) -> CGFloat? {
        let nearest = friends
            .filter { $0.id != pet.id && abs($0.position.y - pet.position.y) < 2 }
            .filter { (80...600).contains(abs($0.position.x - pet.position.x)) }
            .min { abs($0.position.x - pet.position.x) < abs($1.position.x - pet.position.x) }
        guard let friend = nearest else { return nil }
        // 친구와 겹치지 않게 40pt 앞에서 멈춤
        return friend.position.x + (friend.position.x > pet.position.x ? -40 : 40)
    }

    /// 화면 끝 가까이면 안쪽으로, 아니면 무작위
    private func strollDirection(for pet: Pet, in world: World) -> Facing {
        let reach: CGFloat = 150
        let probeY = pet.position.y + 1
        let eastOpen = world.contains(CGPoint(x: pet.position.x + reach, y: probeY))
        let westOpen = world.contains(CGPoint(x: pet.position.x - reach, y: probeY))
        if eastOpen != westOpen { return eastOpen ? .east : .west }
        return random.chance(0.5) ? .east : .west
    }

    private func canJump(_ pet: Pet, in world: World) -> Bool {
        guard let ceiling = world.ceiling(atX: pet.position.x, above: pet.position.y) else { return false }
        let apex = PetPhysics.jumpApex(motionScale: pet.motionScale)
        return pet.position.y + pet.bodyHeight + apex + 8 <= ceiling
    }

    private func pick(_ options: [(weight: Double, make: () -> PetBehavior)]) -> PetBehavior {
        let total = options.reduce(0) { $0 + $1.weight }
        var roll = random.next() * total
        for option in options {
            roll -= option.weight
            if roll < 0 { return option.make() }
        }
        return options[options.count - 1].make()
    }
}
