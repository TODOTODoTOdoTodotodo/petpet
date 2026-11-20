import EventKit
import Foundation

/// This object is responsible for reading the Mac's Calendar events and timed Reminders through EventKit,
/// asking the user for access once, and telling the app when calendar data changes.
/// Accounts added in System Settings (iCloud, Google, Exchange/Outlook) are included automatically.
final class EventKitScheduleSource: ScheduleSource {
    enum Access {
        case granted
        case denied
        case undetermined
    }

    private let store = EKEventStore()
    private var cachedReminders: [ScheduleItem] = []
    private var changeObserver: NSObjectProtocol?
    /// 캘린더 데이터가 바뀌었을 때 (메인 스레드)
    var onChange: (() -> Void)?

    init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            self?.refreshReminders()
            self?.onChange?()
        }
    }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    var eventAccess: Access { Self.access(for: .event) }
    var reminderAccess: Access { Self.access(for: .reminder) }

    /// 캘린더·미리 알림 접근을 차례로 요청. 완료는 메인 스레드
    func requestAccess(completion: @escaping () -> Void) {
        request(.event) { [weak self] in
            self?.request(.reminder) {
                self?.refreshReminders()
                completion()
            }
        }
    }

    func items(from start: Date, to end: Date) -> [ScheduleItem] {
        var items: [ScheduleItem] = []
        if eventAccess == .granted {
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            items += store.events(matching: predicate).map { event in
                ScheduleItem(
                    id: event.eventIdentifier ?? event.calendarItemIdentifier,
                    title: event.title ?? "",
                    start: event.startDate,
                    kind: .event,
                    isAllDay: event.isAllDay
                )
            }
        }
        items += cachedReminders.filter { $0.start >= start && $0.start <= end }
        return items
    }

    /// 미리 알림은 비동기로만 읽을 수 있어 미리 받아 둠 (앞뒤 하루)
    func refreshReminders() {
        guard reminderAccess == .granted else {
            cachedReminders = []
            return
        }
        let now = Date()
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: now.addingTimeInterval(-86_400), ending: now.addingTimeInterval(86_400), calendars: nil
        )
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let items = (reminders ?? []).compactMap { reminder -> ScheduleItem? in
                // 시각 없이 날짜만 있는 미리 알림은 알리지 않음
                guard let components = reminder.dueDateComponents, components.hour != nil,
                      let due = Calendar.current.date(from: components) else { return nil }
                return ScheduleItem(id: reminder.calendarItemIdentifier, title: reminder.title ?? "", start: due, kind: .reminder, isAllDay: false)
            }
            DispatchQueue.main.async {
                self?.cachedReminders = items
                self?.onChange?()
            }
        }
    }

    private func request(_ type: EKEntityType, then next: @escaping () -> Void) {
        guard Self.access(for: type) == .undetermined else {
            next()
            return
        }
        let finish: (Bool, Error?) -> Void = { _, _ in DispatchQueue.main.async(execute: next) }
        if #available(macOS 14.0, *) {
            if type == .event {
                store.requestFullAccessToEvents(completion: finish)
            } else {
                store.requestFullAccessToReminders(completion: finish)
            }
        } else {
            store.requestAccess(to: type, completion: finish)
        }
    }

    private static func access(for type: EKEntityType) -> Access {
        let status = EKEventStore.authorizationStatus(for: type)
        if #available(macOS 14.0, *), status == .fullAccess { return .granted }
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .undetermined
        default: return .denied
        }
    }
}
