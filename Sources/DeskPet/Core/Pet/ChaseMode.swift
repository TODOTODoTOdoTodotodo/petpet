import Foundation

/// 펫들이 쫓아갈 곳 (한 틱 기준)
struct ChaseTarget: Equatable {
    /// 스킬 도약으로 올라갈 창. 없으면 도약하지 않음
    var windowID: UInt32?
    /// 아랫변에 거꾸로 붙으러 갈 창 (포인터가 창 바로 밑에 있을 때)
    var clingWindowID: UInt32?
    /// 펫들이 모일 모니터
    var screenID: UInt32?
    /// 모니터를 건너온 펫이 모일 가로 위치
    var anchorX: CGFloat?
    /// 걸어서 따라갈 지점 (마우스 포인터 모드에서만)
    var point: CGPoint?
    /// 다른 모니터의 펫을 쫓는 곳으로 모을지 (알아서 놀기면 모으지 않음)
    var gathers = true

    static let none = ChaseTarget()
}

/// This object is responsible for deciding, each tick, where the pets should gather:
/// which window to leap onto, which display to cross to, and whether there is a point to walk toward.
protocol ChaseMode: AnyObject {
    /// 메뉴·설정에 쓰는 이름
    var key: String { get }
    func target(in world: World, cursor: CGPoint?, dt: TimeInterval) -> ChaseTarget
}

/// This object is responsible for the default chase: the window the user is working in (front app's first window),
/// and the display that window is on.
final class ActiveWindowChase: ChaseMode {
    static let key = "activeWindow"
    var key: String { Self.key }

    func target(in world: World, cursor: CGPoint?, dt: TimeInterval) -> ChaseTarget {
        guard let id = world.focusedWindowID, let window = world.window(id: id) else { return .none }
        return ChaseTarget(windowID: id, screenID: world.screen(of: window)?.id, anchorX: window.frame.midX)
    }
}

/// This object is responsible for chasing the mouse pointer: the pets walk toward the spot under it,
/// leap onto the window whose top edge is right below it — or cling to the underside of the window right above it,
/// when the pointer is just below a window — once the pointer rests there for a moment
/// (so sweeping across windows does not send them bouncing around), and gather on the pointer's display.
final class PointerChase: ChaseMode {
    static let key = "pointer"
    var key: String { Self.key }

    /// 포인터 아래 창이 이만큼 그대로여야 그 창으로 도약
    static let settleTime: TimeInterval = 0.6
    /// 포인터가 창 아랫변 밑으로 이 안에 있으면 그 아랫변으로 감
    static let clingReach: CGFloat = 150

    /// 포인터가 가리키는 자리: 창 윗변 위, 또는 창 아랫변 밑
    private enum Spot: Equatable {
        case top(UInt32)
        case underside(UInt32)
    }

    private var clock: TimeInterval = 0
    private var candidate: Spot?
    private var candidateSince: TimeInterval = 0
    private var settled: Spot?
    private var last = ChaseTarget.none

    func target(in world: World, cursor: CGPoint?, dt: TimeInterval) -> ChaseTarget {
        clock += dt
        // 포인터를 모르면(화면 밖 등) 직전 목표 유지
        guard let cursor, world.contains(cursor) else { return last }
        let spot = Self.spot(at: cursor, in: world)
        if spot != candidate {
            candidate = spot
            candidateSince = clock
        }
        if clock - candidateSince >= Self.settleTime { settled = candidate }
        var target = ChaseTarget(screenID: world.screen(containing: cursor)?.id, anchorX: cursor.x, point: cursor)
        switch settled {
        case .top(let id) where world.window(id: id) != nil: target.windowID = id
        case .underside(let id) where world.window(id: id) != nil: target.clingWindowID = id
        default: break
        }
        last = target
        return last
    }

    /// 바로 위 가까이에 창 아랫변이 있으면 그 아랫변, 아니면 바로 아래 발판의 창
    private static func spot(at cursor: CGPoint, in world: World) -> Spot? {
        if let ceiling = world.underside(above: cursor), ceiling.y - cursor.y <= clingReach, let id = ceiling.owner.windowID {
            return .underside(id)
        }
        // 열거형 케이스를 함수로 넘기면(.map(Spot.top)) 윈도우 Swift 6.3.3 릴리스 최적화가 멈춰서 풀어 씀
        guard let id = world.ledge(under: cursor)?.owner.windowID else { return nil }
        return .top(id)
    }
}

/// This object is responsible for chasing nothing: the pets roam and play on their own, without leaping
/// to the window the user works in, walking after the pointer, or gathering on another display.
final class FreeRoamChase: ChaseMode {
    static let key = "free"
    var key: String { Self.key }

    func target(in world: World, cursor: CGPoint?, dt: TimeInterval) -> ChaseTarget {
        ChaseTarget(gathers: false)
    }
}

/// 설정 이름으로 쫓기 방식을 만듦 (모르는 이름이면 활성 창)
enum ChaseModes {
    static func make(_ key: String?) -> ChaseMode {
        switch key {
        case PointerChase.key: PointerChase()
        case FreeRoamChase.key: FreeRoamChase()
        default: ActiveWindowChase()
        }
    }
}
