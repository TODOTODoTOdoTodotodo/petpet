import AppKit

/// This object is responsible for the app's lifecycle and its menu bar (👾) menu:
/// loading skins, restoring saved choices, starting the habitat and applying menu changes.
final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var library: MacSkinLibrary!
    private var habitat: Habitat!
    private var lineup: PetLineup!
    private let settings = PetSettings()
    private let treasuryStore = TreasuryStore()
    private var collection: CollectionMenu!
    private let calendar = EventKitScheduleSource()
    private let announcer = ScheduleAnnouncer()
    private var scheduleWatcher: ScheduleWatcher!
    private let usageWatcher = ClaudeUsageWatcher()
    /// 메뉴에 보일 Claude 사용량 요약. nil이면 사용량 정보 없음, ""이면 모두 초기화됨
    private var usageSummary: String?
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
        roster.skills.isEnabled = settings.skillJumpsEnabled
        roster.chase = ChaseModes.make(settings.chaseMode)
        roster.skills.onEvent = { PetLogger.shared.log($0) }
        roster.attention.onEvent = { PetLogger.shared.log($0) }
        roster.social.onEvent = { PetLogger.shared.log($0) }
        roster.towers.onEvent = { PetLogger.shared.log($0) }
        roster.trains.onEvent = { PetLogger.shared.log($0) }
        roster.space.onEvent = { PetLogger.shared.log($0) }
        roster.follow.isEnabled = settings.followsActiveDisplay
        roster.follow.onEvent = { PetLogger.shared.log($0) }
        roster.rhythm.isEnabled = settings.workRhythmEnabled
        roster.typing.isEnabled = settings.typingReactionsEnabled
        roster.pranks.isEnabled = settings.cursorPranksEnabled
        roster.pranks.onEvent = { PetLogger.shared.log($0) }
        roster.typing.onEvent = { PetLogger.shared.log($0) }
        roster.rhythm.onEvent = { PetLogger.shared.log($0) }
        roster.finding.onEvent = { PetLogger.shared.log($0) }
        let treasury = treasuryStore.load()
        PetLogger.shared.log("🎒 collection: \(treasury.total) items, \(treasury.counts.count) kinds")
        collection = CollectionMenu(treasury: treasury, store: treasuryStore, roster: roster) { [unowned self] in self.settings.menuLanguage }
        collection.onChange = { [weak self] in self?.rebuildMenu() }
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
        lineup.petMenuItems = { [weak self] pet in self?.collection.menuItems(for: pet) ?? [] }
        lineup.petLabel = { [weak self] pet in self?.collection.label(for: pet) ?? pet.id }
        lineup.confirmRemoval = { [weak self] pet in self?.collection.confirmRemoval(of: pet) ?? true }
        habitat.onPetContextMenu = { [weak self] pet, point in self?.lineup.showMenu(for: pet, at: point) }
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
    }

    /// Claude 사용량을 펫 기력과 메뉴 요약에 반영
    private func applyUsage(_ usage: ClaudeUsage?) {
        let now = Date()
        let percent = usage?.effectivePercent(at: now)
        habitat.roster.vigor = settings.tiresWithClaudeUsage ? Vigor(usedPercent: percent) : .fresh
        let summary = usage.map { $0.summary(at: now) ?? "" }
        if summary != usageSummary {
            usageSummary = summary
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
        let language = settings.menuLanguage
        func text(_ key: MenuText) -> String { key.text(in: language) }
        let menu = NSMenu()
        let title = NSMenuItem(title: "🐾 DeskPet", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        lineup.statusMenuItems().forEach(menu.addItem)
        menu.addItem(collection.menuItem())
        let hint = NSMenuItem(title: text(.rightClickHint), action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(submenu(text(.chase), items: [
            item(text(.chaseActiveWindow), action: #selector(selectChase(_:)), value: ActiveWindowChase.key,
                 checked: settings.chaseMode == ActiveWindowChase.key),
            item(text(.chasePointer), action: #selector(selectChase(_:)), value: PointerChase.key,
                 checked: settings.chaseMode == PointerChase.key),
        ]))
        menu.addItem(item(text(.skillJumps), action: #selector(toggleSkillJumps), checked: settings.skillJumpsEnabled))
        menu.addItem(item(text(.followDisplay), action: #selector(toggleFollowDisplay), checked: settings.followsActiveDisplay))
        menu.addItem(item(text(.quietDuringCalls), action: #selector(toggleQuietDuringCalls), checked: settings.quietDuringCalls))
        menu.addItem(item(MenuText.tireWithUsage(usageText(in: language), in: language), action: #selector(toggleTiring), checked: settings.tiresWithClaudeUsage))
        menu.addItem(item(text(.reactToTyping), action: #selector(toggleTyping), checked: settings.typingReactionsEnabled))
        menu.addItem(item(text(.pointerPranks), action: #selector(toggleCursorPranks), checked: settings.cursorPranksEnabled))
        menu.addItem(item(text(.breakReminders), action: #selector(toggleWorkRhythm), checked: settings.workRhythmEnabled))
        menu.addItem(.separator())

        menu.addItem(submenu(text(.petSize), items: PetSettings.scales.map { scale in
            item(String(format: "%.1fx", scale), action: #selector(selectScale(_:)), value: scale, checked: scale == settings.scale)
        }))
        menu.addItem(submenu(text(.opacity), items: PetSettings.opacities.map { alpha in
            item("\(Int(alpha * 100))%", action: #selector(selectOpacity(_:)), value: alpha, checked: alpha == settings.opacity)
        }))
        menu.addItem(.separator())
        menu.addItem(item(text(.scheduleBubbles), action: #selector(toggleSchedules), checked: settings.schedulesEnabled))
        menu.addItem(item(text(.hideScheduleTitles), action: #selector(toggleScheduleTitles), checked: settings.hidesScheduleTitles))
        if settings.schedulesEnabled && (calendar.eventAccess == .denied || calendar.reminderAccess == .denied) {
            menu.addItem(item(text(.allowCalendarAccess), action: #selector(openCalendarPrivacy)))
        }
        menu.addItem(.separator())
        menu.addItem(item(text(.openDebugLog), action: #selector(openLog), key: "l"))
        menu.addItem(.separator())
        menu.addItem(submenu(text(.language), items: MenuLanguage.allCases.map { option in
            item(option.displayName, action: #selector(selectLanguage(_:)), value: option.rawValue, checked: option == language)
        }))
        menu.addItem(.separator())
        menu.addItem(item(text(.quit), action: #selector(quit), key: "q"))

        statusItem.menu = menu
    }

    /// 사용량 요약을 메뉴 언어로
    private func usageText(in language: MenuLanguage) -> String {
        guard let usageSummary else { return MenuText.usageNone.text(in: language) }
        return usageSummary.isEmpty ? MenuText.usageReset.text(in: language) : usageSummary
    }

    private func item(_ title: String, action: Selector, key: String = "", value: Any? = nil, checked: Bool = false) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        menuItem.representedObject = value
        menuItem.state = checked ? .on : .off
        return menuItem
    }

    private func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu()
        items.forEach(menu.addItem)
        parent.submenu = menu
        return parent
    }

    // MARK: - Actions

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = MenuLanguage(rawValue: raw) else { return }
        settings.menuLanguage = language
        rebuildMenu()
    }

    @objc private func selectScale(_ sender: NSMenuItem) {
        guard let scale = sender.representedObject as? CGFloat else { return }
        settings.scale = scale
        habitat.roster.rescale(scale)
        rebuildMenu()
    }

    @objc private func selectOpacity(_ sender: NSMenuItem) {
        guard let alpha = sender.representedObject as? CGFloat else { return }
        settings.opacity = alpha
        habitat.opacity = alpha
        rebuildMenu()
    }

    @objc private func selectChase(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, key != settings.chaseMode else { return }
        settings.chaseMode = key
        habitat.roster.chase = ChaseModes.make(key)
        rebuildMenu()
    }

    @objc private func toggleSkillJumps() {
        settings.skillJumpsEnabled.toggle()
        habitat.roster.skills.isEnabled = settings.skillJumpsEnabled
        rebuildMenu()
    }

    @objc private func toggleTiring() {
        settings.tiresWithClaudeUsage.toggle()
        applyUsage(usageWatcher.latest)
        rebuildMenu()
    }

    @objc private func toggleFollowDisplay() {
        settings.followsActiveDisplay.toggle()
        habitat.roster.follow.isEnabled = settings.followsActiveDisplay
        rebuildMenu()
    }

    @objc private func toggleQuietDuringCalls() {
        settings.quietDuringCalls.toggle()
        habitat.quietDuringCalls = settings.quietDuringCalls
        rebuildMenu()
    }

    @objc private func toggleCursorPranks() {
        settings.cursorPranksEnabled.toggle()
        habitat.roster.pranks.isEnabled = settings.cursorPranksEnabled
        rebuildMenu()
    }

    @objc private func toggleTyping() {
        settings.typingReactionsEnabled.toggle()
        habitat.roster.typing.isEnabled = settings.typingReactionsEnabled
        rebuildMenu()
    }

    @objc private func toggleWorkRhythm() {
        settings.workRhythmEnabled.toggle()
        habitat.roster.rhythm.isEnabled = settings.workRhythmEnabled
        rebuildMenu()
    }

    @objc private func toggleSchedules() {
        settings.schedulesEnabled.toggle()
        if settings.schedulesEnabled {
            startSchedules()
        } else {
            scheduleWatcher.stop()
        }
        rebuildMenu()
    }

    @objc private func toggleScheduleTitles() {
        settings.hidesScheduleTitles.toggle()
        announcer.hidesTitles = settings.hidesScheduleTitles
        rebuildMenu()
    }

    /// 시스템 설정의 캘린더 개인정보 화면 열기 (허용은 사용자가 직접)
    @objc private func openCalendarPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(PetLogger.shared.fileURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
