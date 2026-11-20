import Foundation

/// This object is responsible for turning raw key-press counts (never which keys were pressed) into a typing pace:
/// presses per second over the last moment, and how long the user has kept typing without a pause.
struct TypingMeter {
    /// 빠르기를 재는 시간
    static let window: TimeInterval = 2
    /// 이만큼 안 치면 쉰 것으로 봄
    static let pauseGap: TimeInterval = 1.5

    private var presses: [(time: TimeInterval, count: Int)] = []
    private var clock: TimeInterval = 0
    private var lastPress: TimeInterval = -.infinity
    /// 쉬지 않고 친 시간
    private(set) var streak: TimeInterval = 0

    /// 이번 틱에 눌린 키 수를 더함
    mutating func record(_ count: Int, dt: TimeInterval) {
        clock += dt
        if count > 0 {
            presses.append((clock, count))
            lastPress = clock
        }
        presses.removeAll { clock - $0.time > Self.window }
        streak = clock - lastPress <= Self.pauseGap ? streak + dt : 0
    }

    /// 마지막으로 누른 뒤 지난 시간
    var sinceLastPress: TimeInterval { clock - lastPress }

    /// 최근 초당 누른 수
    var rate: Double {
        Double(presses.reduce(0) { $0 + $1.count }) / Self.window
    }
}

/// This object is responsible for the pets reacting to the user's typing pace (counts only, never content):
/// while the user types briskly, free pets now and then join in, drumming along at the typing speed,
/// and a burst of very fast typing gets a 🔥 from one of them.
final class TypingCoordinator {
    /// 이 빠르기(초당 누름)부터 펫이 따라 두드리기 시작
    static let joinRate = 3.0
    /// 한가한 펫이 초당 따라 들어올 확률
    static let joinChance = 0.15
    /// 이 빠르기로 이만큼 이어 치면 🔥
    static let fireRate = 8.0
    static let fireHold: TimeInterval = 2
    static let fireCooldown: TimeInterval = 45
    static let fireText = "🔥"

    var isEnabled = true {
        didSet { if !isEnabled { meter = TypingMeter() } }
    }
    private(set) var meter = TypingMeter()
    private var clock: TimeInterval = 0
    private var fastFor: TimeInterval = 0
    private var lastFire: TimeInterval = -.infinity
    var onEvent: ((String) -> Void)?

    /// 이만큼 안 누르면 멈춘 것으로 보고 빠르기 0
    static let stillTime: TimeInterval = 0.5

    /// 펫이 따라 두드릴 빠르기 (꺼져 있거나 손을 멈췄으면 0)
    var rate: Double { isEnabled && meter.sinceLastPress <= Self.stillTime ? meter.rate : 0 }

    /// 이번 틱에 눌린 키 수
    func record(_ presses: Int, dt: TimeInterval) {
        clock += dt
        guard isEnabled else { return }
        meter.record(presses, dt: dt)
        fastFor = rate >= Self.fireRate ? fastFor + dt : 0
    }

    /// 빠르게 치는 동안 한가한 펫을 하나씩 끌어들이고, 아주 빠르면 한 마리가 🔥. allowsJoining: 지친 펫은 쉼
    func step(dt: TimeInterval, pets: [Pet], planner: BehaviorPlanner, quiet: Bool, allowsJoining: Bool) {
        guard isEnabled, rate >= Self.joinRate else { return }
        if allowsJoining {
            for pet in pets where Self.canJoin(pet) && planner.chance(Self.joinChance * dt) {
                pet.switchTo(DrummingBehavior(hasActionFrames: pet.appearance.supports(.act),
                                              duration: planner.uniform(4, 8)))
                onEvent?("⌨️ [\(pet.id)] drums along (\(Int(rate))/s)")
            }
        }
        if !quiet, fastFor >= Self.fireHold, clock - lastFire >= Self.fireCooldown,
           let cheerer = pets.first(where: { $0.behavior is DrummingBehavior }) ?? pets.first(where: Self.canJoin) {
            lastFire = clock
            cheerer.say(Self.fireText, for: 1.5)
            onEvent?("🔥 [\(cheerer.id)] fast typing")
        }
    }

    /// 쉬거나 거닐거나 바라보던 펫만 (알림을 들었거나 들린 펫은 제외)
    private static func canJoin(_ pet: Pet) -> Bool {
        pet.support != nil && !pet.isShowingNotice && !pet.isDragged
            && (pet.behavior.isAtLeisure || pet.behavior.name == "lookingAtUser")
    }
}
