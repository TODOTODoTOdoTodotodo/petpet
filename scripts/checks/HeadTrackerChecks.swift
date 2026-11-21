import Foundation

/// This object is responsible for checking that hats follow the head frame by frame:
/// the head template finds a moved head, ignores raised arms, falls back when the head is gone,
/// real skins give small believable shifts, and HatPlacement adds the current frame's shift.
enum HeadTrackerChecks {
    static func run(_ check: Checker, skinsDirectory: URL) {
        check.section("Head tracking (hat follows head)")
        synthetic(check)
        placement(check)
        realSkins(check, skinsDirectory: skinsDirectory)
    }

    // MARK: - 만든 그림

    /// 16x16 그림: 머리(빨강 6x4)와 몸(파랑 6x6). headDrop만큼 머리를 내림
    private static func figure(headDrop: Int = 0, headSlide: Int = 0, raisedArm: Bool = false, bodyOnly: Bool = false) -> SpritePixels {
        let side = 16
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        func paint(_ column: Int, _ row: Int, _ color: (UInt8, UInt8, UInt8)) {
            let i = (row * side + column) * 4
            rgba[i] = color.0; rgba[i + 1] = color.1; rgba[i + 2] = color.2; rgba[i + 3] = 255
        }
        if !bodyOnly {
            for row in 4..<8 { for column in 5..<11 { paint(column + headSlide, row + headDrop, (220, 40, 40)) } }
            // 눈 (본 안의 다른 색)
            paint(6 + headSlide, 5 + headDrop, (20, 20, 20))
        }
        for row in 8..<14 { for column in 5..<11 { paint(column, row, (40, 60, 220)) } }
        if raisedArm {
            // 머리 위로 뻗은 팔 (노랑)
            for row in 0..<8 { paint(11, row, (240, 200, 40)) }
        }
        return SpritePixels(width: side, height: side, rgba: rgba)
    }

    private static func synthetic(_ check: Checker) {
        guard let template = HeadTracker.template(from: figure()) else {
            check.expect(false, "머리 본 만들기")
            return
        }
        check.expect(HeadTracker.shift(of: figure(), from: template) == .zero, "같은 그림이면 0")
        check.expect(HeadTracker.shift(of: figure(headDrop: 2), from: template) == CGVector(dx: 0, dy: -2),
                     "머리가 2칸 내려가면 y -2", "\(String(describing: HeadTracker.shift(of: figure(headDrop: 2), from: template)))")
        check.expect(HeadTracker.shift(of: figure(headDrop: -1, headSlide: 2), from: template) == CGVector(dx: 2, dy: 1),
                     "머리가 앞으로 2칸·위로 1칸이면 (2, 1)")
        check.expect(HeadTracker.shift(of: figure(raisedArm: true), from: template) == .zero,
                     "머리 위로 뻗은 팔은 머리로 보지 않음", "\(String(describing: HeadTracker.shift(of: figure(raisedArm: true), from: template)))")
        // 머리가 사라지면 윗줄이 내려간 만큼만 (몸 꼭대기 8번 줄 - 머리 꼭대기 4번 줄)
        check.expect(HeadTracker.shift(of: figure(bodyOnly: true), from: template) == CGVector(dx: 0, dy: -4),
                     "머리를 못 찾으면 낮아진 윗줄을 따라감")
        if let mirrored = HeadTracker.template(from: figure(headSlide: 3), mirrored: true) {
            check.expect(HeadTracker.shift(of: figure(headSlide: 3).mirrored(), from: mirrored) == .zero,
                         "반대 방향 그림을 뒤집어 만든 본도 맞음")
        }
        let wrongSize = SpritePixels(width: 8, height: 8, rgba: [UInt8](repeating: 255, count: 256))
        check.expect(HeadTracker.shift(of: wrongSize, from: template) == nil, "크기가 다른 그림은 재지 않음")
    }

    // MARK: - 모자 자리

    /// 머리가 늘 (1, -2) 옮겨 간 모습
    private final class Bobbing: PetAppearance {
        let name = "Bobbing"
        let body = BodyMetrics(footInset: 0, width: 20, height: 30, centerX: 24)
        let skillStyle: SkillStyle = .bigJump
        func supports(_ kind: AnimationKind) -> Bool { true }
        func cycleDuration(of kind: AnimationKind, facing: Facing) -> TimeInterval { 1 }
        func headShift(for kind: AnimationKind, facing: Facing, elapsed: TimeInterval) -> CGVector {
            CGVector(dx: 1, dy: -2)
        }
    }

    private static func placement(_ check: Checker) {
        let hat = HatCatalog.hat("acorn_cap")!
        let still = Sim.pet(at: CGPoint(x: 500, y: 80), appearance: FakeAppearance(), behavior: IdleBehavior(duration: 99))
        let bobbing = Sim.pet(at: CGPoint(x: 500, y: 80), appearance: Bobbing(), behavior: IdleBehavior(duration: 99))
        bobbing.scale = still.scale
        let s = still.scale
        let base = HatPlacement.frame(of: hat, on: still).rect
        let moved = HatPlacement.frame(of: hat, on: bobbing).rect
        // FakeAppearance 몸 높이 40, Bobbing 30이라 그 차이를 빼고 비교
        let heightGap = (CGFloat(40) - 30) * s
        let gapX: CGFloat = moved.minX - base.minX - s
        let gapY: CGFloat = moved.minY - (base.minY - heightGap - 2 * s)
        check.expect(abs(gapX) < 0.01 && abs(gapY) < 0.01,
                     "모자가 지금 프레임의 머리 이동만큼 옮겨 감", "\(base) → \(moved)")
    }

    // MARK: - 실제 스킨

    private static func realSkins(_ check: Checker, skinsDirectory: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: skinsDirectory.path))?.sorted() ?? []
        var measured = 0
        var largest = CGVector.zero
        var worst = ""
        for name in names {
            let folder = skinsDirectory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("metadata.json").path) else { continue }
            let skin = PetSkin(name: name, directory: folder, loader: DecodedFrame.load)
            var line: [String] = []
            for kind in [AnimationKind.idle, .walk, .airborne, .act, .hang, .sleep, .climb] {
                let duration = skin.cycleDuration(of: kind, facing: .west)
                guard duration > 0 else { continue }
                var shifts: [CGVector] = []
                var t = 0.0
                while t < duration { shifts.append(skin.headShift(for: kind, facing: .west, elapsed: t)); t += 0.05 }
                let dys = shifts.map(\.dy), dxs = shifts.map(\.dx)
                line.append("\(kind.rawValue) y\(fmt(dys.min()!))~\(fmt(dys.max()!)) x\(fmt(dxs.min()!))~\(fmt(dxs.max()!))")
                for shift in shifts {
                    measured += 1
                    if max(abs(shift.dx), abs(shift.dy)) > max(abs(largest.dx), abs(largest.dy)) {
                        largest = shift
                        worst = "\(name) \(kind.rawValue)"
                    }
                }
                // 오른쪽을 보면 x가 반대
                let west = skin.headShift(for: kind, facing: .west, elapsed: 0)
                let east = skin.headShift(for: kind, facing: .east, elapsed: 0)
                if abs(west.dx + east.dx) > 0.01 && abs(west.dx - east.dx) > 0.01 {
                    check.expect(false, "\(name) \(kind.rawValue) 좌우 대칭", "\(west) \(east)")
                }
            }
            if ProcessInfo.processInfo.environment["DESKPET_HEAD_REPORT"] != nil {
                print("    \(name): " + line.joined(separator: " | "))
            }
            check.expect(skin.headShift(for: .dragged, facing: .south, elapsed: 0) == .zero, "\(name) 들린 정지 그림은 이동 없음")
        }
        // 찾는 범위가 ±4·±6 이미지 픽셀이라 48칸 기준으로도 그 안 (32px 그림은 1.5배)
        check.expect(measured > 0 && abs(largest.dx) <= 6.01 && abs(largest.dy) <= 9.01,
                     "실제 스킨 머리 이동이 찾는 범위 안 (\(measured)개 프레임)", "\(worst) \(largest)")
    }

    private static func fmt(_ value: CGFloat) -> String { String(format: "%.1f", Double(value)) }
}
