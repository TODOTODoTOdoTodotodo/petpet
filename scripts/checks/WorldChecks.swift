import Foundation

/// This object is responsible for checking which window edges the world treats as visible ledges and walls.
enum WorldChecks {
    static func run(_ check: Checker) {
        check.section("World: 보이는 면만 발판·벽")

        // A(뒤) 위를 B(앞)가 일부 덮음
        let a = Sim.window(1, 200, 300, 600, 400)   // top 700
        let b = Sim.window(2, 500, 500, 600, 400)   // top 900
        let world = Sim.world(windows: [b, a])

        let aLedges = world.ledges.filter { $0.owner == .window(id: 1) }
        check.expect(aLedges.count == 1 && aLedges[0].minX == 200 && aLedges[0].maxX == 500 && aLedges[0].y == 700,
                     "가려진 창 윗변은 보이는 구간 [200,500]만 발판", "\(aLedges)")

        let bLedges = world.ledges.filter { $0.owner == .window(id: 2) }
        check.expect(bLedges.count == 1 && bLedges[0].minX == 500 && bLedges[0].maxX == 1100,
                     "앞 창 윗변은 전체가 발판", "\(bLedges)")

        let aRight = world.walls.filter { $0.windowID == 1 && $0.face == .right }
        check.expect(aRight.count == 1 && aRight[0].minY == 300 && aRight[0].maxY == 500,
                     "가려진 창 오른쪽 면은 앞 창 아래 구간 [300,500]만 벽", "\(aRight)")

        let ground = world.ledges.filter { $0.owner == .ground(screenID: 1) }
        check.expect(ground.count == 1 && ground[0].y == 80, "바닥은 Dock 위(80)", "\(ground)")

        // 화면 위로 삐져나간 창 윗변은 발판 아님
        let tall = Sim.world(windows: [Sim.window(5, 100, 200, 300, 900)])  // top 1100 > 1000
        check.expect(tall.ledges.allSatisfy { $0.owner != .window(id: 5) }, "화면 밖 윗변은 발판 아님")

        // 위아래로 붙은 모니터: 위 모니터 바닥도 막혀 있음 (모니터 사이는 건너가기로만)
        let upper = ScreenArea(id: 2, name: "Upper", frame: CGRect(x: 0, y: 1000, width: 1600, height: 900),
                               visibleFrame: CGRect(x: 0, y: 1000, width: 1600, height: 900), backingScale: 2)
        let stacked = Sim.world(screens: [Sim.main, upper])
        let upperFloor = stacked.ledges.filter { $0.owner == .ground(screenID: 2) }
        check.expect(upperFloor.count == 1 && upperFloor[0].y == 1000 && upperFloor[0].maxX - upperFloor[0].minX == 1600,
                     "위 모니터 바닥도 막혀 있음", "\(upperFloor)")
    }
}
