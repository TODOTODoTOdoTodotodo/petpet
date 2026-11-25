import Foundation

/// 확인할 때까지 남는 알림을 펫에게 맡기고 거두는 곳 (PetRoster)
protocol NoticeBoard: AnyObject {
    /// 알림을 맡김. 같은 주제를 든 펫이 있으면 문구만 바꿈
    func announce(_ notice: ScheduleNotice)
    /// 그 주제의 알림을 거둠 (기다리던 것도 지움)
    func withdraw(topic: String)
    /// 그 주제의 알림이 아직 떠 있거나 전할 차례를 기다리는지
    func holds(topic: String) -> Bool
}

/// This object is responsible for turning the signals AI coding tools send (`AgentSignal`) into pet bubbles carrying
/// the icon of the app the session lives in: done → a free pet goes to that app's Dock icon and knocks on it
/// (or leaps onto the app's window, or hops in place) with ✅, waiting → a pet holds ✋ until it is poked,
/// the session moves on, or the user switches to that app, limit → 💤. Poking a pet holding such a bubble
/// brings that app forward. It never sees what the tools are doing.
final class AgentSignalCoordinator {
    /// 꺼지면 들어온 신호를 버리고 떠 있는 기다림 말풍선도 거둠
    var isEnabled = true {
        didSet { if !isEnabled { inbox.removeAll() } }
    }
    var onEvent: ((String) -> Void)?
    /// 그 앱을 앞으로 불러옴 (껍데기가 운영체제에 요청)
    var onBringForward: ((Int32) -> Void)?

    static let doneText = "✅"
    static let waitingText = "✋"
    static let limitText = "💤"
    /// 끝남·한도 말풍선이 떠 있는 시간
    static let cheerTime: TimeInterval = 4

    private var inbox: [(signal: AgentSignal, host: AgentHost?)] = []
    /// 기다림 말풍선이 떠 있는 세션: 그 앱의 프로세스 ID, 신호 뒤 사용자가 그 앱을 떠나 있었는지
    private var waits: [String: (hostProcessID: Int32?, wentAway: Bool)] = [:]

    /// 들어온 신호를 다음 틱에 펫에게 전함. host: 그 세션이 사는 앱 (못 찾으면 nil, 아이콘 없이 기호만)
    func receive(_ signal: AgentSignal, from host: AgentHost?) {
        guard isEnabled else { return }
        inbox.append((signal, host))
    }

    func step(pets: [Pet], world: World, board: NoticeBoard, planner: BehaviorPlanner, quiet: Bool) {
        guard isEnabled else {
            waits.keys.forEach(board.withdraw)
            waits.removeAll()
            return
        }
        settleWaits(focused: world.focusedProcessID, board: board)
        let arrived = inbox
        inbox.removeAll()
        for (signal, host) in arrived {
            handle(signal, host: host, pets: pets, world: world, board: board, planner: planner, quiet: quiet)
        }
    }

    /// 기다림 신호 뒤 다른 앱을 보다가 그 앱으로 돌아오면 확인한 것으로 보고 거둠. 펫을 눌러 닫았으면 잊음
    private func settleWaits(focused: Int32?, board: NoticeBoard) {
        for (topic, wait) in waits {
            guard board.holds(topic: topic) else {
                waits[topic] = nil
                continue
            }
            guard let host = wait.hostProcessID else { continue }
            if focused != host {
                waits[topic] = (host, true)
            } else if wait.wentAway {
                end(topic, board: board, reason: "user switched to the app")
            }
        }
    }

    private func handle(_ signal: AgentSignal, host: AgentHost?, pets: [Pet], world: World,
                        board: NoticeBoard, planner: BehaviorPlanner, quiet: Bool) {
        let focused = world.focusedProcessID
        let topic = signal.sessionTopic
        let from = "\(signal.source) (app \(host.map { "\($0.processID)" } ?? "unknown"))"
        switch signal.kind {
        case .waiting:
            board.announce(ScheduleNotice(topic: topic, text: Self.waitingText, discreetText: Self.waitingText,
                                          badge: host?.badge, appProcessID: host?.processID))
            waits[topic] = (host?.processID, host.map { focused != $0.processID } ?? false)
            onEvent?("🤖 \(from) waiting")
        case .working:
            end(topic, board: board, reason: "working")
        case .done, .limit:
            end(topic, board: board, reason: signal.kind.rawValue)
            let text = signal.kind == .done ? Self.doneText : Self.limitText
            guard !quiet else {
                onEvent?("🤖 \(from) \(signal.kind.rawValue), quiet")
                return
            }
            guard let pet = cheerer(among: pets, planner: planner) else {
                onEvent?("🤖 \(from) \(signal.kind.rawValue), no free pet")
                return
            }
            pet.say(text, for: Self.cheerTime, badge: host?.badge, app: host?.processID)
            let move = signal.kind == .done ? go(pet, to: host, text: text, in: world) : nil
            if move == nil, pet.support != nil && pet.behavior.isAtLeisure {
                pet.switchTo(AirborneBehavior.hop(name: "agent \(signal.kind.rawValue)", motionScale: pet.motionScale))
            }
            onEvent?("🤖 [\(pet.id)] \(from) \(signal.kind.rawValue)" + (move.map { ", \($0)" } ?? ""))
        }
    }

    /// 펫을 눌러 그 앱을 앞으로
    func bringForward(_ app: Int32, by pet: Pet) {
        onEvent?("🤖 [\(pet.id)] bring app \(app) forward")
        onBringForward?(app)
    }

    /// 끝난 앱을 찾아감: Dock 아이콘(같은 모니터 바닥 위) → 그 앱의 창 위로 도약. 간 곳을 돌려줌
    private func go(_ pet: Pet, to host: AgentHost?, text: String, in world: World) -> String? {
        guard let host, pet.support != nil, pet.behavior.isAtLeisure || pet.behavior is IdleBehavior else { return nil }
        if let goal = Self.dockSpot(host.dockIcon, in: world),
           world.screen(containing: CGPoint(x: pet.position.x, y: pet.position.y + 1))?.id
            == world.screen(containing: CGPoint(x: goal.x, y: goal.y + 1))?.id {
            pet.switchTo(VisitBehavior(goal: goal, text: text, badge: host.badge, app: host.processID))
            return "to Dock icon x \(Int(goal.x))"
        }
        if let window = world.windows.first(where: { $0.processID == host.processID }), pet.perchWindowID != window.id,
           let plan = LeapPlanner.plan(for: pet, to: window.id, in: world) {
            pet.switchTo(SkillLeapBehavior(plan: plan, style: pet.appearance.skillStyle, hasActionFrames: pet.appearance.supports(.act)))
            return "leap to window \(window.id)"
        }
        return nil
    }

    /// 아래쪽 Dock 아이콘 바로 위 바닥 자리. 옆에 붙은 Dock·숨은 Dock·모르는 경우 nil
    static func dockSpot(_ icon: CGRect?, in world: World) -> CGPoint? {
        guard let icon, let screen = world.screens.first(where: { $0.frame.contains(CGPoint(x: icon.midX, y: icon.midY)) }),
              icon.midY < screen.visibleFrame.minY,
              icon.midX > screen.visibleFrame.minX, icon.midX < screen.visibleFrame.maxX else { return nil }
        return CGPoint(x: icon.midX, y: screen.visibleFrame.minY)
    }

    private func end(_ topic: String, board: NoticeBoard, reason: String) {
        guard waits.removeValue(forKey: topic) != nil else { return }
        board.withdraw(topic: topic)
        onEvent?("🤖 \(topic) wait cleared: \(reason)")
    }

    /// 알림을 들지 않은 기본 펫 중 한가한 펫을 먼저, 없으면 아무 기본 펫이나 (끌려가는 펫 제외)
    private func cheerer(among pets: [Pet], planner: BehaviorPlanner) -> Pet? {
        let free = pets.filter { $0.role == .resident && !$0.isShowingNotice && !$0.isDragged }
        let idle = free.filter { $0.support != nil && $0.behavior.isAtLeisure }
        let group = idle.isEmpty ? free : idle
        guard !group.isEmpty else { return nil }
        return group[min(Int(planner.uniform(0, Double(group.count))), group.count - 1)]
    }
}
