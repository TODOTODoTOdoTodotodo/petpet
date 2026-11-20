import Foundation

// SpriteForge: DeskPet 캐릭터 제작 도구 (생성 모델 호출 없음)
//
//   swift run SpriteForge check <rig.json>
//   swift run SpriteForge build <rig.json> [--out Assets/Skins/<이름>] [--preview <png>]
//   swift run SpriteForge pixelize <image> --out <draft.rig.json> [--height 30] [--colors 10] [--flip]
//   swift run SpriteForge hang <스킨.hang.json> [--out <폴더>] [--preview <png>]
//   swift run SpriteForge import <이름.import.json> [--out Assets/Skins/<이름>] [--preview <png>]

/// This object is responsible for reading the command line and running the matching SpriteForge command.
struct ForgeCommand {
    let arguments: [String]

    func run() throws {
        guard let command = arguments.first else { throw ForgeError(description: Self.usage) }
        let rest = Array(arguments.dropFirst())
        switch command {
        case "check": try check(rest)
        case "build": try build(rest)
        case "pixelize": try pixelize(rest)
        case "hang": try hang(rest)
        case "import": try importSheets(rest)
        default: throw ForgeError(description: Self.usage)
        }
    }

    static let usage = """
    사용법:
      SpriteForge check <rig.json>
      SpriteForge build <rig.json> [--out Assets/Skins/<이름>] [--preview <png>]
      SpriteForge pixelize <image> --out <draft.rig.json> [--height 30] [--colors 10] [--flip]
      SpriteForge hang <스킨.hang.json> [--out <폴더>] [--preview <png>]
        원본 스킨에 매달리기 4프레임 추가. --out을 주면 그 폴더에 프레임만 씀 (검증용)
      SpriteForge import <이름.import.json> [--out Assets/Skins/<이름>] [--preview <png>]
        남이 그린 스프라이트 시트(가로 줄)를 스킨으로 변환
    """

    private func check(_ args: [String]) throws {
        guard let path = args.first else { throw ForgeError(description: Self.usage) }
        let rig = try Rig.load(URL(fileURLWithPath: path))
        let (animations, warnings) = SkinBuilder(rig: rig, rigPath: path).render()
        report(rig, animations: animations, warnings: warnings)
        if !warnings.isEmpty { throw ForgeError(description: "경고 \(warnings.count)건") }
    }

    private func build(_ args: [String]) throws {
        guard let path = args.first else { throw ForgeError(description: Self.usage) }
        let rig = try Rig.load(URL(fileURLWithPath: path))
        let builder = SkinBuilder(rig: rig, rigPath: path)
        let (animations, warnings) = builder.render()
        report(rig, animations: animations, warnings: warnings)
        guard warnings.isEmpty else { throw ForgeError(description: "경고가 있어 저장하지 않음. 리그를 고친 뒤 다시 실행") }

        let out = URL(fileURLWithPath: value(of: "--out", in: args) ?? "Assets/Skins/\(rig.name)")
        try builder.write(to: out, animations: animations)
        print("✓ 스킨 저장: \(out.path)")
        if let preview = value(of: "--preview", in: args) {
            try Preview.write(name: rig.name, animations: animations, to: URL(fileURLWithPath: preview))
            print("✓ 미리보기: \(preview)")
        }
    }

    private func pixelize(_ args: [String]) throws {
        guard let path = args.first, let out = value(of: "--out", in: args) else { throw ForgeError(description: Self.usage) }
        var pixelizer = Pixelizer()
        if let height = value(of: "--height", in: args).flatMap(Int.init) { pixelizer.targetHeight = height }
        if let colors = value(of: "--colors", in: args).flatMap(Int.init) { pixelizer.colorCount = colors }
        pixelizer.flip = args.contains("--flip")
        let outURL = URL(fileURLWithPath: out)
        let name = outURL.deletingPathExtension().deletingPathExtension().lastPathComponent
        let draft = try pixelizer.draftRig(from: URL(fileURLWithPath: path), name: name)
        let data = try JSONSerialization.data(withJSONObject: draft, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: outURL)
        print("✓ 초안 리그: \(out) (body 한 장. 부위로 나누면 동작이 살아남)")
    }

    private func hang(_ args: [String]) throws {
        guard let path = args.first else { throw ForgeError(description: Self.usage) }
        let recipe = try HangRecipe.load(URL(fileURLWithPath: path))
        let skinFolder = URL(fileURLWithPath: "Assets/Skins/\(recipe.skin)")
        let synth = HangSynth(recipe: recipe, skinFolder: skinFolder)
        let (frames, warnings) = try synth.render()
        warnings.forEach { print("⚠️ \($0)") }
        guard warnings.isEmpty else { throw ForgeError(description: "경고가 있어 저장하지 않음. 팔 사각형·legsFrom을 고친 뒤 다시 실행") }

        let out = value(of: "--out", in: args).map { URL(fileURLWithPath: $0) }
        try synth.write(frames, to: out ?? skinFolder, registers: out == nil)
        print("✓ \(recipe.skin): 매달리기 \(frames.count)프레임 → \((out ?? skinFolder).path)/\(recipe.assetRoot)animations/Hang/\(recipe.direction)")
        if let preview = value(of: "--preview", in: args) {
            let still = try HangSynth.grid(from: skinFolder.appendingPathComponent(recipe.base))
            try Preview.write(name: recipe.skin, animations: [RenderedAnimation(key: "바탕", frames: [still]),
                                                              RenderedAnimation(key: "Hang", frames: frames)],
                              to: URL(fileURLWithPath: preview))
            print("✓ 미리보기: \(preview)")
        }
    }

    private func importSheets(_ args: [String]) throws {
        guard let path = args.first else { throw ForgeError(description: Self.usage) }
        let recipe = try ImportRecipe.load(URL(fileURLWithPath: path))
        let importer = SheetImporter(recipe: recipe, recipePath: path)
        let (animations, warnings) = try importer.render()
        print("• \(recipe.name): \(recipe.facing) 방향, 스킬 \(recipe.skill), 동작: "
              + animations.map { "\($0.key) \($0.frames.count)" }.joined(separator: ", "))
        warnings.forEach { print("⚠️ \($0)") }
        guard warnings.isEmpty else { throw ForgeError(description: "경고가 있어 저장하지 않음") }

        let out = URL(fileURLWithPath: value(of: "--out", in: args) ?? "Assets/Skins/\(recipe.name)")
        try importer.write(to: out, animations: animations)
        print("✓ 스킨 저장: \(out.path)")
        if let preview = value(of: "--preview", in: args) {
            try Preview.write(name: recipe.name, animations: animations, to: URL(fileURLWithPath: preview))
            print("✓ 미리보기: \(preview)")
        }
    }

    private func report(_ rig: Rig, animations: [RenderedAnimation], warnings: [String]) {
        let rest = Raster.render(rig, pose: Pose()).grid
        let top = Raster.topRow(rest) ?? 0
        let bottom = Raster.bottomRow(rest) ?? 0
        print("• \(rig.name): \(rig.directionName) 방향, 색 \(rig.colorCount)개, 키 \(bottom - top + 1)px (줄 \(top)~\(bottom)), 스킬 \(rig.skill)")
        print("• 부위: \(Rig.drawOrder.filter { rig.layers[$0] != nil }.joined(separator: ", "))"
              + (rig.overlays.isEmpty ? "" : " / 겹침: \(rig.overlays.keys.sorted().joined(separator: ", "))"))
        print("• 동작: " + animations.map { "\($0.key) \($0.frames.count)" }.joined(separator: ", "))
        warnings.forEach { print("⚠️ \($0)") }
    }

    private func value(of flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}

do {
    try ForgeCommand(arguments: Array(CommandLine.arguments.dropFirst())).run()
} catch {
    FileHandle.standardError.write(Data("✗ \(error)\n".utf8))
    exit(1)
}
