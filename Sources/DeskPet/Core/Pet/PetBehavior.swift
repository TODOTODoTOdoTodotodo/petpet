import Foundation

/// 다른 펫의 위치와 몸 (사교·자리 판단용)
struct FriendSighting {
    let id: String
    let position: CGPoint
    var halfWidth: CGFloat = 0
    var height: CGFloat = 0
    /// 딛고 있는 면 (공중·탑 위면 nil)
    var support: SurfaceOwner?
    /// 발판 위 자리를 차지하는지 (지나가려면 비켜 가야 함)
    var isObstacle = false
    /// 뛰어넘을 수 있는지 (탑은 너무 높아 안 됨)
    var isJumpable = true
    /// 걷는 방향 (걷는 중일 때만)
    var heading: Facing?
}

/// 행동이 한 틱 동안 참고하는 주변 정보
struct PetContext {
    /// 전역 좌표의 마우스 커서
    let cursor: CGPoint?
    let planner: BehaviorPlanner
    /// 마지막 키보드·마우스 입력 후 지난 시간
    var idleSeconds: TimeInterval = 0
    /// 같은 화면의 다른 펫들
    var friends: [FriendSighting] = []
    /// 스킬로 자주 찾아갈 창 (쫓는 창: 보고 있는 창 또는 포인터 아래 창. 스킬을 끄거나 통화 중이면 nil)
    var skillTarget: UInt32?
    /// 그 창에 이미 올라가 있거나 빼꼼 중인 펫 수
    var visitorsOnTarget = 0
    /// 스킬 도약을 써도 되는지 (Skill Jumps 켜짐, 통화 중 아님, 기운 있음). 창 아랫변에 붙으러 가는 도약도 이것을 따름
    var allowsSkills = false
    /// 아랫변에 붙으러 갈 창 (포인터 모드에서 포인터가 창 바로 밑에 있을 때)
    var clingTarget: UInt32?
    /// 걸어서 쫓아갈 마우스 포인터 (포인터 모드에서만)
    var pointer: CGPoint?
    /// 길을 막은 펫에게 결투를 걸어도 되는지 (통화 중 아님, 기운 있음)
    var allowsDuels = false
    /// 사용자가 지금 키를 누르는 빠르기 (초당, 횟수만 셈)
    var typingRate: Double = 0
    /// Claude 사용량에 따른 기력
    var vigor: Vigor = .fresh
    /// 던질 때 겨냥 (없으면 늘 명중)
    var aim: ThrowAim?
}

/// 행동이 요청하는 그리기 효과
enum VisualEffect: Equatable {
    case none
    /// 숨쉬듯 들썩임 (잠)
    case breathing
    /// 스킬 도약 꼬리 입자
    case trail(SkillStyle)
}

/// 그릴 때의 몸 자세 (거꾸로 빼꼼: 위아래를 뒤집고 창 윗변 위는 가림)
struct BodyPose: Equatable {
    /// 발 높이를 축으로 위아래를 뒤집어 그림 (머리가 아래)
    var upsideDown = false
    /// 이 높이(전역 y)보다 위는 그리지 않음 (창 윗변 뒤로 숨은 부분)
    var hiddenAbove: CGFloat?

    static let upright = BodyPose()
}

/// 캐릭터별 도약 스킬 (스킨 metadata.json의 "deskpet": {"skill": ...})
enum SkillStyle: String, Equatable {
    /// 몽둥이 장대높이뛰기, 흙먼지
    case poleVault = "pole_vault"
    /// 마법 불꽃 로켓 점프, 불꽃 꼬리
    case flameRocket = "flame_rocket"
    /// 칼 휘두르며 도약, 칼바람 궤적
    case slashJump = "slash_jump"
    /// 기본 큰 점프
    case bigJump = "big_jump"
}

/// This object is responsible for one way a pet acts over time.
/// Each tick it moves the pet and returns the next behavior when it is done, or nil to continue.
/// It also decides how the pet reacts to clicks and announcements in that state.
protocol PetBehavior: AnyObject {
    var name: String { get }
    var animation: AnimationKind { get }
    /// 펫의 이동 방향과 다른 자세가 필요할 때의 방향
    var displayFacing: Facing? { get }
    /// 애니메이션 재생 속도 배율
    var animationSpeed: Double { get }
    var effect: VisualEffect { get }
    /// 한가해서 인사·스킬 도약으로 끼어들어도 되는 상태인지
    var isAtLeisure: Bool { get }
    /// 발판 없이 붙잡고 있는 창 (거꾸로 빼꼼)
    var heldWindowID: UInt32? { get }
    /// 그릴 때의 몸 자세
    var pose: BodyPose { get }
    /// 그릴 때의 불투명도 (모니터 건너가기 중 사라졌다 나타남)
    var opacity: CGFloat { get }
    /// 펫 탑에서 몇 층인지 (맨 아래 0). 탑이 아니면 nil. 층이 있으면 위에 다른 펫을 태우고 있을 수 있음
    var towerLevel: Int? { get }
    /// 발판 위 자리를 차지하는지 (다른 펫이 지나가려면 비켜 가거나 뛰어넘어야 함)
    var occupiesSpace: Bool { get }
    /// 걷는 방향 (걷는 중일 때만)
    var heading: Facing? { get }
    /// 길을 막은 펫에게 결투를 거는 중이면 그 펫 ID
    var challengedID: String? { get }
    /// 기차놀이에서 몇 번째 칸인지 (기관차 0). 기차가 아니면 nil
    var trainRank: Int? { get }
    /// 몸을 돌려 그리는 각도 (라디안, 반시계 +). 공중제비 중에만
    var bodyRotation: CGFloat { get }
    func begin(_ pet: Pet)
    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior?
    /// 클릭 반응. streak은 짧은 시간 안의 연속 클릭 수
    func poked(_ pet: Pet, streak: Int) -> PetBehavior?
    /// 일정 알림을 말할 때 바꿀 행동
    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior?
}

extension PetBehavior {
    var displayFacing: Facing? { nil }
    var animationSpeed: Double { 1 }
    var effect: VisualEffect { .none }
    var isAtLeisure: Bool { false }
    var heldWindowID: UInt32? { nil }
    var pose: BodyPose { .upright }
    var opacity: CGFloat { 1 }
    var towerLevel: Int? { nil }
    var occupiesSpace: Bool { false }
    var heading: Facing? { nil }
    var challengedID: String? { nil }
    var trainRank: Int? { nil }
    var bodyRotation: CGFloat { 0 }
    func begin(_ pet: Pet) {}

    /// 공중·등반·들린 상태는 하트만 띄움
    func poked(_ pet: Pet, streak: Int) -> PetBehavior? {
        pet.say(pet.loveText)
        return nil
    }

    func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior? {
        nil
    }
}

/// This object is responsible for how a pet standing on a ledge reacts to clicks and announcements,
/// shared by the grounded behaviors (idle, walk, act, greet).
enum GroundReaction {
    /// 연속 클릭 이 횟수부터 화내며 도망
    static let annoyedStreak = 3

    static func poked(_ pet: Pet, streak: Int) -> PetBehavior {
        if streak >= annoyedStreak {
            pet.say(Chatter.annoyed)
            return WalkBehavior(name: "fleeing", direction: pet.facing.opposite, speed: PetPhysics.sprintSpeed, duration: 1.2)
        }
        pet.say(pet.loveText)
        return AirborneBehavior.hop(name: "hopping", motionScale: pet.motionScale)
    }

    static func announcing(_ pet: Pet, for duration: TimeInterval) -> PetBehavior {
        IdleBehavior(duration: min(duration, 4), lookAtUser: true, name: "announcing")
    }
}

/// 펫 몸 크기 1.5배 기준의 물리 상수 (pt, 초)
enum PetPhysics {
    static let walkSpeed: CGFloat = 60
    static let sprintSpeed: CGFloat = 150
    static let climbSpeed: CGFloat = 70
    static let gravity: CGFloat = 1500
    static let terminalSpeed: CGFloat = 1400
    static let jumpSpeed: CGFloat = 520
    static let hopSpeed: CGFloat = 290
    static let jumpDrift: CGFloat = 130
    static let maxThrowSpeed: CGFloat = 900
    /// 낙하 적분 최대 간격
    static let maxStep: TimeInterval = 1.0 / 120
    /// 착지 직후 숨 고르는 시간
    static let landingPause: TimeInterval = 0.35

    /// 점프 최고 높이
    static func jumpApex(motionScale: CGFloat) -> CGFloat {
        let speed = jumpSpeed * motionScale
        return speed * speed / (2 * gravity * motionScale)
    }
}
