import Foundation

/// This object is responsible for checking the shared menus every platform renders: the status menu's rows and
/// check marks, setting commands reaching the pets and the shell, pet lineup changes, and collection choices
/// that go through the platform's dialogs.
enum AppMenuChecks {
    static func run(_ check: Checker, skinsDirectory: URL) {
        check.section("메뉴 데이터 (공통)")
        let world = Sim.world()
        let roster = PetRoster()
        let settings = PetSettings(store: JSONFileSettingsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-menu-\(UUID().uuidString).json")))
        settings.menuLanguage = .english
        settings.petSkins = ["Nabi", "Bolt"]
        let library = SkinLibrary(directory: skinsDirectory, loader: DecodedFrame.load)
        let archive = MemoryTreasuryArchive()
        let store = TreasuryStore(archive: archive)
        let dialogs = ScriptedDialogs()
        let host = ScriptedMenuHost()
        let lineup = PetLineup(library: library, roster: roster, settings: settings) { world }
        let collection = CollectionMenu(treasury: store.load(), store: store, roster: roster, dialogs: dialogs) { .english }
        lineup.petMenuItems = { collection.menuNodes(for: $0) }
        lineup.petLabel = { collection.label(for: $0) }
        lineup.confirmRemoval = { collection.confirmRemoval(of: $0) }
        let menu = AppMenu(settings: settings, roster: roster, host: host,
                           lineup: { lineup.statusMenuNodes() }, collection: { collection.menuNode() }, handlers: [lineup, collection])
        var rebuilds = 0
        menu.onChange = { rebuilds += 1 }
        lineup.restore()
        collection.syncPets()
        menu.applySettingsToPets()

        // 메뉴바 메뉴 모양
        let nodes = menu.nodes()
        check.expect(nodes.first == .heading("🐾 DeskPet") && nodes.last?.title == MenuText.quit.text(in: .english), "머리줄로 시작해 끄기로 끝남",
                     "\(nodes.first?.title ?? "") … \(nodes.last?.title ?? "")")
        check.expect(nodes.find(MenuText.skillJumps.text(in: .english))?.checked == true
                     && nodes.find(MenuText.pointerPranks.text(in: .english))?.checked == false, "켜짐·꺼짐이 설정대로 체크됨")
        check.expect(nodes.find("1.5x")?.checked == true && nodes.find("100%")?.checked == true, "크기·투명도 현재 값 체크")
        check.expect(nodes.find(MenuText.allowCalendarAccess.text(in: .english)) == nil, "일정 권한을 거절하지 않았으면 권한 항목 없음")
        host.denied = true
        check.expect(menu.nodes().find(MenuText.allowCalendarAccess.text(in: .english)) != nil, "거절했으면 권한 허용 항목")
        if case .submenu(let pets, _)? = nodes.find(MenuText.pets.text(in: .english))?.kind {
            check.expect(pets.count == 2, "Pets 하위 메뉴에 펫마다 한 줄", "\(pets.count)")
        } else {
            check.expect(false, "Pets 하위 메뉴 있음")
        }

        // 설정 명령
        menu.perform(.toggle(.skillJumps))
        check.expect(!settings.skillJumpsEnabled && !roster.skills.isEnabled && rebuilds == 1, "도약 끄기: 저장·펫 적용·메뉴 다시 그림")
        menu.perform(.toggle(.quietDuringCalls))
        check.expect(!settings.quietDuringCalls && host.changes.last == .toggle(.quietDuringCalls), "통화 중 조용히: 껍데기에 알림")
        menu.perform(.scale(2.0))
        check.expect(settings.scale == 2.0 && roster.residents.allSatisfy { $0.scale == 2.0 }, "크기 바꾸면 펫도 바뀜")
        menu.perform(.chase(PointerChase.key))
        check.expect(settings.chaseMode == PointerChase.key && roster.chase is PointerChase, "쫓을 것 바꾸기")
        if case .submenu(let levels, _)? = menu.nodes().find(MenuText.throwAccuracy.text(in: .english))?.kind {
            check.expect(levels.count == 4 && levels.first(where: \.checked)?.title == MenuText.accuracy(.often, in: .english),
                         "던지기 정확도: 4단계, 기본 자주 명중 체크")
        } else {
            check.expect(false, "던지기 정확도 하위 메뉴 있음")
        }
        menu.perform(.throwAccuracy(.sometimes))
        check.expect(settings.throwAccuracy == .sometimes && roster.aim.accuracy == .sometimes, "정확도 바꾸면 저장·펫에 적용")
        menu.perform(.platform(.openLog))
        check.expect(host.actions == [.openLog], "로그 열기는 껍데기가 함")

        // 펫 구성
        menu.perform(.addVariety)
        check.expect(roster.residents.count == 3 && settings.petSkins.count == 3 && settings.petIDs.count == 3,
                     "Add Another Pet: 한 마리 더, 저장", "\(settings.petSkins)")
        check.expect(Set(settings.petSkins).count == min(3, library.names.count), "아직 없는 캐릭터를 우선")
        let first = roster.residents[0]
        menu.perform(.restylePet(petID: first.id, skin: "Bolt"))
        check.expect(first.appearance.name == "Bolt" && settings.petSkins.first == "Bolt", "펫 하나 캐릭터 바꾸기")
        menu.perform(.removeLast)
        check.expect(roster.residents.count == 2, "Remove Pet: 마지막 펫 빼기 (Lv.1이면 묻지 않음)")
        check.expect(dialogs.confirms == 0, "Lv.1 펫은 확인 창 없음")

        // 도감: 도토리 5개 → 도토리 모자를 주운 펫이 씀
        guard let acorn = ItemCatalog.item("acorn"), let keeper = first.keeperID else {
            check.expect(false, "도토리·펫 ID 있음")
            return
        }
        for _ in 0..<5 { collection.collect(acorn, by: first.id) }
        check.expect(first.hat != nil && archive.saves > 0, "모자를 얻으면 바로 쓰고 저장", "\(String(describing: first.hat))")
        check.expect(collection.menuNode().title.contains("(5)"), "도감 메뉴에 모은 수")
        menu.perform(.chooseHat(keeperID: keeper, hatID: nil))
        check.expect(first.hat == nil, "모자 벗기기")
        let hatMenu = lineup.petMenu(for: first).find(MenuText.hat.text(in: .english))
        check.expect(hatMenu != nil, "펫 메뉴에 모자 고르기")

        dialogs.answer = false
        menu.perform(.resetCollection)
        check.expect(collection.total == 5 && dialogs.confirms == 1, "초기화는 확인 창에서 취소하면 그대로")
        dialogs.answer = true
        menu.perform(.resetCollection)
        check.expect(collection.total == 0, "확인하면 초기화")

        // Lv.6까지 키우면 이름 짓기, 빼기 전 확인
        let grown = store.load()
        var day = 0
        while grown.level(of: keeper) < Treasury.nameLevel && day < 5000 {
            grown.award(.together, to: keeper, on: "d\(day)")
            day += 1
        }
        let grownMenu = CollectionMenu(treasury: grown, store: store, roster: roster, dialogs: dialogs) { .english }
        dialogs.typed = "  Mochi  "
        _ = grownMenu.perform(.rename(keeperID: keeper))
        check.expect(first.nickname == "Mochi", "이름 짓기 (앞뒤 공백 뺌)", "\(String(describing: first.nickname))")
        dialogs.answer = false
        check.expect(!grownMenu.confirmRemoval(of: first), "Lv.2 이상 펫을 빼기 전에 묻고, 취소하면 남김")
    }
}

/// This object is responsible for answering menu dialogs in checks.
final class ScriptedDialogs: MenuDialogs {
    var answer = true
    var typed: String?
    private(set) var confirms = 0

    func confirm(title: String, message: String, confirm: String, cancel: String) -> Bool {
        confirms += 1
        return answer
    }

    func askText(title: String, message: String, initial: String, save: String, cancel: String) -> String? { typed }
}

/// This object is responsible for standing in for the shell behind the status menu in checks.
final class ScriptedMenuHost: AppMenuHost {
    var usageSummary: String?
    var denied = false
    private(set) var changes: [MenuCommand] = []
    private(set) var actions: [PlatformAction] = []

    var calendarAccessDenied: Bool { denied }

    func settingChanged(_ command: MenuCommand) { changes.append(command) }

    func run(_ action: PlatformAction) { actions.append(action) }
}

/// This object is responsible for keeping collection bytes in memory for checks.
final class MemoryTreasuryArchive: TreasuryArchive {
    private(set) var data: Data?
    private(set) var saves = 0
    private(set) var setAsideData: Data?

    func loadData() -> Data? { data }

    func save(_ data: Data) {
        self.data = data
        saves += 1
    }

    func setAside(_ data: Data) {
        setAsideData = data
        self.data = nil
    }
}
