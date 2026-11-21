import Foundation

/// This object is responsible for the parts of the status menu only the platform shell knows or does:
/// the Claude usage summary, whether calendar access was refused, applying settings that live in the shell
/// (opacity, call detection, schedules, usage), and platform actions (open log, quit, privacy settings).
protocol AppMenuHost: AnyObject {
    /// nil이면 사용량 정보 없음, ""이면 모두 초기화됨
    var usageSummary: String? { get }
    /// 일정 권한을 거절당했는지 (권한 허용 항목을 보일지)
    var calendarAccessDenied: Bool { get }
    /// 껍데기 쪽에 적용할 설정이 바뀜 (값은 settings에서 읽음)
    func settingChanged(_ command: MenuCommand)
    func run(_ action: PlatformAction)
}

/// This object is responsible for the status menu (macOS menu bar 👾, Windows tray) as data: pets, collection,
/// toggles, size, opacity, schedules, log, language and quit, in one fixed order, and for carrying out a chosen
/// command — saving the setting, applying it to the pets, passing pet and collection choices to their owners,
/// and telling the shell what only it can apply.
final class AppMenu {
    private let settings: PetSettings
    private let roster: PetRoster
    private let lineup: () -> [MenuNode]
    private let collection: () -> MenuNode
    private let handlers: [MenuCommandHandler]
    private weak var host: AppMenuHost?
    /// 메뉴를 다시 그려야 할 때
    var onChange: (() -> Void)?

    /// lineup·collection: 메뉴에 넣을 펫 구성·도감 항목. handlers: 그 명령을 처리하는 쪽
    init(settings: PetSettings, roster: PetRoster, host: AppMenuHost,
         lineup: @escaping () -> [MenuNode], collection: @escaping () -> MenuNode, handlers: [MenuCommandHandler]) {
        self.settings = settings
        self.roster = roster
        self.host = host
        self.lineup = lineup
        self.collection = collection
        self.handlers = handlers
    }

    /// 설정을 펫들에게 적용 (시작할 때 한 번)
    func applySettingsToPets() {
        roster.skills.isEnabled = settings.skillJumpsEnabled
        roster.chase = ChaseModes.make(settings.chaseMode)
        roster.follow.isEnabled = settings.followsActiveDisplay
        roster.rhythm.isEnabled = settings.workRhythmEnabled
        roster.typing.isEnabled = settings.typingReactionsEnabled
        roster.pranks.isEnabled = settings.cursorPranksEnabled
        roster.aim.accuracy = settings.throwAccuracy
    }

    func nodes() -> [MenuNode] {
        let language = settings.menuLanguage
        func text(_ key: MenuText) -> String { key.text(in: language) }
        var nodes: [MenuNode] = [.heading("🐾 DeskPet"), .separator]
        nodes += lineup()
        nodes += [collection(), .heading(text(.rightClickHint)), .separator]
        nodes.append(.submenu(text(.chase), [
            .command(text(.chaseActiveWindow), .chase(ActiveWindowChase.key), checked: settings.chaseMode == ActiveWindowChase.key),
            .command(text(.chasePointer), .chase(PointerChase.key), checked: settings.chaseMode == PointerChase.key),
        ]))
        nodes += [
            .command(text(.skillJumps), .toggle(.skillJumps), checked: settings.skillJumpsEnabled),
            .command(text(.followDisplay), .toggle(.followDisplay), checked: settings.followsActiveDisplay),
            .command(text(.quietDuringCalls), .toggle(.quietDuringCalls), checked: settings.quietDuringCalls),
            .command(MenuText.tireWithUsage(usageText(in: language), in: language), .toggle(.tiresWithUsage),
                     checked: settings.tiresWithClaudeUsage),
            .command(text(.reactToTyping), .toggle(.typing), checked: settings.typingReactionsEnabled),
            .command(text(.pointerPranks), .toggle(.pointerPranks), checked: settings.cursorPranksEnabled),
            .submenu(text(.throwAccuracy), ThrowAccuracy.allCases.map { level in
                .command(MenuText.accuracy(level, in: language), .throwAccuracy(level), checked: level == settings.throwAccuracy)
            }),
            .command(text(.breakReminders), .toggle(.workRhythm), checked: settings.workRhythmEnabled),
            .separator,
            .submenu(text(.petSize), PetSettings.scales.map { scale in
                .command(String(format: "%.1fx", Double(scale)), .scale(scale), checked: scale == settings.scale)
            }),
            .submenu(text(.opacity), PetSettings.opacities.map { alpha in
                .command("\(Int(alpha * 100))%", .opacity(alpha), checked: alpha == settings.opacity)
            }),
            .separator,
            .command(text(.scheduleBubbles), .toggle(.schedules), checked: settings.schedulesEnabled),
            .command(text(.hideScheduleTitles), .toggle(.scheduleTitles), checked: settings.hidesScheduleTitles),
        ]
        if settings.schedulesEnabled && host?.calendarAccessDenied == true {
            nodes.append(.command(text(.allowCalendarAccess), .platform(.allowCalendarAccess)))
        }
        nodes += [
            .separator,
            .command(text(.openDebugLog), .platform(.openLog), key: "l"),
            .separator,
            .submenu(text(.language), MenuLanguage.allCases.map { option in
                .command(option.displayName, .language(option), checked: option == language)
            }),
            .separator,
            .command(text(.quit), .platform(.quit), key: "q"),
        ]
        return nodes
    }

    /// 사용량 요약을 메뉴 언어로
    private func usageText(in language: MenuLanguage) -> String {
        guard let summary = host?.usageSummary else { return MenuText.usageNone.text(in: language) }
        return summary.isEmpty ? MenuText.usageReset.text(in: language) : summary
    }

    // MARK: - Commands

    /// 메뉴(메뉴바·펫 우클릭)에서 고른 일
    func perform(_ command: MenuCommand) {
        if handlers.contains(where: { $0.perform(command) }) { return }
        switch command {
        case .chase(let key):
            guard key != settings.chaseMode else { return }
            settings.chaseMode = key
            roster.chase = ChaseModes.make(key)
        case .scale(let scale):
            settings.scale = scale
            roster.rescale(scale)
        case .opacity(let alpha):
            settings.opacity = alpha
            host?.settingChanged(command)
        case .throwAccuracy(let level):
            settings.throwAccuracy = level
            roster.aim.accuracy = level
        case .language(let language):
            settings.menuLanguage = language
        case .toggle(let toggle):
            flip(toggle)
            host?.settingChanged(command)
        case .platform(let action):
            host?.run(action)
            return
        default:
            return
        }
        onChange?()
    }

    private func flip(_ toggle: MenuToggle) {
        switch toggle {
        case .skillJumps:
            settings.skillJumpsEnabled.toggle()
            roster.skills.isEnabled = settings.skillJumpsEnabled
        case .followDisplay:
            settings.followsActiveDisplay.toggle()
            roster.follow.isEnabled = settings.followsActiveDisplay
        case .typing:
            settings.typingReactionsEnabled.toggle()
            roster.typing.isEnabled = settings.typingReactionsEnabled
        case .pointerPranks:
            settings.cursorPranksEnabled.toggle()
            roster.pranks.isEnabled = settings.cursorPranksEnabled
        case .workRhythm:
            settings.workRhythmEnabled.toggle()
            roster.rhythm.isEnabled = settings.workRhythmEnabled
        case .quietDuringCalls:
            settings.quietDuringCalls.toggle()
        case .tiresWithUsage:
            settings.tiresWithClaudeUsage.toggle()
        case .schedules:
            settings.schedulesEnabled.toggle()
        case .scheduleTitles:
            settings.hidesScheduleTitles.toggle()
        }
    }
}
