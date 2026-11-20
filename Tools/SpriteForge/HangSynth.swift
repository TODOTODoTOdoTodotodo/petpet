import Foundation

/// 원본(통짜 이미지) 스킨에 매달리기 프레임을 만드는 방법. `Assets/Rigs/<스킨>.hang.json`
///
/// ```json
/// {
///   "skin": "Goblin",
///   "base": "small_goblin.../rotations/north.png",
///   "direction": "north",
///   "arms": [{ "at": [16, 26], "size": [4, 5] }, { "at": [28, 26], "size": [4, 5] }],
///   "legsFrom": 34
/// }
/// ```
/// - base: 매달린 모습의 바탕 (뒷모습이 있으면 뒷모습, 없으면 정면). 스킨 폴더 기준 경로
/// - arms: 팔(손 포함)만 들어 있는 사각형. 윗줄이 어깨, 아랫줄이 손 끝.
///   선택 "shift": 든 팔을 옆으로 옮길 칸 수 (머리가 큰 정면 캐릭터는 머리 가운데 쪽으로 모아 팔을 머리 뒤에 숨김)
/// - legsFrom: 이 줄부터 아래는 다리 (흔들림용)
/// - reach (선택, 기본 2): 손끝이 머리 위로 올라가는 줄 수
struct HangRecipe {
    struct Arm {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        /// 든 팔의 가로 이동
        var shift = 0

        func contains(_ x: Int, _ y: Int) -> Bool {
            x >= self.x && x < self.x + width && y >= self.y && y < self.y + height
        }
    }

    let skin: String
    let base: String
    let direction: String
    let arms: [Arm]
    let legsFrom: Int
    var reach = 2

    static func load(_ url: URL) throws -> HangRecipe {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ForgeError(description: "매달리기 설정을 읽을 수 없음: \(url.path)")
        }
        guard let skin = json["skin"] as? String, let base = json["base"] as? String,
              let direction = json["direction"] as? String, let legsFrom = json["legsFrom"] as? Int,
              let armList = json["arms"] as? [[String: Any]], !armList.isEmpty else {
            throw ForgeError(description: "skin, base, direction, arms, legsFrom이 필요함: \(url.path)")
        }
        let arms = try armList.map { arm -> Arm in
            guard let at = arm["at"] as? [Int], let size = arm["size"] as? [Int], at.count == 2, size.count == 2,
                  size[0] > 0, size[1] > 1 else {
                throw ForgeError(description: "팔 사각형은 at [x, y], size [폭, 높이≥2]: \(arm)")
            }
            return Arm(x: at[0], y: at[1], width: size[0], height: size[1], shift: arm["shift"] as? Int ?? 0)
        }
        return HangRecipe(skin: skin, base: base, direction: direction, arms: arms, legsFrom: legsFrom,
                          reach: json["reach"] as? Int ?? 2)
    }

    /// 바탕 이미지가 있는 묶음 폴더 ("rotations/" 앞부분, 없으면 빈 문자열)
    var assetRoot: String {
        guard let range = base.range(of: "rotations/") else { return "" }
        return String(base[..<range.lowerBound])
    }

    func framePath(_ index: Int) -> String {
        "\(assetRoot)animations/Hang/\(direction)/frame_\(String(format: "%03d", index)).png"
    }
}

/// This object is responsible for making hang frames for a hand-drawn (single-image) skin:
/// it lifts the arm pixels out of a still pose, flips them above the head (stretching the sleeve to reach),
/// lowers the body so the hands sit where the app expects the window edge, and sways body and legs over 4 frames.
/// Pure pixel moves, so the original art style is kept.
struct HangSynth {
    /// 프레임별 (몸이 처지는 줄 수, 다리가 흔들리는 칸 수)
    static let sway: [(drop: Int, swing: Int)] = [(0, 0), (1, 1), (0, 0), (1, -1)]

    let recipe: HangRecipe
    /// 스킨 폴더
    let skinFolder: URL

    func render() throws -> (frames: [PixelGrid], warnings: [String]) {
        var base = try Self.grid(from: skinFolder.appendingPathComponent(recipe.base))
        let size = base.count
        var warnings: [String] = []

        // 1. 팔을 떼어 냄
        let arms = recipe.arms.map { arm -> PixelGrid in
            (0..<arm.height).map { row in
                (0..<arm.width).map { column in
                    let (x, y) = (arm.x + column, arm.y + row)
                    return x < size && y < size ? base[y][x] : nil
                }
            }
        }
        for arm in recipe.arms {
            for y in arm.y..<min(arm.y + arm.height, size) {
                for x in arm.x..<min(arm.x + arm.width, size) { base[y][x] = nil }
            }
        }
        for (index, arm) in arms.enumerated() where !arm.joined().contains(where: { $0 != nil }) {
            warnings.append("\(index + 1)번 팔 사각형이 비어 있음")
        }
        repairEdges(&base)

        // 2. 손끝이 앱이 창 윗변에 붙이는 줄(대기 자세 맨 윗줄)에 오도록 몸을 내림
        guard let headTop = Raster.topRow(base) else { throw ForgeError(description: "바탕 이미지가 비어 있음") }
        let gripRow = try idleTopRow()
        let lower = gripRow + recipe.reach - headTop

        // 3. 프레임마다 팔을 위로 뒤집어 그리고, 그 위에 몸을 덮음
        let frames = Self.sway.map { pose -> PixelGrid in
            var frame = Raster.blank(size)
            for (arm, pixels) in zip(recipe.arms, arms) {
                let shoulder = arm.y + lower + pose.drop
                let raised = Self.raised(pixels, length: shoulder - gripRow + 1)
                for (row, line) in raised.enumerated() {
                    for (column, color) in line.enumerated() {
                        guard let color else { continue }
                        let (x, y) = (arm.x + arm.shift + column, gripRow + row)
                        if x >= 0, x < size, y >= 0, y < size { frame[y][x] = color }
                    }
                }
            }
            for (y, line) in base.enumerated() {
                for (x, color) in line.enumerated() {
                    guard let color else { continue }
                    let targetY = y + lower + pose.drop
                    let targetX = x + (y >= recipe.legsFrom ? pose.swing : 0)
                    guard targetY < size, targetX >= 0, targetX < size else { continue }
                    frame[targetY][targetX] = color
                }
            }
            return frame
        }
        if let bottom = Raster.bottomRow(base), bottom + lower + 1 >= size {
            warnings.append("몸을 \(lower + 1)줄 내리면 발이 칸 밖으로 나감")
        }
        if lower < 0 { warnings.append("머리가 대기 자세보다 높아 손을 올릴 자리가 없음") }
        return (frames, warnings)
    }

    /// 스킨 폴더에 프레임을 쓰고, metadata.json의 첫 상태에 Hang 동작을 등록
    func write(_ frames: [PixelGrid], to folder: URL, registers: Bool) throws {
        let paths = frames.indices.map(recipe.framePath)
        let hangFolder = folder.appendingPathComponent("\(recipe.assetRoot)animations/Hang")
        try? FileManager.default.removeItem(at: hangFolder)
        for (frame, path) in zip(frames, paths) {
            try Raster.writePNG(frame, to: folder.appendingPathComponent(path))
        }
        guard registers else { return }

        let metaURL = folder.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metaURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var states = json["states"] as? [[String: Any]], var first = states.first,
              var framesTable = first["frames"] as? [String: Any] else {
            throw ForgeError(description: "metadata.json을 읽을 수 없음: \(metaURL.path)")
        }
        var animations = framesTable["animations"] as? [String: Any] ?? [:]
        animations["Hang"] = [recipe.direction: paths]
        framesTable["animations"] = animations
        first["frames"] = framesTable
        states[0] = first
        json["states"] = states
        let encoded = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        // 키 뒤 공백 없는 일반적인 JSON 모양으로 맞춤
        let normalized = String(decoding: encoded, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: #"^(\s*"[^"]*") : "#, with: "$1: ", options: .regularExpression) }
            .joined(separator: "\n")
        try Data((normalized + "\n").utf8).write(to: metaURL)
    }

    // MARK: - Steps

    /// 위로 든 팔: 손이 위, 어깨가 아래. 모자라는 길이는 어깨 줄(소매)을 반복해 채움
    static func raised(_ arm: PixelGrid, length: Int) -> PixelGrid {
        let flipped = Array(arm.reversed())
        guard length > flipped.count, let shoulder = flipped.last else { return flipped }
        return flipped + Array(repeating: shoulder, count: length - flipped.count)
    }

    /// 팔을 뗀 자리 옆의 몸 가장자리가 밝으면 외곽선 색으로 칠함
    private func repairEdges(_ grid: inout PixelGrid) {
        let outline = Self.darkest(in: grid)
        let size = grid.count
        for arm in recipe.arms {
            for y in arm.y..<min(arm.y + arm.height, size) {
                for x in [arm.x - 1, arm.x + arm.width] where x >= 0 && x < size {
                    guard let color = grid[y][x], !recipe.arms.contains(where: { $0.contains(x, y) }),
                          Self.luminance(color) > 0.22 else { continue }
                    grid[y][x] = outline
                }
            }
        }
    }

    /// 앱이 몸 크기를 재는 대기 이미지들(rotations)의 맨 윗줄
    private func idleTopRow() throws -> Int {
        let files = FileManager.default.enumerator(at: skinFolder, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "png" && $0.deletingLastPathComponent().lastPathComponent == "rotations" } ?? []
        let tops = try files.compactMap { Raster.topRow(try Self.grid(from: $0)) }
        guard let top = tops.min() else { throw ForgeError(description: "rotations 이미지를 찾을 수 없음: \(skinFolder.path)") }
        return top
    }

    static func grid(from url: URL) throws -> PixelGrid {
        let image = try Raster.readImage(url)
        return (0..<image.height).map { y in
            (0..<image.width).map { x in
                let pixel = image.pixels[y * image.width + x]
                return pixel.a < 128 ? nil : RGBA(r: pixel.r, g: pixel.g, b: pixel.b, a: 255)
            }
        }
    }

    private static func darkest(in grid: PixelGrid) -> RGBA {
        grid.joined().compactMap { $0 }.min { luminance($0) < luminance($1) } ?? RGBA(r: 0, g: 0, b: 0, a: 255)
    }

    private static func luminance(_ color: RGBA) -> Double {
        (0.2126 * Double(color.r) + 0.7152 * Double(color.g) + 0.0722 * Double(color.b)) / 255
    }
}
