import Foundation

/// 가져올 동작 하나: 프레임 줄 파일(또는 프레임마다 따로 있는 파일들)과 선택 조정
struct ImportedClip {
    let key: String
    /// 차례로 이어 붙여 읽을 파일들 ("file" 하나 또는 "files" 목록)
    let files: [String]
    /// 쓸 프레임 번호 (없으면 전부, 빈 프레임은 빼고)
    let frames: [Int]?
    /// 프레임마다 아래로 내리는 줄 수 (매달려 흔들리기 등). 프레임 수보다 길면 그만큼 반복
    let bob: [Int]?
    /// 앱이 쓸 방향 이름 (없으면 리그 방향)
    let direction: String?
    /// 있으면 그 열을 위에서 아래로 읽음 (열 = 방향, 줄 = 프레임인 시트). 없으면 첫 줄을 왼쪽에서 오른쪽으로
    let column: Int?
}

/// 남이 그린 스프라이트 시트를 DeskPet 스킨으로 바꾸는 방법. `Assets/Rigs/<이름>.import.json`
///
/// ```json
/// { "name": "NinjaFrog", "skill": "slash_jump", "facing": "east",
///   "source": "Assets/Sources/PixelAdventure1/Ninja Frog", "frame": [32, 32], "canvas": 48,
///   "rest": "Idle",
///   "animations": { "Idle": { "file": "Idle (32x32).png" }, "Hang": { "file": "Fall (32x32).png", "bob": [0, 1, 1, 0] } },
///   "intervals": { "idle": 0.06 },
///   "hatAnchor": [6, -2],                          (선택: 모자 자리 보정, 도트 단위. x는 얼굴 쪽 +, y는 위 +)
///   "aim": 0.15,                                   (선택: 던지기 성격, 맞힐 확률에 더함. -0.5~0.5)
///   "crop": [5, 6, 22, 21], "scale": 2,            (선택: 칸 안 잘라 쓸 영역, 정수배 확대)
///   "animations": { "Walking": { "file": "Walk.png", "column": 2 } }   (선택: 열 단위 시트)
///   "credit": { "author": "Pixel Frog", "url": "…", "license": "CC0 1.0" } }
/// ```
struct ImportRecipe {
    let name: String
    let skill: String
    let facing: String
    let source: String
    let frameWidth: Int
    let frameHeight: Int
    let canvas: Int
    let rest: String
    let clips: [ImportedClip]
    let intervals: [String: Double]
    let credit: [String: String]
    /// 모자 자리 보정 (도트, 얼굴 쪽 x·위쪽 y). 없으면 몸 꼭대기 가운데
    var hatAnchor: [Double]?
    /// 던지기 성격 (맞힐 확률에 더하는 값)
    var aim: Double?
    /// 프레임 칸 안에서 쓸 영역 (x, y, 폭, 높이). 없으면 칸 전체
    var crop: (x: Int, y: Int, width: Int, height: Int)?
    /// 정수배 확대 (작은 16px 캐릭터용)
    var scale = 1

    /// 칸에 놓이는 크기
    var drawnWidth: Int { (crop?.width ?? frameWidth) * scale }
    var drawnHeight: Int { (crop?.height ?? frameHeight) * scale }

    static func load(_ url: URL) throws -> ImportRecipe {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ForgeError(description: "가져오기 설정을 읽을 수 없음: \(url.path)")
        }
        guard let name = json["name"] as? String, let source = json["source"] as? String,
              let frame = json["frame"] as? [Int], frame.count == 2,
              let table = json["animations"] as? [String: [String: Any]], !table.isEmpty else {
            throw ForgeError(description: "name, source, frame [폭, 높이], animations가 필요함: \(url.path)")
        }
        let clips = try table.keys.sorted().map { key -> ImportedClip in
            guard let entry = table[key] else { throw ForgeError(description: "\(key): 설정이 없음") }
            let files = (entry["files"] as? [String]) ?? (entry["file"] as? String).map { [$0] } ?? []
            guard !files.isEmpty else { throw ForgeError(description: "\(key): file 또는 files가 필요함") }
            return ImportedClip(key: key, files: files, frames: entry["frames"] as? [Int], bob: entry["bob"] as? [Int],
                                direction: entry["direction"] as? String, column: entry["column"] as? Int)
        }
        let rest = json["rest"] as? String ?? "Idle"
        guard clips.contains(where: { $0.key == rest }) else { throw ForgeError(description: "rest(\(rest)) 동작이 animations에 없음") }
        var recipe = ImportRecipe(
            name: name, skill: json["skill"] as? String ?? "big_jump", facing: json["facing"] as? String ?? "east",
            source: source, frameWidth: frame[0], frameHeight: frame[1], canvas: json["canvas"] as? Int ?? 48,
            rest: rest, clips: clips,
            intervals: (json["intervals"] as? [String: NSNumber])?.mapValues(\.doubleValue) ?? [:],
            credit: json["credit"] as? [String: String] ?? [:]
        )
        if let aim = json["aim"] as? NSNumber {
            guard abs(aim.doubleValue) <= 0.5 else { throw ForgeError(description: "aim은 -0.5~0.5") }
            recipe.aim = aim.doubleValue
        }
        if let anchor = json["hatAnchor"] as? [NSNumber] {
            guard anchor.count == 2 else { throw ForgeError(description: "hatAnchor는 [x, y] 두 수") }
            recipe.hatAnchor = anchor.map(\.doubleValue)
        }
        if let crop = json["crop"] as? [Int], crop.count == 4 {
            guard crop[0] >= 0, crop[1] >= 0, crop[2] > 0, crop[3] > 0,
                  crop[0] + crop[2] <= frame[0], crop[1] + crop[3] <= frame[1] else {
                throw ForgeError(description: "crop [x, y, 폭, 높이]가 프레임 칸을 벗어남")
            }
            recipe.crop = (crop[0], crop[1], crop[2], crop[3])
        }
        recipe.scale = max(1, json["scale"] as? Int ?? 1)
        return recipe
    }
}

/// This object is responsible for turning someone else's sprite sheets (frames laid side by side in strips)
/// into a DeskPet skin folder: slicing frames (from a row, or down one column of a direction-by-frame sheet),
/// optionally cropping each cell and enlarging small sprites by a whole number, dropping blank frames,
/// centring them on the 48x48 canvas, lining hang frames up with the rest pose, and writing PNGs plus `metadata.json`
/// (with the skill, frame timings and the original author's credit).
struct SheetImporter {
    let recipe: ImportRecipe
    let recipePath: String

    func render() throws -> (animations: [RenderedAnimation], warnings: [String]) {
        guard recipe.drawnWidth <= recipe.canvas, recipe.drawnHeight <= recipe.canvas else {
            throw ForgeError(description: "그릴 크기(\(recipe.drawnWidth)x\(recipe.drawnHeight))가 칸(\(recipe.canvas))보다 큼")
        }
        var warnings: [String] = []
        var animations: [RenderedAnimation] = []
        let restTop = try slice(recipe.clips.first { $0.key == recipe.rest }!).first.flatMap(Raster.topRow) ?? 0

        for clip in recipe.clips {
            var frames = try slice(clip)
            if frames.isEmpty {
                warnings.append("\(clip.key): 쓸 프레임이 없음")
                continue
            }
            if clip.key == "Hang" {
                // 손(맨 윗줄)을 대기 자세 맨 윗줄에 맞춤 (앱은 그 높이를 창 윗변에 붙임).
                // 매달린 몸이 대기 자세보다 길면 발이 잘리지 않는 데까지만 내림
                let maxBob = clip.bob?.max() ?? 0
                frames = frames.map { frame in
                    guard let top = Raster.topRow(frame), let bottom = Raster.bottomRow(frame) else { return frame }
                    let room = recipe.canvas - 2 - bottom - maxBob
                    return Raster.shiftedDown(frame, by: min(restTop - top, room))
                }
            }
            if let bob = clip.bob, !bob.isEmpty {
                let count = max(bob.count, frames.count)
                frames = (0..<count).map { index in Raster.shiftedDown(frames[index % frames.count], by: bob[index % bob.count]) }
            }
            if let lowest = frames.compactMap(Raster.bottomRow).max(), lowest >= recipe.canvas - 1 {
                warnings.append("\(clip.key): 프레임 아래가 칸 끝에 닿아 잘렸을 수 있음")
            }
            animations.append(RenderedAnimation(key: clip.key, frames: frames))
        }
        return (animations, warnings)
    }

    /// 파일들을 차례로 잘라 이어 붙인 뒤, 고른 프레임만 남김. 비어 있는 프레임은 뺌
    private func slice(_ clip: ImportedClip) throws -> [PixelGrid] {
        let all = try clip.files.flatMap { try cells(of: $0, column: clip.column) }
        let wanted = clip.frames ?? Array(all.indices)
        return wanted.filter { $0 < all.count }.compactMap { all[$0] }
    }

    /// 시트 하나를 프레임 칸으로 잘라 칸 가운데에 놓음 (빈 칸은 nil)
    private func cells(of file: String, column: Int?) throws -> [PixelGrid?] {
        let url = URL(fileURLWithPath: recipe.source).appendingPathComponent(file)
        let image = try Raster.readImage(url)
        let columns = image.width / recipe.frameWidth
        let rows = image.height / recipe.frameHeight
        guard columns > 0, rows > 0 else {
            throw ForgeError(description: "\(file): \(image.width)x\(image.height)는 \(recipe.frameWidth)x\(recipe.frameHeight) 프레임으로 자를 수 없음")
        }
        if let column, column >= columns {
            throw ForgeError(description: "\(file): \(column)번 열이 없음 (열 \(columns)개)")
        }
        // 칸 원점 목록: 열을 고르면 그 열의 위에서 아래, 아니면 첫 줄의 왼쪽에서 오른쪽
        let origins: [(x: Int, y: Int)] = column.map { column in
            (0..<rows).map { (column * recipe.frameWidth, $0 * recipe.frameHeight) }
        } ?? (0..<columns).map { ($0 * recipe.frameWidth, 0) }
        let area = recipe.crop ?? (0, 0, recipe.frameWidth, recipe.frameHeight)
        let scale = recipe.scale
        let left = (recipe.canvas - recipe.drawnWidth) / 2
        // 세로 가운데에 둠 (매달리기처럼 프레임을 내려도 아래가 잘리지 않게)
        let top = (recipe.canvas - recipe.drawnHeight) / 2
        return origins.map { cell -> PixelGrid? in
            var grid = Raster.blank(recipe.canvas)
            var filled = false
            for y in 0..<area.height {
                for x in 0..<area.width {
                    let pixel = image.pixels[(cell.y + area.y + y) * image.width + cell.x + area.x + x]
                    guard pixel.a >= 128 else { continue }
                    let color = RGBA(r: pixel.r, g: pixel.g, b: pixel.b, a: 255)
                    for dy in 0..<scale {
                        for dx in 0..<scale { grid[top + y * scale + dy][left + x * scale + dx] = color }
                    }
                    filled = true
                }
            }
            return filled ? grid : nil
        }
    }

    /// 스킨 폴더에 씀. SpriteForge가 만든 폴더가 아니면 덮어쓰지 않음
    func write(to folder: URL, animations: [RenderedAnimation]) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.path) {
            guard SkinBuilder.isGenerated(folder) else {
                throw ForgeError(description: "\(folder.path)은(는) SpriteForge가 만든 스킨이 아니라 덮어쓰지 않음")
            }
            try fm.removeItem(at: folder)
        }
        var animationTable: [String: [String: [String]]] = [:]
        for animation in animations {
            let direction = recipe.clips.first { $0.key == animation.key }?.direction ?? recipe.facing
            var paths: [String] = []
            for (index, frame) in animation.frames.enumerated() {
                let path = "animations/\(animation.key)/\(direction)/frame_\(String(format: "%03d", index)).png"
                try Raster.writePNG(frame, to: folder.appendingPathComponent(path))
                paths.append(path)
            }
            animationTable[animation.key] = [direction: paths]
        }
        guard let rest = animations.first(where: { $0.key == recipe.rest })?.frames.first else {
            throw ForgeError(description: "대기 자세 프레임이 없음")
        }
        let restPath = "rotations/\(recipe.facing).png"
        try Raster.writePNG(rest, to: folder.appendingPathComponent(restPath))

        var options: [String: Any] = ["skill": recipe.skill, "generator": SkinBuilder.generatorTag, "import": recipePath]
        if !recipe.intervals.isEmpty { options["intervals"] = recipe.intervals }
        if let anchor = recipe.hatAnchor { options["hatAnchor"] = anchor }
        if let aim = recipe.aim { options["aim"] = aim }
        if !recipe.credit.isEmpty { options["credit"] = recipe.credit }
        let metadata: [String: Any] = [
            "deskpet": options,
            "states": [["frames": ["rotations": [recipe.facing: restPath], "animations": animationTable]]],
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: folder.appendingPathComponent("metadata.json"))
    }
}
