import Foundation

/// This object is responsible for checking the menu language choice: every menu word exists in both languages,
/// each language reads as itself, and the saved choice wins over the Mac's preferred language.
enum MenuChecks {
    static func run(_ check: Checker) {
        check.section("메뉴 언어")
        let hangul = { (text: String) in text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) } }
        for language in MenuLanguage.allCases {
            let texts = MenuText.allCases.map { $0.text(in: language) }
            check.expect(texts.allSatisfy { !$0.isEmpty }, "\(language.displayName): 빈 문구 없음")
            check.expect(Set(texts).count == texts.count, "\(language.displayName): 서로 다른 항목은 다른 문구")
        }
        let english = MenuText.allCases.filter { $0 != .language && hangul($0.text(in: .english)) }
        check.expect(english.isEmpty, "영어 메뉴에 한글 없음", "\(english)")
        let korean = MenuText.allCases.filter { !hangul($0.text(in: .korean)) }
        check.expect(korean.isEmpty, "한국어 메뉴는 모두 한글", "\(korean)")
        check.expect(hangul(MenuText.language.text(in: .english)) && MenuText.language.text(in: .korean).contains("Language"),
                     "언어 메뉴는 두 언어를 함께 적어 어느 쪽에서도 찾음")
        check.expect(MenuText.tireWithUsage("5h 64%", in: .korean) == "Claude 사용량만큼 지침 (5h 64%)", "사용량 요약을 붙인 항목")

        check.expect(MenuLanguage.resolve(stored: nil, preferredLanguages: ["ko-KR", "en-US"]) == .korean, "고른 적 없으면 맥 언어: 한국어")
        check.expect(MenuLanguage.resolve(stored: nil, preferredLanguages: ["en-US", "ko-KR"]) == .english, "고른 적 없으면 맥 언어: 영어")
        check.expect(MenuLanguage.resolve(stored: nil, preferredLanguages: []) == .english, "언어 정보가 없으면 영어")
        check.expect(MenuLanguage.resolve(stored: "en", preferredLanguages: ["ko-KR"]) == .english, "고른 언어가 맥 언어보다 우선")
        check.expect(MenuLanguage.resolve(stored: "xx", preferredLanguages: ["ko"]) == .korean, "알 수 없는 저장 값은 무시")
    }
}
