import Foundation

/// This object is responsible for a pet that reached the top edge of a window with no room to stand on
/// (usually a maximized window right under the menu bar): it slips up behind the edge, hangs upside down
/// with only its head showing below the edge, looks left and right, sometimes ducks and peeks again a little further along,
/// and finally slides out and drops. Meanwhile it follows the window, moves over to a same-height window
/// that comes to the front, and lets go when clicked, when announcing, or when the edge disappears.
/// Only existing idle and airborne frames are used, flipped and clipped by the stage, so every skin works the same way.
final class PeekBehavior: PetBehavior {
    private enum Phase {
        /// 바로 선 채 윗변 뒤로 올라가 사라짐
        case rising
        /// 숨은 채 잠깐 기다림 (다시 빼꼼할 때는 옆으로 옮겨 감)
        case hidden
        /// 머리부터 거꾸로 내려옴
        case emerging
        /// 좌우를 두리번거림
        case looking
        /// 다시 숨음
        case ducking
        /// 몸이 쑥 빠져나와 뒤집으며 떨어짐
        case dropping
    }

    let name = "peeking"
    private var windowID: UInt32
    private var offsetX: CGFloat
    private var phase: Phase = .rising
    private var phaseElapsed: TimeInterval = 0
    /// 마지막으로 본 윗변 높이
    private var edgeY: CGFloat?
    /// 윗변 아래로 내민 길이
    private var depth: CGFloat = 0
    /// 뒤집혀 숨기 전, 발이 윗변보다 높은 정도
    private var lift: CGFloat?
    private var lookFacing: Facing?
    private var hasPeekedAgain = false
    private var dropStartDepth: CGFloat = 0

    /// 올라가 숨는 속도 (기준 크기)
    static let riseSpeed: CGFloat = 240
    static let hiddenPause: TimeInterval = 0.35
    static let emergeTime: TimeInterval = 0.35
    /// 두리번거리는 시간 (처음, 다시 빼꼼)
    static let lookTime: TimeInterval = 4
    static let secondLookTime: TimeInterval = 2.5
    /// 고개를 돌리는 간격
    static let lookStep: TimeInterval = 1
    static let duckTime: TimeInterval = 0.3
    static let dropTime: TimeInterval = 0.2
    /// 몸 중 윗변 아래로 내미는 비율 (머리 정도)
    static let peekShare: CGFloat = 0.5
    /// 다 보고 나서 숨었다가 옆에서 다시 빼꼼할 확률
    static let peekAgainChance = 0.5
    /// 다시 빼꼼할 때 옆으로 옮기는 거리 (기준 크기)
    static let sideStep: CGFloat = 56
    /// 가장 오래 머무는 시간 (올라가기 제외)
    static let longestStay = hiddenPause * 2 + emergeTime * 2 + lookTime + duckTime + secondLookTime + dropTime

    /// 같은 높이로 보는 윗변 차이
    static let sameEdgeTolerance: CGFloat = 2

    init(windowID: UInt32, offsetX: CGFloat) {
        self.windowID = windowID
        self.offsetX = offsetX
    }

    var animation: AnimationKind { phase == .rising || phase == .dropping ? .airborne : .idle }
    var displayFacing: Facing? { phase == .looking ? lookFacing : nil }
    var heldWindowID: UInt32? { windowID }

    var pose: BodyPose {
        BodyPose(upsideDown: phase != .rising, hiddenAbove: edgeY)
    }

    func begin(_ pet: Pet) {
        pet.support = nil
        pet.velocity = .zero
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        guard let window = world.window(id: windowID) else { return letGo(pet) }
        let x = min(max(window.frame.minX + offsetX, window.frame.minX + pet.bodyHalfWidth), window.frame.maxX - pet.bodyHalfWidth)
        // 창 이동이 순간이동 수준이면 따라가지 않고 놓음
        guard abs(x - pet.position.x) <= Pet.maxRideStep else { return letGo(pet) }
        let grip = CGPoint(x: x, y: window.frame.maxY - 1)
        if !world.isVisible(grip, onWindow: windowID) {
            guard let front = sameEdgeWindow(coveringGrip: grip, of: window, in: world) else { return letGo(pet) }
            windowID = front.id
            offsetX = x - front.frame.minX
        }
        edgeY = window.frame.maxY
        pet.position.x = x

        phaseElapsed += dt
        if let next = advance(pet, context: context) { return next }
        place(pet, edge: window.frame.maxY, dt: dt)
        return nil
    }

    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        pet.say(Chatter.surprised)
        startDropping()
        return nil
    }

    /// 알림을 전하려면 내려와야 함
    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        startDropping()
        return nil
    }

    // MARK: - Phases

    /// 단계 시간이 다 되면 다음 단계로. 다 끝났으면 떨어지는 행동을 돌려줌
    private func advance(_ pet: Pet, context: PetContext) -> PetBehavior? {
        switch phase {
        case .rising:
            if let lift, lift >= 2 { enter(.hidden) }
        case .hidden:
            if phaseElapsed >= Self.hiddenPause { enter(.emerging) }
        case .emerging:
            if phaseElapsed >= Self.emergeTime {
                lookFacing = pet.facing
                enter(.looking)
            }
        case .looking:
            let stay = hasPeekedAgain ? Self.secondLookTime : Self.lookTime
            if phaseElapsed >= stay {
                if !hasPeekedAgain, context.planner.chance(Self.peekAgainChance) {
                    let side: CGFloat = context.planner.chance(0.5) ? 1 : -1
                    offsetX += side * Self.sideStep * pet.motionScale
                    hasPeekedAgain = true
                    enter(.ducking)
                } else {
                    startDropping()
                }
            } else {
                // 고개를 번갈아 돌림
                let turns = Int(phaseElapsed / Self.lookStep)
                lookFacing = turns.isMultiple(of: 2) ? pet.facing : pet.facing.opposite
            }
        case .ducking:
            if phaseElapsed >= Self.duckTime { enter(.hidden) }
        case .dropping:
            if phaseElapsed >= Self.dropTime { return letGo(pet) }
        }
        return nil
    }

    private func enter(_ next: Phase) {
        phase = next
        phaseElapsed = 0
    }

    private func startDropping() {
        guard phase != .dropping else { return }
        dropStartDepth = depth
        enter(.dropping)
    }

    /// 단계에 맞춰 윗변 기준으로 몸을 놓음. 뒤집힌 동안 발은 윗변 위(가려진 곳)에 있음
    private func place(_ pet: Pet, edge: CGFloat, dt: TimeInterval) {
        let peek = pet.bodyHeight * Self.peekShare
        switch phase {
        case .rising:
            let current = (lift ?? pet.position.y - edge) + Self.riseSpeed * pet.motionScale * CGFloat(dt)
            lift = current
            pet.position.y = edge + current
            return
        case .hidden:
            depth = 0
        case .emerging:
            let t = CGFloat(min(phaseElapsed / Self.emergeTime, 1))
            depth = peek * (1 - (1 - t) * (1 - t))
        case .looking:
            // 숨 쉬듯 1pt 정도 오르내림
            depth = peek + CGFloat(sin(phaseElapsed * 3)) * pet.motionScale
        case .ducking:
            depth = peek * CGFloat(max(1 - phaseElapsed / Self.duckTime, 0))
        case .dropping:
            let t = CGFloat(min(phaseElapsed / Self.dropTime, 1))
            depth = dropStartDepth + (pet.bodyHeight - dropStartDepth) * t
        }
        pet.position.y = edge + pet.bodyHeight - depth
    }

    /// 놓고 떨어짐. 바로 서는 자리는 Pet이 자세를 풀며 맞춤 (윗변 아래)
    private func letGo(_ pet: Pet) -> PetBehavior {
        AirborneBehavior.falling()
    }

    /// 손 위치를 덮은 앞 창의 윗변이 같은 높이면 그 창
    private func sameEdgeWindow(coveringGrip grip: CGPoint, of window: WindowSnapshot, in world: World) -> WindowSnapshot? {
        guard let front = world.frontWindow(at: grip), front.id != windowID,
              abs(front.frame.maxY - window.frame.maxY) <= Self.sameEdgeTolerance,
              world.isVisible(CGPoint(x: grip.x, y: front.frame.maxY - 1), onWindow: front.id) else { return nil }
        return front
    }
}
