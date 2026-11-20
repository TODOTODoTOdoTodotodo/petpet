import Foundation

/// This object is responsible for noticing when two pets meet on the same ledge and having them
/// greet each other, have a short friendly play-fight with their attack moves, or — sometimes —
/// one hop onto the other's head to start a tower, without repeating the same pair too often.
final class PetSocialCoordinator {
    /// 마주치는 거리
    static let greetingDistance: CGFloat = 60
    /// 같은 짝이 다시 어울리기까지 시간
    static let pairCooldown: TimeInterval = 20
    /// 인사 대신 대결할 확률
    static let sparChance = 0.25
    /// 주고받는 횟수
    static let sparRounds = 3
    /// 대결하지 않을 때 한 마리가 다른 펫 머리에 올라탈 확률
    static let piggybackChance = 0.35

    private var lastGreeting: [String: TimeInterval] = [:]
    private var clock: TimeInterval = 0
    var onEvent: ((String) -> Void)?

    /// allowsSparring: 기력이 떨어지면 대결·올라타기 없이 인사만.
    /// piggyback: (아래 펫, 올라탈 펫)으로 탑을 시작하고 됐으면 true
    func step(dt: TimeInterval, pets: [Pet], planner: BehaviorPlanner, allowsSparring: Bool = true,
              piggyback: ((Pet, Pet) -> Bool)? = nil) {
        clock += dt
        guard pets.count > 1 else { return }
        for (index, first) in pets.enumerated() {
            for second in pets[(index + 1)...] where canMeet(first, second) {
                lastGreeting[pairKey(first, second)] = clock
                if allowsSparring && planner.chance(Self.sparChance) {
                    spar(first, second, planner: planner)
                } else if allowsSparring, let piggyback, planner.chance(Self.piggybackChance),
                          planner.chance(0.5) ? piggyback(first, second) : piggyback(second, first) {
                    continue
                } else {
                    first.switchTo(GlanceBehavior.greeting(friendX: second.position.x))
                    second.switchTo(GlanceBehavior.greeting(friendX: first.position.x))
                }
            }
        }
    }

    /// 길을 막은 펫과 결투. 건 펫(challenger)이 이기면 상대를 뛰어넘어 지나가고, 지면 돌아섬
    func duel(_ challenger: Pet, _ opponent: Pet, planner: BehaviorPlanner) {
        lastGreeting[pairKey(challenger, opponent)] = clock
        spar(challenger, opponent, planner: planner, passing: true)
    }

    private func spar(_ first: Pet, _ second: Pet, planner: BehaviorPlanner, passing: Bool = false) {
        let match = SparMatch(rounds: Self.sparRounds,
                              firstAttacker: planner.chance(0.5) ? 0 : 1,
                              winner: planner.chance(0.5) ? 0 : 1)
        first.switchTo(SparBehavior(match: match, side: 0, opponentX: second.position.x,
                                    hasActionFrames: first.appearance.supports(.act), passingID: passing ? second.id : nil))
        second.switchTo(SparBehavior(match: match, side: 1, opponentX: first.position.x,
                                     hasActionFrames: second.appearance.supports(.act)))
        onEvent?(passing ? "⚔️ [\(first.id)] duels [\(second.id)] to pass" : "⚔️ [\(first.id)] vs [\(second.id)] play-fight")
    }

    private func canMeet(_ first: Pet, _ second: Pet) -> Bool {
        guard first.behavior.isAtLeisure, second.behavior.isAtLeisure,
              let firstSupport = first.support?.owner, firstSupport == second.support?.owner,
              abs(first.position.x - second.position.x) <= Self.greetingDistance,
              // 겹쳐 있으면 먼저 비켜 선 뒤에 어울림
              abs(first.position.x - second.position.x) >= first.bodyHalfWidth + second.bodyHalfWidth
        else { return false }
        if let last = lastGreeting[pairKey(first, second)], clock - last < Self.pairCooldown {
            return false
        }
        return true
    }

    private func pairKey(_ first: Pet, _ second: Pet) -> String {
        [first.id, second.id].sorted().joined(separator: "|")
    }
}
