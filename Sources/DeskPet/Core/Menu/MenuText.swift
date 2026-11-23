import Foundation

/// This object is responsible for which language the menus speak: the user's saved choice,
/// or the Mac's preferred language when nothing has been chosen yet.
enum MenuLanguage: String, CaseIterable {
    case english = "en"
    case korean = "ko"

    /// 언어 메뉴에 보이는 이름 (어느 언어에서도 같은 글자)
    var displayName: String {
        switch self {
        case .english: "English"
        case .korean: "한국어"
        }
    }

    /// 저장된 선택이 없으면 맥의 첫 선호 언어가 한국어일 때만 한국어
    static func resolve(stored: String?, preferredLanguages: [String]) -> MenuLanguage {
        if let stored, let chosen = MenuLanguage(rawValue: stored) { return chosen }
        return preferredLanguages.first?.hasPrefix("ko") == true ? .korean : .english
    }
}

/// This object is responsible for every fixed word shown in the menu bar menu and the pet menus,
/// in each supported language. Adding a case without both translations does not compile.
enum MenuText: CaseIterable {
    case language
    case rightClickHint
    case chase, chaseActiveWindow, chasePointer, chaseNothing
    case skillJumps, followDisplay, quietDuringCalls, tireWithUsage, reactToTyping, pointerPranks, breakReminders
    case petSize, opacity
    case scheduleBubbles, hideScheduleTitles, allowCalendarAccess
    case openDebugLog, quit
    case usageNone, usageReset
    case pets, addPet, addAnotherPet, removePet, allPetsAs, removeThisPet
    case collection, unknownItem, resetCollection, resetTitle, resetMessage, resetConfirm, cancel
    case hat, hatNone, hats, newMark
    case throwAccuracy
    case hold, holdNone, rename, renameTitle, renameMessage, save, removeMessage, removeConfirm

    func text(in language: MenuLanguage) -> String {
        let pair = words
        switch language {
        case .english: return pair.en
        case .korean: return pair.ko
        }
    }

    /// 도감 맨 위 모은 개수와 얻은 모자 수
    static func found(_ count: Int, hats: Int, of total: Int, in language: MenuLanguage) -> String {
        language == .korean ? "모은 물건 \(count) · 모자 \(hats)/\(total)" : "Found \(count) · Hats \(hats)/\(total)"
    }

    /// 펫 메뉴 머리: 이름(없으면 표시 ID) · 캐릭터 · ❤️ Lv.3 (42/60)
    static func petLabel(name: String, look: String, level: Int, hearts: Int, next: Int?) -> String {
        let progress = next.map { "\(hearts)/\($0)" } ?? "\(hearts)"
        return "\(name) · \(look) · ❤️ Lv.\(level) (\(progress))"
    }

    /// 던지기 정확도 단계 이름
    static func accuracy(_ level: ThrowAccuracy, in language: MenuLanguage) -> String {
        switch (level, language) {
        case (.always, .korean): return "늘 명중"
        case (.often, .korean): return "자주 명중"
        case (.sometimes, .korean): return "가끔 명중"
        case (.wild, .korean): return "엉망"
        case (.always, .english): return "Always Hit"
        case (.often, .english): return "Often Hit"
        case (.sometimes, .english): return "Sometimes Hit"
        case (.wild, .english): return "Wild"
        }
    }

    /// 펫 빼기 확인 제목
    static func removeTitle(level: Int, in language: MenuLanguage) -> String {
        language == .korean ? "Lv.\(level) 펫을 뺄까요?" : "Remove this Lv.\(level) pet?"
    }

    /// 사용량 요약을 넣은 Claude 사용량 항목
    static func tireWithUsage(_ summary: String, in language: MenuLanguage) -> String {
        "\(MenuText.tireWithUsage.text(in: language)) (\(summary))"
    }

    private var words: (en: String, ko: String) {
        switch self {
        // 어느 언어로 되어 있어도 찾을 수 있게 두 언어를 함께 씀
        case .language: ("Language · 언어", "언어 · Language")
        case .rightClickHint: ("Right-click a pet: change character", "펫 우클릭: 캐릭터 바꾸기")
        case .chase: ("Chase", "따라갈 곳")
        case .chaseActiveWindow: ("Active Window", "보는 창")
        case .chasePointer: ("Mouse Pointer", "마우스 포인터")
        case .chaseNothing: ("Nothing (Free Roam)", "없음 (알아서 놀기)")
        case .skillJumps: ("Skill Jumps", "스킬 도약")
        case .followDisplay: ("Follow To Display", "모니터 따라가기")
        case .quietDuringCalls: ("Quiet During Calls", "통화 중 조용히")
        case .tireWithUsage: ("Tire With Claude Usage", "Claude 사용량만큼 지침")
        case .reactToTyping: ("React To Typing", "타이핑 반응")
        case .pointerPranks: ("Pointer Pranks", "포인터 장난")
        case .breakReminders: ("Break Reminders", "휴식 알림")
        case .petSize: ("Pet Size", "펫 크기")
        case .opacity: ("Opacity", "불투명도")
        case .scheduleBubbles: ("Schedule Bubbles", "일정 말풍선")
        case .hideScheduleTitles: ("Hide Schedule Titles", "일정 제목 숨김")
        case .allowCalendarAccess: ("Allow Calendar Access…", "캘린더 접근 허용…")
        case .openDebugLog: ("Open Debug Log", "디버그 로그 열기")
        case .quit: ("Quit DeskPet", "DeskPet 종료")
        case .usageNone: ("none", "없음")
        case .usageReset: ("reset", "초기화됨")
        case .pets: ("Pets", "펫 목록")
        case .addPet: ("Add Pet", "펫 추가")
        case .addAnotherPet: ("Add Another Pet (+)", "펫 하나 더 (+)")
        case .removePet: ("Remove Pet (-)", "펫 하나 빼기 (-)")
        case .allPetsAs: ("All Pets As", "모든 펫 캐릭터")
        case .removeThisPet: ("Remove This Pet", "이 펫 빼기")
        case .collection: ("Collection", "도감")
        case .unknownItem: ("???", "아직 못 찾음")
        case .resetCollection: ("Reset Collection…", "도감 초기화…")
        case .resetTitle: ("Reset the collection?", "도감을 초기화할까요?")
        case .resetMessage: ("Every found item and hat is removed. This cannot be undone.", "모은 물건과 모자가 모두 지워집니다. 되돌릴 수 없습니다.")
        case .resetConfirm: ("Reset", "초기화")
        case .cancel: ("Cancel", "취소")
        case .throwAccuracy: ("Throw Accuracy", "던지기 정확도")
        case .hat: ("Hat", "모자")
        case .hatNone: ("None", "안 씀")
        case .hats: ("Hats", "모자 목록")
        case .newMark: ("(New)", "(새 모자)")
        case .hold: ("Hold", "손에 들기")
        case .holdNone: ("Nothing", "안 듦")
        case .rename: ("Name…", "이름 짓기…")
        case .renameTitle: ("Name this pet", "펫 이름")
        case .renameMessage: ("Up to 12 characters. Leave empty to clear.", "12자까지. 비우면 이름 지움")
        case .save: ("Save", "저장")
        case .removeMessage: ("Its affection, hat and name are erased.", "친밀도·모자·이름이 사라집니다.")
        case .removeConfirm: ("Remove", "빼기")
        }
    }
}
