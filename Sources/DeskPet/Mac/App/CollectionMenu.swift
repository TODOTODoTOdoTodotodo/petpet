import AppKit

/// This object is responsible for keeping the collection on this Mac (UserDefaults `treasury.v1`):
/// loading it at launch, moving an unreadable copy aside instead of deleting it, and saving after each change.
final class TreasuryStore {
    private let defaults: UserDefaults
    static let key = "treasury.v1"
    static let brokenKey = "treasury.broken"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Treasury {
        let data = defaults.data(forKey: Self.key)
        let (treasury, broken) = Treasury.restore(from: data)
        if broken, let data {
            defaults.set(data, forKey: Self.brokenKey)
            defaults.removeObject(forKey: Self.key)
            PetLogger.shared.log("⚠️ collection data unreadable, moved to \(Self.brokenKey), starting empty")
        }
        return treasury
    }

    func save(_ treasury: Treasury) {
        defaults.set(treasury.encoded(), forKey: Self.key)
    }
}

/// This object is responsible for the collection as the user sees it: the Collection submenu (items with icons
/// and counts, hats with their progress, reset after confirming), each pet's menu entries (its level, Hat, Hold from Lv.4,
/// Name from Lv.6, confirming removal from Lv.2), putting found items and newly unlocked hats into the collection
/// (a pet without a hat puts the new one on with 🎩), and keeping pets in step with the saved record.
final class CollectionMenu: NSObject, NSMenuDelegate {
    private let treasury: Treasury
    private let store: TreasuryStore
    private let roster: PetRoster
    private let language: () -> MenuLanguage
    /// 도감·펫 기록이 바뀌어 메뉴를 다시 그려야 할 때
    var onChange: (() -> Void)?

    static let hatText = "🎩"

    init(treasury: Treasury, store: TreasuryStore, roster: PetRoster, language: @escaping () -> MenuLanguage) {
        self.treasury = treasury
        self.store = store
        self.roster = roster
        self.language = language
    }

    var total: Int { treasury.total }

    // MARK: - Collection menu

    /// 친밀도가 바뀌면 저장 (레벨이 오르면 메뉴도 다시 그림)
    func heartsChanged(levelUp: Bool) {
        store.save(treasury)
        if levelUp { onChange?() }
    }

    func menuItem() -> NSMenuItem {
        let language = language()
        let unlocked = HatCatalog.all.filter(treasury.isUnlocked)
        let fresh = !treasury.newHats.isEmpty ? " \(MenuText.newMark.text(in: language))" : ""
        let parent = NSMenuItem(title: "\(MenuText.collection.text(in: language)) (\(treasury.total))\(fresh)", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.delegate = self
        let header = NSMenuItem(title: MenuText.found(treasury.total, hats: unlocked.count, of: HatCatalog.all.count, in: language),
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        for kind in ItemCatalog.all {
            let known = treasury.hasFound(kind)
            var title = known ? "\(kind.name(in: language))  ×\(treasury.count(of: kind))" : MenuText.unknownItem.text(in: language)
            // 계절 물건은 나오는 기간을 함께 (못 찾았어도 언제 찾을 수 있는지 알 수 있게)
            if let season = ItemCatalog.seasonLabel(of: kind, in: language) { title += " · \(season)" }
            let row = viewOnly(title)
            row.image = DotArt.icon(named: kind.id, rows: kind.rows, palette: kind.palette, silhouette: !known)
            if known, let day = treasury.firstFound[kind.id] {
                row.toolTip = language == .korean ? "처음 찾은 날 \(day)" : "First found \(day)"
            }
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let hatsTitle = NSMenuItem(title: MenuText.hats.text(in: language), action: nil, keyEquivalent: "")
        hatsTitle.isEnabled = false
        menu.addItem(hatsTitle)
        for hat in HatCatalog.all {
            let row = viewOnly(hatLine(hat, in: language))
            row.image = DotArt.icon(named: "hat." + hat.id, rows: hat.rows, palette: hat.palette, silhouette: !treasury.isUnlocked(hat))
            menu.addItem(row)
        }
        menu.addItem(.separator())
        let reset = NSMenuItem(title: MenuText.resetCollection.text(in: language), action: #selector(confirmReset), keyEquivalent: "")
        reset.target = self
        reset.isEnabled = treasury.total > 0
        menu.addItem(reset)
        parent.submenu = menu
        return parent
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

    /// 보기만 하는 줄 (흐리게 보이지 않게 아무 일 없는 동작을 둠)
    private func viewOnly(_ title: String) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: #selector(noop), keyEquivalent: "")
        row.target = self
        return row
    }

    /// 도감을 열어 봤으면 새 모자 표시를 지움 (지금 열린 메뉴에는 그대로 보임)
    func menuWillOpen(_ menu: NSMenu) {
        guard !treasury.newHats.isEmpty else { return }
        treasury.markHatsSeen()
        store.save(treasury)
    }

    // MARK: - Hat menu (pet right-click)

    // MARK: - Pet menu

    /// 펫 메뉴 머리줄: 이름 · 캐릭터 · ❤️ 레벨 (진행)
    func label(for pet: Pet) -> String {
        guard pet.role == .resident else { return "\(pet.id) · \(pet.appearance.name)" }
        let id = pet.keeperID
        return MenuText.petLabel(name: treasury.name(of: id) ?? pet.id, look: pet.appearance.name, level: treasury.level(of: id),
                                 hearts: treasury.hearts(of: id), next: treasury.nextThreshold(of: id))
    }

    /// 펫 메뉴에 넣을 모자·손 소품(Lv.4)·이름 짓기(Lv.6) 항목
    func menuItems(for pet: Pet) -> [NSMenuItem] {
        [hatMenuItem(for: pet), holdMenuItem(for: pet), renameItem(for: pet)].compactMap { $0 }
    }

    /// 펫을 빼도 되는지. Lv.2 이상이면 확인 창 (친밀도·모자·이름이 사라짐)
    func confirmRemoval(of pet: Pet) -> Bool {
        let level = treasury.level(of: pet.keeperID)
        guard pet.role == .resident, level >= 2 else { return true }
        let language = language()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = MenuText.removeTitle(level: level, in: language)
        alert.informativeText = MenuText.removeMessage.text(in: language)
        alert.addButton(withTitle: MenuText.removeConfirm.text(in: language))
        alert.addButton(withTitle: MenuText.cancel.text(in: language))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func holdMenuItem(for pet: Pet) -> NSMenuItem? {
        guard pet.role == .resident, let keeperID = pet.keeperID, treasury.level(of: keeperID) >= Treasury.holdLevel else { return nil }
        let language = language()
        let parent = NSMenuItem(title: MenuText.hold.text(in: language), action: nil, keyEquivalent: "")
        let menu = NSMenu()
        let none = NSMenuItem(title: MenuText.holdNone.text(in: language), action: #selector(chooseHeld(_:)), keyEquivalent: "")
        none.target = self
        none.representedObject = [keeperID, ""]
        none.state = pet.heldItem == nil ? .on : .off
        menu.addItem(none)
        for kind in ItemCatalog.all where treasury.hasFound(kind) {
            let row = NSMenuItem(title: kind.name(in: language), action: #selector(chooseHeld(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = [keeperID, kind.id]
            row.state = pet.heldItem == kind ? .on : .off
            row.image = DotArt.icon(named: kind.id, rows: kind.rows, palette: kind.palette)
            menu.addItem(row)
        }
        parent.submenu = menu
        return parent
    }

    private func renameItem(for pet: Pet) -> NSMenuItem? {
        guard pet.role == .resident, let keeperID = pet.keeperID, treasury.level(of: keeperID) >= Treasury.nameLevel else { return nil }
        let item = NSMenuItem(title: MenuText.rename.text(in: language()), action: #selector(rename(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = keeperID
        return item
    }

    @objc private func chooseHeld(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let pet = roster.residents.first(where: { $0.keeperID == pair[0] }) else { return }
        let item = ItemCatalog.item(pair[1])
        guard treasury.hold(item, for: pair[0]) else { return }
        pet.heldItem = item
        store.save(treasury)
        PetLogger.shared.log("✋ [\(pet.id)] holds \(item?.id ?? "nothing")")
        onChange?()
    }

    @objc private func rename(_ sender: NSMenuItem) {
        guard let keeperID = sender.representedObject as? String,
              let pet = roster.residents.first(where: { $0.keeperID == keeperID }) else { return }
        let language = language()
        let alert = NSAlert()
        alert.messageText = MenuText.renameTitle.text(in: language)
        alert.informativeText = MenuText.renameMessage.text(in: language)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = treasury.name(of: keeperID) ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: MenuText.save.text(in: language))
        alert.addButton(withTitle: MenuText.cancel.text(in: language))
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // 12자를 넘으면 앞 12자만
        let name = String(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Treasury.maxNameLength))
        guard treasury.rename(keeperID, to: name) else { return }
        pet.nickname = treasury.name(of: keeperID)
        store.save(treasury)
        PetLogger.shared.log("🏷️ [\(pet.id)] named (\(name.count) chars)")
        onChange?()
    }

    /// 펫 하나의 모자 고르기 메뉴. 기본 펫만
    private func hatMenuItem(for pet: Pet) -> NSMenuItem? {
        guard pet.role == .resident, let keeperID = pet.keeperID else { return nil }
        let language = language()
        let parent = NSMenuItem(title: MenuText.hat.text(in: language), action: nil, keyEquivalent: "")
        let menu = NSMenu()
        let none = NSMenuItem(title: MenuText.hatNone.text(in: language), action: #selector(chooseHat(_:)), keyEquivalent: "")
        none.target = self
        none.representedObject = [keeperID, ""]
        none.state = pet.hat == nil ? .on : .off
        menu.addItem(none)
        for hat in HatCatalog.all where treasury.isUnlocked(hat) {
            let row = NSMenuItem(title: hatLine(hat, in: language), action: #selector(chooseHat(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = [keeperID, hat.id]
            row.state = pet.hat == hat ? .on : .off
            row.image = DotArt.icon(named: "hat." + hat.id, rows: hat.rows, palette: hat.palette)
            menu.addItem(row)
        }
        parent.submenu = menu
        return parent
    }

    @objc private func chooseHat(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let pet = roster.residents.first(where: { $0.keeperID == pair[0] }) else { return }
        let hat = HatCatalog.hat(pair[1])
        guard treasury.wear(hat, on: pair[0]) else { return }
        pet.hat = hat
        store.save(treasury)
        PetLogger.shared.log("🎩 [\(pet.id)] wears \(hat?.id ?? "nothing")")
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
            PetLogger.shared.log("🎩 unlocked \(result.unlocked.map(\.id).joined(separator: ", "))" + (result.worn.map { " (\(petID) wears \($0.id))" } ?? ""))
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

    @objc private func noop() {}

    @objc private func confirmReset() {
        let language = language()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = MenuText.resetTitle.text(in: language)
        alert.informativeText = MenuText.resetMessage.text(in: language)
        alert.addButton(withTitle: MenuText.resetConfirm.text(in: language))
        alert.addButton(withTitle: MenuText.cancel.text(in: language))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        treasury.reset()
        store.save(treasury)
        roster.residents.forEach { $0.hat = nil }
        roster.affection.sync(roster.residents)
        PetLogger.shared.log("🧹 collection reset by user")
        onChange?()
    }
}
