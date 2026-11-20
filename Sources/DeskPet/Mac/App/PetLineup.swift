import AppKit

/// This object is responsible for which character each pet wears: restoring the saved lineup at launch,
/// adding, removing and restyling individual pets, remembering the result, and offering those choices
/// as menus (the status menu's pet submenus and a pet's own right-click menu).
final class PetLineup: NSObject {
    private let library: MacSkinLibrary
    private let roster: PetRoster
    private let settings: PetSettings
    private let world: () -> World
    private var messengerCursor = 0
    /// 구성이 바뀌어 메뉴를 다시 그려야 할 때
    var onChange: (() -> Void)?
    /// 펫 메뉴에 넣을 모자·손 소품·이름 항목 (도감 쪽이 만듦)
    var petMenuItems: ((Pet) -> [NSMenuItem])?
    /// 펫 메뉴 머리줄 (이름·캐릭터·레벨)
    var petLabel: ((Pet) -> String)?
    /// 펫을 빼기 전 확인 (false면 빼지 않음)
    var confirmRemoval: ((Pet) -> Bool)?

    init(library: MacSkinLibrary, roster: PetRoster, settings: PetSettings, world: @escaping () -> World) {
        self.library = library
        self.roster = roster
        self.settings = settings
        self.world = world
    }

    /// 저장된 펫별 캐릭터로 펫을 만듦 (없는 캐릭터는 기본 캐릭터로). 한 마리씩 메뉴바 밑에서 보는 창 위로 떨어짐
    func restore() {
        let skins = settings.petSkins.compactMap(library.skin(named:))
        let ids = KeeperIDs.aligned(settings.petIDs, count: skins.count)
        for (order, skin) in skins.enumerated() {
            roster.add(appearance: skin, scale: settings.scale, in: world(), entrance: .startup(order: order)).keeperID = ids[order]
        }
        settings.petIDs = ids
    }

    /// 전령 캐릭터: 기본 펫들이 입지 않은 캐릭터를 돌아가며 (모두 쓰고 있으면 전체에서)
    func nextMessengerLook() -> PetAppearance? {
        let worn = Set(roster.residents.map(\.appearance.name))
        let others = library.names.filter { !worn.contains($0) }
        let names = others.isEmpty ? library.names : others
        guard !names.isEmpty else { return nil }
        defer { messengerCursor += 1 }
        return library.skins[names[messengerCursor % names.count]]
    }

    // MARK: - Menus

    /// 메뉴바 메뉴에 넣을 항목들
    func statusMenuItems() -> [NSMenuItem] {
        let language = settings.menuLanguage
        let residents = roster.residents
        let pets = residents.map { pet -> NSMenuItem in
            let parent = NSMenuItem(title: label(of: pet), action: nil, keyEquivalent: "")
            parent.submenu = petMenu(for: pet, withTitle: false)
            return parent
        }
        let add = library.names.map { item($0, action: #selector(addPet(_:)), value: $0) }
        let everyone = library.names.map { name in
            item(name, action: #selector(restyleAll(_:)), value: name,
                 checked: !residents.isEmpty && residents.allSatisfy { $0.appearance.name == name })
        }
        return [
            submenu(MenuText.pets.text(in: language), items: pets),
            submenu(MenuText.addPet.text(in: language), items: add),
            item(MenuText.addAnotherPet.text(in: language), action: #selector(addVariety), key: "a"),
            item(MenuText.removePet.text(in: language), action: #selector(removeLast), key: "r"),
            submenu(MenuText.allPetsAs.text(in: language), items: everyone),
        ]
    }

    /// 펫 하나의 메뉴 (우클릭 또는 Pets 하위 메뉴)
    func petMenu(for pet: Pet, withTitle: Bool = true) -> NSMenu {
        let menu = NSMenu()
        if withTitle {
            let title = NSMenuItem(title: label(of: pet), action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            menu.addItem(.separator())
        }
        for name in library.names {
            menu.addItem(item(name, action: #selector(restyleOne(_:)), value: [pet.id, name], checked: pet.appearance.name == name))
        }
        if let extras = petMenuItems?(pet), !extras.isEmpty {
            menu.addItem(.separator())
            extras.forEach(menu.addItem)
        }
        if pet.role == .resident {
            menu.addItem(.separator())
            let remove = item(MenuText.removeThisPet.text(in: settings.menuLanguage), action: #selector(removeOne(_:)), value: pet.id)
            remove.isEnabled = roster.residents.count > 1
            menu.addItem(remove)
        }
        return menu
    }

    private func label(of pet: Pet) -> String {
        petLabel?(pet) ?? "\(pet.id) · \(pet.appearance.name)"
    }

    /// 펫을 우클릭한 자리에 그 펫의 메뉴를 띄움
    func showMenu(for pet: Pet, at point: CGPoint) {
        petMenu(for: pet).popUp(positioning: nil, at: point, in: nil)
    }

    // MARK: - Actions

    @objc private func restyleOne(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let pet = roster.pet(withID: pair[0]), let skin = library.skin(named: pair[1]) else { return }
        roster.restyle(pet, as: skin)
        changed()
    }

    @objc private func restyleAll(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let skin = library.skin(named: name) else { return }
        roster.restyle(skin)
        changed()
    }

    @objc private func addPet(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let skin = library.skin(named: name) else { return }
        add(skin)
    }

    /// 아직 없는 캐릭터를 우선해 한 마리 추가
    @objc private func addVariety() {
        let worn = roster.residents.map(\.appearance.name)
        let fresh = library.names.first { !worn.contains($0) }
        let leastUsed = library.names.min { name, other in worn.filter { $0 == name }.count < worn.filter { $0 == other }.count }
        guard let skin = library.skin(named: fresh ?? leastUsed) else { return }
        add(skin)
    }

    @objc private func removeOne(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let pet = roster.pet(withID: id),
              confirmRemoval?(pet) ?? true, roster.remove(pet) else { return }
        changed()
    }

    @objc private func removeLast() {
        guard roster.residents.count > 1, let last = roster.residents.last, confirmRemoval?(last) ?? true else { return }
        roster.removeLast()
        changed()
    }

    private func add(_ skin: MacSkin) {
        guard roster.residents.count < 10 else { return }
        // 새 펫도 보는 창 위로 떨어짐 (자리는 기존 펫 수만큼 벌림)
        roster.add(appearance: skin, scale: settings.scale, in: world(),
                   entrance: EntranceBehavior(order: roster.residents.count, delay: 0)).keeperID = UUID().uuidString
        changed()
    }

    private func changed() {
        settings.petSkins = roster.residents.map(\.appearance.name)
        settings.petIDs = roster.residents.map { $0.keeperID ?? UUID().uuidString }
        onChange?()
    }

    // MARK: - Menu helpers

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
}
