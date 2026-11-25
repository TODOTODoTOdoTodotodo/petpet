import Foundation

/// This object is responsible for notices the user leaves unanswered for a long time: the pet holding one crumples it
/// and tosses it to a pile on one side of its display's floor, where it stays (never lost) until the user clicks a ball
/// to have it announced again, or the notice is withdrawn. It tosses nothing during calls or while turned off.
final class NoticePileCoordinator {
    /// 오래 둔 알림 던지기 (메뉴로 끔)
    var isEnabled = true
    var onEvent: ((String) -> Void)?
    /// 날아가는 중이거나 더미에 놓인 종이 뭉치 (오래된 것부터)
    private(set) var crumples: [CrumpledNotice] = []
    /// 모니터별 더미가 쌓이는 쪽 (첫 뭉치를 던진 펫에게 가까운 끝)
    private var sides: [UInt32: Facing] = [:]
    private var nextNumber = 1

    /// 사용자가 자리에 있는 동안 이만큼 확인하지 않은 알림을 던짐
    static let defaultTossAfter: TimeInterval = 1800
    /// 던지기까지 기다리는 시간 (검사에서 줄임)
    var tossAfter = NoticePileCoordinator.defaultTossAfter
    /// 더미 한 줄마다 놓이는 수 (아래 줄부터). 합이 모니터 하나의 더미 상한
    static let rowSizes = [4, 3, 2, 1]
    static var maxPile: Int { rowSizes.reduce(0, +) }
    /// 화면 끝에서 더미까지 여백
    static let edgeMargin: CGFloat = 12

    func step(dt: TimeInterval, pets: [Pet], world: World, quiet: Bool) {
        crumples.forEach { $0.step(dt: dt) }
        arrange(in: world)
        guard isEnabled, !quiet else { return }
        for pet in pets where wantsToToss(pet) {
            toss(from: pet, in: world)
        }
    }

    /// 확인하지 않은 채 오래 든 알림을 땅 위에서 쉬거나 걷는 중에 던짐
    func wantsToToss(_ pet: Pet) -> Bool {
        guard let speech = pet.speech, speech.kind == .notice, speech.age >= tossAfter,
              pet.support != nil, !pet.isDragged else { return false }
        return pet.behavior is IdleBehavior || pet.behavior is WalkBehavior
    }

    /// 그 점의 종이 뭉치 (놓인 것만, 맨 앞 것)
    func crumple(at point: CGPoint) -> CrumpledNotice? {
        crumples.last { !$0.isFlying && $0.hitRect.contains(point) }
    }

    /// 사용자가 뭉치를 누름: 더미에서 꺼내 그 알림을 돌려줌 (다시 띄우기 위함)
    func reopen(at point: CGPoint) -> ScheduleNotice? {
        guard let picked = crumple(at: point) else { return nil }
        crumples.removeAll { $0 === picked }
        onEvent?("📜 reopened crumpled notice: \(picked.notice.text)")
        return picked.notice
    }

    /// 그 주제의 뭉치를 치움 (알림이 거둬지거나 새 문구로 바뀜). 치운 것이 있으면 true
    @discardableResult
    func withdraw(topic: String) -> Bool {
        let before = crumples.count
        crumples.removeAll { $0.notice.topic == topic }
        return crumples.count != before
    }

    func holds(topic: String) -> Bool {
        crumples.contains { $0.notice.topic == topic }
    }

    // MARK: - Tossing

    private func toss(from pet: Pet, in world: World) {
        guard let screen = world.screen(containing: CGPoint(x: pet.position.x, y: pet.position.y + 1)) ?? world.screens.first else { return }
        let side = sides[screen.id] ?? (pet.position.x < screen.frame.midX ? .west : .east)
        sides[screen.id] = side
        let index = min(crumples.filter { $0.screenID == screen.id }.count, Self.maxPile - 1)
        let target = Self.spot(index, side: side, on: screen, scale: pet.scale, in: world)
        pet.switchTo(TossNoticeBehavior(toward: target.x) { [weak self] pet, hand in
            self?.receive(from: pet, hand: hand, screenID: screen.id, in: world)
        })
        onEvent?("🗞️ [\(pet.id)] crumpling an old notice")
    }

    /// 펫이 손을 놓은 순간: 알림을 구겨 뭉치로 날림. 더미가 차면 가장 오래된 뭉치를 치움
    private func receive(from pet: Pet, hand: CGPoint, screenID: UInt32, in world: World) {
        guard let notice = pet.crumpleNotice() else { return }
        let ball = CrumpledNotice(id: "N-\(nextNumber)", notice: notice, scale: pet.scale, screenID: screenID, from: hand)
        nextNumber += 1
        crumples.append(ball)
        let pile = crumples.filter { $0.screenID == screenID }
        if pile.count > Self.maxPile, let oldest = pile.first {
            crumples.removeAll { $0 === oldest }
            onEvent?("🗑️ pile full, dropped oldest notice: \(oldest.notice.text)")
        }
        arrange(in: world)
        onEvent?("🗞️ [\(pet.id)] tossed notice to the pile: \(notice.text)")
    }

    /// 모니터마다 뭉치를 순서대로 더미 자리에 놓음 (사라진 모니터의 뭉치는 첫 모니터로)
    private func arrange(in world: World) {
        guard let fallback = world.screens.first else { return }
        var counts: [UInt32: Int] = [:]
        for ball in crumples {
            let screen = world.screens.first { $0.id == ball.screenID } ?? fallback
            let index = counts[screen.id, default: 0]
            counts[screen.id] = index + 1
            let side = sides[screen.id] ?? .west
            sides[screen.id] = side
            ball.rest(at: Self.spot(min(index, Self.maxPile - 1), side: side, on: screen, scale: ball.scale, in: world))
        }
    }

    /// 더미의 index번째 자리 (아래 가운데). 아래 줄부터 채우고, 윗줄은 반 칸씩 안쪽으로 얹힘
    static func spot(_ index: Int, side: Facing, on screen: ScreenArea, scale: CGFloat, in world: World) -> CGPoint {
        let ball = 8 * scale
        var row = 0
        var column = index
        while row < rowSizes.count - 1, column >= rowSizes[row] {
            column -= rowSizes[row]
            row += 1
        }
        let offset = edgeMargin + (CGFloat(column) + CGFloat(row) * 0.5) * ball + ball / 2
        let x = side == .west ? screen.visibleFrame.minX + offset : screen.visibleFrame.maxX - offset
        let floor = world.floor(atX: x)?.y ?? screen.visibleFrame.minY
        return CGPoint(x: x, y: floor + CGFloat(row) * ball * 0.8)
    }
}

/// This object is responsible for one crumpled notice: flying in an arc from the tossing pet's hand to its place in
/// the pile, then resting there (moving along if the pile is rearranged) while keeping the notice to announce again.
final class CrumpledNotice {
    let id: String
    let notice: ScheduleNotice
    /// 도트 한 칸 크기 (던진 펫 크기)
    let scale: CGFloat
    /// 쌓이는 모니터
    let screenID: UInt32
    /// 아래 가운데 (전역 좌표)
    private(set) var position: CGPoint
    private var flight: (elapsed: TimeInterval, from: CGPoint)?
    private var spot: CGPoint

    /// 손에서 더미까지 나는 시간
    static let flightTime: TimeInterval = 0.7

    init(id: String, notice: ScheduleNotice, scale: CGFloat, screenID: UInt32, from hand: CGPoint) {
        self.id = id
        self.notice = notice
        self.scale = scale
        self.screenID = screenID
        position = hand
        spot = hand
        flight = (0, hand)
    }

    var side: CGFloat { 8 * scale }
    var isFlying: Bool { flight != nil }
    var rect: CGRect { CGRect(x: position.x - side / 2, y: position.y, width: side, height: side) }
    /// 클릭으로 잡을 영역 (작은 그림이라 넉넉하게)
    var hitRect: CGRect { rect.insetBy(dx: -4, dy: -4) }

    /// 더미 속 자리 (날아가는 중이면 도착할 곳만 바꿈)
    func rest(at point: CGPoint) {
        spot = point
        if flight == nil { position = point }
    }

    func step(dt: TimeInterval) {
        guard var current = flight else { return }
        current.elapsed += dt
        let t = CGFloat(min(current.elapsed / Self.flightTime, 1))
        // 위로 솟았다가 더미 자리로 떨어짐
        let lift = sin(t * .pi) * 80 * scale / 1.5
        position = CGPoint(x: current.from.x + (spot.x - current.from.x) * t,
                           y: current.from.y + (spot.y - current.from.y) * t + lift)
        flight = current.elapsed >= Self.flightTime ? nil : current
        if flight == nil { position = spot }
    }
}

extension ItemKind {
    /// 구겨 던진 알림 (도감에 들지 않음, 더미 그림 전용)
    static let crumpledNotice = ItemKind(
        id: "crumpledNotice", englishName: "Crumpled Notice", koreanName: "구긴 알림",
        rows: ["..kkkk..", ".kwwgwk.", "kwgwwwgk", "kwwgwwwk", "kgwwwgwk", "kwwwgwwk", ".kgwwwk.", "..kkkk.."],
        palette: ["k": 0x8A7F66, "w": 0xFFF3CC, "g": 0xD9C48A],
        rarity: .common, weight: 0
    )
}
