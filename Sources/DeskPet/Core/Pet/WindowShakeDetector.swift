import Foundation

/// 이번 틱에 흔들린 창과, 마지막으로 움직인 속도 (pt/s)
struct WindowShake: Equatable {
    let windowID: UInt32
    let push: CGVector
}

/// This object is responsible for noticing when the user shakes a window back and forth
/// (left-right-left, or up-down-up, quickly), watching only the windows pets are on.
/// A single drag, a slow nudge or a jump to another place (maximize) is not a shake.
final class WindowShakeDetector {
    /// 한 번 휘두른 것으로 칠 최소 이동 거리
    static let minSwing: CGFloat = 40
    /// 흔들기로 볼 휘두름 횟수 (좌·우·좌)
    static let swingsToShake = 3
    /// 그 횟수가 이 시간 안에 있어야 함
    static let shakeWindow: TimeInterval = 1.5

    /// This object is responsible for counting swings along one axis: a swing ends when the window turns back after travelling far enough.
    private struct Axis {
        private var direction: CGFloat = 0
        private var travel: CGFloat = 0
        private var swings: [TimeInterval] = []

        /// 이 축으로 d만큼 움직임. 흔들기가 되면 true
        mutating func move(_ d: CGFloat, at time: TimeInterval) -> Bool {
            swings.removeAll { time - $0 > WindowShakeDetector.shakeWindow }
            guard abs(d) > 0.5 else { return false }
            let sign: CGFloat = d > 0 ? 1 : -1
            if sign == direction {
                travel += abs(d)
            } else {
                if direction != 0 && travel >= WindowShakeDetector.minSwing { swings.append(time) }
                direction = sign
                travel = abs(d)
            }
            // 지금 휘두르는 중인 것도 충분히 움직였으면 셈
            let current = travel >= WindowShakeDetector.minSwing ? 1 : 0
            return swings.count + current >= WindowShakeDetector.swingsToShake
        }
    }

    /// This object is responsible for one watched window's last place and its swings.
    private struct Track {
        var origin: CGPoint
        var movedAt: TimeInterval
        var x = Axis()
        var y = Axis()
    }

    private var tracks: [UInt32: Track] = [:]
    private var clock: TimeInterval = 0

    /// watching 창들의 움직임을 살피고 이번 틱에 흔들린 창을 돌려줌. 살피지 않는 창의 기록은 버림
    func step(dt: TimeInterval, world: World, watching ids: Set<UInt32>) -> [WindowShake] {
        clock += dt
        tracks = tracks.filter { ids.contains($0.key) }
        var shakes: [WindowShake] = []
        for id in ids {
            guard let origin = world.window(id: id)?.frame.origin else {
                tracks[id] = nil
                continue
            }
            guard var track = tracks[id] else {
                tracks[id] = Track(origin: origin, movedAt: clock)
                continue
            }
            let dx = origin.x - track.origin.x
            let dy = origin.y - track.origin.y
            guard dx != 0 || dy != 0 else { continue }
            // 순간이동(최대화·모니터 이동)은 흔들기가 아님
            if hypot(dx, dy) > Pet.maxRideStep {
                tracks[id] = Track(origin: origin, movedAt: clock)
                continue
            }
            let interval = max(clock - track.movedAt, 1.0 / 60)
            let shookX = track.x.move(dx, at: clock)
            let shookY = track.y.move(dy, at: clock)
            if shookX || shookY {
                shakes.append(WindowShake(windowID: id, push: CGVector(dx: dx / interval, dy: dy / interval)))
                tracks[id] = Track(origin: origin, movedAt: clock)
                continue
            }
            track.origin = origin
            track.movedAt = clock
            tracks[id] = track
        }
        return shakes
    }
}
