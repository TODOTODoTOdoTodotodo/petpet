import Foundation

/// This object is responsible for how the resting pets notice the user switching windows:
/// they turn toward the new window, and one of them says a word that fits the kind of app (chat, mail, video, code),
/// at most once per minute per kind. Video apps make that pet stay and watch for a while.
/// Turning around is limited too, so quick window hopping does not keep interrupting the pets.
final class AttentionCoordinator {
    /// 같은 종류 앱에 다시 말하기까지 시간
    static let remarkCooldown: TimeInterval = 60
    /// 영상 앱을 구경하는 시간
    static let watchDuration: TimeInterval = 8
    static let glanceDuration: TimeInterval = 1.0
    /// 다시 돌아보기까지 시간 (창을 자주 바꿔도 펫 일과를 끊지 않게)
    static let glanceCooldown: TimeInterval = 15

    private var clock: TimeInterval = 0
    private var lastRemark: [AppCategory: TimeInterval] = [:]
    private var lastGlance: TimeInterval = -.infinity
    var onEvent: ((String) -> Void)?

    /// leaper: 이번에 도약한 펫 (돌아보지 않고, 말은 이 펫이 함)
    func step(dt: TimeInterval, pets: [Pet], shift: FocusShift?, leaper: Pet?, quiet: Bool = false) {
        clock += dt
        guard let shift else { return }
        let targetX = shift.frame.midX
        let watchers = pets.filter { pet in
            pet !== leaper && pet.role == .resident && pet.behavior.isAtLeisure && pet.support != nil && !pet.isShowingNotice
        }
        let remark = quiet ? nil : takeRemark(for: shift.category)
        var speaker: Pet?
        if let remark {
            speaker = leaper ?? watchers.min { abs($0.position.x - targetX) < abs($1.position.x - targetX) }
            if let leaper, leaper === speaker {
                leaper.say(remark, for: 2)
            }
            if let speaker { onEvent?("👀 [\(speaker.id)] \(remark) for \(shift.category)") }
        }
        let glances = clock - lastGlance >= Self.glanceCooldown
        if glances && !watchers.isEmpty { lastGlance = clock }
        for pet in watchers {
            if pet === speaker, let remark {
                let watching = shift.category == .video
                pet.switchTo(GlanceBehavior(name: watching ? "watching" : "glancing", towardX: targetX,
                                            duration: watching ? Self.watchDuration : Self.glanceDuration * 1.5, remark: remark))
            } else if glances {
                pet.switchTo(GlanceBehavior(name: "glancing", towardX: targetX, duration: Self.glanceDuration))
            }
        }
    }

    /// 그 종류의 말을 할 차례면 꺼내 줌
    private func takeRemark(for category: AppCategory) -> String? {
        guard let remark = category.remark else { return nil }
        if let last = lastRemark[category], clock - last < Self.remarkCooldown { return nil }
        lastRemark[category] = clock
        return remark
    }
}
