import Foundation

/// This object is responsible for the pets living on the desktop: adding, removing and restyling them,
/// advancing each one through the world, letting them meet, giving every schedule notice its own pet
/// (calling in messenger pets when the residents are busy), reacting when the user switches windows,
/// keeping quiet during calls, and dropping lost pets back onto the main display.
/// Pets live here rather than in any display's scene, so display changes never lose them.
final class PetRoster {
    private(set) var pets: [Pet] = []
    private let planner: BehaviorPlanner
    /// 마주치면 인사하거나 티격태격
    let social = PetSocialCoordinator()
    /// 보고 있는 창으로 스킬 도약
    let skills = SkillCoordinator()
    /// 창을 바꾸면 돌아보고 앱 종류에 맞게 한마디
    let attention = AttentionCoordinator()
    /// 쉬지 않고 오래 쓰거나 창을 너무 자주 바꿀 때 한마디 (기본 꺼짐)
    let rhythm = WorkRhythmCoordinator()
    /// 보고 있는 모니터로 나머지 펫이 천천히 따라옴
    let follow = DisplayFollowCoordinator()
    /// 펫 머리 위에 펫이 올라선 탑
    let towers = PetTowerCoordinator()
    /// 겹친 펫 비켜 서기, 길 막은 펫과의 결투 받기
    let space = PersonalSpaceCoordinator()
    /// 키를 빠르게 누르면 따라 두드림 (누른 횟수만 셈)
    let typing = TypingCoordinator()
    /// 한가한 펫들이 가끔 줄줄이 기차놀이
    let trains = TrainCoordinator()
    /// 멈춘 포인터를 펫이 잠깐 들고 달아나는 장난 (기본 꺼짐)
    let pranks = CursorPrankCoordinator()
    /// 사용 중에 가끔 떨어지는 물건과 줍기
    let finding: FindingCoordinator
    /// 펫이 겪은 일을 친밀도(❤️)·레벨로
    let affection = AffectionCoordinator()
    /// 펫이 쥐고 있는 포인터를 이번 틱에 둘 자리 (없으면 포인터를 건드리지 않음)
    var heldCursor: CGPoint? { pranks.heldCursor }
    /// 펫이 올라선 창을 흔들면 튕겨 나감
    private let shakes = WindowShakeDetector()
    private let focus = FocusTracker()
    /// 쫓을 창이 바뀐 순간 (활성 창 모드면 focus와 같음)
    private let chaseFocus = FocusTracker()
    /// 무엇을 쫓아다닐지 (활성 창 또는 마우스 포인터)
    var chase: ChaseMode = ActiveWindowChase() {
        didSet { if chase.key != oldValue.key { onEvent?("🎯 chase \(oldValue.key) → \(chase.key)") } }
    }
    /// 이번 틱에 쫓는 곳
    private(set) var chaseTarget = ChaseTarget.none
    /// Claude 사용량에 따른 기력. 다시 기운을 차리면 ⚡ 하고 일어남
    var vigor: Vigor = .fresh {
        didSet {
            guard vigor != oldValue else { return }
            onEvent?("🔋 vigor \(oldValue) → \(vigor)")
            if oldValue >= .weary && vigor == .fresh { recharge() }
        }
    }
    /// 통화 중: 스스로 하는 도약·인사·한마디를 멈추고, 일정 말풍선은 제목을 숨김
    var isQuiet = false {
        didSet { if isQuiet != oldValue { onEvent?(isQuiet ? "🤫 quiet (call in progress)" : "🔈 quiet off") } }
    }
    private var nextNumber = 1
    /// 날아가는 무기 (포인터 모드에서 닿지 않는 포인터에 던짐)
    private(set) var projectiles: [Projectile] = []
    private var nextProjectile = 1
    /// 동시에 날 수 있는 무기 수
    static let maxProjectiles = 8
    /// 무기가 포인터에 닿았을 때 던진 펫이 하는 말과 확률
    static let hitText = "🎯"
    static let hitRemarkChance = 0.3
    /// 전할 펫을 기다리는 일정 알림
    private(set) var pendingNotices: [ScheduleNotice] = []
    /// 동시에 나와 있을 수 있는 전령 수
    static let maxMessengers = 4
    /// 전령이 쓸 모습 (기본 펫과 다른 스킨을 돌아가며)
    var messengerLook: (() -> PetAppearance?)?
    /// 행동 전환 등 기록할 사건
    var onEvent: ((String) -> Void)?

    /// findingRandom: 물건 떨어뜨리기 전용 난수 (검사에서 고정 시드로 바꿈)
    init(planner: BehaviorPlanner = BehaviorPlanner(), findingRandom: RandomSource = SystemRandomSource()) {
        self.planner = planner
        self.finding = FindingCoordinator(random: findingRandom)
    }

    var residents: [Pet] { pets.filter { $0.role == .resident } }
    var messengers: [Pet] { pets.filter { $0.role == .messenger } }

    /// entrance: 주면 그 등장(메뉴바 밑에서 보는 창 위로 떨어짐)으로 나타남. 없으면 바로 떨어지기 시작
    @discardableResult
    func add(appearance: PetAppearance, scale: CGFloat, in world: World, role: Pet.Role = .resident,
             entrance: EntranceBehavior? = nil) -> Pet {
        // 전령은 사용자가 보고 있는 모니터에 나타남
        let spawn = role == .messenger ? world.spawnPoint(onScreen: follow.activeScreenID) : world.spawnPoint
        let slot = role == .resident ? residents.count % 5 : messengers.count + 1
        let offset = role == .resident ? CGFloat(slot) * 60 - 120 : CGFloat(slot % 2 == 0 ? 1 : -1) * CGFloat(140 + slot * 70)
        let pet = Pet(
            id: role == .resident ? "Pet-\(nextNumber)" : "Messenger-\(nextNumber)",
            role: role,
            appearance: appearance,
            scale: scale,
            position: CGPoint(x: spawn.x + offset, y: spawn.y),
            behavior: entrance ?? AirborneBehavior.falling()
        )
        nextNumber += 1
        pet.onBehaviorChange = { [weak self] pet, from, to in
            let x = String(format: "%.0f", pet.position.x)
            let y = String(format: "%.0f", pet.position.y)
            self?.onEvent?("🐾 [\(pet.id)] \(from) ➔ \(to) at (\(x), \(y))")
        }
        pets.append(pet)
        onEvent?("✨ [\(pet.id)] spawned as \(appearance.name)")
        return pet
    }

    /// 마지막 기본 펫을 뺌 (전령은 대상 아님)
    func removeLast() {
        guard let pet = residents.last else { return }
        remove(pet)
    }

    /// 그 펫을 뺌. 기본 펫은 한 마리는 남김
    @discardableResult
    func remove(_ pet: Pet) -> Bool {
        guard pet.role == .messenger || residents.count > 1, pets.contains(where: { $0 === pet }) else { return false }
        pets.removeAll { $0 === pet }
        onEvent?("👋 [\(pet.id)] removed")
        return true
    }

    /// 모든 기본 펫 캐릭터 교체 (전령은 자기 캐릭터 유지)
    func restyle(_ appearance: PetAppearance) {
        residents.forEach { restyle($0, as: appearance) }
    }

    /// 그 펫 하나의 캐릭터 교체. 발 위치는 그대로
    func restyle(_ pet: Pet, as appearance: PetAppearance) {
        guard pet.appearance.name != appearance.name else { return }
        pet.appearance = appearance
        pet.say(Chatter.surprised, for: 0.8)
        onEvent?("🔄 [\(pet.id)] now \(appearance.name)")
    }

    /// 아이디로 펫 찾기 (메뉴용)
    func pet(withID id: String) -> Pet? {
        pets.first { $0.id == id }
    }

    func rescale(_ scale: CGFloat) {
        pets.forEach { $0.scale = scale }
    }

    /// keyPresses: 지난 틱 뒤 눌린 키 수 (어떤 키인지는 모름)
    func step(dt: TimeInterval, in world: World, cursor: CGPoint?, idleSeconds: TimeInterval = 0, keyPresses: Int = 0) {
        guard !world.screens.isEmpty else { return }
        typing.record(keyPresses, dt: dt)
        let friends = pets.map(PersonalSpace.sighting(of:))
        var context = PetContext(cursor: cursor, planner: planner, idleSeconds: idleSeconds, friends: friends)
        context.vigor = vigor
        context.allowsDuels = !isQuiet && vigor.isEnergetic
        context.typingRate = typing.rate
        chaseTarget = chase.target(in: world, cursor: cursor, dt: dt)
        if !isQuiet { context.pointer = chaseTarget.point }
        context.allowsSkills = skills.isEnabled && !isQuiet && vigor.isEnergetic
        if context.allowsSkills, let target = chaseTarget.windowID {
            context.skillTarget = target
            context.visitorsOnTarget = pets.filter { $0.perchWindowID == target }.count
        }
        if context.allowsSkills { context.clingTarget = chaseTarget.clingWindowID }
        shakeOff(dt: dt, in: world)
        for pet in towerOrder {
            if pet.isLost(in: world) {
                respawn(pet, in: world)
            }
            pet.step(dt: dt, in: world, context: context)
        }
        if !isQuiet {
            social.step(dt: dt, pets: pets, planner: planner, allowsSparring: vigor.isEnergetic) { [towers] base, climber in
                towers.start(base: base, climber: climber, in: world)
            }
            if vigor.isEnergetic {
                towers.step(dt: dt, pets: pets, world: world, planner: planner)
                trains.step(dt: dt, pets: pets, world: world, planner: planner)
            }
        }
        typing.step(dt: dt, pets: pets, planner: planner, quiet: isQuiet, allowsJoining: vigor != .exhausted)
        pranks.step(dt: dt, pets: pets, cursor: cursor, world: world, planner: planner,
                    quiet: isQuiet, sinceTyping: typing.meter.sinceLastPress)
        space.step(dt: dt, pets: pets, world: world, planner: planner, social: social, allowsDuels: context.allowsDuels)
        finding.step(dt: dt, pets: pets, world: world, idleSeconds: idleSeconds, quiet: isQuiet,
                     screenID: chaseTarget.screenID, allowsLeaps: context.allowsSkills, canFetch: vigor != .exhausted)
        // 앱 반응(돌아보기·한마디·작업 리듬)은 실제로 보는 창, 도약·모니터 따라오기는 쫓는 곳 기준
        let shift = focus.update(from: world)
        let chaseShift = chaseFocus.update(to: chaseTarget.windowID, in: world)
        let leaper = skills.step(dt: dt, pets: pets, world: world, shift: chaseShift, quiet: isQuiet || !vigor.isEnergetic)
        attention.step(dt: dt, pets: pets, shift: shift, leaper: leaper, quiet: isQuiet)
        rhythm.step(dt: dt, pets: pets, idleSeconds: idleSeconds, shift: shift, quiet: isQuiet)
        follow.step(dt: dt, pets: pets, world: world, target: chaseTarget, quiet: isQuiet)
        stepProjectiles(dt: dt)
        affection.step(dt: dt, pets: pets, idleSeconds: idleSeconds)
        dismissDeliveredMessengers()
        deliverPendingNotices(in: world)
    }

    /// 일정 알림 접수. 같은 일정을 들고 있는 펫이 있으면 문구만 바꾸고, 아니면 다음 틱에 전할 펫을 정함
    func announce(_ notice: ScheduleNotice) {
        if let holder = pets.first(where: { $0.noticeTopic == notice.topic }) {
            holder.announce(notice)
            onEvent?("📅 [\(holder.id)] notice updated: \(notice.text)")
            return
        }
        pendingNotices.append(notice)
        onEvent?("📅 queued notice: \(notice.text)")
    }

    /// 사용자가 물건을 클릭함: 가까운 한가한 펫이 바로 주우러 감. 물건을 눌렀으면 true
    @discardableResult
    func fetch(itemAt point: CGPoint, in world: World) -> Bool {
        finding.fetch(itemAt: point, pets: pets, world: world)
    }

    /// 화면 좌표의 점 위에 있는 가장 앞쪽 펫
    func pet(at point: CGPoint) -> Pet? {
        pets.last { $0.isTangible && $0.grabRect.contains(point) }
    }

    // MARK: - Notices

    /// 빈손인 기본 펫 → 새 전령 순서로 알림을 맡김. 전령이 꽉 차면 줄에서 기다림
    private func deliverPendingNotices(in world: World) {
        while let notice = pendingNotices.first {
            if let free = residents.first(where: { !$0.isShowingNotice && !$0.isDragged }) {
                free.announce(notice)
            } else if messengers.count < Self.maxMessengers, let look = messengerLook?() ?? pets.first?.appearance {
                let scale = residents.first?.scale ?? 1.5
                add(appearance: look, scale: scale, in: world, role: .messenger).announce(notice)
            } else {
                return
            }
            pendingNotices.removeFirst()
        }
    }

    /// 탑은 아래층부터, 탑에 뛰어오르는 펫은 맨 나중에 진행 (같은 틱에 움직인 아래 펫 머리를 딛도록). 그 밖의 펫은 원래 순서
    private var towerOrder: [Pet] {
        let rank = { (pet: Pet) -> Int in pet.behavior is StackLeapBehavior ? .max : pet.behavior.towerLevel ?? 0 }
        guard pets.contains(where: { rank($0) > 0 }) else { return pets }
        return pets.enumerated().sorted { lhs, rhs in
            let left = rank(lhs.element)
            let right = rank(rhs.element)
            return left != right ? left < right : lhs.offset < rhs.offset
        }.map(\.element)
    }

    // MARK: - Shaking

    /// 펫이 있는 창을 사용자가 흔들면 그 창의 펫들이 💫 하고 흩어지며 튕겨 나감 (통화 중에도 사용자가 한 일이라 반응)
    private func shakeOff(dt: TimeInterval, in world: World) {
        let perches = Set(pets.compactMap(\.perchWindowID)).union(finding.perches)
        for shake in shakes.step(dt: dt, world: world, watching: perches) {
            finding.shake(windowID: shake.windowID, push: shake.push)
            let riders = pets.filter { $0.perchWindowID == shake.windowID && !$0.isDragged }
            riders.forEach { $0.shakeOff(push: shake.push, spread: CGFloat(planner.uniform(-1, 1))) }
            onEvent?("🫨 window \(shake.windowID) shaken: \(riders.map(\.id).joined(separator: ", ")) flung")
        }
    }

    // MARK: - Projectiles

    /// 펫이 던진 무기를 받아 날리고, 닿으면 던진 펫이 가끔 🎯. 너무 많으면 새로 던진 것은 버림
    private func stepProjectiles(dt: TimeInterval) {
        for pet in pets {
            for request in pet.takeThrows() where projectiles.count < Self.maxProjectiles {
                projectiles.append(Projectile(id: "P-\(nextProjectile)", kind: request.kind, throwerID: pet.id,
                                              from: request.from, to: request.to, scale: pet.scale))
                nextProjectile += 1
                onEvent?("🎯 [\(pet.id)] threw \(request.kind.name) at (\(Int(request.to.x)), \(Int(request.to.y)))")
            }
        }
        for projectile in projectiles where projectile.step(dt: dt) {
            if planner.chance(Self.hitRemarkChance) {
                pet(withID: projectile.throwerID)?.say(Self.hitText, for: 1.0)
            }
        }
        projectiles.removeAll { $0.isFinished }
    }

    /// 확인받고 인사까지 마친 전령을 내보냄
    private func dismissDeliveredMessengers() {
        for messenger in pets where messenger.isReadyToLeave {
            onEvent?("👋 [\(messenger.id)] delivered and left")
        }
        pets.removeAll { $0.isReadyToLeave }
    }

    /// 사용량이 초기화되어 기운을 되찾음: 쉬던·지친 펫이 ⚡ 하고 깡충
    private func recharge() {
        for pet in residents where !pet.isDragged && pet.support != nil
            && (pet.behavior.isAtLeisure || pet.behavior is ExhaustedBehavior || pet.behavior is IdleBehavior) {
            pet.say(Vigor.rechargedText, for: 1.5)
            pet.switchTo(AirborneBehavior.hop(name: "recharged", motionScale: pet.motionScale))
        }
    }

    private func respawn(_ pet: Pet, in world: World) {
        onEvent?("🌀 [\(pet.id)] lost at (\(Int(pet.position.x)), \(Int(pet.position.y))), dropping back in")
        pet.position = world.spawnPoint
        pet.switchTo(AirborneBehavior.falling())
    }
}
