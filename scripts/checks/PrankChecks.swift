import CoreGraphics
import Foundation

/// This object is responsible for checking the opt-in pointer prank: a pet snatches a pointer resting by it,
/// dashes off holding it, lets go on its own or the instant the user moves the mouse, and never pranks
/// when turned off, during calls, right after typing, or again too soon.
enum PrankChecks {
    static func run(_ check: Checker) {
        snatching(check)
        restraint(check)
    }

    private static func setup(seed: UInt64, enabled: Bool = true, windows: [WindowSnapshot] = [], y: CGFloat = 80) -> (PetRoster, World, Pet) {
        let world = Sim.world(windows: windows)
        let roster = PetRoster(planner: BehaviorPlanner(random: SeededRandomSource(seed: seed)))
        roster.pranks.isEnabled = enabled
        let pet = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
        pet.position = CGPoint(x: 800, y: y)
        pet.settle(in: world)
        pet.switchTo(IdleBehavior(duration: 999))
        return (roster, world, pet)
    }

    /// 앱처럼 진행: 펫이 쥐고 있으면 다음 틱 포인터는 그 자리 (사용자가 움직이면 nudge만큼 벗어남)
    private static func run(_ roster: PetRoster, in world: World, cursor: inout CGPoint, seconds: Double,
                            keyPresses: Int = 0, nudge: CGVector? = nil, until stop: (() -> Bool)? = nil) {
        for _ in 0..<Int(seconds * 60) {
            roster.step(dt: Sim.dt, in: world, cursor: cursor, keyPresses: keyPresses)
            if let held = roster.heldCursor { cursor = held }
            if let nudge, roster.heldCursor != nil { cursor.x += nudge.dx; cursor.y += nudge.dy }
            if let stop, stop() { return }
        }
    }

    /// 펫 몸 위에 포인터를 두고 기다리기를 몇 번 (멈춤마다 한 번 굴림). 잡으면 true
    private static func restUntilSnatched(_ roster: PetRoster, world: World, pet: Pet, cursor: inout CGPoint, tries: Int = 10, keyPresses: Int = 0) -> Bool {
        for attempt in 0..<tries {
            cursor = CGPoint(x: pet.position.x + CGFloat(attempt % 3) * 3, y: pet.position.y + 20)
            run(roster, in: world, cursor: &cursor, seconds: CursorPrankCoordinator.stillTime + 0.3, keyPresses: keyPresses,
                until: { pet.behavior is CursorCarryBehavior })
            if pet.behavior is CursorCarryBehavior { return true }
        }
        return false
    }

    private static func snatching(_ check: Checker) {
        check.section("포인터 장난: 들고 달아나기")
        do {
            let (roster, world, pet) = setup(seed: 111)
            var cursor = CGPoint.zero
            check.expect(restUntilSnatched(roster, world: world, pet: pet, cursor: &cursor), "펫 곁에 멈춘 포인터를 가끔 잡음")
            check.expect(pet.speech?.text == CursorCarryBehavior.grabText && roster.heldCursor == CursorCarryBehavior.hand(of: pet),
                         "😆 하고 손에 쥠")
            let start = cursor
            var followed = true
            run(roster, in: world, cursor: &cursor, seconds: 3, until: {
                if let held = roster.heldCursor, held != CursorCarryBehavior.hand(of: pet) { followed = false }
                return roster.heldCursor == nil
            })
            check.expect(followed && abs(cursor.x - start.x) > 60 && abs(cursor.x - start.x) < 300,
                         "1초쯤 달리며 포인터를 끌고 감", "\(cursor.x - start.x)")
            check.expect(roster.heldCursor == nil && pet.speech?.text == CursorCarryBehavior.doneText, "다 달리면 😝 하고 놓음")
            let dropped = cursor
            run(roster, in: world, cursor: &cursor, seconds: 1)
            check.expect(cursor == dropped, "놓은 뒤에는 포인터를 건드리지 않음")
        }
        do {
            let (roster, world, pet) = setup(seed: 112)
            var cursor = CGPoint.zero
            _ = restUntilSnatched(roster, world: world, pet: pet, cursor: &cursor)
            run(roster, in: world, cursor: &cursor, seconds: 0.3)
            run(roster, in: world, cursor: &cursor, seconds: Sim.dt * 3, nudge: CGVector(dx: 0, dy: 25))
            check.expect(roster.heldCursor == nil && !(pet.behavior is CursorCarryBehavior) && pet.speech?.text == Chatter.surprised,
                         "사용자가 마우스를 움직이면 바로 돌려주고 깜짝", pet.behavior.name)
        }
        do {
            // 한쪽에 다른 펫이 붙어 있으면 비어 있는 쪽으로 달아남
            let (roster, world, pet) = setup(seed: 119)
            let neighbor = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
            // 넓이가 같으면 동쪽을 고르므로, 동쪽에 붙여 두어야 고친 규칙을 확인함
            neighbor.position = CGPoint(x: pet.position.x + 2 * pet.bodyHalfWidth + 6, y: 80)
            neighbor.settle(in: world)
            neighbor.switchTo(IdleBehavior(duration: 999, lookAtUser: true))
            let other = roster.add(appearance: FakeAppearance(), scale: 1.5, in: world)
            other.position = CGPoint(x: 100, y: 80)
            other.settle(in: world)
            other.switchTo(IdleBehavior(duration: 999, lookAtUser: true))
            var cursor = CGPoint.zero
            _ = restUntilSnatched(roster, world: world, pet: pet, cursor: &cursor)
            let start = pet.position.x
            run(roster, in: world, cursor: &cursor, seconds: 3, until: { roster.heldCursor == nil })
            check.expect(start - pet.position.x > 60, "옆 펫이 막은 쪽이 아닌 빈 쪽으로 달아남", "\(pet.position.x - start)")
        }
        do {
            // 창 위에서는 끝에서 멈추고 떨어지지 않음
            let (roster, world, pet) = setup(seed: 113, windows: [Sim.window(7, 700, 300, 260, 300)], y: 600)
            var cursor = CGPoint.zero
            _ = restUntilSnatched(roster, world: world, pet: pet, cursor: &cursor)
            run(roster, in: world, cursor: &cursor, seconds: 3, until: { roster.heldCursor == nil })
            check.expect(pet.perchWindowID == 7 && pet.position.x <= 960 - pet.bodyHalfWidth + 1 && pet.position.x >= 700 + pet.bodyHalfWidth - 1,
                         "창 끝에서 멈추고 떨어지지 않음", "\(pet.position)")
        }
    }

    private static func restraint(_ check: Checker) {
        check.section("포인터 장난: 하지 않을 때")
        do {
            let (roster, world, pet) = setup(seed: 114, enabled: false)
            var cursor = CGPoint.zero
            check.expect(!restUntilSnatched(roster, world: world, pet: pet, cursor: &cursor) && roster.heldCursor == nil,
                         "기본은 꺼져 있음 (Pointer Pranks)")
        }
        do {
            let (roster, world, pet) = setup(seed: 115)
            roster.isQuiet = true
            var cursor = CGPoint.zero
            check.expect(!restUntilSnatched(roster, world: world, pet: pet, cursor: &cursor), "통화 중에는 하지 않음")
        }
        do {
            let (roster, world, pet) = setup(seed: 116)
            var cursor = CGPoint.zero
            check.expect(!restUntilSnatched(roster, world: world, pet: pet, cursor: &cursor, keyPresses: 1), "키를 누르는 중에는 하지 않음")
        }
        do {
            let (roster, world, pet) = setup(seed: 117)
            var cursor = CGPoint(x: pet.position.x + 200, y: pet.position.y + 20)
            run(roster, in: world, cursor: &cursor, seconds: 20)
            check.expect(!(pet.behavior is CursorCarryBehavior) && roster.heldCursor == nil, "펫에서 먼 포인터는 잡지 않음")
        }
        do {
            let (roster, world, pet) = setup(seed: 118)
            var cursor = CGPoint.zero
            _ = restUntilSnatched(roster, world: world, pet: pet, cursor: &cursor)
            run(roster, in: world, cursor: &cursor, seconds: 3, until: { roster.heldCursor == nil })
            pet.switchTo(IdleBehavior(duration: 999))
            check.expect(!restUntilSnatched(roster, world: world, pet: pet, cursor: &cursor, tries: 20), "한 번 장난친 뒤 2분은 쉼")
        }
    }
}
