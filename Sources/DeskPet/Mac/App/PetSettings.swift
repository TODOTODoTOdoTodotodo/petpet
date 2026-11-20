import Foundation
import CoreGraphics

/// This object is responsible for remembering the user's pet choices between launches.
final class PetSettings {
    static let scales: [CGFloat] = [1.0, 1.5, 2.0, 2.5]
    static let opacities: [CGFloat] = [1.0, 0.75, 0.5]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var skinName: String? {
        get { defaults.string(forKey: "skinName") }
        set { defaults.set(newValue, forKey: "skinName") }
    }

    /// 레티나에서 도트 1개가 정수 픽셀이 되는 배율만 허용
    var scale: CGFloat {
        get {
            let stored = CGFloat(defaults.double(forKey: "scale"))
            return Self.scales.contains(stored) ? stored : 1.5
        }
        set { defaults.set(Double(newValue), forKey: "scale") }
    }

    var opacity: CGFloat {
        get {
            let stored = CGFloat(defaults.double(forKey: "opacity"))
            return Self.opacities.contains(stored) ? stored : 1.0
        }
        set { defaults.set(Double(newValue), forKey: "opacity") }
    }

    /// 일정 말풍선 사용 (기본 켜짐)
    var schedulesEnabled: Bool {
        get { defaults.object(forKey: "schedulesEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "schedulesEnabled") }
    }

    /// 보고 있는 창으로 스킬 도약 (기본 켜짐)
    var skillJumpsEnabled: Bool {
        get { defaults.object(forKey: "skillJumpsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "skillJumpsEnabled") }
    }

    /// 펫들이 쫓아다닐 것: "activeWindow"(기본) 또는 "pointer"
    var chaseMode: String {
        get { defaults.string(forKey: "chaseMode") ?? ActiveWindowChase.key }
        set { defaults.set(newValue, forKey: "chaseMode") }
    }

    /// 보고 있는 모니터로 펫들이 따라감 (기본 켜짐)
    var followsActiveDisplay: Bool {
        get { defaults.object(forKey: "followsActiveDisplay") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "followsActiveDisplay") }
    }

    /// Claude 사용량에 따라 펫 기력이 줄어듦 (기본 켜짐)
    var tiresWithClaudeUsage: Bool {
        get { defaults.object(forKey: "tiresWithClaudeUsage") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "tiresWithClaudeUsage") }
    }

    /// 통화 중 조용히 (기본 켜짐)
    var quietDuringCalls: Bool {
        get { defaults.object(forKey: "quietDuringCalls") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "quietDuringCalls") }
    }

    /// 멈춘 포인터를 펫이 잠깐 들고 달아남 (기본 꺼짐)
    var cursorPranksEnabled: Bool {
        get { defaults.bool(forKey: "cursorPranksEnabled") }
        set { defaults.set(newValue, forKey: "cursorPranksEnabled") }
    }

    /// 키를 빠르게 누르면 펫이 따라 두드림 (기본 켜짐)
    var typingReactionsEnabled: Bool {
        get { defaults.object(forKey: "typingReactionsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "typingReactionsEnabled") }
    }

    /// 기지개·어지러움 한마디 (기본 꺼짐)
    var workRhythmEnabled: Bool {
        get { defaults.bool(forKey: "workRhythmEnabled") }
        set { defaults.set(newValue, forKey: "workRhythmEnabled") }
    }

    /// 일정 제목 숨김 (화면 공유 대비)
    var hidesScheduleTitles: Bool {
        get { defaults.bool(forKey: "hidesScheduleTitles") }
        set { defaults.set(newValue, forKey: "hidesScheduleTitles") }
    }

    /// 메뉴 언어. 고른 적이 없으면 맥 선호 언어를 따름
    var menuLanguage: MenuLanguage {
        get { MenuLanguage.resolve(stored: defaults.string(forKey: "menuLanguage"), preferredLanguages: Locale.preferredLanguages) }
        set { defaults.set(newValue.rawValue, forKey: "menuLanguage") }
    }

    var petCount: Int {
        get { min(max(defaults.integer(forKey: "petCount"), 1), 10) }
        set { defaults.set(newValue, forKey: "petCount") }
    }

    /// 펫마다 오래가는 ID (petSkins와 같은 순서, 수집·성장 기록용)
    var petIDs: [String] {
        get { defaults.stringArray(forKey: "petIDs") ?? [] }
        set { defaults.set(newValue, forKey: "petIDs") }
    }

    /// 펫마다 입은 캐릭터 (순서대로). 예전 설정(한 캐릭터 × 펫 수)에서 이어받음
    var petSkins: [String] {
        get {
            if let stored = defaults.stringArray(forKey: "petSkins"), !stored.isEmpty { return Array(stored.prefix(10)) }
            return Array(repeating: skinName ?? "", count: petCount)
        }
        set {
            defaults.set(newValue, forKey: "petSkins")
            petCount = newValue.count
        }
    }
}
