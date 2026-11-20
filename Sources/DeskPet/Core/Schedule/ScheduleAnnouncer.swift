import Foundation

/// 알릴 일정 하나 (캘린더 일정 또는 마감 시각 있는 미리 알림)
struct ScheduleItem: Equatable {
    enum Kind: Equatable {
        case event
        case reminder
    }

    let id: String
    let title: String
    let start: Date
    let kind: Kind
    let isAllDay: Bool
}

/// This object is responsible for supplying upcoming calendar items, whatever app stores them.
protocol ScheduleSource: AnyObject {
    func items(from start: Date, to end: Date) -> [ScheduleItem]
}

/// This object is responsible for deciding which schedule items to announce right now and in what words:
/// 10 minutes before and at the start of events, at the due time of reminders, each moment only once,
/// and never a moment that passed more than 90 seconds ago (so a late launch does not replay old items).
final class ScheduleAnnouncer {
    static let leadTime: TimeInterval = 10 * 60
    static let freshness: TimeInterval = 90
    static let maxTitleLength = 24

    var hidesTitles = false
    private var announced: Set<String> = []

    /// now 시점에 새로 말할 알림들 (시간순)
    func announcements(for items: [ScheduleItem], at now: Date) -> [ScheduleNotice] {
        var due: [(moment: Date, notice: ScheduleNotice)] = []
        for item in items where !item.isAllDay {
            for (moment, phrase) in moments(of: item) {
                let age = now.timeIntervalSince(moment)
                guard age >= 0, age < Self.freshness else { continue }
                let key = "\(item.id)|\(moment.timeIntervalSince1970)"
                guard !announced.contains(key) else { continue }
                announced.insert(key)
                let notice = ScheduleNotice(topic: item.id, text: text(phrase, title: item.title, hidden: hidesTitles),
                                            discreetText: text(phrase, title: item.title, hidden: true))
                due.append((moment, notice))
            }
        }
        forgetOld(before: now.addingTimeInterval(-Self.leadTime - Self.freshness * 2))
        return due.sorted { $0.moment < $1.moment }.map(\.notice)
    }

    /// 항목별 알릴 시점과 앞말
    private func moments(of item: ScheduleItem) -> [(Date, Phrase)] {
        switch item.kind {
        case .event:
            return [(item.start.addingTimeInterval(-Self.leadTime), .soon), (item.start, .now)]
        case .reminder:
            return [(item.start, .todo)]
        }
    }

    private enum Phrase {
        case soon
        case now
        case todo
    }

    /// 짧은 명사형 문구. 제목을 숨기면 종류만 말함
    private func text(_ phrase: Phrase, title: String, hidden: Bool) -> String {
        let minutes = Int(Self.leadTime / 60)
        if hidden {
            switch phrase {
            case .soon: return "\(minutes)분 뒤 일정"
            case .now: return "지금 일정"
            case .todo: return "할 일 시간"
            }
        }
        let shortTitle = Self.shorten(title)
        switch phrase {
        case .soon: return "\(minutes)분 뒤 · \(shortTitle)"
        case .now: return "지금 · \(shortTitle)"
        case .todo: return "할 일 · \(shortTitle)"
        }
    }

    static func shorten(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "제목 없음" : trimmed
        return base.count > maxTitleLength ? String(base.prefix(maxTitleLength)) + "…" : base
    }

    /// 지난 시점 기록 정리 (키 끝의 시각 기준)
    private func forgetOld(before limit: Date) {
        announced = announced.filter { key in
            guard let stamp = key.split(separator: "|").last.flatMap({ Double($0) }) else { return false }
            return stamp >= limit.timeIntervalSince1970
        }
    }
}
