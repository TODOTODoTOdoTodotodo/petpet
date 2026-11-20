import Foundation

/// This object is responsible for checking saved settings on every platform: defaults and allowed values
/// in `PetSettings`, and the JSON-file store the Windows shell keeps them in.
enum SettingsChecks {
    static func run(_ check: Checker) {
        check.section("설정 (공통)")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deskpet-checks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("DeskPet").appendingPathComponent("settings.json")

        let fresh = PetSettings(store: JSONFileSettingsStore(fileURL: file))
        check.expect(fresh.scale == 1.5 && fresh.opacity == 1 && fresh.petCount == 1, "처음에는 크기 1.5·투명도 100%·펫 1마리")
        check.expect(fresh.schedulesEnabled && fresh.skillJumpsEnabled && fresh.typingReactionsEnabled
                     && !fresh.cursorPranksEnabled && !fresh.workRhythmEnabled && !fresh.hidesScheduleTitles,
                     "켜짐·꺼짐 기본값 (포인터 장난·작업 리듬 꺼짐)")
        check.expect(fresh.chaseMode == ActiveWindowChase.key && fresh.petSkins == [""], "기본은 활성 창 쫓기, 캐릭터는 아직 없음")
        check.expect(!FileManager.default.fileExists(atPath: file.path), "읽기만 하면 파일을 만들지 않음")

        fresh.scale = 2.0
        fresh.opacity = 0.75
        fresh.skillJumpsEnabled = false
        fresh.cursorPranksEnabled = true
        fresh.menuLanguage = .korean
        fresh.petSkins = ["Nabi", "Bolt"]
        fresh.petIDs = ["a", "b"]
        fresh.skinName = "Nabi"
        fresh.skinName = nil
        let reopened = PetSettings(store: JSONFileSettingsStore(fileURL: file))
        check.expect(reopened.scale == 2.0 && reopened.opacity == 0.75, "다시 열어도 크기·투명도 유지")
        check.expect(!reopened.skillJumpsEnabled && reopened.cursorPranksEnabled && reopened.menuLanguage == .korean,
                     "참거짓·언어 유지")
        check.expect(reopened.petSkins == ["Nabi", "Bolt"] && reopened.petCount == 2 && reopened.petIDs == ["a", "b"],
                     "펫별 캐릭터를 저장하면 펫 수도 맞춰짐")
        check.expect(reopened.skinName == nil, "nil을 쓰면 값을 지움")

        let store = JSONFileSettingsStore(fileURL: file)
        store.set(number: 3.3, forKey: "scale")
        store.set(number: 40, forKey: "petCount")
        check.expect(PetSettings(store: store).scale == 1.5 && PetSettings(store: store).petCount == 10,
                     "허용되지 않는 크기는 기본값, 펫 수는 10마리까지")
        store.set(flag: true, forKey: "check")
        check.expect(JSONFileSettingsStore(fileURL: file).flag(forKey: "check") == true
                     && JSONFileSettingsStore(fileURL: file).number(forKey: "check") == nil, "JSON의 참거짓은 숫자로 읽히지 않음")

        let legacyFile = folder.appendingPathComponent("legacy.json")
        try? Data(#"{"skinName": "Foxy", "petCount": 3}"#.utf8).write(to: legacyFile)
        check.expect(PetSettings(store: JSONFileSettingsStore(fileURL: legacyFile)).petSkins == ["Foxy", "Foxy", "Foxy"],
                     "예전 설정(한 캐릭터 × 펫 수)을 이어받음")

        let brokenFile = folder.appendingPathComponent("broken.json")
        try? Data("{oops".utf8).write(to: brokenFile)
        check.expect(PetSettings(store: JSONFileSettingsStore(fileURL: brokenFile)).scale == 1.5, "깨진 파일이면 기본값으로 시작")
    }
}
