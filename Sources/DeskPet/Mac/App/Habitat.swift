import AppKit

/// This object is responsible for running the desktop pet simulation on one steady clock:
/// refreshing the world from macOS, stepping the pets, drawing them and routing clicks to grabbable pets.
final class Habitat {
    let world = World()
    let roster: PetRoster
    private let desktop: DesktopSource
    private let director = StageDirector()
    private let dragInput: PetDragInput
    /// 키를 누른 수만 셈 (어떤 키인지는 모름)
    private let keys = KeyPressCounter()
    /// 펫이 포인터를 쥐었을 때만 옮김
    private let cursorMover = CursorMover()
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var sinceWindowRefresh: TimeInterval = 0
    private var sinceMicrophoneCheck: TimeInterval = .infinity
    /// 마이크가 쓰이는 동안(통화 중) 조용히 할지
    var quietDuringCalls = true {
        didSet { sinceMicrophoneCheck = .infinity }
    }

    /// 마이크 사용 여부를 확인하는 간격
    private let microphoneCheckInterval: TimeInterval = 1

    /// 창 목록을 다시 읽는 간격
    private let windowRefreshInterval: TimeInterval = 0.1
    /// 창이 움직이는 동안 읽는 간격 (흔들기를 놓치지 않고 올라탄 펫이 매끄럽게 따라오게)
    private let movingRefreshInterval: TimeInterval = 1.0 / 30
    /// 창이 멈춘 뒤에도 빨리 읽는 시간
    private let movingLinger: TimeInterval = 0.5
    private var fastRefreshLeft: TimeInterval = 0
    /// 한 틱 최대 시간 (멈췄다 돌아온 뒤 순간이동 방지)
    private let maxTickDuration: TimeInterval = 0.1

    /// 펫 우클릭 메뉴를 띄울 곳
    var onPetContextMenu: ((Pet, CGPoint) -> Void)?

    var opacity: CGFloat {
        get { director.opacity }
        set { director.opacity = newValue }
    }

    init(roster: PetRoster, desktop: DesktopSource = SystemDesktop()) {
        self.roster = roster
        self.desktop = desktop
        self.dragInput = PetDragInput(roster: roster)
        dragInput.onEvent = { PetLogger.shared.log($0) }
        dragInput.onItemClick = { [unowned self] point in self.roster.fetch(itemAt: point, in: self.world) }
        dragInput.onContextMenu = { [weak self] pet, point in self?.onPetContextMenu?(pet, point) }
    }

    func start() {
        refreshDisplays()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshDisplays()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.director.bringToFront()
        }

        // 키 누름 수를 읽을 수 있는지 기록 (권한 없이 읽히면 0이 아닌 값)
        PetLogger.shared.log("⌨️ key-press counter starts at \(KeyPressCounter.total()) (counts only)")
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 모니터 구성 변경 시 월드와 무대만 다시 만듦
    func refreshDisplays() {
        let areas = desktop.displays()
        world.update(screens: areas, windows: desktop.windows())
        director.rebuild(for: areas)
        let summary = areas.map { "\($0.name) \(Int($0.frame.width))x\(Int($0.frame.height))@(\(Int($0.frame.minX)),\(Int($0.frame.minY)))" }
        PetLogger.shared.log("🖥️ Displays: \(summary.joined(separator: ", "))")
    }

    /// 마지막 키보드·마우스 입력 후 지난 시간 (입력 내용은 읽지 않음, 권한 불필요)
    static func secondsSinceUserInput() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, maxTickDuration)
        lastTick = now

        sinceWindowRefresh += dt
        fastRefreshLeft -= dt
        if sinceWindowRefresh >= (fastRefreshLeft > 0 ? movingRefreshInterval : windowRefreshInterval) {
            sinceWindowRefresh = 0
            let windows = desktop.windows()
            if windows.map(\.frame) != world.windows.map(\.frame) { fastRefreshLeft = movingLinger }
            world.update(windows: windows)
            let app = desktop.frontmostApp()
            world.focus(processID: app?.processID, bundleID: app?.bundleID)
        }
        sinceMicrophoneCheck += dt
        if sinceMicrophoneCheck >= microphoneCheckInterval {
            sinceMicrophoneCheck = 0
            roster.isQuiet = quietDuringCalls && MicrophoneMonitor.isInUse()
        }

        let cursor = NSEvent.mouseLocation
        roster.step(dt: dt, in: world, cursor: cursor, idleSeconds: Self.secondsSinceUserInput(), keyPresses: keys.newPresses())
        if let held = roster.heldCursor { cursorMover.move(to: held) }
        director.render(roster.pets, projectiles: roster.projectiles, items: roster.finding.items, discreet: roster.isQuiet)
        director.routeMouse(at: cursor, toPets: dragInput.isHolding || roster.pet(at: cursor) != nil || roster.finding.item(at: cursor) != nil)
    }
}
