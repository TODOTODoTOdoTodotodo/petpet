import Foundation

/// 팔 돌리기 (어깨를 축으로)
enum Turn {
    case none
    /// 위로 뒤집기 (손이 머리 위로)
    case up
    /// 앞으로 90도 (주먹 내밀기)
    case forward
}

/// 부위 하나의 자세
struct PartPose {
    var dx = 0
    var dy = 0
    var turn: Turn = .none
}

/// This object is responsible for one frame's pose: how far each part moves or turns from rest.
struct Pose {
    /// 전체 이동
    var dx = 0
    var dy = 0
    var parts: [String: PartPose] = [:]
    var eyesClosed = false
    /// 위로 든 팔을 머리 뒤로 그리고 발(손)끝이 머리 위로 나오게 늘림 (머리 큰 캐릭터의 매달리기·점프)
    var reachAboveHead = false

    /// 상체(몸·머리·팔·꼬리)를 함께 움직임
    static let torso = ["body", "head", "frontArm", "backArm", "tail"]

    mutating func move(_ names: [String], dx: Int = 0, dy: Int = 0) {
        for name in names {
            parts[name, default: PartPose()].dx += dx
            parts[name, default: PartPose()].dy += dy
        }
    }

    mutating func turn(_ names: [String], _ turn: Turn) {
        for name in names { parts[name, default: PartPose()].turn = turn }
    }
}

/// 한 동작의 프레임 목록
struct Animation {
    /// metadata.json의 애니메이션 키 (앱의 동작 칸 이름)
    let key: String
    let frames: [Pose]
    /// 손끝이 대기 자세의 머리 꼭대기 높이에 오도록 프레임 전체를 내림 (매달리기)
    var alignTopToIdle = false
}

/// This object is responsible for turning one set of drawn parts into every animation the app uses,
/// purely by moving, flipping and rotating parts. No frame is drawn twice, so all frames stay consistent.
enum Poser {
    static func animations(facingWest: Bool) -> [Animation] {
        let forward = facingWest ? -1 : 1
        return [idle(), walk(forward: forward), jump(), hang(), sleep(), attack(forward: forward)]
    }

    /// 숨쉬기 6프레임, 다섯 번째에 눈 깜빡임
    static func idle() -> Animation {
        let bob = [0, 0, 1, 1, 1, 0]
        return Animation(key: "Idle", frames: bob.enumerated().map { index, dy in
            var pose = Pose()
            pose.move(Pose.torso, dy: dy)
            pose.eyesClosed = index == 4
            return pose
        })
    }

    /// 걷기 8프레임: 다리 앞뒤 교차, 앞으로 넘어가는 다리는 1px 들림, 지나갈 때 몸이 살짝 뜸, 팔은 다리와 반대로
    static func walk(forward: Int) -> Animation {
        let stride = [2, 1, 0, -1, -2, -1, 0, 1]
        let bob = [0, 0, -1, 0, 0, 0, -1, 0]
        return Animation(key: "Walking", frames: stride.indices.map { index in
            let step = stride[index]
            var pose = Pose()
            pose.move(Pose.torso, dy: bob[index])
            pose.move(["frontLeg"], dx: step * forward, dy: (5...7).contains(index) ? -1 : 0)
            pose.move(["backLeg"], dx: -step * forward, dy: (1...3).contains(index) ? -1 : 0)
            let swing = step > 0 ? -1 : (step < 0 ? 1 : 0)
            pose.move(["frontArm"], dx: swing * forward)
            pose.move(["backArm"], dx: -swing * forward)
            return pose
        })
    }

    /// 공중 1프레임: 다리 접고 팔 위로
    static func jump() -> Animation {
        var pose = Pose()
        pose.move(["frontLeg", "backLeg"], dy: -2)
        pose.turn(["frontArm", "backArm"], .up)
        pose.reachAboveHead = true
        return Animation(key: "Jump", frames: [pose])
    }

    /// 매달리기 4프레임: 팔 위로, 다리 늘어뜨리고 좌우로 살랑
    static func hang() -> Animation {
        let sway = [0, 1, 0, -1]
        return Animation(key: "Hang", frames: sway.map { dx in
            var pose = Pose()
            pose.turn(["frontArm", "backArm"], .up)
            pose.reachAboveHead = true
            pose.move(["frontLeg", "backLeg"], dx: dx, dy: 1)
            pose.move(["tail"], dx: -dx)
            return pose
        }, alignTopToIdle: true)
    }

    /// 잠 2프레임: 눈 감고 머리를 떨군 채 숨쉬기
    static func sleep() -> Animation {
        Animation(key: "Sleep", frames: [1, 2].map { dy in
            var pose = Pose()
            pose.eyesClosed = true
            pose.move(Pose.torso, dy: dy)
            pose.move(["head"], dy: 1)
            return pose
        })
    }

    /// 공격 4프레임: 뒤로 젖혔다가 앞팔을 내지르며 한 발 나감
    static func attack(forward: Int) -> Animation {
        var windUp = Pose()
        windUp.move(Pose.torso, dx: -forward)
        var strike = Pose()
        strike.turn(["frontArm"], .forward)
        var lunge = strike
        lunge.dx = forward
        return Animation(key: "swing_attack", frames: [windUp, strike, lunge, Pose()])
    }
}
