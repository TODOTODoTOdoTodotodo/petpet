import Foundation

/// This object is responsible for holding the saved collection bytes on one platform
/// (macOS `UserDefaults` `treasury.v1`, Windows a file next to the settings), and keeping an unreadable copy aside.
protocol TreasuryArchive: AnyObject {
    func loadData() -> Data?
    func save(_ data: Data)
    /// 읽을 수 없는 기록을 지우지 않고 옆에 옮겨 둠
    func setAside(_ data: Data)
}

/// This object is responsible for keeping the collection between launches: loading it, moving an unreadable
/// copy aside instead of deleting it (and starting empty), and saving after each change.
final class TreasuryStore {
    private let archive: TreasuryArchive
    /// 읽지 못한 기록을 옮겼을 때
    var onEvent: ((String) -> Void)?

    init(archive: TreasuryArchive) {
        self.archive = archive
    }

    func load() -> Treasury {
        let data = archive.loadData()
        let (treasury, broken) = Treasury.restore(from: data)
        if broken, let data {
            archive.setAside(data)
            onEvent?("⚠️ collection data unreadable, moved aside, starting empty")
        }
        return treasury
    }

    func save(_ treasury: Treasury) {
        archive.save(treasury.encoded())
    }
}

/// This object is responsible for the collection as the user sees it: the Collection submenu (items with icons
/// and counts, hats with their progress, reset after confirming), each pet's menu entries (its level, Hat, Hold from Lv.4,
/// Name from Lv.6, confirming removal from Lv.2), putting found items and newly unlocked hats into the collection
/// (a pet without a hat puts the new one on with 🎩), and keeping pets in step with the saved record.
/// Menus are data (`MenuNode`); dialogs go through the platform's `MenuDialogs`.
final class CollectionMenu: MenuCommandHandler {
    private let treasury: Treasury
    private let store: TreasuryStore
    private let roster: PetRoster
    private let dialogs: MenuDialogs
    private let language: () -> MenuLanguage
    /// 도감·펫 기록이 바뀌어 메뉴를 다시 그려야 할 때
    var onChange: (() -> Void)?
    /// 기록 남기기
    var onEvent: ((String) -> Void)?

    static let hatText = "🎩"

    init(treasury: Treasury, store: TreasuryStore, roster: PetRoster, dialogs: MenuDialogs, language: @escaping () -> MenuLanguage) {
        self.treasury = treasury
        self.store = store
        self.roster = roster
        self.dialogs = dialogs
        self.language = language
    }

    var total: Int { treasury.total }

    // MARK: - Collection menu

    /// 친밀도가 바뀌면 저장 (레벨이 오르면 메뉴도 다시 그림)
    func heartsChanged(levelUp: Bool) {
        store.save(treasury)
        if levelUp { onChange?() }
    }

    func menuNode() -> MenuNode {
        let language = language()
        let unlocked = HatCatalog.all.filter(treasury.isUnlocked)
        let fresh = !treasury.newHats.isEmpty ? " \(MenuText.newMark.text(in: language))" : ""
        var nodes: [MenuNode] = [
            .heading(MenuText.found(treasury.total, hats: unlocked.count, of: HatCatalog.all.count, in: language)),
            .separator,
        ]
        for kind in ItemCatalog.all {
            let known = treasury.hasFound(kind)
            var title = known ? "\(kind.name(in: language))  ×\(treasury.count(of: kind))" : MenuText.unknownItem.text(in: language)
            // 계절 물건은 나오는 기간을 함께 (못 찾았어도 언제 찾을 수 있는지 알 수 있게)
            if let season = ItemCatalog.seasonLabel(of: kind, in: language) { title += " · \(season)" }
            let day = known ? treasury.firstFound[kind.id] : nil
            nodes.append(.info(title, icon: Self.icon(of: kind, silhouette: !known),
                               toolTip: day.map { language == .korean ? "처음 찾은 날 \($0)" : "First found \($0)" }))
        }
        nodes += [.separator, .heading(MenuText.hats.text(in: language))]
        for hat in HatCatalog.all {
            nodes.append(.info(hatLine(hat, in: language), icon: Self.icon(of: hat, silhouette: !treasury.isUnlocked(hat))))
        }
        nodes += [.separator, .command(MenuText.resetCollection.text(in: language), .resetCollection, enabled: treasury.total > 0)]
        return .submenu("\(MenuText.collection.text(in: language)) (\(treasury.total))\(fresh)", nodes, onOpen: .collectionOpened)
    }

    static func icon(of kind: ItemKind, silhouette: Bool = false) -> MenuIcon {
        MenuIcon(name: kind.id, rows: kind.rows, palette: kind.palette, silhouette: silhouette)
    }

    static func icon(of hat: HatKind, silhouette: Bool = false) -> MenuIcon {
        MenuIcon(name: "hat." + hat.id, rows: hat.rows, palette: hat.palette, silhouette: silhouette)
    }

    /// 얻은 모자는 이름(새 모자면 표시), 못 얻은 모자는 조건과 모은 수
    private func hatLine(_ hat: HatKind, in language: MenuLanguage) -> String {
        if treasury.isUnlocked(hat) {
            return hat.name(in: language) + (treasury.newHats.contains(hat.id) ? " \(MenuText.newMark.text(in: language))" : "")
        }
        let goal: String
        switch hat.condition {
        case .total: goal = language == .korean ? "물건" : "Items"
        case .item(let id, _): goal = ItemCatalog.item(id)?.name(in: language) ?? id
        }
        return "\(hat.name(in: language)) — \(goal) \(treasury.progress(toward: hat))/\(hat.condition.need)"
    }

    // MARK: - Pet menu

    /// 펫 메뉴 머리줄: 이름 · 캐릭터 · ❤️ 레벨 (진행)
    func label(for pet: Pet) -> String {
        guard pet.role == .resident else { return "\(pet.id) · \(pet.appearance.name)" }
        let id = pet.keeperID
        return MenuText.petLabel(name: treasury.name(of: id) ?? pet.id, look: pet.appearance.name, level: treasury.level(of: id),
                                 hearts: treasury.hearts(of: id), next: treasury.nextThreshold(of: id))
    }

    /// 펫 메뉴에 넣을 모자·손 소품(Lv.4)·이름 짓기(Lv.6) 항목
    func menuNodes(for pet: Pet) -> [MenuNode] {
        [hatMenu(for: pet), holdMenu(for: pet), renameNode(for: pet)].compactMap { $0 }
    }

    /// 펫을 빼도 되는지. Lv.2 이상이면 확인 창 (친밀도·모자·이름이 사라짐)
    func confirmRemoval(of pet: Pet) -> Bool {
        let level = treasury.level(of: pet.keeperID)
        guard pet.role == .resident, level >= 2 else { return true }
        let language = language()
        return dialogs.confirm(title: MenuText.removeTitle(level: level, in: language),
                               message: MenuText.removeMessage.text(in: language),
                               confirm: MenuText.removeConfirm.text(in: language),
                               cancel: MenuText.cancel.text(in: language))
    }

    /// 펫 하나의 모자 고르기 메뉴. 기본 펫만
    private func hatMenu(for pet: Pet) -> MenuNode? {
        guard pet.role == .resident, let keeperID = pet.keeperID else { return nil }
        let language = language()
        var nodes: [MenuNode] = [.command(MenuText.hatNone.text(in: language), .chooseHat(keeperID: keeperID, hatID: nil), checked: pet.hat == nil)]
        for hat in HatCatalog.all where treasury.isUnlocked(hat) {
            nodes.append(.command(hatLine(hat, in: language), .chooseHat(keeperID: keeperID, hatID: hat.id),
                                  checked: pet.hat == hat, icon: Self.icon(of: hat)))
        }
        return .submenu(MenuText.hat.text(in: language), nodes)
    }

    private func holdMenu(for pet: Pet) -> MenuNode? {
        guard pet.role == .resident, let keeperID = pet.keeperID, treasury.level(of: keeperID) >= Treasury.holdLevel else { return nil }
        let language = language()
        var nodes: [MenuNode] = [.command(MenuText.holdNone.text(in: language), .chooseHeld(keeperID: keeperID, itemID: nil),
                                          checked: pet.heldItem == nil)]
        for kind in ItemCatalog.all where treasury.hasFound(kind) {
            nodes.append(.command(kind.name(in: language), .chooseHeld(keeperID: keeperID, itemID: kind.id),
                                  checked: pet.heldItem == kind, icon: Self.icon(of: kind)))
        }
        return .submenu(MenuText.hold.text(in: language), nodes)
    }

    private func renameNode(for pet: Pet) -> MenuNode? {
        guard pet.role == .resident, let keeperID = pet.keeperID, treasury.level(of: keeperID) >= Treasury.nameLevel else { return nil }
        return .command(MenuText.rename.text(in: language()), .rename(keeperID: keeperID))
    }

    // MARK: - Commands

    func perform(_ command: MenuCommand) -> Bool {
        switch command {
        case .chooseHat(let keeperID, let hatID):
            chooseHat(hatID.flatMap(HatCatalog.hat), for: keeperID)
        case .chooseHeld(let keeperID, let itemID):
            chooseHeld(itemID.flatMap(ItemCatalog.item), for: keeperID)
        case .rename(let keeperID):
            rename(keeperID)
        case .resetCollection:
            confirmReset()
        case .collectionOpened:
            // 도감을 열어 봤으면 새 모자 표시를 지움 (지금 열린 메뉴에는 그대로 보임)
            guard !treasury.newHats.isEmpty else { return true }
            treasury.markHatsSeen()
            store.save(treasury)
        default:
            return false
        }
        return true
    }

    private func resident(keeperID: String) -> Pet? {
        roster.residents.first { $0.keeperID == keeperID }
    }

    private func chooseHat(_ hat: HatKind?, for keeperID: String) {
        guard let pet = resident(keeperID: keeperID), treasury.wear(hat, on: keeperID) else { return }
        pet.hat = hat
        store.save(treasury)
        onEvent?("🎩 [\(pet.id)] wears \(hat?.id ?? "nothing")")
        onChange?()
    }

    private func chooseHeld(_ item: ItemKind?, for keeperID: String) {
        guard let pet = resident(keeperID: keeperID), treasury.hold(item, for: keeperID) else { return }
        pet.heldItem = item
        store.save(treasury)
        onEvent?("✋ [\(pet.id)] holds \(item?.id ?? "nothing")")
        onChange?()
    }

    private func rename(_ keeperID: String) {
        guard let pet = resident(keeperID: keeperID) else { return }
        let language = language()
        guard let typed = dialogs.askText(title: MenuText.renameTitle.text(in: language),
                                          message: MenuText.renameMessage.text(in: language),
                                          initial: treasury.name(of: keeperID) ?? "",
                                          save: MenuText.save.text(in: language),
                                          cancel: MenuText.cancel.text(in: language)) else { return }
        // 12자를 넘으면 앞 12자만
        let name = String(typed.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Treasury.maxNameLength))
        guard treasury.rename(keeperID, to: name) else { return }
        pet.nickname = treasury.name(of: keeperID)
        store.save(treasury)
        onEvent?("🏷️ [\(pet.id)] named (\(name.count) chars)")
        onChange?()
    }

    private func confirmReset() {
        let language = language()
        guard dialogs.confirm(title: MenuText.resetTitle.text(in: language),
                              message: MenuText.resetMessage.text(in: language),
                              confirm: MenuText.resetConfirm.text(in: language),
                              cancel: MenuText.cancel.text(in: language)) else { return }
        treasury.reset()
        store.save(treasury)
        roster.residents.forEach { $0.hat = nil }
        roster.affection.sync(roster.residents)
        onEvent?("🧹 collection reset by user")
        onChange?()
    }

    // MARK: - Collecting

    /// 주운 물건을 넣고 저장. 새 모자를 얻으면 주운 펫이 🎩 (모자가 없으면 바로 씀)
    func collect(_ kind: ItemKind, by petID: String) {
        let pet = roster.pet(withID: petID)
        let result = treasury.collect(kind, on: Treasury.day(of: Date()), by: pet?.keeperID)
        if let worn = result.worn { pet?.hat = worn }
        if !result.unlocked.isEmpty {
            pet?.say(Self.hatText, for: 1.8)
            onEvent?("🎩 unlocked \(result.unlocked.map(\.id).joined(separator: ", "))" + (result.worn.map { " (\(petID) wears \($0.id))" } ?? ""))
        }
        store.save(treasury)
        onChange?()
    }

    /// 지금 펫들에게 저장된 모자·레벨·이름·소품을 반영하고, 빠진 펫의 기록은 지움
    func syncPets() {
        let residents = roster.residents
        for pet in residents { pet.hat = treasury.hat(of: pet.keeperID) }
        roster.affection.sync(residents)
        let before = treasury.encoded()
        treasury.keepPets(residents.compactMap(\.keeperID))
        if treasury.encoded() != before { store.save(treasury) }
    }
}
