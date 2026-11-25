import Foundation

/// This object is responsible for remembering the user's pet choices between launches:
/// which settings exist, their defaults and allowed values. Where they are kept is the platform's
/// `SettingsStore` (macOS `UserDefaults`, Windows a JSON file), so every shell reads them the same way.
final class PetSettings {
    static let scales: [CGFloat] = [1.0, 1.5, 2.0, 2.5]
    static let opacities: [CGFloat] = [1.0, 0.75, 0.5]

    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    var skinName: String? {
        get { store.string(forKey: "skinName") }
        set { store.set(string: newValue, forKey: "skinName") }
    }

    /// 레티나에서 도트 1개가 정수 픽셀이 되는 배율만 허용
    var scale: CGFloat {
        get {
            let stored = CGFloat(store.number(forKey: "scale") ?? 0)
            return Self.scales.contains(stored) ? stored : 1.5
        }
        set { store.set(number: Double(newValue), forKey: "scale") }
    }

    var opacity: CGFloat {
        get {
            let stored = CGFloat(store.number(forKey: "opacity") ?? 0)
            return Self.opacities.contains(stored) ? stored : 1.0
        }
        set { store.set(number: Double(newValue), forKey: "opacity") }
    }

    /// 던지기 정확도 (기본 자주 명중)
    var throwAccuracy: ThrowAccuracy {
        get { store.string(forKey: "throwAccuracy").flatMap(ThrowAccuracy.init(rawValue:)) ?? .standard }
        set { store.set(string: newValue.rawValue, forKey: "throwAccuracy") }
    }

    /// 일정 말풍선 사용 (기본 켜짐)
    var schedulesEnabled: Bool {
        get { store.flag(forKey: "schedulesEnabled") ?? true }
        set { store.set(flag: newValue, forKey: "schedulesEnabled") }
    }

    /// 보고 있는 창으로 스킬 도약 (기본 켜짐)
    var skillJumpsEnabled: Bool {
        get { store.flag(forKey: "skillJumpsEnabled") ?? true }
        set { store.set(flag: newValue, forKey: "skillJumpsEnabled") }
    }

    /// 펫들이 쫓아다닐 것: "activeWindow"(기본) 또는 "pointer"
    var chaseMode: String {
        get { store.string(forKey: "chaseMode") ?? ActiveWindowChase.key }
        set { store.set(string: newValue, forKey: "chaseMode") }
    }

    /// 보고 있는 모니터로 펫들이 따라감 (기본 켜짐)
    var followsActiveDisplay: Bool {
        get { store.flag(forKey: "followsActiveDisplay") ?? true }
        set { store.set(flag: newValue, forKey: "followsActiveDisplay") }
    }

    /// Claude 사용량에 따라 펫 기력이 줄어듦 (기본 켜짐)
    var tiresWithClaudeUsage: Bool {
        get { store.flag(forKey: "tiresWithClaudeUsage") ?? true }
        set { store.set(flag: newValue, forKey: "tiresWithClaudeUsage") }
    }

    /// AI 도구가 보낸 신호(끝남·기다림·한도)를 펫이 앱 아이콘 말풍선으로 알림 (기본 켜짐)
    var agentSignalsEnabled: Bool {
        get { store.flag(forKey: "agentSignalsEnabled") ?? true }
        set { store.set(flag: newValue, forKey: "agentSignalsEnabled") }
    }

    /// 오래 확인하지 않은 알림을 펫이 구겨 바닥 더미에 던짐 (누르면 다시 띄움, 기본 켜짐)
    var tossesOldNotices: Bool {
        get { store.flag(forKey: "tossesOldNotices") ?? true }
        set { store.set(flag: newValue, forKey: "tossesOldNotices") }
    }

    /// AI 작업이 끝나면 펫이 그 앱의 Dock 아이콘으로 걸어감 (맥은 손쉬운 사용 권한 필요, 기본 꺼짐)
    var visitsDockIcons: Bool {
        get { store.flag(forKey: "visitsDockIcons") ?? false }
        set { store.set(flag: newValue, forKey: "visitsDockIcons") }
    }

    /// 통화 중 조용히 (기본 켜짐)
    var quietDuringCalls: Bool {
        get { store.flag(forKey: "quietDuringCalls") ?? true }
        set { store.set(flag: newValue, forKey: "quietDuringCalls") }
    }

    /// 멈춘 포인터를 펫이 잠깐 들고 달아남 (기본 꺼짐)
    var cursorPranksEnabled: Bool {
        get { store.flag(forKey: "cursorPranksEnabled") ?? false }
        set { store.set(flag: newValue, forKey: "cursorPranksEnabled") }
    }

    /// 키를 빠르게 누르면 펫이 따라 두드림 (기본 켜짐)
    var typingReactionsEnabled: Bool {
        get { store.flag(forKey: "typingReactionsEnabled") ?? true }
        set { store.set(flag: newValue, forKey: "typingReactionsEnabled") }
    }

    /// 기지개·어지러움 한마디 (기본 꺼짐)
    var workRhythmEnabled: Bool {
        get { store.flag(forKey: "workRhythmEnabled") ?? false }
        set { store.set(flag: newValue, forKey: "workRhythmEnabled") }
    }

    /// 일정 제목 숨김 (화면 공유 대비)
    var hidesScheduleTitles: Bool {
        get { store.flag(forKey: "hidesScheduleTitles") ?? false }
        set { store.set(flag: newValue, forKey: "hidesScheduleTitles") }
    }

    /// 메뉴 언어. 고른 적이 없으면 운영체제 선호 언어를 따름
    var menuLanguage: MenuLanguage {
        get { MenuLanguage.resolve(stored: store.string(forKey: "menuLanguage"), preferredLanguages: Locale.preferredLanguages) }
        set { store.set(string: newValue.rawValue, forKey: "menuLanguage") }
    }

    var petCount: Int {
        get { min(max(Int(store.number(forKey: "petCount") ?? 0), 1), 10) }
        set { store.set(number: Double(newValue), forKey: "petCount") }
    }

    /// 펫마다 오래가는 ID (petSkins와 같은 순서, 수집·성장 기록용)
    var petIDs: [String] {
        get { store.strings(forKey: "petIDs") ?? [] }
        set { store.set(strings: newValue, forKey: "petIDs") }
    }

    /// 펫마다 입은 캐릭터 (순서대로). 예전 설정(한 캐릭터 × 펫 수)에서 이어받음
    var petSkins: [String] {
        get {
            if let stored = store.strings(forKey: "petSkins"), !stored.isEmpty { return Array(stored.prefix(10)) }
            return Array(repeating: skinName ?? "", count: petCount)
        }
        set {
            store.set(strings: newValue, forKey: "petSkins")
            petCount = newValue.count
        }
    }
}
