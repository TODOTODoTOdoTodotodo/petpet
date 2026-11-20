import Foundation

/// This object is responsible for answering where pets can stand, climb and move,
/// given the displays and the front-to-back list of visible windows.
/// Only edges that are actually visible count, because pets are always drawn above every window.
final class World {
    private(set) var screens: [ScreenArea] = []
    /// 앞에서 뒤 순서
    private(set) var windows: [WindowSnapshot] = []
    private(set) var ledges: [Ledge] = []
    /// 거꾸로 붙어 다닐 수 있는 창 아랫변 (보이는 구간)
    private(set) var undersides: [Ledge] = []
    private(set) var walls: [Wall] = []
    private var windowsByID: [UInt32: WindowSnapshot] = [:]
    /// 사용자가 보고 있는 앱의 맨 앞 창
    private(set) var focusedWindowID: UInt32?
    /// 사용자가 보고 있는 앱의 번들 ID (앱 종류별 반응용)
    private(set) var focusedBundleID: String?

    /// 설 수 없을 만큼 짧은 발판·벽 조각 기준
    static let minimumEdgeLength: CGFloat = 24
    /// 아랫변이 그 모니터 바닥보다 이만큼은 높아야 매달릴 자리로 봄 (몸이 늘어질 공간)
    static let undersideClearance: CGFloat = 60

    func update(screens: [ScreenArea], windows: [WindowSnapshot]) {
        self.screens = screens
        self.windows = windows
        rebuild()
    }

    func update(windows: [WindowSnapshot]) {
        guard windows != self.windows else { return }
        self.windows = windows
        rebuild()
    }

    /// 맨 앞 앱의 프로세스 ID로 보고 있는 창을 정함 (앞에서 뒤 순서상 그 앱의 첫 창)
    func focus(processID: Int32?, bundleID: String? = nil) {
        focusedWindowID = processID.flatMap { pid in windows.first { $0.processID == pid }?.id }
        focusedBundleID = bundleID
    }

    // MARK: - Queries

    func window(id: UInt32) -> WindowSnapshot? {
        windowsByID[id]
    }

    /// 점을 덮고 있는 가장 앞쪽 창
    func frontWindow(at point: CGPoint) -> WindowSnapshot? {
        windows.first { $0.frame.contains(point) }
    }

    /// 창 안의 점이 앞쪽 다른 창에 가려지지 않고 보이는지
    func isVisible(_ point: CGPoint, onWindow id: UInt32) -> Bool {
        guard let index = windows.firstIndex(where: { $0.id == id }), windows[index].frame.contains(point) else { return false }
        return !windows[..<index].contains { $0.frame.contains(point) }
    }

    /// 점이 들어 있는 모니터
    func screen(containing point: CGPoint) -> ScreenArea? {
        screens.first { $0.frame.contains(point) }
    }

    /// 창이 주로 걸쳐 있는 모니터 (윗변 가운데 기준, 없으면 창 가운데)
    func screen(of window: WindowSnapshot) -> ScreenArea? {
        screen(containing: CGPoint(x: window.frame.midX, y: window.frame.maxY - 1))
            ?? screen(containing: CGPoint(x: window.frame.midX, y: window.frame.midY))
    }

    /// 점이 어느 모니터 안에든 있는지
    func contains(_ point: CGPoint) -> Bool {
        screens.contains { $0.frame.contains(point) }
    }

    /// x 위치에서 높이 y가 속한 사용 가능 영역의 윗변. 바로 위에 이어지는 영역이 있으면 함께 올라가고,
    /// 메뉴바처럼 끊긴 곳에서 멈춤 (위아래 모니터 사이의 메뉴바도 천장)
    func ceiling(atX x: CGFloat, above y: CGFloat) -> CGFloat? {
        let areas = screens
            .filter { x >= $0.frame.minX && x < $0.frame.maxX }
            .map(\.visibleFrame)
        guard !areas.isEmpty else { return nil }
        guard var top = areas.first(where: { $0.minY - 1 <= y && y < $0.maxY })?.maxY else {
            return areas.map(\.maxY).max()
        }
        while let above = areas.first(where: { abs($0.minY - top) <= 1 && $0.maxY > top }) {
            top = above.maxY
        }
        return top
    }

    /// x 위치의 가장 낮은 바닥 발판
    func floor(atX x: CGFloat) -> Ledge? {
        ledges
            .filter { $0.owner.windowID == nil && $0.spans(x) }
            .min { $0.y < $1.y }
    }

    /// y 근처(tolerance 이내)에서 x를 지나는 보이는 발판. 가장 가까운 높이 우선
    func ledge(atX x: CGFloat, nearY y: CGFloat, tolerance: CGFloat = 3, margin: CGFloat = 0) -> Ledge? {
        ledges
            .filter { abs($0.y - y) <= tolerance && $0.spans(x, margin: margin) }
            .min { abs($0.y - y) < abs($1.y - y) }
    }

    /// fromY에서 toY로 내려가는 동안 x에서 처음 만나는(가장 높은) 발판
    func landingLedge(atX x: CGFloat, from fromY: CGFloat, to toY: CGFloat) -> Ledge? {
        guard fromY >= toY else { return nil }
        return ledges
            .filter { $0.y <= fromY + 0.5 && $0.y >= toY && $0.spans(x, margin: 2) }
            .max { $0.y < $1.y }
    }

    /// 높이 y 근처에서 x를 지나는 보이는 창 아랫변
    func underside(atX x: CGFloat, nearY y: CGFloat, tolerance: CGFloat = 3) -> Ledge? {
        undersides
            .filter { abs($0.y - y) <= tolerance && $0.spans(x) }
            .min { abs($0.y - y) < abs($1.y - y) }
    }

    /// 점 바로 위(같은 x)에서 처음 만나는 보이는 창 아랫변
    func underside(above point: CGPoint) -> Ledge? {
        undersides
            .filter { $0.y >= point.y && $0.spans(point.x) }
            .min { $0.y < $1.y }
    }

    /// 점 바로 아래(같은 x)에서 처음 만나는 보이는 발판 (마우스 포인터가 떠 있는 곳의 바닥)
    func ledge(under point: CGPoint) -> Ledge? {
        landingLedge(atX: point.x, from: point.y, to: -.greatestFiniteMagnitude)
    }

    /// 몸 앞쪽이 fromX에서 toX로 움직일 때 부딪히는 보이는 벽 중 가장 가까운 것
    func wall(hitMovingEast movingEast: Bool, from fromX: CGFloat, to toX: CGFloat, bottom: CGFloat, top: CGFloat) -> Wall? {
        let face: WallFace = movingEast ? .left : .right
        let candidates = walls.filter { wall in
            guard wall.face == face, wall.minY < top, wall.maxY > bottom + 4 else { return false }
            return movingEast
                ? (fromX <= wall.x + 0.5 && toX >= wall.x)
                : (fromX >= wall.x - 0.5 && toX <= wall.x)
        }
        return movingEast
            ? candidates.min { $0.x < $1.x }
            : candidates.max { $0.x < $1.x }
    }

    /// 창 옆면 중 높이 y를 포함하는 보이는 조각
    func visibleWall(windowID: UInt32, face: WallFace, coveringY y: CGFloat) -> Wall? {
        walls.first { $0.windowID == windowID && $0.face == face && $0.minY <= y && y <= $0.maxY }
    }

    /// 새 펫이 떨어지기 시작할 위치 (주 모니터 가운데 위쪽)
    var spawnPoint: CGPoint {
        spawnPoint(onScreen: nil)
    }

    /// 그 모니터 가운데 위쪽 (없으면 주 모니터)
    func spawnPoint(onScreen id: UInt32?) -> CGPoint {
        let main = screens.first { $0.frame.origin == .zero } ?? screens.first
        let screen = id.flatMap { id in screens.first { $0.id == id } } ?? main
        guard let area = screen?.visibleFrame else { return CGPoint(x: 400, y: 400) }
        return CGPoint(x: area.midX, y: area.maxY - area.height * 0.25)
    }

    // MARK: - Building edges

    private func rebuild() {
        windowsByID = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var newLedges = groundLedges()
        var newWalls: [Wall] = []
        var newUndersides: [Ledge] = []
        for (index, window) in windows.enumerated() {
            let front = Array(windows[..<index])
            newLedges += topLedges(of: window, behind: front)
            newWalls += sideWalls(of: window, behind: front)
            newUndersides += bottomEdges(of: window, behind: front)
        }
        ledges = newLedges
        walls = newWalls
        undersides = newUndersides
    }

    /// 모니터 바닥. 아래에 다른 모니터가 붙어 있어도 막혀 있음
    /// (아래 모니터의 메뉴바가 올라가는 천장이듯 내려가는 바닥. 모니터 사이는 건너가기로만 오감)
    private func groundLedges() -> [Ledge] {
        screens
            .filter { $0.frame.width >= Self.minimumEdgeLength }
            .map { Ledge(owner: .ground(screenID: $0.id), y: $0.visibleFrame.minY, minX: $0.frame.minX, maxX: $0.frame.maxX) }
    }

    /// 창 윗변 중 화면 안에 있고 앞 창에 가려지지 않은 구간
    private func topLedges(of window: WindowSnapshot, behind front: [WindowSnapshot]) -> [Ledge] {
        let y = window.frame.maxY
        let onScreen = screens
            .filter { $0.frame.minY <= y && y < $0.frame.maxY }
            .map { (lo: $0.frame.minX, hi: $0.frame.maxX) }
        let covers = front
            .filter { $0.frame.minY <= y && y < $0.frame.maxY }
            .map { (lo: $0.frame.minX, hi: $0.frame.maxX) }
        return SpanMath.intersect((window.frame.minX, window.frame.maxX), onScreen)
            .flatMap { SpanMath.subtract($0, covers) }
            .filter { $0.hi - $0.lo >= Self.minimumEdgeLength }
            .map { Ledge(owner: .window(id: window.id), y: y, minX: $0.lo, maxX: $0.hi) }
    }

    /// 창 아랫변 중 화면 안에 있고 앞 창에 가려지지 않으며, 그 모니터 바닥보다 충분히 높은 구간
    private func bottomEdges(of window: WindowSnapshot, behind front: [WindowSnapshot]) -> [Ledge] {
        let y = window.frame.minY
        let onScreen = screens
            .filter { $0.frame.minY < y && y <= $0.frame.maxY && y >= $0.visibleFrame.minY + Self.undersideClearance }
            .map { (lo: $0.frame.minX, hi: $0.frame.maxX) }
        let covers = front
            .filter { $0.frame.minY < y && y <= $0.frame.maxY }
            .map { (lo: $0.frame.minX, hi: $0.frame.maxX) }
        return SpanMath.intersect((window.frame.minX, window.frame.maxX), onScreen)
            .flatMap { SpanMath.subtract($0, covers) }
            .filter { $0.hi - $0.lo >= Self.minimumEdgeLength }
            .map { Ledge(owner: .window(id: window.id), y: y, minX: $0.lo, maxX: $0.hi) }
    }

    /// 창 옆변 중 화면 안에 있고 앞 창에 가려지지 않은 구간
    private func sideWalls(of window: WindowSnapshot, behind front: [WindowSnapshot]) -> [Wall] {
        [WallFace.left, .right].flatMap { face -> [Wall] in
            let x = face == .left ? window.frame.minX : window.frame.maxX
            let onScreen = screens
                .filter { x >= $0.frame.minX - 1 && x <= $0.frame.maxX + 1 }
                .map { (lo: $0.frame.minY, hi: $0.frame.maxY) }
            let covers = front
                .filter { $0.frame.minX < x && x < $0.frame.maxX }
                .map { (lo: $0.frame.minY, hi: $0.frame.maxY) }
            return SpanMath.intersect((window.frame.minY, window.frame.maxY), onScreen)
                .flatMap { SpanMath.subtract($0, covers) }
                .filter { $0.hi - $0.lo >= Self.minimumEdgeLength }
                .map { Wall(windowID: window.id, face: face, x: x, minY: $0.lo, maxY: $0.hi) }
        }
    }
}
