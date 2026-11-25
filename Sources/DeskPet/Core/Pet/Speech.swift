import Foundation

/// This object is responsible for one speech bubble's text, kind and remaining time.
/// Notices (schedule) outrank chatter (reactions) and stay until the user acknowledges them,
/// growing a little in steps while the user is around and leaves them unanswered.
struct Speech: Equatable {
    enum Kind: Equatable {
        /// 반응용 짧은 기호
        case chatter
        /// 일정 안내 (확인할 때까지 유지)
        case notice
    }

    let text: String
    let kind: Kind
    var remaining: TimeInterval
    /// 알림이 가리키는 일정 ID (같은 일정의 다음 알림은 문구만 바꾸기 위함)
    var topic: String?
    /// 남에게 보이면 안 될 때(통화 중) 대신 보여 줄 문구
    var discreetText: String?
    /// 글자 앞에 붙는 작은 그림 (신호를 보낸 앱 아이콘)
    var badge: SpeechBadge?
    /// 이 말풍선을 든 펫을 누르면 앞으로 불러올 앱의 프로세스 ID
    var appProcessID: Int32?
    /// 사용자가 자리에 있는 동안 떠 있던 시간 (자리를 비운 동안은 늘지 않음)
    var age: TimeInterval = 0

    /// 알림이 커지는 단계 (떠 있던 시간, 배율). 마지막 배율이 상한
    static let swellSteps: [(age: TimeInterval, scale: CGFloat)] = [(300, 1.15), (900, 1.3)]
    /// 입력이 이보다 오래 없으면 자리를 비운 것으로 보고 나이를 세지 않음
    static let presenceLimit: TimeInterval = 60

    /// 그릴 배율. 잡담은 늘 1, 알림은 오래 둘수록 단계별로 커짐
    var swell: CGFloat {
        guard kind == .notice else { return 1 }
        return Self.swellSteps.last { age >= $0.age }?.scale ?? 1
    }

    /// 알림이면 다시 띄울 수 있는 알림 내용 (구겨 던질 때 더미에 남김)
    var notice: ScheduleNotice? {
        guard kind == .notice, let topic else { return nil }
        return ScheduleNotice(topic: topic, text: text, discreetText: discreetText, badge: badge, appProcessID: appProcessID)
    }

    /// 통화 중 보여 줄 말풍선 (제목 없는 문구가 있으면 그것으로, 커지지 않음)
    var discreet: Speech {
        var copy = self
        if let discreetText {
            copy = Speech(text: discreetText, kind: kind, remaining: remaining, topic: topic, badge: badge, appProcessID: appProcessID)
        }
        copy.age = 0
        return copy
    }

    /// 지금 말풍선을 새 말이 덮어쓸 수 있는지
    func yields(to next: Speech) -> Bool {
        kind == .chatter || next.kind == .notice
    }
}

/// 말풍선 글자 앞에 붙는 작은 그림 (곧은 알파 RGBA, 맨 윗줄부터)
struct SpeechBadge: Equatable {
    /// 같은 그림인지 가리는 이름 (앱 번들 ID 등). 비교는 이름으로만 함
    let id: String
    let pixels: SpritePixels

    static func == (lhs: SpeechBadge, rhs: SpeechBadge) -> Bool { lhs.id == rhs.id }
}

/// 확인할 때까지 남는 알림 하나 (어느 일정·세션의 무슨 문구인지)
struct ScheduleNotice: Equatable {
    let topic: String
    let text: String
    /// 제목을 뺀 문구 (통화 중 표시용)
    var discreetText: String? = nil
    /// 글자 앞에 붙일 앱 아이콘
    var badge: SpeechBadge? = nil
    /// 든 펫을 누르면 앞으로 불러올 앱
    var appProcessID: Int32? = nil
}

/// 반응 말풍선 문구
enum Chatter {
    static let love = "❤️"
    static let annoyed = "💢"
    static let surprised = "!"
    static let drowsy = "…"
    static let asleep = "Zzz"
    static let hello = "👋"
    /// 흔들린 창에서 튕겨 나가거나 탑이 무너질 때
    static let dizzy = "💫"
    /// 탑이 높아졌을 때 맨 위 펫
    static let cheer = "🎉"
    /// 오래 둔 알림을 구겨 던질 때
    static let tossed = "💨"
}
