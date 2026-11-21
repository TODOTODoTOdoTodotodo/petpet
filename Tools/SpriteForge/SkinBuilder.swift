import Foundation

/// 만든 동작 하나 (프레임 격자 목록)
struct RenderedAnimation {
    let key: String
    let frames: [PixelGrid]
}

/// This object is responsible for turning a rig into a DeskPet skin folder:
/// rendering every animation, checking frames, and writing PNGs plus `metadata.json` in the app's format.
struct SkinBuilder {
    /// 이 도구가 만든 스킨임을 표시 (다른 스킨을 덮어쓰지 않기 위함)
    static let generatorTag = "SpriteForge"

    let rig: Rig
    let rigPath: String

    /// 모든 동작을 그리고 문제(빈 프레임, 칸 밖 픽셀)를 모음
    func render() -> (animations: [RenderedAnimation], warnings: [String]) {
        var warnings: [String] = []
        let idleTop = Raster.topRow(Raster.render(rig, pose: Pose()).grid) ?? 0
        let animations = Poser.animations(facingWest: rig.facingWest).map { animation -> RenderedAnimation in
            let frames = animation.frames.enumerated().map { index, pose -> PixelGrid in
                let (grid, clipped, handTop) = Raster.render(rig, pose: pose)
                if clipped > 0 { warnings.append("\(animation.key) \(index)번 프레임: \(clipped)픽셀이 칸 밖으로 나감") }
                guard animation.alignTopToIdle, let top = handTop ?? Raster.topRow(grid) else { return grid }
                // 손끝을 대기 자세의 맨 윗줄 높이에 맞춤 (앱은 그 높이를 창 윗변에 붙임)
                let shift = idleTop - top
                if shift < 0, let gridTop = Raster.topRow(grid), gridTop + shift < 0 {
                    warnings.append("\(animation.key) \(index)번 프레임: 손 높이를 맞추면 위쪽이 잘림")
                }
                return Raster.shiftedDown(grid, by: shift)
            }
            for (index, frame) in frames.enumerated() where Raster.topRow(frame) == nil {
                warnings.append("\(animation.key) \(index)번 프레임이 비어 있음")
            }
            return RenderedAnimation(key: animation.key, frames: frames)
        }
        return (animations, warnings)
    }

    /// 스킨 폴더에 씀. 이 도구가 만든 폴더가 아니면 덮어쓰지 않음
    func write(to folder: URL, animations: [RenderedAnimation]) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.path) {
            guard Self.isGenerated(folder) else {
                throw ForgeError(description: "\(folder.path)은(는) SpriteForge가 만든 스킨이 아니라 덮어쓰지 않음")
            }
            try fm.removeItem(at: folder)
        }
        let direction = rig.directionName
        var animationTable: [String: [String: [String]]] = [:]
        for animation in animations {
            var paths: [String] = []
            for (index, frame) in animation.frames.enumerated() {
                let path = "animations/\(animation.key)/\(direction)/frame_\(String(format: "%03d", index)).png"
                try Raster.writePNG(frame, to: folder.appendingPathComponent(path))
                paths.append(path)
            }
            animationTable[animation.key] = [direction: paths]
        }

        let restPath = "rotations/\(direction).png"
        try Raster.writePNG(Raster.render(rig, pose: Pose()).grid, to: folder.appendingPathComponent(restPath))

        var options: [String: Any] = ["skill": rig.skill, "generator": Self.generatorTag, "rig": rigPath]
        if let aim = rig.aim { options["aim"] = aim }
        let metadata: [String: Any] = [
            "deskpet": options,
            "states": [["frames": ["rotations": [direction: restPath], "animations": animationTable]]],
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: folder.appendingPathComponent("metadata.json"))
    }

    static func isGenerated(_ folder: URL) -> Bool {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("metadata.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let options = json["deskpet"] as? [String: Any] else { return false }
        return options["generator"] as? String == generatorTag
    }
}
