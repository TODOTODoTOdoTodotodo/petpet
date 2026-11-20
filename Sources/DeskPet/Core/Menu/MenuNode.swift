import Foundation

/// 메뉴 줄 앞의 도트 아이콘 (물건·모자). 플랫폼이 이 도트로 그림을 만듦
struct MenuIcon: Equatable {
    let name: String
    let rows: [String]
    let palette: [Character: UInt32]
    /// 못 찾은 것은 실루엣으로
    var silhouette = false
}

/// 메뉴바 메뉴의 켜고 끄는 항목
enum MenuToggle: Equatable {
    case skillJumps, followDisplay, quietDuringCalls, tiresWithUsage, typing, pointerPranks, workRhythm
    case schedules, scheduleTitles
}

/// 운영체제가 해야 하는 일 (로그 열기, 끄기, 캘린더 권한 화면)
enum PlatformAction: Equatable {
    case openLog, quit, allowCalendarAccess
}

/// 메뉴에서 고른 일. 껍데기는 이 값을 그대로 Core에 돌려줌
enum MenuCommand: Equatable {
    // 펫 구성
    case restylePet(petID: String, skin: String)
    case restyleAll(skin: String)
    case addPet(skin: String)
    case addVariety
    case removePet(petID: String)
    case removeLast
    // 도감
    case chooseHat(keeperID: String, hatID: String?)
    case chooseHeld(keeperID: String, itemID: String?)
    case rename(keeperID: String)
    case resetCollection
    /// 도감 하위 메뉴를 열었음 (새 모자 표시 지우기)
    case collectionOpened
    // 설정
    case chase(String)
    case scale(CGFloat)
    case opacity(CGFloat)
    case language(MenuLanguage)
    case toggle(MenuToggle)
    case platform(PlatformAction)
}

/// This object is responsible for describing one menu row as plain data — its title, check mark, icon and what
/// choosing it does — so the shared code builds every DeskPet menu once and each platform only renders it
/// (`NSMenu` on macOS, `HMENU` on Windows) and hands the chosen `MenuCommand` back.
struct MenuNode: Equatable {
    enum Kind: Equatable {
        case command(MenuCommand)
        /// onOpen: 하위 메뉴를 열 때 알릴 일
        case submenu([MenuNode], onOpen: MenuCommand?)
        /// 흐린 머리줄
        case heading
        /// 보기만 하는 줄 (흐리지 않음)
        case info
        case separator
    }

    let title: String
    let kind: Kind
    var checked = false
    var enabled = true
    var icon: MenuIcon?
    var toolTip: String?
    /// 키보드 단축키 (맥 메뉴만)
    var key = ""

    static let separator = MenuNode(title: "", kind: .separator)

    static func heading(_ title: String) -> MenuNode {
        MenuNode(title: title, kind: .heading)
    }

    static func info(_ title: String, icon: MenuIcon? = nil, toolTip: String? = nil) -> MenuNode {
        MenuNode(title: title, kind: .info, icon: icon, toolTip: toolTip)
    }

    static func command(_ title: String, _ command: MenuCommand, checked: Bool = false, enabled: Bool = true,
                        icon: MenuIcon? = nil, key: String = "") -> MenuNode {
        MenuNode(title: title, kind: .command(command), checked: checked, enabled: enabled, icon: icon, key: key)
    }

    static func submenu(_ title: String, _ items: [MenuNode], onOpen: MenuCommand? = nil) -> MenuNode {
        MenuNode(title: title, kind: .submenu(items, onOpen: onOpen))
    }

    /// 이 줄과 하위 메뉴 안에서 제목이 같은 첫 줄 (검사·찾기용)
    func find(_ title: String) -> MenuNode? {
        if self.title == title { return self }
        if case .submenu(let items, _) = kind {
            return items.lazy.compactMap { $0.find(title) }.first
        }
        return nil
    }
}

extension Array where Element == MenuNode {
    /// 메뉴 목록 안에서 제목이 같은 첫 줄
    func find(_ title: String) -> MenuNode? {
        lazy.compactMap { $0.find(title) }.first
    }
}

/// This object is responsible for the dialogs a menu choice may need, shown by the platform
/// (macOS `NSAlert`, Windows message box): confirming a destructive choice and asking for a short text.
protocol MenuDialogs: AnyObject {
    /// 확인을 누르면 true
    func confirm(title: String, message: String, confirm: String, cancel: String) -> Bool
    /// 저장을 누르면 입력한 글, 취소하면 nil
    func askText(title: String, message: String, initial: String, save: String, cancel: String) -> String?
}

/// This object is responsible for carrying out the menu commands it owns and ignoring the rest.
protocol MenuCommandHandler: AnyObject {
    /// 처리했으면 true
    func perform(_ command: MenuCommand) -> Bool
}
