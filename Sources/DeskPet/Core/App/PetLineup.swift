import Foundation

/// This object is responsible for which character each pet wears: restoring the saved lineup at launch,
/// adding, removing and restyling individual pets, remembering the result, and offering those choices
/// as menu data (the status menu's pet submenus and a pet's own right-click menu).
/// `Frame` is the platform texture the skins were loaded with.
final class PetLineup<Frame>: MenuCommandHandler {
    private let library: SkinLibrary<Frame>
    private let roster: PetRoster
    private let settings: PetSettings
    private let world: () -> World
    private var messengerCursor = 0
    /// 최대 펫 수
    static var maxPets: Int { 10 }
    /// 구성이 바뀌어 메뉴를 다시 그려야 할 때
    var onChange: (() -> Void)?
    /// 펫 메뉴에 넣을 모자·손 소품·이름 항목 (도감 쪽이 만듦)
    var petMenuItems: ((Pet) -> [MenuNode])?
    /// 펫 메뉴 머리줄 (이름·캐릭터·레벨)
    var petLabel: ((Pet) -> String)?
    /// 펫을 빼기 전 확인 (false면 빼지 않음)
    var confirmRemoval: ((Pet) -> Bool)?

    init(library: SkinLibrary<Frame>, roster: PetRoster, settings: PetSettings, world: @escaping () -> World) {
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
    func statusMenuNodes() -> [MenuNode] {
        let language = settings.menuLanguage
        let residents = roster.residents
        let pets = residents.map { pet in MenuNode.submenu(label(of: pet), petMenu(for: pet, withTitle: false)) }
        let add = library.names.map { MenuNode.command($0, .addPet(skin: $0)) }
        let everyone = library.names.map { name in
            MenuNode.command(name, .restyleAll(skin: name),
                             checked: !residents.isEmpty && residents.allSatisfy { $0.appearance.name == name })
        }
        return [
            .submenu(MenuText.pets.text(in: language), pets),
            .submenu(MenuText.addPet.text(in: language), add),
            .command(MenuText.addAnotherPet.text(in: language), .addVariety, key: "a"),
            .command(MenuText.removePet.text(in: language), .removeLast, key: "r"),
            .submenu(MenuText.allPetsAs.text(in: language), everyone),
        ]
    }

    /// 펫 하나의 메뉴 (우클릭 또는 Pets 하위 메뉴)
    func petMenu(for pet: Pet, withTitle: Bool = true) -> [MenuNode] {
        var nodes: [MenuNode] = withTitle ? [.heading(label(of: pet)), .separator] : []
        nodes += library.names.map { name in
            MenuNode.command(name, .restylePet(petID: pet.id, skin: name), checked: pet.appearance.name == name)
        }
        if let extras = petMenuItems?(pet), !extras.isEmpty {
            nodes += [.separator] + extras
        }
        if pet.role == .resident {
            nodes += [.separator, .command(MenuText.removeThisPet.text(in: settings.menuLanguage), .removePet(petID: pet.id),
                                           enabled: roster.residents.count > 1)]
        }
        return nodes
    }

    private func label(of pet: Pet) -> String {
        petLabel?(pet) ?? "\(pet.id) · \(pet.appearance.name)"
    }

    // MARK: - Commands

    func perform(_ command: MenuCommand) -> Bool {
        switch command {
        case .restylePet(let petID, let name):
            guard let pet = roster.pet(withID: petID), let skin = library.skin(named: name) else { return true }
            roster.restyle(pet, as: skin)
            changed()
        case .restyleAll(let name):
            guard let skin = library.skin(named: name) else { return true }
            roster.restyle(skin)
            changed()
        case .addPet(let name):
            if let skin = library.skin(named: name) { add(skin) }
        case .addVariety:
            addVariety()
        case .removePet(let petID):
            guard let pet = roster.pet(withID: petID), confirmRemoval?(pet) ?? true, roster.remove(pet) else { return true }
            changed()
        case .removeLast:
            guard roster.residents.count > 1, let last = roster.residents.last, confirmRemoval?(last) ?? true else { return true }
            roster.removeLast()
            changed()
        default:
            return false
        }
        return true
    }

    /// 아직 없는 캐릭터를 우선해 한 마리 추가
    private func addVariety() {
        let worn = roster.residents.map(\.appearance.name)
        let fresh = library.names.first { !worn.contains($0) }
        let leastUsed = library.names.min { name, other in worn.filter { $0 == name }.count < worn.filter { $0 == other }.count }
        guard let skin = library.skin(named: fresh ?? leastUsed) else { return }
        add(skin)
    }

    private func add(_ skin: PetSkin<Frame>) {
        guard roster.residents.count < Self.maxPets else { return }
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
}
