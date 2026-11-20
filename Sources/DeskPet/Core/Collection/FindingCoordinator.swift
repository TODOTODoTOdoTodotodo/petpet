import Foundation

/// 줍기 기록 (시뮬레이션·로그용)
struct FindingStats: Equatable {
    var dropped = 0
    var collected = 0
    var missed = 0
    /// 놓이고 주울 때까지 걸린 시간들
    var fetchTimes: [TimeInterval] = []
}

/// This object is responsible for items turning up while the user works: counting only time in use,
/// dropping one item now and then onto a visible ledge near the pets, sending the nearest free pet on that ledge
/// to fetch it (after a while, a pet from elsewhere leaps or walks down to it), answering a click on an item,
/// and reporting each item that reaches the collection.
final class FindingCoordinator {
    var isEnabled = true
    /// 떨어뜨릴 때·곳·종류를 고르는 난수 (펫 행동 난수와 따로 두어 서로 영향을 주지 않음)
    private let random: RandomSource
    private(set) var items: [DroppedItem] = []
    /// 물건이 주워져 날아갈 곳 (메뉴바 👾). 없으면 그 모니터 위쪽
    var collectTarget: CGPoint?
    /// 지금 달 (계절 물건용, 검사에서 바꿈)
    var month: () -> Int = { Calendar.current.component(.month, from: Date()) }
    var onEvent: ((String) -> Void)?
    /// 물건이 도감에 들어갈 때 (주운 펫 ID)
    var onCollect: ((ItemKind, String) -> Void)?
    private(set) var stats = FindingStats()
    /// 사용 중인 시간 누적
    private(set) var activeTime: TimeInterval = 0
    /// 다음 물건을 떨어뜨릴 사용 시간
    private(set) var nextDropAt: TimeInterval?
    private var credited = Set<String>()
    /// 물건별 마지막으로 다른 발판 펫을 보낸 때
    private var lastCall: [String: TimeInterval] = [:]
    private var clock: TimeInterval = 0
    private var nextNumber = 1
    /// 펫별 마지막으로 줍기를 보낸 때 (그만두자마자 다시 보내지 않음)
    private var sentAt: [String: TimeInterval] = [:]
    /// 놓인 걸 이미 알아챈 드문 물건
    private var noticed = Set<String>()

    /// 입력이 이만큼 없으면 사용 중이 아님
    static let idleLimit: TimeInterval = 300
    /// 켠 뒤 첫 물건, 그다음 물건 간격 (사용 중 시간, 초)
    static let firstDrop: ClosedRange<Double> = 180...480
    static let dropGap: ClosedRange<Double> = 360...1080
    /// 떨어뜨릴 곳이 없으면 다시 해 보는 간격
    static let retryGap: TimeInterval = 60
    /// 같은 발판에 아무도 없을 때 다른 발판 펫을 보내기까지
    static let callWait: TimeInterval = 30
    /// 다른 발판 펫을 다시 보내는 간격
    static let recallGap: TimeInterval = 10
    /// 드문 물건이 놓이면 돌아보는 펫 수와 거리 (기준 크기)
    static let noticeCount = 3
    static let noticeReach: CGFloat = 500
    static let noticeTime: TimeInterval = 1.2
    /// 줍기를 그만둔 펫을 다시 보내기까지
    static let resendGap: TimeInterval = 2
    /// 한가한 펫이 있는 발판을 고를 비율
    static let besidePetShare = 0.7
    static let edgeMargin: CGFloat = 20
    static let petClearance: CGFloat = 40
    /// 발판 폭이 펫 몸 폭의 이 배 이상이어야 떨어뜨림
    static let minimumLedgeBodies: CGFloat = 3

    init(random: RandomSource = SystemRandomSource()) {
        self.random = random
    }

    // MARK: - Tick

    /// screenID: 쫓는 곳이 있는 모니터. allowsLeaps: 스킬 도약을 써도 되는지. canFetch: 지친 펫이 아닌지
    func step(dt: TimeInterval, pets: [Pet], world: World, idleSeconds: TimeInterval,
              quiet: Bool, screenID: UInt32?, allowsLeaps: Bool, canFetch: Bool = true) {
        clock += dt
        if nextDropAt == nil { nextDropAt = random.uniform(Self.firstDrop.lowerBound, Self.firstDrop.upperBound) }
        for item in items { item.step(dt: dt, in: world) }
        settleAccounts()

        guard isEnabled else { return }
        if idleSeconds < Self.idleLimit && !quiet { activeTime += dt }
        if !quiet, let due = nextDropAt, activeTime >= due, !items.contains(where: { $0.state == .falling || $0.isResting }) {
            let dropped = drop(in: world, pets: pets, screenID: screenID) != nil
            nextDropAt = activeTime + (dropped ? random.uniform(Self.dropGap.lowerBound, Self.dropGap.upperBound) : Self.retryGap)
        }
        guard canFetch else { return }
        for item in items where item.isResting {
            dispatch(for: item, pets: pets, world: world, urgent: false, allowsLeaps: allowsLeaps)
            if item.kind.rarity == .rare && !noticed.contains(item.id) { notice(item, pets: pets) }
        }
    }

    /// 드문 물건이 놓이면 가까운 한가한 펫 몇이 그쪽을 돌아보며 "!"
    private func notice(_ item: DroppedItem, pets: [Pet]) {
        noticed.insert(item.id)
        let k = pets.first?.motionScale ?? 1
        let watchers = pets
            .filter { Self.canFetch($0) && hypot($0.position.x - item.position.x, $0.position.y - item.position.y) <= Self.noticeReach * k }
            .sorted { abs($0.position.x - item.position.x) < abs($1.position.x - item.position.x) }
            .prefix(Self.noticeCount)
        for pet in watchers {
            pet.switchTo(GlanceBehavior(name: "noticing", towardX: item.position.x, duration: Self.noticeTime, remark: Chatter.surprised))
        }
        if !watchers.isEmpty { onEvent?("👀 \(watchers.map(\.id).joined(separator: ", ")) noticed \(item.kind.id)") }
    }

    /// 사용자가 클릭한 점의 물건: 반짝이고, 가장 가까운 한가한 펫이 바로 감 (필요하면 도약). 물건을 눌렀으면 true
    @discardableResult
    func fetch(itemAt point: CGPoint, pets: [Pet], world: World) -> Bool {
        guard let item = item(at: point) else { return false }
        item.flash()
        onEvent?("👆 \(item.kind.id) clicked")
        dispatch(for: item, pets: pets, world: world, urgent: true, allowsLeaps: true)
        return true
    }

    /// 점 위의 놓인 물건
    func item(at point: CGPoint) -> DroppedItem? {
        items.last { $0.isResting && $0.hitRect.contains(point) }
    }

    /// 흔들기 감지에 넣을 창 (물건이 놓인 창)
    var perches: Set<UInt32> { Set(items.compactMap(\.perchWindowID)) }

    /// 흔들린 창의 물건이 튕겨 나감
    func shake(windowID: UInt32, push: CGVector) {
        for item in items where item.perchWindowID == windowID {
            item.fling(push: push, spread: CGFloat(random.uniform(-1, 1)))
        }
    }

    // MARK: - Dropping

    /// 지금 물건 하나를 떨어뜨림. 쫓는 곳의 모니터(없으면 보는 창·주 모니터)의 넓은 발판 중,
    /// 70%는 한가한 펫이 있는 발판에서 펫과 떨어진 x를 고름. 메뉴바 밑에서 떨어져 처음 닿는 곳이 그 발판인 자리만
    @discardableResult
    func drop(_ kind: ItemKind? = nil, in world: World, pets: [Pet], screenID: UInt32?) -> DroppedItem? {
        guard let screen = Self.screen(for: screenID, in: world) else { return nil }
        let scale = pets.first?.scale ?? 1.5
        let bodyWidth = pets.map { $0.bodyHalfWidth * 2 }.max() ?? 30 * scale
        let side = 8 * scale
        let top = screen.visibleFrame.maxY - side - 4
        let ledges = world.ledges.filter { ledge in
            screen.frame.contains(CGPoint(x: (ledge.minX + ledge.maxX) / 2, y: ledge.y + 1))
                && ledge.maxX - ledge.minX >= Self.minimumLedgeBodies * bodyWidth && ledge.y < top - 20
        }
        let beside = ledges.filter { ledge in pets.contains { Self.canFetch($0) && Self.isOn(ledge, $0) } }
        let first = !beside.isEmpty && random.chance(Self.besidePetShare) ? beside : ledges
        let order = shuffled(first) + shuffled(ledges.filter { !first.contains($0) })
        for ledge in order {
            for _ in 0..<6 {
                let x = CGFloat(random.uniform(Double(ledge.minX + Self.edgeMargin), Double(ledge.maxX - Self.edgeMargin)))
                let crowded = pets.contains { pet in
                    abs(pet.position.y - ledge.y) < pet.bodyHeight && abs(pet.position.x - x) < pet.bodyHalfWidth + Self.petClearance
                }
                guard !crowded, let landing = world.landingLedge(atX: x, from: top, to: ledge.y - 1),
                      landing.owner == ledge.owner, abs(landing.y - ledge.y) < 0.5 else { continue }
                let item = DroppedItem(id: "I-\(nextNumber)", kind: kind ?? ItemCatalog.pick(roll: random.next(), month: month()),
                                       scale: scale, position: CGPoint(x: x, y: top))
                nextNumber += 1
                items.append(item)
                stats.dropped += 1
                onEvent?("🎁 dropped \(item.kind.id) at (\(Int(x)), \(Int(ledge.y))) on \(Self.label(ledge.owner))")
                return item
            }
        }
        return nil
    }

    /// 정해 둔 물건을 그 자리에서 떨어뜨림 (검사·연출용)
    func release(_ item: DroppedItem) {
        items.append(item)
        stats.dropped += 1
    }

    // MARK: - Fetching

    /// 물건을 주울 수 있는 펫: 기본 펫, 알림·들림·탑·기차·장난 중 아님, 쉬거나 거닐거나 포인터를 쫓는 중
    static func canFetch(_ pet: Pet) -> Bool {
        guard pet.role == .resident, !pet.isShowingNotice, !pet.isDragged, pet.support != nil,
              pet.behavior.towerLevel == nil, pet.behavior.trainRank == nil else { return false }
        return pet.behavior.isAtLeisure || pet.behavior is IdleBehavior || pet.behavior.name == "chasingPointer"
    }

    private func dispatch(for item: DroppedItem, pets: [Pet], world: World, urgent: Bool, allowsLeaps: Bool) {
        guard !pets.contains(where: { ($0.behavior as? FetchBehavior)?.isFetching(item) == true }),
              let ledge = item.ledge(in: world) else { return }
        let free = pets.filter { Self.canFetch($0) && (urgent || clock - (sentAt[$0.id] ?? -.infinity) >= Self.resendGap) }
        let deliver = collectTarget ?? CGPoint(x: item.position.x, y: (Self.screen(for: nil, in: world, near: item.position)?.visibleFrame.maxY ?? item.position.y) + 10)

        let nearest = { (candidates: [Pet]) in candidates.min { abs($0.position.x - item.position.x) < abs($1.position.x - item.position.x) } }
        if let pet = nearest(free.filter { Self.isOn(ledge, $0) }) {
            send(pet, to: item, deliver: deliver, mode: "walks")
            return
        }
        guard urgent || item.restingTime >= Self.callWait, clock - (lastCall[item.id] ?? -.infinity) >= (urgent ? 0 : Self.recallGap) else { return }

        // 위쪽 발판의 펫은 걸어 내려옴
        let above = free.filter { $0.position.y > item.position.y + 3 && world.screen(containing: CGPoint(x: $0.position.x, y: $0.position.y + 1))?.id
            == world.screen(containing: CGPoint(x: item.position.x, y: item.position.y + 1))?.id }
        // 물건이 창 위면 아래 펫이 그 창으로 도약
        var leap: (Pet, LeapPlan)?
        if let windowID = ledge.owner.windowID, allowsLeaps {
            leap = free.compactMap { pet -> (Pet, LeapPlan)? in
                guard let plan = LeapPlanner.plan(for: pet, to: windowID, in: world), case .stand = plan.target else { return nil }
                return (pet, plan)
            }.min { abs($0.1.launch.dx) < abs($1.1.launch.dx) }
        }
        if let (pet, plan) = leap, abs(pet.position.x - item.position.x) <= abs((nearest(above)?.position.x ?? .infinity) - item.position.x) {
            lastCall[item.id] = clock
            pet.switchTo(SkillLeapBehavior(plan: plan, style: pet.appearance.skillStyle, hasActionFrames: pet.appearance.supports(.act)))
            onEvent?("🦘 [\(pet.id)] leaps toward \(item.kind.id)")
        } else if let pet = nearest(above) {
            lastCall[item.id] = clock
            send(pet, to: item, deliver: deliver, mode: "comes down")
        }
    }

    private func send(_ pet: Pet, to item: DroppedItem, deliver: CGPoint, mode: String) {
        sentAt[pet.id] = clock
        pet.switchTo(FetchBehavior(item: item, deliverTo: deliver))
        onEvent?("🏃 [\(pet.id)] \(mode) to fetch \(item.kind.id)")
    }

    /// 주워진 물건은 한 번만 도감에 넣고, 사라진 물건은 놓친 것으로 셈
    private func settleAccounts() {
        for item in items where !credited.contains(item.id) {
            if let collector = item.collector {
                credited.insert(item.id)
                stats.collected += 1
                stats.fetchTimes.append(item.restingTime)
                onEvent?("✨ [\(collector)] picked up \(item.kind.id) after \(Int(item.restingTime))s")
                onCollect?(item.kind, collector)
            } else if item.state == .expired {
                credited.insert(item.id)
                stats.missed += 1
                onEvent?("🍂 \(item.kind.id) faded away (nobody came)")
            }
        }
        items.removeAll { $0.isFinished }
        lastCall = lastCall.filter { id, _ in items.contains { $0.id == id } }
        noticed = noticed.filter { id in items.contains { $0.id == id } }
    }

    // MARK: - Helpers

    private static func isOn(_ ledge: Ledge, _ pet: Pet) -> Bool {
        abs(pet.position.y - ledge.y) <= 1 && ledge.spans(pet.position.x) && pet.support?.owner == ledge.owner
    }

    private static func screen(for id: UInt32?, in world: World, near point: CGPoint? = nil) -> ScreenArea? {
        if let id, let screen = world.screens.first(where: { $0.id == id }) { return screen }
        if let point, let screen = world.screen(containing: CGPoint(x: point.x, y: point.y + 1)) { return screen }
        if let window = world.focusedWindowID.flatMap(world.window(id:)), let screen = world.screen(of: window) { return screen }
        return world.screens.first { $0.frame.origin == .zero } ?? world.screens.first
    }

    private func shuffled(_ ledges: [Ledge]) -> [Ledge] {
        ledges.map { ($0, random.next()) }.sorted { $0.1 < $1.1 }.map(\.0)
    }

    private static func label(_ owner: SurfaceOwner) -> String {
        owner.windowID.map { "window \($0)" } ?? "floor"
    }
}
