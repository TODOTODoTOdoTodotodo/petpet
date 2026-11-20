import AppKit

/// This object is responsible for hosting the shared `HabitatLoop` on macOS: a 60Hz timer on the main run loop,
/// display and Space change notifications, and the macOS readers and stages the loop works through.
final class Habitat {
    let roster: PetRoster
    private let loop: HabitatLoop
    private let director = StageDirector()
    private let senses = MacHostSenses()
    private let dragInput: PetDragInput
    private var timer: Timer?

    var world: World { loop.world }

    /// 마이크가 쓰이는 동안(통화 중) 조용히 할지
    var quietDuringCalls: Bool {
        get { loop.quietDuringCalls }
        set { loop.quietDuringCalls = newValue }
    }

    /// 펫 우클릭 메뉴를 띄울 곳
    var onPetContextMenu: ((Pet, CGPoint) -> Void)? {
        get { loop.gesture.onContextMenu }
        set { loop.gesture.onContextMenu = newValue }
    }

    var opacity: CGFloat {
        get { director.opacity }
        set { director.opacity = newValue }
    }

    init(roster: PetRoster, desktop: DesktopSource = SystemDesktop()) {
        self.roster = roster
        loop = HabitatLoop(roster: roster, desktop: desktop, senses: senses, stage: director)
        loop.onEvent = { PetLogger.shared.log($0) }
        loop.gesture.onEvent = { PetLogger.shared.log($0) }
        dragInput = PetDragInput(gesture: loop.gesture)
    }

    func start() {
        loop.refreshDisplays()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.loop.refreshDisplays()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.director.bringToFront()
        }

        // 키 누름 수를 읽을 수 있는지 기록 (권한 없이 읽히면 0이 아닌 값)
        PetLogger.shared.log("⌨️ key-press counter starts at \(KeyPressCounter.total()) (counts only)")
        loop.tick(now: CACurrentMediaTime())
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.loop.tick(now: CACurrentMediaTime())
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

/// This object is responsible for the macOS readings the habitat needs each tick:
/// pointer location, idle time, key-press count, microphone use, and moving a held pointer.
final class MacHostSenses: HostSenses {
    /// 키를 누른 수만 셈 (어떤 키인지는 모름)
    private let keys = KeyPressCounter()
    /// 펫이 포인터를 쥐었을 때만 옮김
    private let cursorMover = CursorMover()

    var cursor: CGPoint { NSEvent.mouseLocation }

    /// 마지막 키보드·마우스 입력 후 지난 시간 (입력 내용은 읽지 않음, 권한 불필요)
    func secondsSinceUserInput() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    func newKeyPresses() -> Int { keys.newPresses() }

    func microphoneInUse() -> Bool { MicrophoneMonitor.isInUse() }

    func moveCursor(to point: CGPoint) { cursorMover.move(to: point) }
}
