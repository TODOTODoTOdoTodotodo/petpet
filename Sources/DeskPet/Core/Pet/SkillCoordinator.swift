import Foundation

/// This object is responsible for sending a pet to leap onto the window the user switched to with its character skill.
/// A pet that was on the previous window follows right away; otherwise one free pet goes, at most once per cooldown.
/// When the window is on a display with no pet and no leap can reach it, the pet crosses to that display first.
final class SkillCoordinator {
    /// 스킬 재사용 대기
    static let cooldown: TimeInterval = 30

    var isEnabled = true
    private var clock: TimeInterval = 0
    private var lastUse: TimeInterval = -.infinity
    /// 지난 틱에 각 펫이 올라가 있던 창 (가려져 떨어진 펫도 어디 있었는지 알기 위함)
    private var perches: [String: UInt32] = [:]
    /// 스킬 사용 기록
    var onEvent: ((String) -> Void)?

    /// 도약시킨 펫을 돌려줌 (다른 펫의 반응에서 빼기 위함)
    @discardableResult
    func step(dt: TimeInterval, pets: [Pet], world: World, shift: FocusShift?, quiet: Bool = false) -> Pet? {
        clock += dt
        defer {
            perches = Dictionary(pets.compactMap { pet in pet.perchWindowID.map { (pet.id, $0) } }, uniquingKeysWith: { first, _ in first })
        }
        guard isEnabled, !quiet, let shift else { return nil }
        // 이미 그 창에 있는 펫이 있으면 생략 (같은 높이 창으로 옮겨 잡은 펫 포함)
        guard !pets.contains(where: { $0.perchWindowID == shift.to }) else { return nil }

        // 보던 창에 있던 펫은 대기 시간 없이 따라감
        let riders = pets.filter { pet in
            shift.from != nil && perches[pet.id] == shift.from && pet.role == .resident
                && !pet.isShowingNotice && !pet.isDragged && !(pet.behavior is SkillLeapBehavior)
        }
        if let (pet, plan) = nearest(riders, to: shift.to, in: world, fromAnywhere: true) {
            launch(pet, plan, mode: "follow")
            return pet
        }
        if let pet = hop(riders, to: shift.to, pets: pets, in: world, mode: "follow") {
            return pet
        }

        guard clock - lastUse >= Self.cooldown else { return nil }
        let candidates = pets.filter { $0.role == .resident && $0.behavior.isAtLeisure && !$0.isShowingNotice }
        if let (pet, plan) = nearest(candidates, to: shift.to, in: world, fromAnywhere: false) {
            launch(pet, plan, mode: nil)
            return pet
        }
        return hop(candidates, to: shift.to, pets: pets, in: world, mode: nil)
    }

    /// 다른 모니터의 창이면 그 모니터로 건너감. 그 모니터에 기본 펫이 이미 있으면 그 펫들 몫으로 남김
    private func hop(_ movers: [Pet], to windowID: UInt32, pets: [Pet], in world: World, mode: String?) -> Pet? {
        guard let window = world.window(id: windowID), let target = world.screen(of: window) else { return nil }
        let residentsThere = pets.contains { pet in
            pet.role == .resident && world.screen(containing: CGPoint(x: pet.position.x, y: pet.position.y + 1))?.id == target.id
        }
        guard !residentsThere else { return nil }
        let choices = movers.compactMap { pet in ScreenHopPlanner.arrival(for: pet, to: window, in: world).map { (pet, $0) } }
        guard let (pet, arrival) = choices.min(by: { abs($0.0.position.x - window.frame.midX) < abs($1.0.position.x - window.frame.midX) }) else {
            return nil
        }
        lastUse = clock
        let style = pet.appearance.skillStyle
        pet.switchTo(ScreenHopBehavior(windowID: windowID, arrival: arrival, style: style, hasActionFrames: pet.appearance.supports(.act)))
        let label = [mode, target.name].compactMap { $0 }.joined(separator: ", ")
        onEvent?("🌀 [\(pet.id)] \(style.rawValue) → display \(label) (\(Int(arrival.x)), \(Int(arrival.y)))")
        return pet
    }

    private func nearest(_ pets: [Pet], to windowID: UInt32, in world: World, fromAnywhere: Bool) -> (Pet, LeapPlan)? {
        pets.compactMap { pet in LeapPlanner.plan(for: pet, to: windowID, in: world, fromAnywhere: fromAnywhere).map { (pet, $0) } }
            .min { abs($0.1.launch.dx) < abs($1.1.launch.dx) }
    }

    private func launch(_ pet: Pet, _ plan: LeapPlan, mode: String?) {
        lastUse = clock
        let style = pet.appearance.skillStyle
        pet.switchTo(SkillLeapBehavior(plan: plan, style: style, hasActionFrames: pet.appearance.supports(.act)))
        var target = "stand"
        if case .peek = plan.target { target = "peek" }
        if case .cling = plan.target { target = "cling" }
        let label = [mode, target].compactMap { $0 }.joined(separator: ", ")
        onEvent?("🦘 [\(pet.id)] \(style.rawValue) → window \(plan.target.windowID) (\(label))")
    }
}
