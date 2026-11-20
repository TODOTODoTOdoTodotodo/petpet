import Foundation

/// This object is responsible for a pet's entrance when the app starts or a pet is added:
/// staying out of sight until its turn, then dropping from just under the menu bar onto the window
/// the user is looking at (spread out from the others, so they land side by side), and waving 👋 at the user on landing.
/// With no window to land on, it drops onto the floor of that display instead.
final class EntranceBehavior: PetBehavior {
    let name = "entering"
    let animation: AnimationKind = .idle
    private let delay: TimeInterval
    /// 몇 번째로 내려오는지 (자리 벌리기용)
    private let order: Int
    private var elapsed: TimeInterval = 0

    /// 앱을 켠 뒤 첫 펫이 내려오기까지 (창 목록·보는 창을 읽을 시간)
    static let firstDelay: TimeInterval = 0.6
    /// 다음 펫이 내려오는 간격
    static let stagger: TimeInterval = 0.45
    /// 내려앉는 자리 사이 간격 (기준 크기)
    static let spacing: CGFloat = 70
    /// 메뉴바 바로 밑에서 떨어지기 시작하는 틈
    static let dropGap: CGFloat = 4

    init(order: Int, delay: TimeInterval) {
        self.order = order
        self.delay = delay
    }

    /// 앱을 켤 때 order번째 펫
    static func startup(order: Int) -> EntranceBehavior {
        EntranceBehavior(order: order, delay: firstDelay + Double(order) * stagger)
    }

    var opacity: CGFloat { 0 }

    func begin(_ pet: Pet) {
        pet.support = nil
        pet.velocity = .zero
    }

    func step(_ pet: Pet, in world: World, context: PetContext, dt: TimeInterval) -> PetBehavior? {
        elapsed += dt
        guard elapsed >= delay else { return nil }
        pet.position = Self.dropPoint(for: pet, order: order, in: world)
        return AirborneBehavior(name: "droppingIn", launch: .zero, landingRemark: Chatter.hello)
    }

    /// 보는 창 윗변 위(가운데부터 번갈아 벌림) 메뉴바 바로 밑. 그 x에서 떨어지면 처음 닿는 곳이 그 창인 자리만 고름.
    /// 그런 자리가 없으면 그 모니터(없으면 주 모니터) 바닥 위
    static func dropPoint(for pet: Pet, order: Int, in world: World) -> CGPoint {
        let window = world.focusedWindowID.flatMap(world.window(id:))
        let screen = window.flatMap(world.screen(of:)) ?? world.screen(containing: world.spawnPoint)
        let top = (screen?.visibleFrame.maxY ?? world.spawnPoint.y) - pet.bodyHeight - dropGap
        let k = pet.motionScale
        let step = spacing * k
        let offsets = (0..<12).map { DisplayFollowCoordinator.offset(forArrival: order + $0) / DisplayFollowCoordinator.spacing * step }

        if let window {
            let owner = SurfaceOwner.window(id: window.id)
            let spans = world.ledges.filter { $0.owner == owner && $0.maxX - $0.minX >= 2 * pet.bodyHalfWidth }
            for offset in offsets {
                let wanted = window.frame.midX + offset
                // 가장 가까운 보이는 윗변 구간 안으로
                guard let span = spans.min(by: { distance(wanted, $0) < distance(wanted, $1) }) else { break }
                let x = min(max(wanted, span.minX + pet.bodyHalfWidth), span.maxX - pet.bodyHalfWidth)
                if top > span.y, world.landingLedge(atX: x, from: top, to: span.y - 1)?.owner == owner {
                    return CGPoint(x: x, y: top)
                }
            }
        }
        let area = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let center = window.map { min(max($0.frame.midX, area.minX), area.maxX) } ?? area.midX
        let x = min(max(center + offsets[0], area.minX + pet.bodyHalfWidth), area.maxX - pet.bodyHalfWidth)
        return CGPoint(x: x, y: top)
    }

    private static func distance(_ x: CGFloat, _ ledge: Ledge) -> CGFloat {
        x < ledge.minX ? ledge.minX - x : (x > ledge.maxX ? x - ledge.maxX : 0)
    }
}
