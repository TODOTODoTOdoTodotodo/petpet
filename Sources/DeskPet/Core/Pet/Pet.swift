import Foundation

/// 펫이 바라보는 방향
enum Facing: String, CaseIterable {
    case east
    case west
    case south
    case north

    /// 수평 이동 부호 (west만 음수)
    var sign: CGFloat { self == .west ? -1 : 1 }

    var opposite: Facing {
        switch self {
        case .east: return .west
        case .west: return .east
        case .south: return .north
        case .north: return .south
        }
    }
}

/// 행동이 요구하는 애니메이션 종류
enum AnimationKind: String {
    case idle
    case walk
    case climb
    case airborne
    case act
    case dragged
    case hang
    case sleep
}

/// 48x48 칸 안에서 몸이 차지하는 영역 (스프라이트 픽셀 단위)
struct BodyMetrics: Equatable {
    /// 칸 아래쪽 투명 여백
    let footInset: CGFloat
    let width: CGFloat
    let height: CGFloat
    /// 칸 왼쪽에서 몸 중심까지 거리
    let centerX: CGFloat

    static let fullFrame = BodyMetrics(footInset: 0, width: 48, height: 48, centerX: 24)
}

/// This object is responsible for telling the simulation what a pet's look allows,
/// independent of how its textures are stored or drawn.
protocol PetAppearance: AnyObject {
    var name: String { get }
    var body: BodyMetrics { get }
    var skillStyle: SkillStyle { get }
    /// 모자 자리 보정 (스킨 도트 단위, x는 얼굴 쪽 +, y는 위 +)
    var hatAnchor: CGVector { get }
    /// 던지기 성격: 맞힐 확률에 더하는 값 (예: 닌자 +0.15, 덩치 큰 악마 -0.15)
    var aimBias: Double { get }
    func supports(_ kind: AnimationKind) -> Bool
    /// 지금 프레임에서 머리가 서 있는 그림보다 옮겨 간 정도 (스킨 도트 단위, 화면 기준 x 오른쪽 +, y 위 +)
    func headShift(for kind: AnimationKind, facing: Facing, elapsed: TimeInterval) -> CGVector
    /// 지금 프레임에서 앞손(물건 드는 손)이 서 있는 그림보다 옮겨 간 정도 (단위·방향은 머리와 같음)
    func handShift(for kind: AnimationKind, facing: Facing, elapsed: TimeInterval) -> CGVector
    /// 애니메이션 한 바퀴 시간
    func cycleDuration(of kind: AnimationKind, facing: Facing) -> TimeInterval
}

extension PetAppearance {
    var hatAnchor: CGVector { .zero }
    var aimBias: Double { 0 }
    func headShift(for kind: AnimationKind, facing: Facing, elapsed: TimeInterval) -> CGVector { .zero }
    func handShift(for kind: AnimationKind, facing: Facing, elapsed: TimeInterval) -> CGVector {
        headShift(for: kind, facing: facing, elapsed: elapsed)
    }
}

/// 펫이 딛고 있는 면과, 그 면이 창이면 직전에 본 창 위치
struct Support {
    let owner: SurfaceOwner
    var anchor: CGRect?
}

/// This object is responsible for one pet's body in global coordinates: where its feet are,
/// which way it faces, what it stands on and which behavior currently drives it.
final class Pet {
    static let frameSide: CGFloat = 48

    /// 기본 펫인지, 일정 하나를 전하러 온 전령인지
    enum Role {
        case resident
        case messenger
    }

    let id: String
    /// 설정에 저장된 오래가는 ID (기본 펫만, 앱을 다시 켜도 같음). 표시 ID(Pet-1)는 로그용
    var keeperID: String?
    /// 쓰고 있는 모자 (캐릭터를 바꿔도 유지)
    var hat: HatKind?
    /// 친밀도 레벨 (1~6). 레벨별 동작을 정함
    var level = 1
    /// 반짝 발자국 색 단계 (❤️ 300 분홍, 500 금색)
    var sparkleTier = 0
    /// 지어 준 이름 (Lv.6)
    var nickname: String?
    /// 앞손에 든 물건 (Lv.4)
    var heldItem: ItemKind?
    /// 아직 거두지 않은 친밀도 사건
    private var moments: [PetMoment] = []
    let role: Role
    /// 전령이 알림을 전하고(확인받고) 떠날 차례인지
    private(set) var hasDelivered = false
    var appearance: PetAppearance
    var scale: CGFloat
    /// 발 중앙 위치 (전역 좌표)
    var position: CGPoint
    var velocity: CGVector = .zero
    var facing: Facing = .east
    var support: Support?
    private(set) var behavior: PetBehavior
    private(set) var animationElapsed: TimeInterval = 0
    private(set) var speech: Speech?
    /// 펫이 살아온 시간 (연속 클릭 판정용)
    private(set) var clock: TimeInterval = 0
    private var pokeTimes: [TimeInterval] = []
    /// 던졌지만 아직 무대(PetRoster)에 넘기지 않은 무기
    private var thrown: [ThrowRequest] = []
    /// 행동 전환 알림 (이전 이름, 새 이름)
    var onBehaviorChange: ((Pet, String, String) -> Void)?

    /// 연속 클릭으로 보는 시간 범위
    static let pokeStreakWindow: TimeInterval = 2.5
    /// 창 갱신 한 번(0.1초)에 이보다 많이 움직이면 순간이동으로 봄
    static let maxRideStep: CGFloat = 250

    init(id: String, role: Role = .resident, appearance: PetAppearance, scale: CGFloat, position: CGPoint, behavior: PetBehavior) {
        self.id = id
        self.role = role
        self.appearance = appearance
        self.scale = scale
        self.position = position
        self.behavior = behavior
        behavior.begin(self)
    }

    // MARK: - Body

    var spriteSide: CGFloat { Pet.frameSide * scale }
    var bodyHalfWidth: CGFloat { appearance.body.width * scale / 2 }
    var bodyHeight: CGFloat { appearance.body.height * scale }
    /// 크기에 비례한 이동 속도 배율 (기준 1.5배)
    var motionScale: CGFloat { scale / 1.5 }
    var displayFacing: Facing { behavior.displayFacing ?? facing }
    var animation: AnimationKind { behavior.animation }
    var isDragged: Bool { behavior is DraggedBehavior }
    var effect: VisualEffect { behavior.effect }
    var opacity: CGFloat { behavior.opacity }
    /// 잡을 수 있게 보이는지 (건너가는 중 사라진 펫은 잡지 않음)
    var isTangible: Bool { opacity >= 0.5 }
    var isShowingNotice: Bool { speech?.kind == .notice }
    var pose: BodyPose { behavior.pose }
    /// 올라서 있거나 붙잡고 있는 창
    var perchWindowID: UInt32? { behavior.heldWindowID ?? support?.owner.windowID }
    /// 들고 있는 알림의 일정 ID
    var noticeTopic: String? { isShowingNotice ? speech?.topic : nil }
    /// 확인받고 인사도 끝나 화면에서 내보낼 전령인지
    var isReadyToLeave: Bool { role == .messenger && hasDelivered && speech == nil && !isDragged }

    /// 몸이 차지하는 사각형 (뒤집혔으면 발 아래로 몸이 늘어짐, 가림 전)
    var bodyRect: CGRect {
        CGRect(x: position.x - bodyHalfWidth, y: pose.upsideDown ? position.y - bodyHeight : position.y,
               width: bodyHalfWidth * 2, height: bodyHeight)
    }

    /// 화면에 보이는 몸 (창 윗변 뒤로 숨은 부분 제외). 다 숨었으면 nil
    var visibleBodyRect: CGRect? {
        guard let hiddenAbove = pose.hiddenAbove else { return bodyRect }
        let body = bodyRect
        let top = min(body.maxY, hiddenAbove)
        guard top > body.minY else { return nil }
        return CGRect(x: body.minX, y: body.minY, width: body.width, height: top - body.minY)
    }

    /// 잡을 수 있는 영역 (보이는 몸 둘레)
    var grabRect: CGRect {
        visibleBodyRect?.insetBy(dx: -4, dy: -2) ?? .null
    }

    // MARK: - Simulation

    /// 화면 밖으로 사라졌는지. 창 윗변 뒤에 숨은 펫은 발이 화면 위로 나가도 붙잡은 창이 있으니 제외
    func isLost(in world: World) -> Bool {
        !isDragged && behavior.heldWindowID == nil && !world.contains(CGPoint(x: position.x, y: position.y + 1))
    }

    func step(dt: TimeInterval, in world: World, context: PetContext) {
        clock += dt
        animationElapsed += dt * behavior.animationSpeed
        if var current = speech {
            current.remaining -= dt
            if context.idleSeconds < Speech.presenceLimit { current.age += dt }
            speech = current.remaining > 0 ? current : nil
        }
        if let next = behavior.step(self, in: world, context: context, dt: dt) {
            switchTo(next)
        }
    }

    // MARK: - Throwing

    /// 손(몸 앞쪽 어깨 높이)에서 target으로 무기를 던짐. PetRoster가 다음에 받아 감
    func hurl(_ kind: ProjectileKind, at target: CGPoint, missed: Bool = false) {
        let hand = CGPoint(x: position.x + facing.sign * bodyHalfWidth, y: position.y + bodyHeight * 0.6)
        thrown.append(ThrowRequest(kind: kind, from: hand, to: target, missed: missed))
    }

    /// 친밀도가 될 일을 쌓아 둠 (AffectionCoordinator가 거둠)
    func note(_ moment: PetMoment) {
        moments.append(moment)
    }

    func takeMoments() -> [PetMoment] {
        defer { moments.removeAll() }
        return moments
    }

    /// 쓰다듬었을 때 하트 (이름이 있으면 함께)
    var loveText: String {
        nickname.map { "\(Chatter.love) \($0)" } ?? Chatter.love
    }

    /// 던진 무기를 넘겨주고 비움
    func takeThrows() -> [ThrowRequest] {
        defer { thrown.removeAll() }
        return thrown
    }

    // MARK: - Speech

    /// 말풍선을 띄움. 알림이 떠 있으면 잡담은 무시됨
    /// badge·app: 앱 아이콘과, 펫을 누르면 앞으로 불러올 그 앱
    func say(_ text: String, kind: Speech.Kind = .chatter, for duration: TimeInterval = 1.6,
             badge: SpeechBadge? = nil, app: Int32? = nil) {
        let next = Speech(text: text, kind: kind, remaining: duration, badge: badge, appProcessID: app)
        if let current = speech, !current.yields(to: next) { return }
        speech = next
    }

    func clearSpeech() {
        speech = nil
    }

    // MARK: - Reactions

    /// 클릭(쓰다듬기). 알림 말풍선이 떠 있으면 확인으로 보고 닫음. 전령은 인사하고 떠날 준비
    func poke() {
        if isShowingNotice {
            dismissNotice()
            return
        }
        pokeTimes = pokeTimes.filter { clock - $0 <= Pet.pokeStreakWindow } + [clock]
        if pokeTimes.count < GroundReaction.annoyedStreak { note(.poked) }
        if let next = behavior.poked(self, streak: pokeTimes.count) {
            switchTo(next)
        }
    }

    /// 알림 말풍선을 닫음. 전령은 인사하고 떠날 준비
    func dismissNotice() {
        guard isShowingNotice else { return }
        clearSpeech()
        if role == .messenger {
            hasDelivered = true
            say(Chatter.hello, for: 1.2)
        }
    }

    /// 오래 둔 알림을 구겨 버림: 말풍선을 닫고 그 알림을 돌려줌 (더미에 남기기 위함). 전령은 이걸로 할 일을 마침
    func crumpleNotice() -> ScheduleNotice? {
        guard let notice = speech?.notice else { return nil }
        clearSpeech()
        if role == .messenger { hasDelivered = true }
        say(Chatter.tossed, for: 1.0)
        return notice
    }

    /// 일정 알림. 확인할 때까지 유지. 서 있으면 정면을 보고 잠시 멈추고, 자고 있었으면 깸
    func announce(_ notice: ScheduleNotice) {
        speech = Speech(text: notice.text, kind: .notice, remaining: .infinity, topic: notice.topic,
                        discreetText: notice.discreetText, badge: notice.badge, appProcessID: notice.appProcessID)
        if let next = behavior.announcing(self, for: Pet.announcePause) {
            switchTo(next)
        }
    }

    /// 알릴 때 멈춰 서서 정면을 보는 시간
    static let announcePause: TimeInterval = 4

    /// 올라서 있거나 붙잡은 창이 흔들려 💫 하고 튕겨 나감.
    /// push는 창이 마지막으로 움직인 속도(pt/s), spread(-1~1)는 펫마다 흩어지는 정도
    func shakeOff(push: CGVector, spread: CGFloat) {
        guard perchWindowID != nil, !isDragged else { return }
        let k = motionScale
        let side = max(min(push.dx * Self.flingCarry + spread * Self.flingSpread, Self.maxFlingSide), -Self.maxFlingSide)
        let up = PetPhysics.jumpSpeed * (1.1 + 0.2 * abs(spread)) + max(push.dy, 0) * Self.flingCarry
        switchTo(AirborneBehavior.flung(CGVector(dx: side * k, dy: min(up, Self.maxFlingUp) * k)))
        say(Chatter.dizzy, for: 2)
    }

    /// 창 속도 중 펫에게 실리는 비율
    static let flingCarry: CGFloat = 0.5
    /// 펫마다 옆으로 흩어지는 속도
    static let flingSpread: CGFloat = 120
    static let maxFlingSide: CGFloat = 650
    static let maxFlingUp: CGFloat = 900

    /// 같은 행동 안에서 동작을 처음부터 다시 재생 (대결 중 연속 공격)
    func restartAnimation() {
        animationElapsed = 0
    }

    func switchTo(_ next: PetBehavior) {
        let previous = behavior.name
        position = uprightPosition
        behavior = next
        animationElapsed = 0
        next.begin(self)
        onBehaviorChange?(self, previous, next.name)
    }

    /// 지금 자세를 풀고 바로 섰을 때의 발 위치.
    /// 거꾸로였으면 같은 자리에서 뒤집고, 윗변 뒤에 숨은 몸은 윗변 아래로 내림 (빼꼼 중 다른 행동으로 넘어갈 때)
    private var uprightPosition: CGPoint {
        var point = position
        if pose.upsideDown { point.y -= bodyHeight }
        if let line = pose.hiddenAbove { point.y = min(point.y, line - bodyHeight) }
        return point
    }

    /// 딛고 있는 창이 움직였으면 따라 움직이고 발을 맞춤. 설 곳이 없으면 false
    func followSupport(in world: World) -> Bool {
        guard var current = support else { return false }
        if let windowID = current.owner.windowID {
            guard let window = world.window(id: windowID) else {
                support = nil
                return false
            }
            let shift = current.anchor.map { window.frame.minX - $0.minX } ?? 0
            let ridden = CGPoint(x: position.x + shift, y: window.frame.maxY)
            // 창이 순간이동(최대화, 모니터 이동)했거나 따라가면 화면 밖이면 타지 않고 그 자리에서 떨어짐
            guard abs(shift) <= Pet.maxRideStep, abs(ridden.y - position.y) <= Pet.maxRideStep,
                  world.contains(CGPoint(x: ridden.x, y: ridden.y + 1)) else {
                support = nil
                return false
            }
            position = ridden
            current.anchor = window.frame
            support = current
        }
        return settle(in: world)
    }

    /// 지금 x에서 보이는 발판에 발을 맞춤. 없으면 support를 비우고 false
    @discardableResult
    func settle(in world: World, tolerance: CGFloat = 3) -> Bool {
        guard let ledge = world.ledge(atX: position.x, nearY: position.y, tolerance: tolerance, margin: bodyHalfWidth * 0.6) else {
            support = nil
            return false
        }
        stand(on: ledge, in: world)
        return true
    }

    /// 발판 위에 발을 올림
    func stand(on ledge: Ledge, in world: World) {
        position.y = ledge.y
        if support?.owner != ledge.owner {
            support = Support(owner: ledge.owner, anchor: ledge.owner.windowID.flatMap { world.window(id: $0)?.frame })
        }
    }

    // MARK: - Drag

    func beginDrag(grabbedAt cursor: CGPoint) {
        // 거꾸로 빼꼼하던 몸은 바로 세운 자리 기준으로 들어 올림
        let start = uprightPosition
        switchTo(DraggedBehavior(grabOffset: CGVector(dx: start.x - cursor.x, dy: start.y - cursor.y)))
    }

    func drag(to cursor: CGPoint) {
        (behavior as? DraggedBehavior)?.move(to: cursor)
    }

    func endDrag() {
        (behavior as? DraggedBehavior)?.release()
    }
}
