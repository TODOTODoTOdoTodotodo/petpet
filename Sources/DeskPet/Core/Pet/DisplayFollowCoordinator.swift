import Foundation

/// This object is responsible for the pets slowly gathering on the display they chase (the active window's display,
/// or the mouse pointer's): once that display has stayed the same for a few seconds, free pets left on other displays cross over
/// one at a time, spreading out on the floor around the window. It also tells where newly called pets should appear.
final class DisplayFollowCoordinator {
    /// 이만큼 그 모니터에 머물러야 따라가기 시작 (잠깐 들른 모니터로는 옮기지 않음)
    static let settleDelay: TimeInterval = 5
    /// 한 마리씩 건너가는 간격
    static let interval: TimeInterval = 8
    /// 나타날 때 서로 벌리는 간격 (펫 크기 1.5배 기준)
    static let spacing: CGFloat = 90

    var isEnabled = true
    /// 쫓는 곳이 있는 모니터 (보고 있는 창 또는 마우스 포인터)
    private(set) var activeScreenID: UInt32?
    private var clock: TimeInterval = 0
    private var activeSince: TimeInterval = 0
    private var lastMove: TimeInterval = -.infinity
    var onEvent: ((String) -> Void)?

    func step(dt: TimeInterval, pets: [Pet], world: World, target chased: ChaseTarget, quiet: Bool = false) {
        clock += dt
        if let screenID = chased.screenID, screenID != activeScreenID {
            activeScreenID = screenID
            activeSince = clock
        }
        guard isEnabled, !quiet, world.screens.count > 1,
              let screen = world.screens.first(where: { $0.id == activeScreenID }),
              clock - activeSince >= Self.settleDelay, clock - lastMove >= Self.interval else { return }

        let onTarget = { (pet: Pet) in world.screen(containing: CGPoint(x: pet.position.x, y: pet.position.y + 1))?.id == screen.id }
        // 일정 알림을 든 펫도 따라옴 (보이는 곳에서 알려야 하므로)
        guard let pet = pets.first(where: { !onTarget($0) && $0.behavior.isAtLeisure && !$0.isDragged }) else { return }
        let anchor = chased.anchorX
            .flatMap { x in screen.frame.minX...screen.frame.maxX ~= x ? x : nil } ?? screen.visibleFrame.midX
        let x = anchor + Self.offset(forArrival: pets.filter(onTarget).count) * pet.motionScale
        guard let arrival = ScreenHopPlanner.arrival(for: pet, on: screen, nearX: x, in: world) else { return }

        lastMove = clock
        pet.switchTo(ScreenHopBehavior(windowID: nil, arrival: arrival, style: pet.appearance.skillStyle,
                                       hasActionFrames: pet.appearance.supports(.act)))
        onEvent?("🌀 [\(pet.id)] following to display \(screen.name) (\(Int(arrival.x)), \(Int(arrival.y)))")
    }

    /// 0, -1, +1, -2, +2 … 칸씩 번갈아 벌림
    static func offset(forArrival index: Int) -> CGFloat {
        let step = CGFloat((index + 1) / 2)
        return (index % 2 == 0 ? step : -step) * spacing
    }
}
