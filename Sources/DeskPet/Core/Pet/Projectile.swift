import Foundation

/// 던지는 무기 한 종류: 도트 그림과 나는 방식 (그림은 무대가 텍스처로 바꿈)
struct ProjectileKind: Equatable {
    let name: String
    /// 위에서 아래 줄 순서의 도트. "."은 투명, 나머지 글자는 palette 키
    let rows: [String]
    let palette: [Character: UInt32]
    /// 중력 (0이면 곧게 날아감)
    let gravity: CGFloat
    /// 초당 회전 (라디안)
    let spin: CGFloat
    /// 나는 속도 (기준 크기, pt/s)
    let speed: CGFloat

    /// 몽둥이 (Goblin 등 pole_vault)
    static let club = ProjectileKind(
        name: "club",
        rows: [".....kk.", "....kbbk", "...kblbk", "..kbbbk.", ".kbbk...", "kbk.....", "kk......", "........"],
        palette: ["k": 0x3B2414, "b": 0x8B5A2B, "l": 0xB07A45],
        gravity: 1200, spin: 14, speed: 650
    )
    /// 불꽃 (flame_rocket)
    static let fireball = ProjectileKind(
        name: "fireball",
        rows: ["..rrrr..", ".royyor.", "royywyor", "roywwyor", "royywyor", ".royyor.", "..rrrr..", "........"],
        palette: ["r": 0xD8402A, "o": 0xF08A24, "y": 0xFFD23F, "w": 0xFFF6D0],
        gravity: 0, spin: 0, speed: 520
    )
    /// 칼 (slash_jump)
    static let blade = ProjectileKind(
        name: "blade",
        rows: ["......kw", ".....kwk", "....kwk.", "...kwk..", ".hkwk...", "..hk....", ".h.h....", "h......."],
        palette: ["k": 0x5A6070, "w": 0xE8F0FF, "h": 0xC89B3C],
        gravity: 600, spin: 18, speed: 750
    )
    /// 돌멩이 (big_jump)
    static let rock = ProjectileKind(
        name: "rock",
        rows: ["..kkkk..", ".kggggk.", "kgglgggk", "kggggggk", "kgggggdk", "kggggddk", ".kgdddk.", "..kkkk.."],
        palette: ["k": 0x3A3A40, "g": 0x8A8A94, "l": 0xC8C8D0, "d": 0x6A6A74],
        gravity: 1400, spin: 8, speed: 650
    )
    /// 닿은 자리의 반짝임 (무기 공통)
    static let burstRows = ["...y....", ".y.y.y..", "..yyy...", "yyywyyy.", "..yyy...", ".y.y.y..", "...y....", "........"]
    static let burstPalette: [Character: UInt32] = ["y": 0xFFD23F, "w": 0xFFFFFF]

    static func == (lhs: ProjectileKind, rhs: ProjectileKind) -> Bool { lhs.name == rhs.name }
}

extension SkillStyle {
    /// 캐릭터 스킬에 어울리는 던질 무기
    var projectile: ProjectileKind {
        Self.projectiles[self] ?? .rock
    }

    private static let projectiles: [SkillStyle: ProjectileKind] = [
        .poleVault: .club, .flameRocket: .fireball, .slashJump: .blade, .bigJump: .rock,
    ]
}

/// 펫이 던진 무기 (무대로 넘기기 전)
struct ThrowRequest: Equatable {
    let kind: ProjectileKind
    let from: CGPoint
    let to: CGPoint
}

/// This object is responsible for one thrown weapon: flying from a pet's hand to the point it was aimed at
/// (in an arc, or straight for fire) in a planned time, spinning on the way, then showing a short burst there.
final class Projectile {
    let id: String
    let kind: ProjectileKind
    /// 던진 펫
    let throwerID: String
    /// 무기 도트 한 칸 크기 (던진 펫 크기)
    let scale: CGFloat
    private(set) var position: CGPoint
    private(set) var rotation: CGFloat = 0
    private var velocity: CGVector
    private let target: CGPoint
    private let flightTime: TimeInterval
    private let gravity: CGFloat
    private var age: TimeInterval = 0

    /// 닿은 뒤 반짝임이 보이는 시간
    static let burstTime: TimeInterval = 0.35
    /// 비행 시간 범위
    static let flightRange: ClosedRange<TimeInterval> = 0.25...1.2

    init(id: String, kind: ProjectileKind, throwerID: String, from start: CGPoint, to target: CGPoint, scale: CGFloat) {
        self.id = id
        self.kind = kind
        self.throwerID = throwerID
        self.scale = scale
        self.position = start
        self.target = target
        let motionScale = scale / 1.5
        let distance = hypot(target.x - start.x, target.y - start.y)
        let time = min(max(TimeInterval(distance / (kind.speed * motionScale)), Self.flightRange.lowerBound), Self.flightRange.upperBound)
        flightTime = time
        gravity = kind.gravity * motionScale
        // 정한 시간에 목표에 닿는 포물선
        let t = CGFloat(time)
        velocity = CGVector(dx: (target.x - start.x) / t, dy: (target.y - start.y) / t + 0.5 * gravity * t)
    }

    /// 목표에 닿아 반짝이는 중인지
    var isBursting: Bool { age >= flightTime }
    /// 반짝임 진행 (0~1). 날아가는 중이면 nil
    var burstProgress: Double? { isBursting ? min((age - flightTime) / Self.burstTime, 1) : nil }
    var isFinished: Bool { age >= flightTime + Self.burstTime }

    /// 진행. 이번 틱에 목표에 닿았으면 true
    @discardableResult
    func step(dt: TimeInterval) -> Bool {
        let wasFlying = !isBursting
        let flying = min(dt, max(flightTime - age, 0))
        age += dt
        if flying > 0 {
            let t = CGFloat(flying)
            position = CGPoint(x: position.x + velocity.dx * t, y: position.y + velocity.dy * t - 0.5 * gravity * t * t)
            velocity.dy -= gravity * t
            rotation += kind.spin * t
        }
        if wasFlying && isBursting {
            position = target
            return true
        }
        return false
    }
}
