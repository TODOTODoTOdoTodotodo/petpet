import Foundation

/// This object is responsible for finding the skins folder and loading every character in it.
/// New characters appear by adding a folder, without rebuilding the app. The platform decodes the pictures.
final class SkinLibrary<Frame> {
    private(set) var skins: [String: PetSkin<Frame>] = [:]

    var names: [String] { skins.keys.sorted() }

    init(directory: URL, loader: @escaping (URL) -> LoadedSprite<Frame>?) {
        let subdirectories = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        )) ?? []
        for folder in subdirectories where (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let skin = PetSkin(name: folder.lastPathComponent, directory: folder, loader: loader)
            skins[skin.name] = skin
        }
    }

    /// 저장된 캐릭터가 없을 때 고르는 순서 (공개 배포에 늘 있는 자체 제작 캐릭터 먼저)
    static var defaultNames: [String] { ["Nabi", "Goblin"] }

    func skin(named name: String?) -> PetSkin<Frame>? {
        if let name, let skin = skins[name] { return skin }
        return Self.defaultNames.lazy.compactMap { self.skins[$0] }.first ?? names.first.flatMap { skins[$0] }
    }
}

/// This object is responsible for finding the Assets/Skins folder next to or inside the running app.
enum SkinFolder {
    /// 앱 번들 Resources → 실행 파일 옆(윈도우 zip 설치) → 실행 위치 순서로 Assets/Skins 탐색
    static func locate() -> URL {
        let fm = FileManager.default
        let current = URL(fileURLWithPath: fm.currentDirectoryPath)
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Assets/Skins"))
        }
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent("Assets/Skins"))
        }
        candidates += [
            current.appendingPathComponent("Assets/Skins"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Assets/Skins"),
        ]
        return candidates.first { fm.fileExists(atPath: $0.path) } ?? candidates[0]
    }
}
