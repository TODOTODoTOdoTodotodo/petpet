import AppKit
import SpriteKit

/// This object is responsible for the macOS app's lifecycle: loading skins, restoring saved choices, starting the habitat,
/// showing the shared status menu (`AppMenu`) in the menu bar (👾), and applying the settings only the shell owns.
final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var library: MacSkinLibrary!
    private var habitat: Habitat!
    private var lineup: PetLineup<SKTexture>!
    private let settings = PetSettings(store: UserDefaultsSettingsStore())
    private let treasuryStore = TreasuryStore(archive: UserDefaultsTreasuryArchive())
    private var collection: CollectionMenu!
    private var appMenu: AppMenu!
    private lazy var menuRenderer = MacMenuRenderer { [weak self] command in self?.appMenu.perform(command) }
    private let calendar = EventKitScheduleSource()
    private let announcer = ScheduleAnnouncer()
    private var scheduleWatcher: ScheduleWatcher!
    private let usageWatcher = ClaudeUsageWatcher()
    /// AI 도구 훅이 남긴 신호와, 그 세션이 사는 앱 찾기
    private let agentInbox = AgentSignalInbox(folder: AgentSignalInbox.homeFolder)
    private let agentHosts = AgentHostFinder()
    /// 메뉴에 보일 Claude 사용량 요약. nil이면 사용량 정보 없음, ""이면 모두 초기화됨
    private var usageText: String?
    /// App Nap으로 타이머가 멈추지 않게 유지하는 활동 토큰 (맥 자동 잠자기는 허용)
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "DeskPet animation"
        )

        let skinsDirectory = SkinFolder.locate()
        library = MacSkinLibrary(directory: skinsDirectory, loader: MacSpriteLoader.load)
        for name in library.names {
            let blank = library.skins[name]?.blankFrameCount ?? 0
            PetLogger.shared.log("📦 Loaded skin asset: \(name)" + (blank > 0 ? " (skipped \(blank) blank frames)" : ""))
        }

        let roster = PetRoster()
        roster.onEvent = { PetLogger.shared.log($0) }
        roster.messengerLook = { [weak self] in self?.lineup.nextMessengerLook() }
        roster.skills.onEvent = { PetLogger.shared.log($0) }
        roster.attention.onEvent = { PetLogger.shared.log($0) }
        roster.social.onEvent = { PetLogger.shared.log($0) }
        roster.towers.onEvent = { PetLogger.shared.log($0) }
        roster.trains.onEvent = { PetLogger.shared.log($0) }
        roster.space.onEvent = { PetLogger.shared.log($0) }
        roster.follow.onEvent = { PetLogger.shared.log($0) }
        roster.pranks.onEvent = { PetLogger.shared.log($0) }
        roster.typing.onEvent = { PetLogger.shared.log($0) }
        roster.rhythm.onEvent = { PetLogger.shared.log($0) }
        roster.finding.onEvent = { PetLogger.shared.log($0) }
        roster.agents.onEvent = { PetLogger.shared.log($0) }
        roster.notices.onEvent = { PetLogger.shared.log($0) }
        roster.agents.onBringForward = { app in
            NSRunningApplication(processIdentifier: app)?.activate(options: [.activateAllWindows])
        }
        treasuryStore.onEvent = { PetLogger.shared.log($0) }
        let treasury = treasuryStore.load()
        PetLogger.shared.log("🎒 collection: \(treasury.total) items, \(treasury.counts.count) kinds")
        collection = CollectionMenu(treasury: treasury, store: treasuryStore, roster: roster, dialogs: MacMenuDialogs()) { [unowned self] in
            self.settings.menuLanguage
        }
        collection.onChange = { [weak self] in self?.rebuildMenu() }
        collection.onEvent = { PetLogger.shared.log($0) }
        roster.finding.onCollect = { [weak self] kind, petID in self?.collection.collect(kind, by: petID) }
        roster.affection.treasury = treasury
        roster.affection.onEvent = { PetLogger.shared.log($0) }
        roster.affection.onChange = { [weak self] levelUp in self?.collection.heartsChanged(levelUp: levelUp) }
        habitat = Habitat(roster: roster)
        habitat.quietDuringCalls = settings.quietDuringCalls
        habitat.opacity = settings.opacity
        habitat.start()

        lineup = PetLineup(library: library, roster: roster, settings: settings) { [unowned self] in self.habitat.world }
        lineup.onChange = { [weak self] in
            self?.collection.syncPets()
            self?.rebuildMenu()
        }
        lineup.petMenuItems = { [weak self] pet in self?.collection.menuNodes(for: pet) ?? [] }
        lineup.petLabel = { [weak self] pet in self?.collection.label(for: pet) ?? pet.id }
        lineup.confirmRemoval = { [weak self] pet in self?.collection.confirmRemoval(of: pet) ?? true }
        appMenu = AppMenu(settings: settings, roster: roster, host: self,
                          lineup: { [unowned self] in self.lineup.statusMenuNodes() },
                          collection: { [unowned self] in self.collection.menuNode() },
                          handlers: [lineup, collection])
        appMenu.onChange = { [weak self] in self?.rebuildMenu() }
        appMenu.applySettingsToPets()
        // 펫을 우클릭한 자리에 그 펫의 메뉴를 띄움
        habitat.onPetContextMenu = { [weak self] pet, point in
            guard let self else { return }
            self.menuRenderer.menu(from: self.lineup.petMenu(for: pet)).popUp(positioning: nil, at: point, in: nil)
        }
        if library.names.isEmpty {
            PetLogger.shared.log("⚠️ No skins found at \(skinsDirectory.path)")
        }
        lineup.restore()
        collection.syncPets()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "👾"
        statusItem.button?.toolTip = "DeskPet"
        rebuildMenu()
        aimCollectedItems()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.aimCollectedItems()
        }

        announcer.hidesTitles = settings.hidesScheduleTitles
        scheduleWatcher = ScheduleWatcher(source: calendar, announcer: announcer) { [weak roster] notice in
            roster?.announce(notice)
        }
        calendar.onChange = { [weak self] in
            self?.scheduleWatcher.check()
            self?.logScheduleSummary()
        }
        if settings.schedulesEnabled {
            startSchedules()
        }

        usageWatcher.onChange = { [weak self] usage in self?.applyUsage(usage) }
        usageWatcher.start()

        agentInbox.onSignal = { [weak self, weak roster] signal in
            guard let self else { return }
            let dock = signal.kind == .done && self.settings.visitsDockIcons
            roster?.agents.receive(signal, from: self.agentHosts.host(for: signal.processID, withDockIcon: dock))
        }
        agentInbox.start()
    }

    /// Claude 사용량을 펫 기력과 메뉴 요약에 반영
    private func applyUsage(_ usage: ClaudeUsage?) {
        let now = Date()
        let percent = usage?.effectivePercent(at: now)
        habitat.roster.vigor = settings.tiresWithClaudeUsage ? Vigor(usedPercent: percent) : .fresh
        let summary = usage.map { $0.summary(at: now) ?? "" }
        if summary != usageText {
            usageText = summary
            rebuildMenu()
        }
    }

    private var lastScheduleSummary = ""

    /// 앞으로 24시간 일정 개수와 다음 시각만 기록 (제목은 남기지 않음)
    private func logScheduleSummary() {
        let now = Date()
        let items = calendar.items(from: now, to: now.addingTimeInterval(86_400))
        let timed = items.filter { !$0.isAllDay && $0.start > now }.sorted { $0.start < $1.start }
        let events = items.filter { $0.kind == .event }.count
        let reminders = items.filter { $0.kind == .reminder }.count
        let next = timed.first.map { "next in \(Int($0.start.timeIntervalSince(now) / 60)) min" } ?? "nothing timed ahead"
        let summary = "📅 Next 24h: \(events) events, \(reminders) timed reminders, \(next)"
        guard summary != lastScheduleSummary else { return }
        lastScheduleSummary = summary
        PetLogger.shared.log(summary)
    }

    /// 권한을 받은 뒤 일정 확인 시작
    private func startSchedules() {
        // 권한 설명 문구가 없는 실행 파일(swift build 직접 실행)은 권한 요청 시 종료되므로 건너뜀
        guard Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil else {
            PetLogger.shared.log("📅 Schedule bubbles need the packaged app (DeskPet.app)")
            return
        }
        calendar.requestAccess { [weak self] in
            guard let self else { return }
            PetLogger.shared.log("📅 Calendar access: events=\(self.calendar.eventAccess) reminders=\(self.calendar.reminderAccess)")
            if self.settings.schedulesEnabled {
                self.scheduleWatcher.start()
                self.logScheduleSummary()
            }
            self.rebuildMenu()
        }
    }

    /// 주운 물건이 메뉴바 👾 쪽으로 날아가게 그 자리를 알려 줌
    private func aimCollectedItems() {
        guard let frame = statusItem.button?.window?.frame, frame.width > 0 else { return }
        habitat.roster.finding.collectTarget = CGPoint(x: frame.midX, y: frame.minY)
    }

    // MARK: - Menu

    private func rebuildMenu() {
        statusItem.menu = menuRenderer.menu(from: appMenu.nodes())
    }
}

extension AppController: AppMenuHost {
    var usageSummary: String? { usageText }
    var supportsDockVisits: Bool { true }

    var calendarAccessDenied: Bool {
        calendar.eventAccess == .denied || calendar.reminderAccess == .denied
    }

    /// 껍데기 쪽 설정 적용 (값은 이미 settings에 저장됨)
    func settingChanged(_ command: MenuCommand) {
        switch command {
        case .opacity:
            habitat.opacity = settings.opacity
        case .toggle(.quietDuringCalls):
            habitat.quietDuringCalls = settings.quietDuringCalls
        case .toggle(.tiresWithUsage):
            applyUsage(usageWatcher.latest)
        case .toggle(.schedules):
            if settings.schedulesEnabled {
                startSchedules()
            } else {
                scheduleWatcher.stop()
            }
        case .toggle(.dockVisits):
            // 켤 때 권한이 없으면 시스템 허용 창 (허용 전에는 창 도약·제자리 알림으로 대신함)
            if settings.visitsDockIcons && !DockIconLocator.isTrusted {
                DockIconLocator.requestTrust()
            }
            PetLogger.shared.log("🧭 dock visits \(settings.visitsDockIcons ? "on" : "off"), accessibility \(DockIconLocator.isTrusted ? "granted" : "not granted")")
        case .toggle(.scheduleTitles):
            announcer.hidesTitles = settings.hidesScheduleTitles
        default:
            break
        }
    }

    func run(_ action: PlatformAction) {
        switch action {
        case .openLog:
            NSWorkspace.shared.open(PetLogger.shared.fileURL)
        case .quit:
            NSApp.terminate(nil)
        case .allowCalendarAccess:
            // 시스템 설정의 캘린더 개인정보 화면 열기 (허용은 사용자가 직접)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
