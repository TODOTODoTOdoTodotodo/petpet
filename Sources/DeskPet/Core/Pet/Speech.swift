import Foundation

/// This object is responsible for one speech bubble's text, kind and remaining time.
/// Notices (schedule) outrank chatter (reactions) and stay until the user acknowledges them.
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

    /// 통화 중 보여 줄 말풍선 (제목 없는 문구가 있으면 그것으로)
    var discreet: Speech {
        var copy = self
        if let discreetText { copy = Speech(text: discreetText, kind: kind, remaining: remaining, topic: topic) }
        return copy
    }

    /// 지금 말풍선을 새 말이 덮어쓸 수 있는지
    func yields(to next: Speech) -> Bool {
        kind == .chatter || next.kind == .notice
    }
}

/// 일정 알림 하나 (어느 일정의 무슨 문구인지)
struct ScheduleNotice: Equatable {
    let topic: String
    let text: String
    /// 제목을 뺀 문구 (통화 중 표시용)
    var discreetText: String? = nil
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
}
