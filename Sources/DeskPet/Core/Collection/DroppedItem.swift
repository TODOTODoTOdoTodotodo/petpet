import Foundation

/// This object is responsible for one item on the desktop: falling from under the menu bar with one small bounce,
/// resting on a ledge and riding its window, falling again when that spot disappears, being flung by a shaken window,
/// fading out after a while if nobody picks it up, and flying off to the menu bar once a pet picks it up.
final class DroppedItem {
    enum State: Equatable {
        case falling
        case resting
        /// 주워져 메뉴바 쪽으로 날아가는 중 (주운 펫 ID)
        case collected(by: String)
        /// 아무도 줍지 않아 사라짐
        case expired
        /// 날아가기 끝 (도감에 들어감)
        case delivered
    }

    let id: String
    let kind: ItemKind
    /// 도트 한 칸 크기 (펫 크기와 같음)
    let scale: CGFloat
    /// 아래쪽 가운데 (전역 좌표)
    private(set) var position: CGPoint
    private(set) var state: State = .falling
    private(set) var support: Support?
    private var velocity: CGVector
    private var hasBounced = false
    /// 놓여 있은 시간
    private(set) var restingTime: TimeInterval = 0
    /// 주워진 뒤 날아간 시간과 출발·도착 지점
    private var flight: (elapsed: TimeInterval, from: CGPoint, to: CGPoint)?
    /// 사용자가 클릭했을 때 한 번 반짝이는 남은 시간
    private(set) var flashLeft: TimeInterval = 0

    /// 놓여 있는 최대 시간과, 그중 마지막에 깜빡이는 시간
    static let lifetime: TimeInterval = 180
    static let blinkTime: TimeInterval = 20
    /// 착지 때 튀어 오르는 비율
    static let bounce: CGFloat = 0.3
    /// 메뉴바 쪽으로 날아가는 시간
    static let flightTime: TimeInterval = 0.6
    static let flashTime: TimeInterval = 0.4

    init(id: String, kind: ItemKind, scale: CGFloat, position: CGPoint) {
        self.id = id
        self.kind = kind
        self.scale = scale
        self.position = position
        self.velocity = .zero
    }

    var side: CGFloat { 8 * scale }
    var halfWidth: CGFloat { side / 2 }
    var isResting: Bool { state == .resting }
    var isOnScreen: Bool { state == .falling || state == .resting || isFlying }
    var isFlying: Bool { if case .collected = state { return true } else { return false } }
    var isFinished: Bool { state == .expired || state == .delivered }
    private var motionScale: CGFloat { scale / 1.5 }

    /// 그림 사각형 (날아가는 중이면 작아짐)
    var rect: CGRect {
        let size = side * CGFloat(1 - 0.6 * (flightProgress ?? 0))
        return CGRect(x: position.x - size / 2, y: position.y, width: size, height: size)
    }

    /// 클릭으로 잡을 영역 (작은 그림이라 넉넉하게)
    var hitRect: CGRect { rect.insetBy(dx: -8, dy: -6) }

    /// 날아가기 진행 (0~1). 날지 않으면 nil
    var flightProgress: Double? { flight.map { min($0.elapsed / Self.flightTime, 1) } }

    /// 사라지기 전 깜빡이는 동안 이번 순간 보이는지
    var isBlinkedOut: Bool {
        guard state == .resting, restingTime > Self.lifetime - Self.blinkTime else { return false }
        return Int(restingTime / 0.25) % 2 == 1
    }

    /// 주운 펫. 날아가는 중일 때만
    var collector: String? { if case .collected(let id) = state { return id } else { return nil } }

    // MARK: - Messages

    /// 펫이 주움. 놓여 있을 때만 됨. to는 날아갈 곳 (메뉴바 쪽)
    @discardableResult
    func pickUp(by petID: String, flyingTo target: CGPoint) -> Bool {
        guard state == .resting else { return false }
        state = .collected(by: petID)
        flight = (0, position, target)
        support = nil
        return true
    }

    /// 사용자가 클릭하면 한 번 반짝
    func flash() {
        flashLeft = Self.flashTime
    }

    /// 놓인 창이 흔들려 튕겨 나감
    func fling(push: CGVector, spread: CGFloat) {
        guard state == .resting else { return }
        let k = motionScale
        velocity = CGVector(dx: (push.dx * 0.5 + spread * 160) * k, dy: PetPhysics.jumpSpeed * 0.9 * k)
        state = .falling
        support = nil
        hasBounced = true
    }

    /// 놓인 창 (흔들기 감지용)
    var perchWindowID: UInt32? { state == .resting ? support?.owner.windowID : nil }

    // MARK: - Simulation

    func step(dt: TimeInterval, in world: World) {
        flashLeft = max(flashLeft - dt, 0)
        switch state {
        case .falling:
            var remaining = dt
            while remaining > 0, state == .falling {
                let slice = min(remaining, PetPhysics.maxStep)
                remaining -= slice
                fall(in: world, dt: CGFloat(slice))
            }
        case .resting:
            restingTime += dt
            if restingTime >= Self.lifetime {
                state = .expired
            } else if !followSupport(in: world) {
                state = .falling
                velocity = .zero
                hasBounced = true
            }
        case .collected:
            guard var current = flight else { return }
            current.elapsed += dt
            flight = current
            let t = CGFloat(min(current.elapsed / Self.flightTime, 1))
            // 위로 솟았다가 도착점으로 (살짝 휘어짐)
            let ease = t * t * (3 - 2 * t)
            position = CGPoint(x: current.from.x + (current.to.x - current.from.x) * ease,
                               y: current.from.y + (current.to.y - current.from.y) * ease + sin(t * .pi) * 60 * motionScale)
            if current.elapsed >= Self.flightTime { state = .delivered }
        case .expired, .delivered:
            break
        }
    }

    private func fall(in world: World, dt: CGFloat) {
        let k = motionScale
        velocity.dy = max(velocity.dy - PetPhysics.gravity * k * dt, -PetPhysics.terminalSpeed * k)
        var next = CGPoint(x: position.x + velocity.dx * dt, y: position.y + velocity.dy * dt)
        if velocity.dx != 0 {
            let front = CGPoint(x: next.x + (velocity.dx > 0 ? halfWidth : -halfWidth), y: max(next.y, position.y) + 1)
            if !world.contains(front) {
                velocity.dx = -velocity.dx * 0.3
                next.x = position.x
            }
        }
        if velocity.dy > 0, let ceiling = world.ceiling(atX: next.x, above: position.y), next.y + side > ceiling {
            next.y = max(position.y, ceiling - side)
            velocity.dy = 0
        }
        if velocity.dy <= 0, let ledge = world.landingLedge(atX: next.x, from: position.y, to: next.y)
            ?? world.floor(atX: next.x).flatMap({ next.y < $0.y ? $0 : nil }) {
            land(on: ledge, atX: next.x, in: world)
            return
        }
        position = next
        // 화면 밖으로 빠지면 사라짐 (도감에 들어가지 않음)
        if !world.contains(CGPoint(x: position.x, y: position.y + 1)) && position.y < -2000 { state = .expired }
    }

    private func land(on ledge: Ledge, atX x: CGFloat, in world: World) {
        position = CGPoint(x: x, y: ledge.y)
        if !hasBounced, velocity.dy < -120 * motionScale {
            hasBounced = true
            velocity = CGVector(dx: velocity.dx * 0.5, dy: -velocity.dy * Self.bounce)
            return
        }
        velocity = .zero
        state = .resting
        support = Support(owner: ledge.owner, anchor: ledge.owner.windowID.flatMap { world.window(id: $0)?.frame })
    }

    /// 놓인 창이 움직였으면 따라가고, 그 자리가 사라졌거나 창이 순간이동했으면 false
    private func followSupport(in world: World) -> Bool {
        guard var current = support else { return false }
        if let windowID = current.owner.windowID {
            guard let window = world.window(id: windowID) else { return false }
            let shift = current.anchor.map { window.frame.minX - $0.minX } ?? 0
            let ridden = CGPoint(x: position.x + shift, y: window.frame.maxY)
            guard abs(shift) <= Pet.maxRideStep, abs(ridden.y - position.y) <= Pet.maxRideStep else { return false }
            position = ridden
            current.anchor = window.frame
            support = current
        }
        guard let ledge = world.ledge(atX: position.x, nearY: position.y, tolerance: 3), ledge.owner == current.owner else { return false }
        position.y = ledge.y
        return true
    }

    /// 지금 놓인 발판 구간
    func ledge(in world: World) -> Ledge? {
        guard state == .resting else { return nil }
        return world.ledge(atX: position.x, nearY: position.y, tolerance: 1)
    }
}
