import CoreGraphics
import Foundation

/// This object is responsible for counting and printing check results.
final class Checker {
    private(set) var failures = 0
    private(set) var total = 0

    func section(_ name: String) {
        print("\n\(name)")
    }

    func expect(_ condition: Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
        total += 1
        if condition {
            print("  ✓ \(label)")
        } else {
            failures += 1
            print("  ✗ \(label) \(detail())")
        }
    }
}

/// This object is responsible for a body-only pet look used in simulation checks.
final class FakeAppearance: PetAppearance {
    let name = "Fake"
    let body = BodyMetrics(footInset: 0, width: 24, height: 40, centerX: 24)
    let skillStyle: SkillStyle = .bigJump
    private let hasAction: Bool

    init(hasAction: Bool = false) {
        self.hasAction = hasAction
    }

    func supports(_ kind: AnimationKind) -> Bool {
        kind == .act ? hasAction : true
    }

    func cycleDuration(of kind: AnimationKind, facing: Facing) -> TimeInterval {
        kind == .act && hasAction ? 0.6 : 0
    }
}

/// This object is responsible for always returning the same number, forcing every chance to pass.
final class FixedRandom: RandomSource {
    private let value: Double
    init(_ value: Double) { self.value = value }
    func next() -> Double { value }
}

/// This object is responsible for the scripted screens and the 60Hz stepping used by checks.
enum Sim {
    static let dt: TimeInterval = 1.0 / 60

    /// 1600x1000, Dock 80pt, 메뉴바 25pt
    static let main = ScreenArea(
        id: 1, name: "Main",
        frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
        visibleFrame: CGRect(x: 0, y: 80, width: 1600, height: 815),
        backingScale: 2
    )

    static func world(screens: [ScreenArea] = [main], windows: [WindowSnapshot] = []) -> World {
        let world = World()
        world.update(screens: screens, windows: windows)
        return world
    }

    static func window(_ id: UInt32, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> WindowSnapshot {
        WindowSnapshot(id: id, owner: "App\(id)", frame: CGRect(x: x, y: y, width: width, height: height), processID: Int32(id))
    }

    static func pet(at point: CGPoint, appearance: PetAppearance = FakeAppearance(), behavior: PetBehavior) -> Pet {
        Pet(id: "Check", appearance: appearance, scale: 1.5, position: point, behavior: behavior)
    }

    /// seconds 동안(또는 stop이 참이 될 때까지) 진행하고 거친 행동 이름 목록을 돌려줌
    @discardableResult
    static func run(_ pet: Pet, in world: World, planner: BehaviorPlanner, seconds: Double,
                    cursor: CGPoint? = nil, idleSeconds: TimeInterval = 0, until stop: ((Pet) -> Bool)? = nil) -> [String] {
        var names = [pet.behavior.name]
        let context = PetContext(cursor: cursor, planner: planner, idleSeconds: idleSeconds)
        var elapsed = 0.0
        while elapsed < seconds {
            pet.step(dt: dt, in: world, context: context)
            if names.last != pet.behavior.name { names.append(pet.behavior.name) }
            elapsed += dt
            if let stop, stop(pet) { break }
        }
        return names
    }

    static func isGrounded(_ pet: Pet) -> Bool {
        !(pet.behavior is AirborneBehavior) && !(pet.behavior is ClimbBehavior)
    }
}
