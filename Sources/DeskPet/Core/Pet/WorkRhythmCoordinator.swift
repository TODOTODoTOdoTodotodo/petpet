import Foundation

/// This object is responsible for gentle work-rhythm nudges (off by default): a stretch reminder after
/// 50 minutes of input without a 5-minute break, and a dizzy face when the user hops between windows very fast.
/// It only counts input idle time and window switches, never what is typed or shown.
final class WorkRhythmCoordinator {
    /// 쉬지 않고 이만큼 쓰면 기지개 권유
    static let breakAfter: TimeInterval = 50 * 60
    /// 입력이 이만큼 없으면 쉰 것으로 봄
    static let restResets: TimeInterval = 5 * 60
    /// 짧은 시간에 이만큼 창을 바꾸면 어지러움
    static let rapidSwitches = 6
    static let rapidWindow: TimeInterval = 20
    static let rapidCooldown: TimeInterval = 120

    static let stretchText = "기지개 🙆"
    static let dizzyText = "😵"

    var isEnabled = false {
        didSet { if !isEnabled { reset() } }
    }
    private var clock: TimeInterval = 0
    private(set) var activeStreak: TimeInterval = 0
    private var switches: [TimeInterval] = []
    private var lastDizzy: TimeInterval = -.infinity
    var onEvent: ((String) -> Void)?

    func step(dt: TimeInterval, pets: [Pet], idleSeconds: TimeInterval, shift: FocusShift?, quiet: Bool = false) {
        clock += dt
        guard isEnabled else { return }
        activeStreak = idleSeconds >= Self.restResets ? 0 : activeStreak + dt
        if shift != nil {
            switches = switches.filter { clock - $0 <= Self.rapidWindow } + [clock]
        }
        guard !quiet, let speaker = pets.first(where: { $0.role == .resident && !$0.isShowingNotice && !$0.isDragged }) else { return }

        if activeStreak >= Self.breakAfter {
            activeStreak = 0
            speaker.say(Self.stretchText, for: 8)
            onEvent?("🙆 [\(speaker.id)] stretch reminder")
        }
        let recent = switches.filter { clock - $0 <= Self.rapidWindow }
        if recent.count >= Self.rapidSwitches, clock - lastDizzy >= Self.rapidCooldown {
            lastDizzy = clock
            switches = []
            speaker.say(Self.dizzyText, for: 2.5)
            onEvent?("😵 [\(speaker.id)] rapid window switching")
        }
    }

    private func reset() {
        activeStreak = 0
        switches = []
    }
}
