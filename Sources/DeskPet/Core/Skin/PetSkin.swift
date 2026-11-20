import Foundation

/// 그릴 프레임과 좌우 반전 여부. Frame은 플랫폼 텍스처 (맥은 SKTexture)
struct SpriteFrame<Frame> {
    let texture: Frame
    let mirrored: Bool
}

/// 그림 한 장을 읽은 결과: 플랫폼이 그릴 프레임과, 빈 칸·몸 크기 측정용 픽셀
struct LoadedSprite<Frame> {
    let frame: Frame
    /// 읽지 못했으면 nil (그 프레임은 쓰되 측정은 건너뜀)
    let pixels: SpritePixels?
}

/// 동작별 기본 프레임 간격 (제네릭 타입 안에는 정적 저장 속성을 둘 수 없어 밖에 둠)
private enum FrameInterval {
    static let walk: TimeInterval = 0.11
    static let climb: TimeInterval = 0.13
    static let act: TimeInterval = 0.10
    static let idle: TimeInterval = 0.18
    static let jump: TimeInterval = 0.12
    static let hang: TimeInterval = 0.25
    static let sleep: TimeInterval = 0.6
}

/// This object is responsible for loading one character's sprite frames from its folder
/// (`metadata.json` + PNGs) and choosing the frame to draw for an animation, facing and time.
/// Decoding a PNG into a drawable frame is left to the platform through `loader`.
final class PetSkin<Frame>: PetAppearance {
    let name: String
    let basePath: URL
    private let loader: (URL) -> LoadedSprite<Frame>?
    private(set) var idleTextures: [Facing: Frame] = [:]
    private(set) var walkTextures: [Facing: [Frame]] = [:]
    private(set) var actionTextures: [Facing: [Frame]] = [:]
    /// 선택 동작 칸 (없으면 대기 이미지 등으로 대체)
    private(set) var idleLoopTextures: [Facing: [Frame]] = [:]
    private(set) var jumpTextures: [Facing: [Frame]] = [:]
    private(set) var hangTextures: [Facing: [Frame]] = [:]
    private(set) var sleepTextures: [Facing: [Frame]] = [:]
    private(set) var climbTextures: [Facing: [Frame]] = [:]
    /// 픽셀이 없어 로드에서 제외한 프레임 수
    private(set) var blankFrameCount = 0
    private(set) var body: BodyMetrics = .fullFrame
    /// 도약 스킬 (metadata.json의 "deskpet": {"skill": ...}, 없으면 기본 큰 점프)
    private(set) var skillStyle: SkillStyle = .bigJump
    /// 모자 자리 보정 (metadata.json의 "deskpet": {"hatAnchor": [dx, dy]}, 스킨 도트 단위)
    private(set) var hatAnchor: CGVector = .zero
    private var idleBounds: CGRect?
    /// 동작별 프레임 간격 덮어쓰기 (metadata.json의 "deskpet": {"intervals": {"idle": 0.06}})
    private var intervalOverrides: [AnimationKind: TimeInterval] = [:]

    init(name: String, directory: URL, loader: @escaping (URL) -> LoadedSprite<Frame>?) {
        self.name = name
        self.basePath = directory
        self.loader = loader
        load()
        if let bounds = idleBounds {
            body = BodyMetrics(footInset: bounds.minY, width: bounds.width, height: bounds.height, centerX: bounds.midX)
        }
    }

    // MARK: - PetAppearance

    func supports(_ kind: AnimationKind) -> Bool {
        kind == .act ? !actionTextures.isEmpty : true
    }

    func cycleDuration(of kind: AnimationKind, facing: Facing) -> TimeInterval {
        guard let clip = clip(for: kind, facing: facing) else { return 0 }
        return Double(clip.frames.count) * clip.interval
    }

    // MARK: - Frame choice

    func sprite(for kind: AnimationKind, facing: Facing, elapsed: TimeInterval) -> SpriteFrame<Frame>? {
        guard let clip = clip(for: kind, facing: facing), !clip.frames.isEmpty else { return nil }
        let tick = Int(elapsed / clip.interval)
        // 동작은 한 번만 재생하고 마지막 프레임에서 멈춤
        let index = kind == .act ? min(tick, clip.frames.count - 1) : tick % clip.frames.count
        return SpriteFrame(texture: clip.frames[index], mirrored: clip.mirrored)
    }

    // MARK: - Clip selection

    private struct Clip {
        let frames: [Frame]
        let mirrored: Bool
        let interval: TimeInterval
    }

    private func clip(for kind: AnimationKind, facing: Facing) -> Clip? {
        guard let base = defaultClip(for: kind, facing: facing) else { return nil }
        guard let interval = intervalOverrides[kind], base.interval != 1 else { return base }
        return Clip(frames: base.frames, mirrored: base.mirrored, interval: interval)
    }

    private func defaultClip(for kind: AnimationKind, facing: Facing) -> Clip? {
        let stills = idleTextures.mapValues { [$0] }
        switch kind {
        case .idle:
            // 정면을 보라는 요청(south)은 정면 이미지가 있으면 그것을 우선
            if facing == .south, let front = idleTextures[.south] {
                return Clip(frames: [front], mirrored: false, interval: 1)
            }
            return sided(idleLoopTextures, facing: facing, interval: FrameInterval.idle)
                ?? sided(stills, facing: facing, interval: 1)
        case .airborne:
            return sided(jumpTextures, facing: facing, interval: FrameInterval.jump)
                ?? sided(stills, facing: facing, interval: 1)
        case .dragged:
            return sided(stills, facing: .south, interval: 1)
        case .hang:
            return sided(hangTextures, facing: facing, interval: FrameInterval.hang)
                ?? sided(stills, facing: .south, interval: 1)
        case .sleep:
            return sided(sleepTextures, facing: facing, interval: FrameInterval.sleep)
                ?? sided(stills, facing: .south, interval: 1)
        case .walk:
            return sided(walkTextures, facing: facing, interval: FrameInterval.walk)
                ?? sided(stills, facing: facing, interval: 1)
        case .climb:
            // 전용 오르기(뒷모습) → 전용 오르기(옆, 벽 쪽 방향 기준) → 뒷모습 걷기 → 벽 쪽을 향한 걷기
            if let climb = climbTextures[.north], !climb.isEmpty {
                return Clip(frames: climb, mirrored: false, interval: FrameInterval.climb)
            }
            if let side = sided(climbTextures.filter { $0.key == .east || $0.key == .west }, facing: facing, interval: FrameInterval.climb) {
                return side
            }
            if let climb = climbTextures.values.first, !climb.isEmpty {
                return Clip(frames: climb, mirrored: false, interval: FrameInterval.climb)
            }
            if let back = walkTextures[.north], !back.isEmpty {
                return Clip(frames: back, mirrored: false, interval: FrameInterval.climb)
            }
            return sided(walkTextures, facing: facing, interval: FrameInterval.climb)
                ?? sided(stills, facing: facing, interval: 1)
        case .act:
            return sided(actionTextures, facing: facing, interval: FrameInterval.act)
        }
    }

    /// 그 방향 이미지가 있으면 그대로, 없으면 반대 방향을 좌우 반전, 그것도 없으면 정면
    private func sided(_ table: [Facing: [Frame]], facing: Facing, interval: TimeInterval) -> Clip? {
        if let frames = table[facing], !frames.isEmpty {
            return Clip(frames: frames, mirrored: false, interval: interval)
        }
        if facing == .east || facing == .west, let frames = table[facing.opposite], !frames.isEmpty {
            return Clip(frames: frames, mirrored: true, interval: interval)
        }
        if let frames = table[.south], !frames.isEmpty {
            return Clip(frames: frames, mirrored: false, interval: interval)
        }
        return table.values.first { !$0.isEmpty }.map { Clip(frames: $0, mirrored: false, interval: interval) }
    }

    // MARK: - Loading

    private func load() {
        let metaURL = basePath.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metaURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let states = json["states"] as? [[String: Any]] else {
            return
        }
        if let options = json["deskpet"] as? [String: Any] {
            if let skill = (options["skill"] as? String).flatMap(SkillStyle.init(rawValue:)) {
                skillStyle = skill
            }
            if let pair = options["hatAnchor"] as? [Any], pair.count == 2 {
                let number = { (value: Any) in (value as? NSNumber)?.doubleValue ?? (value as? Double) ?? 0 }
                hatAnchor = CGVector(dx: number(pair[0]), dy: number(pair[1]))
            }
            for (key, value) in options["intervals"] as? [String: Any] ?? [:] {
                // 숫자가 NSNumber로 오지 않는 Foundation(윈도우 등)도 있어 Double도 받음
                let seconds = (value as? NSNumber)?.doubleValue ?? (value as? Double) ?? 0
                guard let kind = AnimationKind(rawValue: key), seconds > 0 else { continue }
                intervalOverrides[kind] = seconds
            }
        }

        // 뒤 상태의 회전 이미지가 앞 상태를 덮어씀 (Radish의 별도 대기 상태)
        for state in states {
            let frames = state["frames"] as? [String: Any] ?? [:]
            for (key, path) in frames["rotations"] as? [String: String] ?? [:] {
                guard let facing = Facing(rawValue: key), let texture = loadTexture(path, measuresBody: true) else { continue }
                idleTextures[facing] = texture
            }
        }

        let animations = (states.first?["frames"] as? [String: Any])?["animations"] as? [String: Any] ?? [:]
        let keys = animations.keys.sorted()
        if let walkKey = keys.first(where: { $0.contains("Walk") || $0.contains("Run") }) {
            walkTextures = loadDirectionalFrames(animations[walkKey])
        }
        if let actionKey = keys.first(where: { $0.lowercased().contains("attack") || $0.lowercased().contains("swing") }) {
            actionTextures = loadDirectionalFrames(animations[actionKey])
        }
        // 선택 동작 칸은 이름이 정확히 같을 때만 (Blink 같은 다른 대기 변형과 섞이지 않게)
        idleLoopTextures = loadDirectionalFrames(animations["Idle"])
        jumpTextures = loadDirectionalFrames(animations["Jump"])
        hangTextures = loadDirectionalFrames(animations["Hang"])
        sleepTextures = loadDirectionalFrames(animations["Sleep"])
        climbTextures = loadDirectionalFrames(animations["Climb"])
    }

    /// 방향별 프레임 목록. "south-25d6d0a4"처럼 변형이 여럿이면 정렬상 첫 번째만 사용
    private func loadDirectionalFrames(_ value: Any?) -> [Facing: [Frame]] {
        guard let table = value as? [String: Any] else { return [:] }
        var result: [Facing: [Frame]] = [:]
        for key in table.keys.sorted() {
            guard let facing = Facing.allCases.first(where: { key.hasPrefix($0.rawValue) }),
                  result[facing] == nil,
                  let paths = table[key] as? [String] else { continue }
            let textures = paths.compactMap { loadTexture($0, measuresBody: false) }
            if !textures.isEmpty {
                result[facing] = textures
            }
        }
        return result
    }

    private func loadTexture(_ relativePath: String, measuresBody: Bool) -> Frame? {
        guard let loaded = loader(basePath.appendingPathComponent(relativePath)) else { return nil }
        if let pixels = loaded.pixels {
            switch SpriteAlphaScanner.scan(pixels) {
            case .blank:
                // 시트 분할 시 생긴 투명 칸은 애니메이션 중 깜빡임을 만들므로 제외함
                blankFrameCount += 1
                return nil
            case .visible(let bounds) where measuresBody:
                let unit = Pet.frameSide / CGFloat(pixels.width)
                let scaled = CGRect(x: bounds.minX * unit, y: bounds.minY * unit, width: bounds.width * unit, height: bounds.height * unit)
                idleBounds = idleBounds.map { $0.union(scaled) } ?? scaled
            case .visible, .unreadable:
                break
            }
        }
        return loaded.frame
    }
}
