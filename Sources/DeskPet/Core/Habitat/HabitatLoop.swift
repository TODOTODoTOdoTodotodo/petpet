import Foundation

/// This object is responsible for running the desktop pet simulation on one steady clock, in a fixed order:
/// refreshing the world from the desktop (faster while windows move), stepping the pets, drawing them,
/// and letting only the stage under a grabbable pet or item (a crumpled notice included) take the mouse.
/// The platform shell only drives `tick(now:)` from its 60Hz timer and supplies the host contracts.
final class HabitatLoop {
    let world = World()
    let roster: PetRoster
    let gesture: PetPointerGesture
    private let desktop: DesktopSource
    private let senses: HostSenses
    private let stage: PetStage

    /// 창 목록을 다시 읽는 간격
    static let windowRefreshInterval: TimeInterval = 0.1
    /// 창이 움직이는 동안 읽는 간격 (흔들기를 놓치지 않고 올라탄 펫이 매끄럽게 따라오게)
    static let movingRefreshInterval: TimeInterval = 1.0 / 30
    /// 창이 멈춘 뒤에도 빨리 읽는 시간
    static let movingLinger: TimeInterval = 0.5
    /// 마이크 사용 여부를 확인하는 간격
    static let microphoneCheckInterval: TimeInterval = 1
    /// 한 틱 최대 시간 (멈췄다 돌아온 뒤 순간이동 방지)
    static let maxTickDuration: TimeInterval = 0.1
    /// 간격 비교 여유 (부동소수 누적 오차)
    private static let timingTolerance: TimeInterval = 1e-6

    private var lastTick: TimeInterval?
    private var sinceWindowRefresh: TimeInterval = 0
    private var fastRefreshLeft: TimeInterval = 0
    private var sinceMicrophoneCheck: TimeInterval = .infinity

    /// 마이크가 쓰이는 동안(통화 중) 조용히 할지
    var quietDuringCalls = true {
        didSet { sinceMicrophoneCheck = .infinity }
    }
    /// 모니터 구성 기록
    var onEvent: ((String) -> Void)?

    init(roster: PetRoster, desktop: DesktopSource, senses: HostSenses, stage: PetStage) {
        self.roster = roster
        self.desktop = desktop
        self.senses = senses
        self.stage = stage
        gesture = PetPointerGesture(roster: roster)
        gesture.onItemClick = { [unowned self] point in self.roster.fetch(itemAt: point, in: self.world) }
    }

    /// 모니터 구성 변경 시 월드와 무대만 다시 만듦 (펫은 roster에 그대로 남음)
    func refreshDisplays() {
        let areas = desktop.displays()
        world.update(screens: areas, windows: desktop.windows())
        stage.rebuild(for: areas)
        let summary = areas.map { "\($0.name) \(Int($0.frame.width))x\(Int($0.frame.height))@(\(Int($0.frame.minX)),\(Int($0.frame.minY)))" }
        onEvent?("🖥️ Displays: \(summary.joined(separator: ", "))")
    }

    /// now: 단조 증가하는 초 단위 시계 (첫 틱은 시간을 재기만 함)
    func tick(now: TimeInterval) {
        let dt = lastTick.map { min(max(now - $0, 0), Self.maxTickDuration) } ?? 0
        lastTick = now

        sinceWindowRefresh += dt
        fastRefreshLeft -= dt
        // 1/60초 틱을 더한 값이 0.1초에 살짝 못 미쳐 한 틱 늦게 읽지 않도록 작은 여유를 둠
        let refreshInterval = fastRefreshLeft > 0 ? Self.movingRefreshInterval : Self.windowRefreshInterval
        if sinceWindowRefresh >= refreshInterval - Self.timingTolerance {
            sinceWindowRefresh = 0
            let windows = desktop.windows()
            if windows.map(\.frame) != world.windows.map(\.frame) { fastRefreshLeft = Self.movingLinger }
            world.update(windows: windows)
            let app = desktop.frontmostApp()
            world.focus(processID: app?.processID, bundleID: app?.bundleID)
        }
        sinceMicrophoneCheck += dt
        if sinceMicrophoneCheck >= Self.microphoneCheckInterval - Self.timingTolerance {
            sinceMicrophoneCheck = 0
            roster.isQuiet = quietDuringCalls && senses.microphoneInUse()
        }

        let cursor = senses.cursor
        roster.step(dt: dt, in: world, cursor: cursor, idleSeconds: senses.secondsSinceUserInput(), keyPresses: senses.newKeyPresses())
        if let held = roster.heldCursor { senses.moveCursor(to: held) }
        stage.render(roster.pets, projectiles: roster.projectiles, items: roster.finding.items, notes: roster.notices.crumples,
                     discreet: roster.isQuiet)
        let grabbable = gesture.isHolding || roster.pet(at: cursor) != nil || roster.hasItem(at: cursor)
        stage.routeMouse(at: cursor, toPets: grabbable)
    }
}
