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
    /// 던지기 성격 (metadata.json의 "deskpet": {"aim": 0.15}, 맞힐 확률에 더함)
    private(set) var aimBias: Double = 0
    private var idleBounds: CGRect?
    /// 방향별 서 있는 그림 픽셀 (머리 본의 기준)
    private var referencePixels: [Facing: SpritePixels] = [:]
    private var headTemplates: [Facing: HeadTracker.Template?] = [:]
    private var handTemplates: [Facing: HeadTracker.Template?] = [:]
    /// 동작 칸별·방향별 프레임마다 머리·손이 옮겨 간 정도 (스킨 도트 단위, 그림 기준 x 오른쪽 +, y 위 +)
    private var headShifts: [String: [Facing: [BoneShift]]] = [:]
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
        return SpriteFrame(texture: clip.frames[clip.index(at: elapsed, for: kind)], mirrored: clip.mirrored)
    }

    /// 지금 그리는 프레임에서 머리가 서 있는 그림보다 옮겨 간 정도 (스킨 도트 단위, 화면 기준 x 오른쪽 +, y 위 +)
    func headShift(for kind: AnimationKind, facing: Facing, elapsed: TimeInterval) -> CGVector {
        guard let clip = clip(for: kind, facing: facing), !clip.frames.isEmpty else { return .zero }
        let index = clip.index(at: elapsed, for: kind)
        guard index < clip.heads.count else { return .zero }
        let shift = clip.heads[index].head
        // 좌우 반전해 그리면 x도 반대
        return CGVector(dx: clip.mirrored ? -shift.dx : shift.dx, dy: shift.dy)
    }

    /// 지금 그리는 프레임에서 앞손(물건 드는 손)이 서 있는 그림보다 옮겨 간 정도. 손을 못 찾은 프레임은 머리 이동
    func handShift(for kind: AnimationKind, facing: Facing, elapsed: TimeInterval) -> CGVector {
        guard let clip = clip(for: kind, facing: facing), !clip.frames.isEmpty else { return .zero }
        let index = clip.index(at: elapsed, for: kind)
        guard index < clip.heads.count else { return .zero }
        let shift = clip.heads[index].hand
        return CGVector(dx: clip.mirrored ? -shift.dx : shift.dx, dy: shift.dy)
    }

    // MARK: - Clip selection

    private struct Clip {
        let frames: [Frame]
        let mirrored: Bool
        let interval: TimeInterval
        /// 프레임마다 머리·손 이동 (비었으면 움직이지 않는 것으로 봄)
        var heads: [BoneShift] = []

        func index(at elapsed: TimeInterval, for kind: AnimationKind) -> Int {
            let tick = Int(elapsed / interval)
            // 동작은 한 번만 재생하고 마지막 프레임에서 멈춤
            return kind == .act ? min(tick, frames.count - 1) : tick % frames.count
        }
    }

    private func clip(for kind: AnimationKind, facing: Facing) -> Clip? {
        guard let base = defaultClip(for: kind, facing: facing) else { return nil }
        guard let interval = intervalOverrides[kind], base.interval != 1 else { return base }
        return Clip(frames: base.frames, mirrored: base.mirrored, interval: interval, heads: base.heads)
    }

    private func defaultClip(for kind: AnimationKind, facing: Facing) -> Clip? {
        let stills = idleTextures.mapValues { [$0] }
        switch kind {
        case .idle:
            // 정면을 보라는 요청(south)은 정면 이미지가 있으면 그것을 우선
            if facing == .south, let front = idleTextures[.south] {
                return Clip(frames: [front], mirrored: false, interval: 1)
            }
            return sided(idleLoopTextures, heads: headShifts["idle"], facing: facing, interval: FrameInterval.idle)
                ?? sided(stills, facing: facing, interval: 1)
        case .airborne:
            return sided(jumpTextures, heads: headShifts["jump"], facing: facing, interval: FrameInterval.jump)
                ?? sided(stills, facing: facing, interval: 1)
        case .dragged:
            return sided(stills, facing: .south, interval: 1)
        case .hang:
            return sided(hangTextures, heads: headShifts["hang"], facing: facing, interval: FrameInterval.hang)
                ?? sided(stills, facing: .south, interval: 1)
        case .sleep:
            return sided(sleepTextures, heads: headShifts["sleep"], facing: facing, interval: FrameInterval.sleep)
                ?? sided(stills, facing: .south, interval: 1)
        case .walk:
            return sided(walkTextures, heads: headShifts["walk"], facing: facing, interval: FrameInterval.walk)
                ?? sided(stills, facing: facing, interval: 1)
        case .climb:
            // 전용 오르기(뒷모습) → 전용 오르기(옆, 벽 쪽 방향 기준) → 뒷모습 걷기 → 벽 쪽을 향한 걷기
            if let climb = climbTextures[.north], !climb.isEmpty {
                return Clip(frames: climb, mirrored: false, interval: FrameInterval.climb, heads: headShifts["climb"]?[.north] ?? [])
            }
            if let side = sided(climbTextures.filter { $0.key == .east || $0.key == .west }, heads: headShifts["climb"], facing: facing, interval: FrameInterval.climb) {
                return side
            }
            if let climb = climbTextures.values.first, !climb.isEmpty {
                return Clip(frames: climb, mirrored: false, interval: FrameInterval.climb)
            }
            if let back = walkTextures[.north], !back.isEmpty {
                return Clip(frames: back, mirrored: false, interval: FrameInterval.climb)
            }
            return sided(walkTextures, heads: headShifts["walk"], facing: facing, interval: FrameInterval.climb)
                ?? sided(stills, facing: facing, interval: 1)
        case .act:
            return sided(actionTextures, heads: headShifts["act"], facing: facing, interval: FrameInterval.act)
        }
    }

    /// 그 방향 이미지가 있으면 그대로, 없으면 반대 방향을 좌우 반전, 그것도 없으면 정면
    private func sided(_ table: [Facing: [Frame]], heads: [Facing: [BoneShift]]? = nil, facing: Facing, interval: TimeInterval) -> Clip? {
        if let frames = table[facing], !frames.isEmpty {
            return Clip(frames: frames, mirrored: false, interval: interval, heads: heads?[facing] ?? [])
        }
        if facing == .east || facing == .west, let frames = table[facing.opposite], !frames.isEmpty {
            return Clip(frames: frames, mirrored: true, interval: interval, heads: heads?[facing.opposite] ?? [])
        }
        if let frames = table[.south], !frames.isEmpty {
            return Clip(frames: frames, mirrored: false, interval: interval, heads: heads?[.south] ?? [])
        }
        return table.first { !$0.value.isEmpty }.map {
            Clip(frames: $0.value, mirrored: false, interval: interval, heads: heads?[$0.key] ?? [])
        }
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
            if let aim = options["aim"].flatMap(JSONNumber.double) {
                aimBias = min(max(aim, -0.5), 0.5)
            }
            if let pair = options["hatAnchor"] as? [Any], pair.count == 2 {
                hatAnchor = CGVector(dx: JSONNumber.double(pair[0]) ?? 0, dy: JSONNumber.double(pair[1]) ?? 0)
            }
            for (key, value) in options["intervals"] as? [String: Any] ?? [:] {
                // 숫자가 NSNumber로 오지 않는 Foundation(윈도우 등)도 있어 JSONNumber로 받음
                let seconds = JSONNumber.double(value) ?? 0
                guard let kind = AnimationKind(rawValue: key), seconds > 0 else { continue }
                intervalOverrides[kind] = seconds
            }
        }

        // 뒤 상태의 회전 이미지가 앞 상태를 덮어씀 (Radish의 별도 대기 상태)
        for state in states {
            let frames = state["frames"] as? [String: Any] ?? [:]
            for (key, path) in frames["rotations"] as? [String: String] ?? [:] {
                guard let facing = Facing(rawValue: key), let loaded = loadTexture(path, measuresBody: true) else { continue }
                idleTextures[facing] = loaded.frame
                referencePixels[facing] = loaded.pixels
            }
        }

        let animations = (states.first?["frames"] as? [String: Any])?["animations"] as? [String: Any] ?? [:]
        let keys = animations.keys.sorted()
        if let walkKey = keys.first(where: { $0.contains("Walk") || $0.contains("Run") }) {
            walkTextures = loadDirectionalFrames(animations[walkKey], track: "walk")
        }
        if let actionKey = keys.first(where: { $0.lowercased().contains("attack") || $0.lowercased().contains("swing") }) {
            actionTextures = loadDirectionalFrames(animations[actionKey], track: "act")
        }
        // 선택 동작 칸은 이름이 정확히 같을 때만 (Blink 같은 다른 대기 변형과 섞이지 않게)
        idleLoopTextures = loadDirectionalFrames(animations["Idle"], track: "idle")
        jumpTextures = loadDirectionalFrames(animations["Jump"], track: "jump")
        hangTextures = loadDirectionalFrames(animations["Hang"], track: "hang")
        sleepTextures = loadDirectionalFrames(animations["Sleep"], track: "sleep")
        climbTextures = loadDirectionalFrames(animations["Climb"], track: "climb")
    }

    /// 방향별 프레임 목록. "south-25d6d0a4"처럼 변형이 여럿이면 정렬상 첫 번째만 사용. 프레임마다 머리 이동도 잼
    private func loadDirectionalFrames(_ value: Any?, track: String) -> [Facing: [Frame]] {
        guard let table = value as? [String: Any] else { return [:] }
        var result: [Facing: [Frame]] = [:]
        for key in table.keys.sorted() {
            guard let facing = Facing.allCases.first(where: { key.hasPrefix($0.rawValue) }),
                  result[facing] == nil,
                  let paths = table[key] as? [String] else { continue }
            let sprites = paths.compactMap { loadTexture($0, measuresBody: false) }
            if !sprites.isEmpty {
                result[facing] = sprites.map(\.frame)
                headShifts[track, default: [:]][facing] = sprites.map { boneShift(of: $0.pixels, facing: facing) }
            }
        }
        return result
    }

    /// 서 있는 그림 대비 머리·앞손 이동 (스킨 도트 단위). 머리를 잴 수 없으면 0, 손을 잴 수 없으면 머리 이동
    private func boneShift(of pixels: SpritePixels?, facing: Facing) -> BoneShift {
        guard let pixels else { return BoneShift() }
        let unit = Pet.frameSide / CGFloat(pixels.width)
        let scaled = { (shift: CGVector) in CGVector(dx: shift.dx * unit, dy: shift.dy * unit) }
        let head = headTemplate(for: facing).flatMap { HeadTracker.shift(of: pixels, from: $0) }.map(scaled) ?? .zero
        let hand = handTemplate(for: facing).flatMap { HeadTracker.shift(of: pixels, from: $0) }.map(scaled) ?? head
        return BoneShift(head: head, hand: hand)
    }

    /// 그 방향 서 있는 그림의 앞손 본 (옆모습만 앞쪽이 있음, 정면·뒷면은 가슴 높이 전체)
    private func handTemplate(for facing: Facing) -> HeadTracker.Template? {
        if let cached = handTemplates[facing] { return cached }
        let template: HeadTracker.Template?
        if let own = referencePixels[facing] {
            template = HeadTracker.template(from: own, bone: .hand, front: facing)
        } else if facing == .east || facing == .west, let other = referencePixels[facing.opposite] {
            template = HeadTracker.template(from: other, mirrored: true, bone: .hand, front: facing)
        } else {
            template = (referencePixels[.south] ?? referencePixels.values.first).flatMap { HeadTracker.template(from: $0, bone: .hand) }
        }
        handTemplates[facing] = template
        return template
    }

    /// 그 방향 서 있는 그림, 없으면 반대 방향을 뒤집은 것, 그것도 없으면 정면에서 만든 머리 본
    private func headTemplate(for facing: Facing) -> HeadTracker.Template? {
        if let cached = headTemplates[facing] { return cached }
        let template: HeadTracker.Template?
        if let own = referencePixels[facing] {
            template = HeadTracker.template(from: own)
        } else if facing == .east || facing == .west, let other = referencePixels[facing.opposite] {
            template = HeadTracker.template(from: other, mirrored: true)
        } else {
            template = (referencePixels[.south] ?? referencePixels.values.first).flatMap { HeadTracker.template(from: $0) }
        }
        headTemplates[facing] = template
        return template
    }

    /// 보이는 픽셀이 없는 칸은 nil
    private func loadTexture(_ relativePath: String, measuresBody: Bool) -> LoadedSprite<Frame>? {
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
        return loaded
    }
}

/// 한 프레임에서 머리와 앞손이 서 있는 그림보다 옮겨 간 정도 (스킨 도트 단위)
struct BoneShift: Equatable {
    var head: CGVector = .zero
    var hand: CGVector = .zero
}
